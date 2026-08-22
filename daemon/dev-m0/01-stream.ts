/**
 * M0 演示 ①：流式文本
 * 建会话 → 订阅 message_update(text_delta) → 流式输出 → agent_end 结束
 */
import { createM0Session } from "./common";

const runtime = await createM0Session();
const session = runtime.session;

let text = "";
let thought = 0;

session.subscribe((event) => {
  switch (event.type) {
    case "message_update":
      if (event.assistantMessageEvent.type === "text_delta") {
        process.stdout.write(event.assistantMessageEvent.delta);
        text += event.assistantMessageEvent.delta;
      } else if (event.assistantMessageEvent.type === "thinking_delta") {
        thought += event.assistantMessageEvent.delta.length;
      }
      break;
    case "message_start":
      console.log(`\n[message_start] ${event.message.role === "assistant" ? "助手" : "用户"}`);
      break;
    case "message_end":
      console.log(`\n[message_end] 累计文本 ${text.length} 字符，思考 ${thought} 字符`);
      break;
    case "agent_end":
      console.log(`[agent_end] willRetry=${event.willRetry}`);
      break;
  }
});

await session.prompt("用一句中文介绍你自己，不要超过 40 个字。");
console.log("\n[完成] 流式文本演示通过 ✅");
session.dispose();
await runtime.dispose();
process.exit(0);