/**
 * config.ts — 路径 / 端口 / 默认值解析 + token 鉴权管理
 */
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";

const HOME = homedir();

export const DEFAULTS = {
  agentDir: join(HOME, ".config", "kairo", "agent"),
  sessionDir: join(HOME, ".local", "share", "kairo", "sessions"),
  workdir: join(HOME, ".local", "share", "kairo", "workdir"),
  stateDir: join(HOME, ".local", "state", "kairo"),
  settingsPath: join(HOME, ".config", "kairo", "settings.json"),
  host: "127.0.0.1",
  port: 44811,
  defaultMode: "command" as "chat" | "command",
  commandTools: ["read", "bash", "edit", "write", "grep", "find", "ls"],
  readOnlyAutoApprove: ["read", "grep", "find", "ls"],
  approvalTimeoutMs: 10 * 60 * 1000, // 10 分钟
};

export interface KairoSettings {
  port?: number;
  host?: string;
  defaultMode?: "chat" | "command";
  workdir?: string;
  readOnlyAutoApprove?: string[];
  approvalTimeoutMs?: number;
}

function loadSettings(path: string): KairoSettings {
  try {
    if (existsSync(path)) {
      return JSON.parse(readFileSync(path, "utf8")) as KairoSettings;
    }
  } catch {
    // 配置损坏时回退默认值
  }
  return {};
}

export interface KairoConfig {
  host: string;
  port: number;
  agentDir: string;
  sessionDir: string;
  workdir: string;
  stateDir: string;
  settingsPath: string;
  defaultMode: "chat" | "command";
  commandTools: string[];
  readOnlyAutoApprove: string[];
  approvalTimeoutMs: number;
  token: string;
}

export function resolveConfig(): KairoConfig {
  const settings = loadSettings(DEFAULTS.settingsPath);
  const workdir = resolve(settings.workdir ?? process.env.KAIRO_WORKDIR ?? DEFAULTS.workdir);
  const sessionDir = resolve(process.env.KAIRO_SESSION_DIR ?? DEFAULTS.sessionDir);
  const stateDir = resolve(process.env.KAIRO_STATE_DIR ?? DEFAULTS.stateDir);
  const agentDir = resolve(process.env.KAIRO_AGENT_DIR ?? DEFAULTS.agentDir);

  for (const d of [sessionDir, stateDir, workdir]) mkdirSync(d, { recursive: true });

  return {
    host: settings.host ?? process.env.KAIRO_HOST ?? DEFAULTS.host,
    port: settings.port ?? DEFAULTS.port,
    agentDir,
    sessionDir,
    workdir,
    stateDir,
    settingsPath: DEFAULTS.settingsPath,
    defaultMode: settings.defaultMode ?? DEFAULTS.defaultMode,
    commandTools: DEFAULTS.commandTools,
    readOnlyAutoApprove: settings.readOnlyAutoApprove ?? DEFAULTS.readOnlyAutoApprove,
    approvalTimeoutMs: settings.approvalTimeoutMs ?? DEFAULTS.approvalTimeoutMs,
    token: loadOrCreateToken(stateDir),
  };
}

/** 启动时生成随机 token 写入 stateDir/token（0600），供 HTTP/WS 鉴权 */
function loadOrCreateToken(stateDir: string): string {
  const tokenPath = join(stateDir, "token");
  try {
    if (existsSync(tokenPath)) {
      const token = readFileSync(tokenPath, "utf8").trim();
      if (token) return token;
    }
  } catch {
    /* 重新生成 */
  }
  const token = randomBytes(32).toString("hex");
  writeFileSync(tokenPath, token, { mode: 0o600 });
  return token;
}