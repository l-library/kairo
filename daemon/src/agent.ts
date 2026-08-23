/**
 * agent.ts — AgentSession 封装：prompt/abort/模式切换/事件归一化
 *
 * 持有当前 AgentSessionRuntime；会话替换后通过 setRebindSession 完成：
 *  ① 重订阅事件流
 *  ② 按当前模式重设工具
 *  ③ 清空该会话的 pending 审批并通知 UI
 *
 * 确认门（内联扩展）随会话重建自动重新挂载。
 */
import { existsSync, readFileSync, writeFileSync, chmodSync } from "node:fs";
import { execFile } from "node:child_process";
import { join } from "node:path";
import {
  type AgentSession,
  type AgentSessionEvent,
  type AgentSessionRuntime,
  type CreateAgentSessionRuntimeFactory,
  createAgentSessionFromServices,
  createAgentSessionRuntime,
  createAgentSessionServices,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import type { KairoConfig } from "./config.js";
import type { KairoMode } from "./modes.js";
import { applyMode, modeHint, MODE_SYSTEM_PROMPT, MODE_TOOLS } from "./modes.js";
import type { ApprovalRegistry } from "./approval.js";
import { createApprovalGateExtension } from "./approval.js";
import type {
  BroadcastFn,
  ModelInfo,
  PluginInfo,
  ProviderInfo,
  SessionListItem,
  SessionStatus,
  SkillInfo,
  WsServerEvent,
} from "./ws-types.js";

/** 从 agent 状态提取可渲染历史（用户/助手文本） */
function buildHistory(session: AgentSession): { role: "user" | "assistant"; text: string }[] {
  const out: { role: "user" | "assistant"; text: string }[] = [];
  for (const m of session.agent.state.messages) {
    if (m.role !== "user" && m.role !== "assistant") continue;
    const content = (m as { content?: { type?: string; text?: string }[] }).content;
    if (!Array.isArray(content)) continue;
    const text = content
      .filter((c) => c && c.type === "text" && typeof c.text === "string")
      .map((c) => c.text as string)
      .join("\n")
      .trim();
    if (!text) continue;
    out.push({ role: m.role, text });
  }
  return out;
}

/** SDK 事件 → WS 事件（服务端广播） */
function normalizeEvent(event: AgentSessionEvent): WsServerEvent | null {
  switch (event.type) {
    case "agent_start":
      return { type: "agent_start" };
    case "agent_end":
      return { type: "agent_end" };
    case "turn_start":
      return { type: "turn_start" };
    case "turn_end":
      return {
        type: "turn_end",
        toolResults: event.toolResults.map((t) => ({
          toolCallId: t.toolCallId,
          toolName: t.toolName,
          content: t.content,
        })),
      };
    case "message_start":
      return { type: "message_start" };
    case "message_end":
      return { type: "message_end" };
    case "message_update": {
      const m = event.assistantMessageEvent;
      if (m.type === "text_delta")
        return { type: "message_update", messageId: "", kind: "text_delta", delta: m.delta };
      if (m.type === "thinking_delta")
        return { type: "message_update", messageId: "", kind: "thinking_delta", delta: m.delta };
      return null;
    }
    case "tool_execution_start":
      return { type: "tool_execution_start", toolCallId: event.toolCallId, toolName: event.toolName, args: event.args };
    case "tool_execution_update":
      return { type: "tool_execution_update", toolCallId: event.toolCallId, chunk: event.partialResult };
    case "tool_execution_end":
      return { type: "tool_execution_end", toolCallId: event.toolCallId, isError: event.isError, result: event.result };
    default:
      return null;
  }
}

/** resolve 前实时读取的会话名（sessionManager 内部状态） */
function currentSessionName(session: AgentSession | undefined): string | undefined {
  return session?.sessionManager?.getSessionName() ?? undefined;
}

/** 自动命名只接触 modelRuntime 的最小结构（避免依赖 SDK 精确类型） */
interface NamingModelRuntime {
  getModel(providerId: string, modelId: string): unknown;
  completeSimple(
    model: unknown,
    context: unknown,
    options?: Record<string, unknown>,
  ): Promise<{ content: unknown }>;
}

/** 模型清单 / 切换只接触 modelRuntime 的视图 */
interface KairoModelRuntime {
  getProviders?(): unknown[];
  getModels?(providerId?: string): { id: string; name?: string; reasoning?: boolean }[];
  getModel?(providerId: string, modelId: string): unknown;
  hasConfiguredAuth?(providerId: string): boolean;
}

type KnownModel = { id: string; name?: string; reasoning?: boolean };

export class AgentBridge {
  runtime: AgentSessionRuntime | null = null;
  private unsubscribe: (() => void) | null = null;
  private mode: KairoMode;
  /** 自动命名进行中的会话 id（防重入） */
  private namingInFlight = new Set<string>();

  constructor(
    private config: KairoConfig,
    private approvals: ApprovalRegistry,
    private broadcast: BroadcastFn,
    private persistMode: (mode: KairoMode) => void,
    initialMode: KairoMode,
    /** 注入列表回调，命名后广播最新会话列表（避免 agent 反向依赖 session-manager） */
    private getSessionList: () => Promise<SessionListItem[]>,
  ) {
    this.mode = initialMode;
  }

  /** 插件扩展注册的工具名（Command 模式下与内置工具合并激活） */
  private extensionToolNames = new Set<string>();

  /**
   * 快照扩展工具名。必须在 applyMode 之前、会话为全新状态时调用：
   * 新建/恢复/重载后的会话，SDK 默认 includeAllExtensionTools 全量注册，
   * getActiveToolNames() 此时包含全部插件工具；过滤掉内置模式工具即得扩展工具。
   */
  private captureExtensionTools(session: AgentSession): void {
    const modeTools = new Set([...MODE_TOOLS.chat, ...MODE_TOOLS.command]);
    this.extensionToolNames = new Set(
      session.getActiveToolNames().filter((n) => !modeTools.has(n)),
    );
    if (this.extensionToolNames.size > 0) {
      console.log("[agent] 扩展工具已快照:", [...this.extensionToolNames].join(", "));
    }
  }

  /** 创建 runtime 工厂（资源加载器内联扩展 = 确认门 + 按模式系统提示 + 资源隔离） */
  private makeRuntimeFactory(): CreateAgentSessionRuntimeFactory {
    const config = this.config;
    const approvals = this.approvals;
    return async ({ cwd, agentDir, sessionManager, sessionStartEvent }) => {
      // 隔离：只保留 kairo agentDir 内的资源（skills/prompts/themes/extensions），
      // 丢弃 SDK 默认目录（如 ~/.agents/skills）泄漏进来的宿主资源
      const inAgentDir = (p: string | undefined): boolean =>
        !!p && (p.startsWith(config.agentDir + "/") || p === config.agentDir);
      const services = await createAgentSessionServices({
        cwd,
        agentDir,
        resourceLoaderOptions: {
          extensionFactories: [createApprovalGateExtension(approvals, config)],
          // 按模式注入系统提示：闭包在 loader 创建 / reload 时求值，读当前 mode。
          // Chat 整体替换 pi 基础提示（其内置首句宣称可读文件/执行命令，
          // 即使无工具也会让模型误称能编辑文件）；Command 前置模式说明保留基础提示。
          systemPromptOverride: (base: string | undefined) => {
            if (this.mode === "chat") return MODE_SYSTEM_PROMPT.chat;
            return [MODE_SYSTEM_PROMPT.command, base].filter((s) => s && s.trim()).join("\n\n");
          },
          skillsOverride: (base) => ({
            ...base,
            skills: base.skills.filter((s) => inAgentDir(s.filePath)),
          }),
          promptsOverride: (base) => ({
            ...base,
            prompts: base.prompts.filter((p) => inAgentDir((p as { path?: string }).path)),
          }),
          themesOverride: (base) => ({
            ...base,
            themes: base.themes.filter((t) => inAgentDir((t as { path?: string }).path)),
          }),
          extensionsOverride: (base) => ({
            ...base,
            extensions: base.extensions.filter((e) =>
              inAgentDir((e as { baseDir?: string; path?: string }).baseDir ?? (e as { path?: string }).path),
            ),
          }),
        },
      });
      return {
        ...(await createAgentSessionFromServices({ services, sessionManager, sessionStartEvent })),
        services,
        diagnostics: services.diagnostics,
      };
    };
  }

  /** 启动：恢复最近会话（listAll 按 mtime 取最新）或新建 */
  async start(): Promise<void> {
    const restored = await this.findMostRecentSession();
    const sessionManager = restored
      ? SessionManager.open(restored.path, this.config.sessionDir, this.config.workdir)
      : SessionManager.create(this.config.workdir, this.config.sessionDir);
    const runtime = await createAgentSessionRuntime(this.makeRuntimeFactory(), {
      cwd: this.config.workdir,
      agentDir: this.config.agentDir,
      sessionManager,
    });
    this.attach(runtime);
  }

  /** daemon 重启后恢复最近活跃会话（listAll 按 mtime 排序） */
  private async findMostRecentSession(): Promise<{ path: string } | null> {
    try {
      const sessions = await SessionManager.listAll(this.config.sessionDir);
      const match = sessions[0];
      if (!match) return null;
      return { path: match.path };
    } catch {
      return null;
    }
  }

  private attach(runtime: AgentSessionRuntime): void {
    this.runtime = runtime;
    runtime.setRebindSession((session) => this.rebindSession(session));
    this.rebindSession(runtime.session).catch((err) => {
      console.error("[agent] rebind 失败:", err);
    });
  }

  private async rebindSession(session: AgentSession): Promise<void> {
    this.unsubscribe?.();
    // ① 清空该会话的 pending 审批（会话已切换，审批已无意义）
    this.approvals.rejectAll("会话已切换");
    // ② 先快照扩展工具（会话新建/恢复时全量注册），再按当前模式重设工具，
    //    避免整体替换时丢掉插件工具
    this.captureExtensionTools(session);
    applyMode(session, this.mode, this.extensionToolNames);
    // ③ 重订阅事件流
    this.unsubscribe = session.subscribe((event) => {
      const ws = normalizeEvent(event);
      if (ws) this.broadcast(ws);
      // turn 结束后自动命名（仅未命名且有内容的会话）
      if (event.type === "agent_end") {
        void this.maybeAutoName(session);
      }
    });
    this.broadcast({
      type: "session_active",
      id: session.sessionId,
      name: currentSessionName(session),
    });
    // 会话历史回放（新建/切换后 UI 恢复消息流）
    const history = buildHistory(session);
    if (history.length > 0) {
      this.broadcast({ type: "session_history", messages: history });
    }
    this.broadcast({ type: "status", status: this.status() });
  }

  /** 发送消息（/chat /cmd 输入命令切模式） */
  async prompt(text: string): Promise<void> {
    const session = this.runtime?.session;
    if (!session) throw new Error("daemon 尚未就绪");
    if (text === "/chat" || text === "/cmd") {
      await this.setMode(text === "/chat" ? "chat" : "command");
      return;
    }
    if (session.isStreaming) {
      await session.followUp(text); // 流式中排队为 follow-up
      return;
    }
    await session.prompt(text);
  }

  /** 中止当前流式/工具执行（含全部 pending 审批） */
  async abort(): Promise<void> {
    this.approvals.rejectAll("操作已被中止");
    await this.runtime?.session.abort().catch(() => {});
  }

  async setMode(mode: KairoMode): Promise<void> {
    if (mode === this.mode) return;
    this.mode = mode;
    this.persistMode(mode);
    const session = this.runtime?.session;
    if (session) {
      // 中途切模式：systemPromptOverride 只在 loader 创建 / reload 时求值，
      // 必须先 reload 让缓存系统提示按新模式重建，再 applyMode 重组提示。
      const loader = this.runtime?.services?.resourceLoader as
        | { reload?: () => Promise<void> }
        | undefined;
      await loader?.reload?.().catch(() => {
        console.error("[agent] 模式切换时资源加载器 reload 失败:");
      });
      applyMode(session, mode, this.extensionToolNames);
      // 模式提示语以自定义消息注入（display:false，不触发新 turn，不显示在 UI）
      await session
        .sendCustomMessage({
          customType: "kairo_mode_hint",
          content: modeHint(mode),
          display: false,
          details: { mode },
        })
        .catch(() => {});
    }
    this.broadcast({ type: "mode_changed", mode });
  }

  get isStreaming(): boolean {
    return this.runtime?.session.isStreaming ?? false;
  }

  /** 会话操作：新建 / 切换 */
  async newSession(name?: string): Promise<{ id: string }> {
    const runtime = this.runtime;
    if (!runtime) throw new Error("daemon 尚未就绪");
    await runtime.newSession({
      setup: async (sm) => {
        if (name) sm.appendSessionInfo(name);
      },
    });
    return { id: runtime.session.sessionId };
  }

  async switchSession(sessionPath: string): Promise<{ id: string }> {
    const runtime = this.runtime;
    if (!runtime) throw new Error("daemon 尚未就绪");
    await runtime.switchSession(sessionPath, { cwdOverride: this.config.workdir });
    return { id: runtime.session.sessionId };
  }

  /**
   * 自动命名：在 agent_end（rebind/重启恢复/切换/turn 结束）后调用。
   * 短首条消息直接当标题（零成本）；长消息尝试经当前默认模型精简为 ≤12 字标题，
   * 失败回退为截断首条消息。命名后广播 status（刷新标题栏名字，不清 UI 视图）
   * + session_list 同步侧边栏。
   */
  private async maybeAutoName(session: AgentSession): Promise<void> {
    const id = session.sessionId;
    if (this.namingInFlight.has(id)) return;
    if (session.sessionManager?.getSessionName()) return; // 已有名字
    const firstUser = buildHistory(session).find((m) => m.role === "user")?.text;
    if (!firstUser) return; // 尚无用户消息（空新会话）
    this.namingInFlight.add(id);
    try {
      const clean = firstUser.replace(/\s+/g, " ").trim();
      const fallback = clean.slice(0, 24);
      // 短消息虽“启发式”但已是自然标题，避免无谓的模型调用
      const title =
        clean.length <= 24 ? clean : await this.generateAiTitle(clean, fallback);
      if (!title) return;
      if (this.runtime?.session.sessionId !== id) return; // 命名期间已切会话
      if (session.sessionManager?.getSessionName()) return; // 已被并发命名
      session.setSessionName(title);
      console.log(`[agent] 会话自动命名: ${title}`);
      // 注意：不能广播 session_active——UI 收到它会把消息视图 resetMessages()，
      // 刚完成的对话会被清空（看起来像全新对话）。改广播 status 刷新标题栏名字。
      // 但 agent_end 回调期间 session.isStreaming 仍为 true（SDK 在事件派发后才
      // 清理），直接广播 status() 会把 streaming=true 带回 UI，导致状态点一直
      // 黄色、发送按钮卡在「中止」。因此等会话真正空闲后再广播；若一直忙
      // （用户已发起新一轮）则跳过，名字由 session_list 与下一次 status 承担。
      await this.waitUntilIdle(session, 3000);
      if (!session.isStreaming) {
        this.broadcast({ type: "status", status: this.status() });
      }
      const list = await this.getSessionList();
      this.broadcast({ type: "session_list", sessions: list });
    } catch (err) {
      console.error("[agent] 自动命名失败:", err);
    } finally {
      this.namingInFlight.delete(id);
    }
  }

  /** 经当前默认模型生成中文短标题（不可用时返回回退值） */
  private async generateAiTitle(clean: string, fallback: string): Promise<string> {
    try {
      const services = (this.runtime as unknown as {
        services?: {
          modelRuntime?: NamingModelRuntime;
          settingsManager?: {
            getDefaultProvider(): string | undefined;
            getDefaultModel(): string | undefined;
          };
        };
      })?.services;
      const modelRuntime = services?.modelRuntime;
      const settingsManager = services?.settingsManager;
      if (!modelRuntime || !settingsManager) {
        console.log("[agent] 命名: services 不完整");
        return fallback;
      }
      // kairo 的 settings.json 是 defaultProvider + defaultModel 分开存；
      // 也兼容 "provider/model" 组合格式
      let provider = settingsManager.getDefaultProvider() ?? "";
      let modelId = settingsManager.getDefaultModel() ?? "";
      const slash = modelId.indexOf("/");
      if (slash > 0) {
        if (!provider) provider = modelId.slice(0, slash);
        modelId = modelId.slice(slash + 1);
      }
      if (!provider || !modelId) {
        console.log("[agent] 命名: 无 provider/model", { provider, modelId });
        return fallback;
      }
      const model = modelRuntime.getModel(provider, modelId);
      if (!model) {
        console.log("[agent] 命名: getModel 未命中", provider, modelId);
        return fallback;
      }
      const res = await modelRuntime.completeSimple(
        model,
        {
          // 必须传完整 Context 对象（含 tools:[]）；直接传消息数组会导致 SDK 内部
          // tools.map 崩溃（Cannot read properties of undefined (reading 'map')）
          systemPrompt: "你是 kairo 的会话命名助手，只输出简洁的中文短标题。",
          messages: [
            {
              role: "user",
              content: `请为下面的对话生成一个简洁的中文标题（不超过 12 个字）。只输出标题本身，不要引号、标点或任何解释。\n\n对话开头：${clean.slice(0, 400)}`,
            },
          ],
          tools: [],
        },
        { temperature: 0.2, maxTokens: 100 },
      );
      const parts = res.content;
      const text = Array.isArray(parts)
        ? parts
            .filter((c) => c && typeof c === "object" && (c as { type?: string }).type === "text")
            .map((c) => (c as { text?: string }).text ?? "")
            .join(" ")
            .trim()
        : "";
      const title = text.replace(/^["'“”《》【】\s]+|["'“”《》【】\s]+$/g, "").slice(0, 24);
      console.log("[agent] 命名: LLM 结果原文=", JSON.stringify(text.slice(0, 80)));
      return title || fallback;
    } catch (err) {
      console.log("[agent] 命名: LLM 调用异常=", err?.constructor?.name, (err as Error)?.message?.slice(0, 120));
      return fallback;
    }
  }

  /** 当前会话可渲染历史（供连接快照/回放；无会话时返回空数组） */
  currentHistory(): { role: "user" | "assistant"; text: string }[] {
    const session = this.runtime?.session;
    return session ? buildHistory(session) : [];
  }

  /**
   * 当前活动会话的列表条目（合成项）。
   * 新建的会话在收到第一条助手消息前不落盘（SDK newSession 的 no-assistant
   * 保护），磁盘列表会漏掉它；此方法合成一条可见条目供 listWithActive 注入，
   * 保证 UI 会话列表始终显示并高亮当前会话。
   */
  activeSessionInfo(): SessionListItem {
    const session = this.runtime?.session;
    const now = new Date().toISOString();
    return {
      id: session?.sessionId ?? "",
      path: session?.sessionManager?.getSessionFile() ?? "",
      name: currentSessionName(session),
      cwd: this.config.workdir,
      createdAt: now,
      modifiedAt: now,
      messageCount: 0,
      firstMessage: "",
    };
  }

  /** 当前会话 ID（供调用方判断活动会话） */
  get sessionId(): string {
    return this.runtime?.session.sessionId ?? "";
  }

  // =========================================================================
  // 模型 / 思维等级
  // =========================================================================

  /** 当前模型摘要（provider/id + 思维等级 + 可用等级），供 status / model_changed */
  currentModelLabel(): {
    provider: string;
    model: string;
    thinkingLevel: string;
    thinkingLevels: string[];
  } {
    const session = this.runtime?.session;
    const m = session?.model;
    return {
      provider: m?.provider ?? "",
      model: m?.id ?? "",
      thinkingLevel: session?.thinkingLevel ?? "medium",
      thinkingLevels: session?.getAvailableThinkingLevels() ?? [],
    };
  }

  /** 可用模型清单（目录快照 + 鉴权标记），供 GUI 模型选择器 */
  listModels(): ModelInfo[] {
    const session = this.runtime?.session;
    const mr = this.runtime?.services?.modelRuntime as unknown as KairoModelRuntime | undefined;
    if (!mr) return [];
    const providers = (mr.getProviders?.() ?? []) as unknown[];
    const current = session?.model;
    const out: ModelInfo[] = [];
    for (const p of providers) {
      const pid =
        typeof p === "string" ? p : (p as { id?: string } | null)?.id ?? String(p);
      const models = (mr.getModels?.(pid) ?? []) as KnownModel[];
      const authed = !!mr.hasConfiguredAuth?.(pid);
      // 只展示已鉴权模型——目录快照会包含全部内置目（数百个未配置 provider 的模型），
      // 选择器只对可用的模型有意义
      if (!authed) continue;
      for (const m of models) {
        out.push({
          provider: pid,
          id: m.id,
          name: m.name ?? m.id,
          reasoning: !!m.reasoning,
          authed,
          current: current ? current.provider === pid && current.id === m.id : false,
        });
      }
    }
    return out;
  }

  /** 切换模型（setModel 自带鉴权校验与 settings 持久化） */
  async setModel(provider: string, modelId: string): Promise<void> {
    const runtime = this.runtime;
    const session = runtime?.session;
    const mr = runtime?.services?.modelRuntime as unknown as KairoModelRuntime | undefined;
    if (!session || !mr) throw new Error("daemon 尚未就绪");
    if (session.isStreaming) {
      await session.abort().catch(() => {});
    }
    const model = mr.getModel?.(provider, modelId);
    if (!model) throw new Error(`模型不存在: ${provider}/${modelId}`);
    await session.setModel(model as never);
  }

  /** 设置思维等级（按当前模型可用等级校验） */
  async setThinkingLevel(level: string): Promise<void> {
    const session = this.runtime?.session;
    if (!session) throw new Error("daemon 尚未就绪");
    const levels = session.getAvailableThinkingLevels();
    if (!levels.includes(level as never)) {
      throw new Error(`当前模型不支持思维等级: ${level}（可用: ${levels.join("/")}）`);
    }
    session.setThinkingLevel(level as never);
  }

  // =========================================================================
  // 技能（只读展示） / pi 插件（安装/移除）
  // =========================================================================

  /** 已加载技能清单（来自 resourceLoader，含内置 kairo-skills） */
  listSkills(): SkillInfo[] {
    const rl = this.runtime?.services?.resourceLoader;
    const res = rl?.getSkills();
    return (res?.skills ?? []).map((s) => ({
      name: s.name,
      description: s.description,
      path: s.filePath,
    }));
  }

  /** 已配置的 pi 插件清单 */
  listPlugins(): PluginInfo[] {
    const pm = this.resourceLoaderPackageManager();
    if (!pm) return [];
    return (pm.listConfiguredPackages() ?? []).map((p) => ({
      source: p.source,
      scope: p.scope,
      installedPath: p.installedPath,
    }));
  }

  /** 安装 pi 插件（npm/git/本地），成功后 reload 资源并广播 */
  async installPlugin(source: string): Promise<void> {
    const rl = this.runtime?.services?.resourceLoader;
    const pm = this.resourceLoaderPackageManager();
    if (!pm || !rl) throw new Error("包管理器不可用");
    await pm.installAndPersist(source);
    await this.reloadSessionForPlugins();
    this.broadcast({ type: "plugins_changed", plugins: this.listPlugins() });
    this.broadcast({ type: "skills_response", skills: this.listSkills() });
  }

  /** 移除 pi 插件，成功后 reload 资源并广播 */
  async removePlugin(source: string): Promise<void> {
    const rl = this.runtime?.services?.resourceLoader;
    const pm = this.resourceLoaderPackageManager();
    if (!pm || !rl) throw new Error("包管理器不可用");
    await pm.removeAndPersist(source);
    await this.reloadSessionForPlugins();
    this.broadcast({ type: "plugins_changed", plugins: this.listPlugins() });
    this.broadcast({ type: "skills_response", skills: this.listSkills() });
  }

  /**
   * 插件安装/移除后重建会话运行时：只 reload 资源加载器不会重建 ExtensionRunner，
   * 新插件工具要等 daemon 重启才注册。这里先中断流式，再 session.reload()
   * 重建扩展与工具注册表，随后重新快照扩展工具并按当前模式恢复工具集。
   */
  private async reloadSessionForPlugins(): Promise<void> {
    const rl = this.runtime?.services?.resourceLoader;
    if (!rl) return;
    await (rl as { reload?: () => Promise<void> }).reload?.();
    const session = this.runtime?.session;
    if (!session) return;
    if (session.isStreaming) {
      await session.abort().catch(() => {});
    }
    await session.reload().catch((err) => {
      console.error("[plugins] 会话 reload 失败（插件可能需重启 daemon 后生效）:", err);
    });
    // reload 后活动工具 = 原活动 ∪ 全部扩展工具；重新快照并按当前模式恢复
    this.captureExtensionTools(session);
    applyMode(session, this.mode, this.extensionToolNames);
  }

  // =========================================================================
  // 提供商（auth.json / models-store.json 读写 + runtime 刷新）
  // =========================================================================

  /** 已配置提供商清单（含鉴权状态与模型数） */
  listProviders(): ProviderInfo[] {
    const mr = this.runtime?.services?.modelRuntime as unknown as KairoModelRuntime | undefined;
    if (!mr) return [];
    const providers = (mr.getProviders?.() ?? []) as unknown[];
    // 可移除 = kairo 自定义（models.json / auth.json / models-store.json 有记录）；
    // SDK 内置提供商不可删
    const modelsJson = this.readJson<{ providers?: Record<string, unknown> }>(
      join(this.config.agentDir, "models.json"),
      {},
    );
    const auth = this.readJson<Record<string, unknown>>(this.authJsonPath(), {});
    const store = this.readJson<Record<string, unknown>>(this.modelsStorePath(), {});
    const custom = new Set([
      ...Object.keys(modelsJson.providers ?? {}),
      ...Object.keys(auth),
      ...Object.keys(store),
    ]);
    const out: ProviderInfo[] = [];
    for (const p of providers) {
      const pid = typeof p === "string" ? p : (p as { id?: string } | null)?.id ?? String(p);
      out.push({
        id: pid,
        authed: !!mr.hasConfiguredAuth?.(pid),
        modelCount: (mr.getModels?.(pid) ?? []).length,
        removable: custom.has(pid),
      });
    }
    return out;
  }

  private authJsonPath(): string {
    return join(this.config.agentDir, "auth.json");
  }
  private modelsStorePath(): string {
    return join(this.config.agentDir, "models-store.json");
  }

  private readJson<T>(path: string, fallback: T): T {
    try {
      if (existsSync(path)) return JSON.parse(readFileSync(path, "utf8")) as T;
    } catch {
      /* ignore */
    }
    return fallback;
  }
  private writeJson(path: string, data: unknown): void {
    writeFileSync(path, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 });
    try {
      chmodSync(path, 0o600);
    } catch {
      /* best effort */
    }
  }

  /**
   * 添加提供商：写 auth.json（密钥）+ models-store.json（模型目录，
   * 给 baseUrl 时自动探测 OpenAI 兼容 /models 端点），再刷新 runtime。
   * 不重启 daemon（setRuntimeApiKey + refresh 使内存状态即时生效）。
   */
  async addProvider(id: string, apiKey: string, baseUrl?: string): Promise<{ models: string[] }> {
    const cleanId = id.trim();
    const cleanKey = apiKey.trim();
    if (!/^[A-Za-z0-9._-]+$/.test(cleanId)) {
      throw new Error("提供商 id 只能包含字母、数字、点、下划线、连字符");
    }
    if (!cleanKey) throw new Error("api key 不能为空");
    if (cleanId === "kairo") throw new Error("kairo 为保留 id");

    let fetched: { id: string; name?: string }[] = [];
    let normalizedBase = "";
    if (baseUrl && baseUrl.trim()) {
      normalizedBase = baseUrl.trim().replace(/\/+$/, "");
      // 先探测 /models，失败则报错（不落盘，避免残留半配置）
      fetched = await this.fetchOpenAiModels(normalizedBase, cleanKey);
    }

    // 1) auth.json（密钥，与既有 provider 一致）
    const auth = this.readJson<Record<string, unknown>>(this.authJsonPath(), {});
    auth[cleanId] = { type: "api_key", key: cleanKey };
    this.writeJson(this.authJsonPath(), auth);

    // 2) models.json（自定义 provider 的权威定义——SDK 只在启动时从 models.json
    //    组合自定义提供商；models-store.json 只是原生 provider 的目录缓存，
    //    写它无法让新 provider 生效）
    const modelsJson = this.readJson<{ providers?: Record<string, unknown> }>(
      join(this.config.agentDir, "models.json"),
      {},
    );
    if (!modelsJson.providers) modelsJson.providers = {};
    modelsJson.providers[cleanId] = {
      name: cleanId,
      baseUrl: normalizedBase || undefined,
      api: normalizedBase ? "openai-completions" : undefined,
      // 内联 apiKey：无需 auth.json 也能鉴权（与 auth.json 双保险）
      apiKey: cleanKey,
      models: fetched.map((m) => ({
        id: m.id,
        name: m.name ?? m.id,
        api: "openai-completions",
        baseUrl: normalizedBase,
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 128000,
        maxTokens: 32768,
        compat: {
          supportsStore: false,
          supportsDeveloperRole: false,
          maxTokensField: "max_tokens",
          requiresReasoningContentOnAssistantMessages: false,
        },
        thinkingLevelMap: { off: null },
      })),
    };
    this.writeJson(join(this.config.agentDir, "models.json"), modelsJson);

    // 3) 生效：SDK 只在 services 初始化时组合 models-store 里的新提供商，
    //    refresh()/setRuntimeApiKey 均无法让新 provider 即时可见——延迟自重启。
    //    先给客户端足够时间收到落盘确认，再由 systemd 拉起新进程（面板自动重连）。
    this.scheduleDaemonRestart();
    return { models: fetched.map((m) => m.id) };
  }

  /** 移除提供商（不能移除当前模型正在使用的提供商） */
  async removeProvider(id: string): Promise<void> {
    const cleanId = id.trim();
    const session = this.runtime?.session;
    if (session?.model?.provider === cleanId) {
      throw new Error("不能移除当前正在使用的提供商，请先切换到其它提供商");
    }
    // 1) auth.json 与 models.json 同步清理
    const auth = this.readJson<Record<string, unknown>>(this.authJsonPath(), {});
    if (auth[cleanId]) {
      delete auth[cleanId];
      this.writeJson(this.authJsonPath(), auth);
    }
    const modelsJson = this.readJson<{ providers?: Record<string, unknown> }>(
      join(this.config.agentDir, "models.json"),
      {},
    );
    if (modelsJson.providers?.[cleanId]) {
      delete modelsJson.providers[cleanId];
      this.writeJson(join(this.config.agentDir, "models.json"), modelsJson);
    }
    const store = this.readJson<Record<string, unknown>>(this.modelsStorePath(), {});
    if (store[cleanId]) {
      delete store[cleanId];
      this.writeJson(this.modelsStorePath(), store);
    }
    // 3) 生效：同样需要重启才能从 runtime 移除（同 addProvider）
    this.scheduleDaemonRestart();
  }

  /** 延迟自重启：落盘后由 systemd 重启 daemon 让新配置生效 */
  private scheduleDaemonRestart(): void {
    setTimeout(() => {
      execFile("systemctl", ["--user", "restart", "kairo-daemon"], (err) => {
        if (err) {
          console.error("[providers] 自动重启失败，请手动运行 kairoctl restart:", err.message);
        }
      });
    }, 600);
  }

  /** 轮询等待会话空闲（isStreaming 变 false），超时则放弃 */
  private async waitUntilIdle(session: AgentSession, timeoutMs: number): Promise<void> {
    const start = Date.now();
    while (session.isStreaming && Date.now() - start < timeoutMs) {
      await new Promise((r) => setTimeout(r, 50));
    }
  }

  /** 探测 OpenAI 兼容 /models 端点（返回模型 id 列表） */
  private async fetchOpenAiModels(baseUrl: string, apiKey: string): Promise<{ id: string; name?: string }[]> {
    const url = `${baseUrl}/models`;
    let res: Response;
    try {
      res = await fetch(url, {
        headers: { Authorization: `Bearer ${apiKey}` },
        signal: AbortSignal.timeout(15000),
      });
    } catch {
      throw new Error(`无法连接 ${url}，请检查 baseUrl`);
    }
    if (!res.ok) {
      throw new Error(`模型目录探测失败 ${url}: HTTP ${res.status}`);
    }
    const body = (await res.json().catch(() => null)) as { data?: { id?: string }[] } | null;
    const ids = (body?.data ?? []).map((m) => m.id).filter((v): v is string => !!v);
    if (ids.length === 0) {
      throw new Error(`模型目录探测返回空（${url} 不是 OpenAI 兼容端点？）`);
    }
    return ids.map((id) => ({ id }));
  }

  private resourceLoaderPackageManager() {
    return (this.runtime?.services?.resourceLoader as unknown as {
      packageManager?: {
        installAndPersist(source: string, options?: { local?: boolean }): Promise<void>;
        removeAndPersist(source: string, options?: { local?: boolean }): Promise<boolean>;
        listConfiguredPackages(): {
          source: string;
          scope: "user" | "project";
          installedPath?: string;
        }[];
      };
    }).packageManager;
  }

  status(): SessionStatus {
    const m = this.runtime?.session?.model;
    return {
      mode: this.mode,
      sessionId: this.runtime?.session.sessionId ?? "",
      sessionName: currentSessionName(this.runtime?.session),
      streaming: this.isStreaming,
      pendingApprovals: this.approvals.size,
      model: m ? `${m.provider}/${m.id}` : "",
      thinkingLevel: this.runtime?.session?.thinkingLevel ?? "",
    };
  }

  dispose(): void {
    this.unsubscribe?.();
    this.approvals.rejectAll("daemon 关闭");
    void this.runtime?.dispose().catch(() => {});
    this.runtime = null;
  }
}