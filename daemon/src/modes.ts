/**
 * modes.ts — chat / command 双模式定义与切换
 *
 * 切换 = session.setActiveToolsByName()：同步重建系统提示，Chat 模式下
 * 不残留任何工具描述。模式提示语以会话消息方式注入（无公开 systemPrompt setter）。
 */
import type { AgentSession } from "@earendil-works/pi-coding-agent";

export type KairoMode = "chat" | "command";

export const MODE_TOOLS: Record<KairoMode, string[]> = {
  chat: [],
  command: ["read", "bash", "edit", "write", "grep", "find", "ls"],
};

const MODE_HINT: Record<KairoMode, string> = {
  chat: "你当前处于 Chat 模式：纯对话，不能调用任何工具。适合问答、闲聊、翻译与总结。",
  command:
    "你当前处于 Command 模式：可以读写文件、执行命令（读写文件前会先向用户展示差异等待确认）。请主动使用工具完成任务。",
};

export function applyMode(session: AgentSession, mode: KairoMode): void {
  session.setActiveToolsByName(MODE_TOOLS[mode]);
}

export function modeHint(mode: KairoMode): string {
  return MODE_HINT[mode];
}