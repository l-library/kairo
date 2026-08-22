/**
 * panel-socket.ts — 面板专用 Unix domain socket 通道
 *
 * 背景：quickshell QML 端只能访问 Unix socket（QLocalSocket），无法直连 TCP/WS，
 * 因此 daemon 额外暴露一个本地 socket（~/.local/state/kairo/panel.sock）。
 *
 * - 鉴权：socket 文件 0600 + 仅同用户可连，等价于 token 鉴权
 * - 协议：换行分隔 JSON；服务端事件 = daemon 级广播（由 main.ts 注入 enqueue）
 * - 客户端事件：与 WS 共用 handleClientEvent
 * - 断连：pending 审批置为拒绝（与 WS 一致，防 turn 卡死）
 */
import { createServer, type Socket } from "node:net";
import { unlinkSync, existsSync, chmodSync } from "node:fs";
import { join } from "node:path";
import type { AgentBridge } from "./agent.js";
import type { ApprovalRegistry } from "./approval.js";
import type { KairoSessionManager } from "./session-manager.js";
import type { WsClientEvent } from "./ws-types.js";
import { handleClientEvent } from "./client-rpc.js";

export interface PanelSocketDeps {
  stateDir: string;
  approvals: ApprovalRegistry;
  agent: AgentBridge;
  sessions: KairoSessionManager;
}

export interface PanelSocketHandle {
  /** daemon 级广播 → 推送给全部面板客户端 */
  enqueue: (event: unknown) => void;
  close: () => void;
}

/** 换行分隔 JSON 包解析器 */
class LineSplitter {
  private buffer = "";
  constructor(private onLine: (line: string) => void) {}
  push(chunk: Buffer): void {
    this.buffer += chunk.toString("utf8");
    let idx: number;
    while ((idx = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, idx).trim();
      this.buffer = this.buffer.slice(idx + 1);
      if (line) this.onLine(line);
    }
  }
}

export function startPanelSocket(deps: PanelSocketDeps): PanelSocketHandle {
  const { stateDir, approvals, agent, sessions } = deps;
  const sockPath = join(stateDir, "panel.sock");
  if (existsSync(sockPath)) unlinkSync(sockPath);

  const clients = new Set<Socket>();

  const server = createServer((client: Socket) => {
    clients.add(client);
    const send = (event: unknown): void => {
      if (!client.destroyed) client.write(JSON.stringify(event) + "\n");
    };
    // 连接快照
    send({ type: "status", status: agent.status() });
    void sessions.list().then((list) => send({ type: "session_list", sessions: list }));

    const splitter = new LineSplitter((line) => {
      let msg: WsClientEvent;
      try {
        msg = JSON.parse(line) as WsClientEvent;
      } catch {
        return;
      }
      void handleClientEvent(msg, { approvals, agent, sessions, broadcast: send }).catch((err) => {
        console.error("[panel-socket] 客户端事件处理失败:", err);
      });
    });

    client.on("data", (chunk) => splitter.push(chunk));
    client.on("close", () => {
      clients.delete(client);
      const ids = approvals.rejectAll("面板断开");
      if (ids.length > 0) console.log(`[panel-socket] 面板断开，拒绝 ${ids.length} 个待审批操作`);
    });
    client.on("error", () => {
      clients.delete(client);
    });
  });

  server.listen(sockPath, () => {
    try {
      chmodSync(sockPath, 0o600);
    } catch {
      /* best effort */
    }
    console.log(`[kairo-daemon] 面板 socket: ${sockPath}`);
  });

  return {
    enqueue: (event) => {
      const data = JSON.stringify(event);
      for (const client of clients) {
        if (!client.destroyed) client.write(data + "\n");
      }
    },
    close: () => {
      server.close();
      for (const client of clients) client.destroy();
      if (existsSync(sockPath)) unlinkSync(sockPath);
    },
  };
}