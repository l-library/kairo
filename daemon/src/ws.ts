/**
 * ws.ts — WebSocket 服务器：事件流广播 + 客户端事件处理
 *
 * 鉴权：握手时校验 `Authorization: Bearer <token>` 或查询参数 `?token=`。
 * 断开连接：与该客户端相关的 pending 审批全部置为拒绝（否则 turn 卡死）。
 */
import { WebSocketServer, type WebSocket } from "ws";
import type { Server } from "node:http";
import type { AgentBridge } from "./agent.js";
import type { ApprovalRegistry } from "./approval.js";
import type { KairoSessionManager } from "./session-manager.js";
import type { WsClientEvent } from "./ws-types.js";
import { handleClientEvent } from "./client-rpc.js";

export interface WsServerDeps {
  httpServer: Server;
  token: string;
  approvals: ApprovalRegistry;
  agent: AgentBridge;
  sessions: KairoSessionManager;
  themeStore: { get: () => string; set: (theme: string) => void };
}

export function startWsServer(deps: WsServerDeps): WebSocketServer {
  const { httpServer, token, approvals, agent, sessions, themeStore } = deps;
  const wss = new WebSocketServer({ noServer: true });

  httpServer.on("upgrade", (req, socket, head) => {
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
    if (url.pathname !== "/ws") {
      socket.destroy();
      return;
    }
    const bearer = req.headers.authorization?.replace(/^Bearer\s+/i, "") ?? "";
    const queryToken = url.searchParams.get("token") ?? "";
    if (bearer !== token && queryToken !== token) {
      socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req);
    });
  });

  wss.on("connection", (ws) => {
    // 补发状态快照 + 当前会话历史回放（同 panel-socket：重连后 UI 恢复消息流）
    ws.send(JSON.stringify({ type: "status", status: agent.status() }));
    const active = agent.activeSessionInfo();
    ws.send(JSON.stringify({ type: "session_active", id: active.id, name: active.name }));
    const history = agent.currentHistory();
    if (history.length > 0) {
      ws.send(JSON.stringify({ type: "session_history", messages: history }));
    }
    void sessions.listWithActive(active).then((list) =>
      ws.send(JSON.stringify({ type: "session_list", sessions: list })),
    );

    ws.on("message", (raw) => {
      let msg: WsClientEvent;
      try {
        msg = JSON.parse(String(raw)) as WsClientEvent;
      } catch {
        return;
      }
      void handleClientEvent(msg, { approvals, agent, sessions, broadcast: (ev) => sendTo(ws, ev), themeStore }).catch(
        (err) => console.error("[ws] 客户端事件处理失败:", err),
      );
    });

    ws.on("close", () => {
      const ids = approvals.rejectAll("客户端已断开");
      if (ids.length > 0) {
        console.log(`[ws] 客户端断开，拒绝 ${ids.length} 个待审批操作`);
      }
    });

    ws.on("error", () => {
      /* ignore */
    });
  });

  return wss;
}

function sendTo(ws: WebSocket, event: unknown): void {
  if (ws.readyState === 1 /* OPEN */) {
    ws.send(JSON.stringify(event));
  }
}