import { homedir } from "node:os";
import { join } from "node:path";
import {
  createAgentSessionRuntime,
  type CreateAgentSessionRuntimeFactory,
  createAgentSessionFromServices,
  createAgentSessionServices,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import type { AgentSessionRuntime } from "@earendil-works/pi-coding-agent";

/** kairo 独立 agentDir（与宿主 ~/.pi 完全隔离） */
export const KAIRO_AGENT_DIR =
  process.env.KAIRO_AGENT_DIR ?? join(homedir(), ".config", "kairo", "agent");
/** 会话目录 */
export const KAIRO_SESSION_DIR =
  process.env.KAIRO_SESSION_DIR ?? join(homedir(), ".local", "share", "kairo", "sessions");
/** 中性工作目录（不放置任何 AGENTS.md / .pi / .agents，保证隔离） */
export const KAIRO_WORKDIR =
  process.env.KAIRO_WORKDIR ?? join(homedir(), ".local", "share", "kairo", "workdir");

const createRuntime: CreateAgentSessionRuntimeFactory = async ({
  cwd,
  agentDir,
  sessionManager,
  sessionStartEvent,
}) => {
  const services = await createAgentSessionServices({ cwd, agentDir });
  return {
    ...(await createAgentSessionFromServices({
      services,
      sessionManager,
      sessionStartEvent,
    })),
    services,
    diagnostics: services.diagnostics,
  };
};

/** 创建 runtime（M0 用内存会话，不改动磁盘） */
export async function createM0Session(opts?: { workdir?: string }): Promise<AgentSessionRuntime> {
  const workdir = opts?.workdir ?? KAIRO_WORKDIR;
  return createAgentSessionRuntime(createRuntime, {
    cwd: workdir,
    agentDir: KAIRO_AGENT_DIR,
    sessionManager: SessionManager.inMemory(),
  });
}