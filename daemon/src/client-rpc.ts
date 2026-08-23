/**
 * client-rpc.ts — 客户端事件处理（WS 与 panel-socket 共用）
 *
 * 除 approve/reject/cancel 外，面板控制类（prompt/mode/sessions/status）
 * 也通过事件通道处理，同一套逻辑对 WS 客户端与 Unix socket 客户端生效。
 */
import type { AgentBridge } from "./agent.js";
import type { ApprovalRegistry } from "./approval.js";
import type { KairoSessionManager } from "./session-manager.js";
import type { BroadcastFn, WsClientEvent } from "./ws-types.js";

export interface ClientRpcDeps {
  approvals: ApprovalRegistry;
  agent: AgentBridge;
  sessions: KairoSessionManager;
  broadcast: BroadcastFn;
  /** 主题持久化（settings.json 的 theme 字段） */
  themeStore: { get: () => string; set: (theme: string) => void };
}

export async function handleClientEvent(
  msg: WsClientEvent,
  deps: ClientRpcDeps,
): Promise<void> {
  const { approvals, agent, sessions, broadcast, themeStore } = deps;
  switch (msg.type) {
    case "approve":
    case "reject":
      approvals.respond(msg.id, msg.type === "approve");
      break;
    case "cancel":
      await agent.abort();
      break;
    case "prompt": {
      if (typeof msg.message !== "string" || msg.message.trim() === "") return;
      // 面板隐藏时中止当前流式；发送新消息走 prompt
      await agent.prompt(msg.message);
      break;
    }
    case "mode": {
      if (msg.mode === "chat" || msg.mode === "command") {
        await agent.setMode(msg.mode);
      }
      break;
    }
    case "sessions_new": {
      const { id } = await agent.newSession(
        typeof msg.name === "string" && msg.name ? msg.name : undefined,
      );
      broadcast({ type: "session_list", sessions: await sessions.list() });
      void id;
      break;
    }
    case "sessions_activate": {
      const target = await sessions.findPathById(msg.id);
      if (!target) {
        broadcast({ type: "error", code: "session_not_found", message: `会话不存在: ${msg.id}` });
        return;
      }
      await agent.abort(); // 切换前停止当前流式
      await agent.switchSession(target);
      broadcast({ type: "session_list", sessions: await sessions.list() });
      break;
    }
    case "sessions_delete": {
      const active = agent.status().sessionId;
      if (active === msg.id) {
        broadcast({ type: "error", code: "active_session", message: "不能删除当前活动会话" });
        return;
      }
      const deleted = await sessions.deleteById(msg.id);
      if (!deleted) {
        broadcast({ type: "error", code: "session_not_found", message: `会话不存在: ${msg.id}` });
        return;
      }
      broadcast({ type: "session_list", sessions: await sessions.list() });
      break;
    }
    case "theme_set": {
      if (msg.theme === "dark" || msg.theme === "light") {
        themeStore.set(msg.theme);
        broadcast({ type: "theme_changed", theme: msg.theme });
      }
      break;
    }
    case "theme_get":
      broadcast({ type: "theme_changed", theme: themeStore.get() });
      break;
    case "get_status":
      broadcast({ type: "status", status: agent.status() });
      broadcast({ type: "session_list", sessions: await sessions.list() });
      break;
  }
}