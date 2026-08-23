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
import { applyMode, modeHint } from "./modes.js";
import type { ApprovalRegistry } from "./approval.js";
import { createApprovalGateExtension } from "./approval.js";
import type { BroadcastFn, SessionStatus, WsServerEvent } from "./ws-types.js";

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

export class AgentBridge {
  runtime: AgentSessionRuntime | null = null;
  private unsubscribe: (() => void) | null = null;
  private mode: KairoMode;

  constructor(
    private config: KairoConfig,
    private approvals: ApprovalRegistry,
    private broadcast: BroadcastFn,
    private persistMode: (mode: KairoMode) => void,
    initialMode: KairoMode,
  ) {
    this.mode = initialMode;
  }

  /** 创建 runtime 工厂（资源加载器内联扩展 = 确认门） */
  private makeRuntimeFactory(): CreateAgentSessionRuntimeFactory {
    const config = this.config;
    const approvals = this.approvals;
    return async ({ cwd, agentDir, sessionManager, sessionStartEvent }) => {
      const services = await createAgentSessionServices({
        cwd,
        agentDir,
        resourceLoaderOptions: {
          extensionFactories: [createApprovalGateExtension(approvals, config)],
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