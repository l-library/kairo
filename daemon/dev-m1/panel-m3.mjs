import { connect } from "node:net";
import { writeFileSync, readFileSync, rmSync } from "node:fs";
const sock = connect(process.env.HOME + "/.local/state/kairo/panel.sock");
const f = process.env.HOME + "/.local/share/kairo/workdir/m3-test.txt";
rmSync(f, { force: true });
writeFileSync(f, "keep-me\n", "utf8");

const results = [];
const check = (n, ok) => { results.push([n, ok]); console.log(`${ok ? "✅" : "❌"} ${n}`); };

sock.on("connect", () => {
  sock.write(JSON.stringify({ type: "mode", mode: "command" }) + "\n");
  setTimeout(() => {
    sock.write(JSON.stringify({ type: "prompt", message: "使用 bash 工具执行命令: echo KAIRO_M3_OK" }) + "\n");
  }, 200);
});

let bufs = "";
let phase = 0; // 0: bash测试 1: 拒绝测试 2: 中止测试
let rejectPrompted = false;
let abortPrompted = false;

sock.on("data", (d) => {
  bufs += d; let i;
  while ((i = bufs.indexOf("\n")) >= 0) {
    const line = bufs.slice(0, i); bufs = bufs.slice(i + 1);
    if (!line.trim()) continue;
    const ev = JSON.parse(line);
    switch (phase) {
      case 0:
        if (ev.type === "approval_requested" && ev.toolName === "bash") {
          check("bash 触发确认卡（含命令+cwd）", !!ev.command && !!ev.cwd, ev.command);
          sock.write(JSON.stringify({ type: "approve", id: ev.id }) + "\n");
        }
        if (ev.type === "tool_execution_end" && ev.toolName === "bash") {
          check("bash 执行结果含输出", JSON.stringify(ev.result).includes("KAIRO_M3_OK"));
        }
        if (ev.type === "agent_end" && phase === 0) {
          phase = 1;
          setTimeout(() => {
            sock.write(JSON.stringify({ type: "prompt", message: "使用 edit 工具把 m3-test.txt 的 keep-me 改为 changed" }) + "\n");
          }, 300);
        }
        break
      case 1:
        if (ev.type === "approval_requested" && ev.toolName === "edit") {
          rejectPrompted = true;
          sock.write(JSON.stringify({ type: "reject", id: ev.id }) + "\n");
        }
        if (ev.type === "approval_resolved" && rejectPrompted) {
          check("拒绝 edit 返回 approval_resolved(false)", ev.allowed === false);
          rejectPrompted = false;
        }
        if (ev.type === "agent_end" && phase === 1) {
          const content = readFileSync(f, "utf8");
          check("拒绝后文件未落盘", content === "keep-me\n", JSON.stringify(content));
          phase = 2;
          // 中止测试：发一个长流式问题后立刻 cancel
          sock.write(JSON.stringify({ type: "prompt", message: "详细解释量子计算原理，写 500 字" }) + "\n");
          setTimeout(() => sock.write(JSON.stringify({ type: "cancel" }) + "\n"), 1500);
        }
        break
      case 2:
        if (ev.type === "agent_end" && phase === 2) {
          check("中止后 turn 正常结束（未卡死）", true);
          sock.destroy();
          const failed = results.filter(([, ok]) => !ok).length;
          console.log(`== M3 结果: ${results.length - failed}/${results.length} ==`);
          process.exit(failed ? 1 : 0);
        }
        break
    }
  }
});
setTimeout(() => { console.log("超时"); process.exit(1); }, 120000);
