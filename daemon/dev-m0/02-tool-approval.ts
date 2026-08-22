/**
 * M0 演示 ②：工具事件链 + tool_call 阻塞钩子 + diff + 批准后执行
 *
 * 流程：
 *   1. 在临时 workdir 创建 test.txt
 *   2. 内联扩展注册 tool_call 钩子：edit/write 生成 diff → 挂起等待"审批"
 *   3. 审批 Promise 由注册表持有，3 秒后模拟"批准"→ 放行执行
 *   4. 订阅工具事件链 (tool_execution_start/update/end) 并验证文件已更新
 */
import { mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { generateDiffString, isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { KAIRO_AGENT_DIR } from "./common";
import {
  createAgentSessionRuntime,
  type CreateAgentSessionRuntimeFactory,
  createAgentSessionFromServices,
  createAgentSessionServices,
  SessionManager,
} from "@earendil-works/pi-coding-agent";

const workdir = join(tmpdir(), "kairo-m0-02");
rmSync(workdir, { recursive: true, force: true });
mkdirSync(workdir, { recursive: true });
writeFileSync(join(workdir, "test.txt"), "Hello kairo!\n这是一行中文。\n", "utf8");

/** 审批注册表：只有"daemon"自己（此处为脚本主流程）能 resolve */
const pending = new Map<
  string,
  { resolve: (allowed: boolean) => void; toolName: string; args: unknown }
>();

const resourceLoaderOptions = {
  extensionFactories: [
    (pi) => {
      pi.on("tool_call", async (event) => {
        if (isToolCallEventType("edit", event) || isToolCallEventType("write", event)) {
          // 读目标文件 → 生成 unified diff（只读操作不进审批门）
          const target = event.input.path.startsWith("/")
            ? event.input.path
            : join(workdir, event.input.path);
          let diffText = "(新文件)";
          try {
            const old = readFileSync(target, "utf8");
            // edit 工具入参是 edits[]，先把每个替换应用到旧内容上再算 diff
            let newContent = old;
            for (const e of event.input.edits ?? []) {
              newContent = newContent.split(e.oldText).join(e.newText);
            }
            const { diff } = generateDiffString(old, newContent);
            diffText = diff;
          } catch {
            /* 文件不存在 = 新建 */
          }
          console.log(`\n[审批门] ${event.toolName} -> ${event.input.path}`);
          console.log(diffText.split("\n").slice(0, 12).join("\n"));

          // 挂起直到审批：注册 promise，主流程 3 秒后批准
          const id = event.toolCallId;
          await new Promise<void>((resolve) => {
            pending.set(id, {
              resolve: (allowed) => {
                if (allowed) console.log(`[审批门] 已批准 ${event.toolName} 执行 ✅`);
                else console.log(`[审批门] 用户拒绝 ❌`);
                resolve();
              },
              toolName: event.toolName,
              args: event.input,
            });
          });
          const decision = pending.get(id)!;
          pending.delete(id);
          return undefined; // 放行
        }
        // 只读工具：不阻塞，直接放行
        console.log(`[审批门] 只读放行: ${event.toolName}`);
        return undefined;
      });
    },
  ],
};

const createRuntime: CreateAgentSessionRuntimeFactory = async ({
  cwd,
  agentDir,
  sessionManager,
  sessionStartEvent,
}) => {
  const services = await createAgentSessionServices({ cwd, agentDir, resourceLoaderOptions });
  return {
    ...(await createAgentSessionFromServices({ services, sessionManager, sessionStartEvent })),
    services,
    diagnostics: services.diagnostics,
  };
};

const runtime = await createAgentSessionRuntime(createRuntime, {
  cwd: workdir,
  agentDir: KAIRO_AGENT_DIR,
  sessionManager: SessionManager.inMemory(),
});
const session = runtime.session;

session.subscribe((event) => {
  switch (event.type) {
    case "tool_execution_start":
      console.log(`[事件] tool_execution_start ${event.toolName} args=${JSON.stringify(event.args)}`);
      break;
    case "tool_execution_update":
      // 仅示意，通常内容较多
      break;
    case "tool_execution_end":
      console.log(`[事件] tool_execution_end ${event.toolName} isError=${event.isError}`);
      break;
    case "turn_end":
      console.log(`[事件] turn_end，本轮工具结果 ${event.toolResults.length} 条`);
      break;
  }
});

// 模拟 daemon 侧审批：监听并自动批准（演示脚本约定 3 秒后批准）
const autoApprove = setInterval(() => {
  for (const [id, p] of pending) {
    if (p.toolName === "edit" || p.toolName === "write") {
      p.resolve(true);
    }
  }
}, 3000);

await session.prompt("把 test.txt 中的 'Hello kairo!' 改成 'Hello Kairo M0!'。");
clearInterval(autoApprove);

const content = readFileSync(join(workdir, "test.txt"), "utf8");
if (content.includes("Hello Kairo M0!")) {
  console.log("[验证] 文件内容已更新 ✅");
  console.log(content);
} else {
  console.error("[验证] 文件未被修改 ❌ 内容如下：");
  console.error(content);
  process.exit(1);
}
session.dispose();
await runtime.dispose();
console.log("[完成] 工具链 + 审批门演示通过 ✅");