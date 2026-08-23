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
import { applyMode, modeHint, MODE_SYSTEM_PROMPT } from "./modes.js";
import type { ApprovalRegistry } from "./approval.js";
import { createApprovalGateExtension } from "./approval.js";
import type {
  BroadcastFn,
  SessionListItem,
  SessionStatus,
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

  /** 创建 runtime 工厂（资源加载器内联扩展 = 确认门 + 按模式系统提示） */
  private makeRuntimeFactory(): CreateAgentSessionRuntimeFactory {
    const config = this.config;
    const approvals = this.approvals;
    return async ({ cwd, agentDir, sessionManager, sessionStartEvent }) => {
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
    // ② 按当前模式重设工具
    applyMode(session, this.mode);
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
      applyMode(session, mode);
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
   * 失败回退为截断首条消息。命名后广播 session_active + session_list 同步 UI。
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
      this.broadcast({ type: "session_active", id, name: title });
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

  status(): SessionStatus {
    return {
      mode: this.mode,
      sessionId: this.runtime?.session.sessionId ?? "",
      sessionName: currentSessionName(this.runtime?.session),
      streaming: this.isStreaming,
      pendingApprovals: this.approvals.size,
    };
  }

  dispose(): void {
    this.unsubscribe?.();
    this.approvals.rejectAll("daemon 关闭");
    void this.runtime?.dispose().catch(() => {});
    this.runtime = null;
  }
}