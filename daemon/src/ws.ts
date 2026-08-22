/**
 * ws.ts — WebSocket 服务器：事件流广播 + 确认应答 + 取消
 *
 * 鉴权：握手时校验 `Authorization: Bearer <token>` 或查询参数 `?token=`。
 * 断开连接：与该客户端相关的 pending 审批全部置为拒绝（否则 turn 卡死）。
 */
import { WebSocketServer, type WebSocket } from "ws";
import type { Server } from "node:http";
import type { AgentBridge } from "./agent.js";
import type { ApprovalRegistry } from "./approval.js";
import type { WsClientEvent } from "./ws-types.js";

export interface WsServerDeps {
  httpServer: Server;
  token: string;
  approvals: ApprovalRegistry;
  agent: AgentBridge;
}

export function startWsServer(deps: WsServerDeps): WebSocketServer {
  const { httpServer, token, approvals, agent } = deps;
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
    // 补发状态快照
    ws.send(JSON.stringify({ type: "status", status: agent.status() }));

    ws.on("message", (raw) => {
      let msg: WsClientEvent;
      try {
        msg = JSON.parse(String(raw)) as WsClientEvent;
      } catch {
        return;
      }
      switch (msg.type) {
        case "approve":
        case "reject":
          approvals.respond(msg.id, msg.type === "approve");
          break;
        case "cancel":
          void agent.abort();
          break;
      }
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