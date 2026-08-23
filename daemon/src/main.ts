/**
 * main.ts — daemon 入口：装配 config / approvals / agent / sessions / HTTP / WS
 */
import { createServer } from "node:http";
import { readFileSync, writeFileSync } from "node:fs";
import { existsSync } from "node:fs";
import { resolveConfig } from "./config.js";
import { ApprovalRegistry } from "./approval.js";
import { AgentBridge } from "./agent.js";
import { KairoSessionManager } from "./session-manager.js";
import { startHttpApi } from "./http.js";
import { startWsServer } from "./ws.js";
import { startPanelSocket, type PanelSocketHandle } from "./panel-socket.js";
import type { KairoMode } from "./modes.js";
import type { WsServerEvent } from "./ws-types.js";

const config = resolveConfig();

// --- 模式/主题持久化（写入 ~/.config/kairo/settings.json） ---
function readSettings(): Record<string, unknown> {
  try {
    if (existsSync(config.settingsPath)) {
      return JSON.parse(readFileSync(config.settingsPath, "utf8")) as Record<string, unknown>;
    }
  } catch {
    /* ignore */
  }
  return {};
}
function writeSettings(settings: Record<string, unknown>): void {
  writeFileSync(config.settingsPath, JSON.stringify(settings, null, 2) + "\n");
}
function persistMode(mode: KairoMode): void {
  const settings = readSettings();
  settings.defaultMode = mode;
  writeSettings(settings);
}
const themeStore = {
  get: () => {
    const t = readSettings().theme;
    return t === "light" ? "light" : "dark";
  },
  set: (theme: string) => {
    const settings = readSettings();
    settings.theme = theme;
    writeSettings(settings);
    console.log(`[kairo-daemon] 主题已保存: ${theme}`);
  },
};
const savedMode: KairoMode = readSettings().defaultMode === "chat" ? "chat" : "command";

// --- 确认门注册表 + 事件桥 ---
const wssRef: { current: ReturnType<typeof startWsServer> | null } = { current: null };
const panelRef: { current: PanelSocketHandle | null } = { current: null };
const broadcast = (event: WsServerEvent): void => {
  const wss = wssRef.current;
  if (wss) {
    const data = JSON.stringify(event);
    for (const client of wss.clients) {
      if (client.readyState === 1) client.send(data);
    }
  }
  panelRef.current?.enqueue(event);
};

const approvals = new ApprovalRegistry(config, {
  onRequest: (req) => {
    broadcast({
      type: "approval_requested",
      id: req.id,
      toolName: req.toolName,
      target: req.target,
      diff: req.diff,
      command: req.command,
      cwd: req.cwd,
    });
    console.log(
      `[approval] 请求审批: ${req.toolName} ${req.target ?? req.command?.slice(0, 40) ?? ""}`,
    );
  },
  onResolved: (id, allowed) => {
    broadcast({ type: "approval_resolved", id, allowed });
    console.log(`[approval] ${allowed ? "批准" : "拒绝"}: ${id}`);
  },
});

// --- AgentBridge / 会话管理 ---
const agent = new AgentBridge(config, approvals, broadcast, persistMode, savedMode);
const sessions = new KairoSessionManager({ sessionDir: config.sessionDir });

// --- HTTP + WS ---
const httpServer = createServer(startHttpApi({ agent, sessions, token: config.token }));

async function main(): Promise<void> {
  wssRef.current = startWsServer({ httpServer, token: config.token, approvals, agent, sessions, themeStore });
  panelRef.current = startPanelSocket({ stateDir: config.stateDir, approvals, agent, sessions, themeStore });
  await agent.start();

  httpServer.listen(config.port, config.host, () => {
    console.log(`[kairo-daemon] 监听 ${config.host}:${config.port}`);
    console.log(`[kairo-daemon] agentDir=${config.agentDir}`);
    console.log(`[kairo-daemon] sessionDir=${config.sessionDir}`);
    console.log(`[kairo-daemon] 模式=${agent.status().mode} 会话=${agent.status().sessionId}`);
  });
}

// SIGTERM/SIGINT 优雅退出
for (const sig of ["SIGTERM", "SIGINT"] as const) {
  process.on(sig, () => {
    console.log(`[kairo-daemon] 收到 ${sig}，退出中…`);
    agent.dispose();
    panelRef.current?.close();
    httpServer.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}

main().catch((err) => {
  console.error("[kairo-daemon] 启动失败:", err);
  process.exit(1);
});