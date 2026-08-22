/**
 * M0 演示 ③：模式切换（chat 无工具 / command 全工具）
 *
 * 验证点：
 *   1. 默认工具集 = [read,bash,edit,write]
 *   2. setActiveToolsByName([]) → 工具清空、系统提示不含工具描述；同样提问不触发工具
 *   3. setActiveToolsByName(全 7 工具) → 工具恢复；提问触发工具执行
 */
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { createM0Session } from "./common";

const runtime = await createM0Session();
const session = runtime.session;

const toolNames = () => session.agent.state.tools.map((t) => t.name);

let toolRuns: string[] = [];
session.subscribe((event) => {
  if (event.type === "tool_execution_start") toolRuns.push(event.toolName);
});

// --- 1. 默认工具 ---
console.log("[1] 默认工具:", toolNames().join(", "));
if (!toolNames().includes("read")) {
  console.error("[1] 失败：默认无 read 工具");
  process.exit(1);
}

// --- 2. Chat 模式：清空工具 ---
session.setActiveToolsByName([]);
console.log("[2] chat 模式工具:", toolNames().length === 0 ? "(空)" : toolNames().join(", "));
if (toolNames().length !== 0) {
  console.error("[2] 失败：chat 模式工具未清空");
  process.exit(1);
}

toolRuns = [];
await session.prompt("用一句话说：你当前能操作文件系统吗？");
console.log(`[2] chat 模式工具执行次数: ${toolRuns.length}（期望 0）`);
if (toolRuns.length > 0) {
  console.error("[2] 失败：chat 模式不应执行工具");
  process.exit(1);
}

// --- 3. Command 模式：全 7 工具 ---
const ALL_TOOLS = ["read", "bash", "edit", "write", "grep", "find", "ls"];
session.setActiveToolsByName(ALL_TOOLS);
console.log("[3] command 模式工具:", toolNames().join(", "));
if (toolNames().join() !== ALL_TOOLS.join()) {
  console.error("[3] 失败：工具集不完整");
  process.exit(1);
}

toolRuns = [];
await session.prompt("用 ls 工具列出当前目录下的文件，然后告诉我你看到了什么。");
console.log(`[3] command 模式工具执行: [${toolRuns.join(", ")}]（期望包含 ls）`);
if (!toolRuns.includes("ls")) {
  console.error("[3] 失败：command 模式未执行 ls");
  process.exit(1);
}

session.dispose();
await runtime.dispose();
console.log("[完成] 模式切换演示通过 ✅");