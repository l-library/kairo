/**
 * M1 补充验收：拒绝路径 + abort 解锁 + 重启恢复最近会话
 *
 *   G. 拒绝 edit → 文件不落盘，turn 正常结束（不卡死）
 *   H. 审批挂起时 abort → 审批被拒绝、turn 结束
 *   I. kill daemon 重启 → 恢复最近会话（会话 id 不变）
 */
import { WebSocket } from "ws";
import { readFileSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";

const BASE = "http://127.0.0.1:44811";
const TOKEN = readFileSync(join(process.env.HOME, ".local/state/kairo/token"), "utf8").trim();
const WORKDIR = process.env.KAIRO_WORKDIR ?? join(process.env.HOME, ".local/share/kairo/workdir");
const TESTFILE = join(WORKDIR, "m1-reject.txt");

let failed = 0;
const check = (name, ok, detail = "") => {
  console.log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failed++;
};
const api = async (method, path, body) => {
  const res = await fetch(BASE + path, {
    method,
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => ({})) };
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** G. 拒绝写操作 */
await api("POST", "/api/mode", { mode: "command" });
writeFileSync(TESTFILE, "original\n", "utf8");
{
  const ws = new WebSocket(`ws://127.0.0.1:44811/ws?token=${TOKEN}`);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("G 超时")), 90000);
    ws.on("open", () =>
      void api("POST", "/api/prompt", { message: "用 edit 工具把 m1-reject.txt 的 original 改成 changed" }),
    );
    ws.on("message", (raw) => {
      const ev = JSON.parse(String(raw));
      if (ev.type === "approval_requested") {
        ws.send(JSON.stringify({ type: "reject", id: ev.id })); // 拒绝
      }
      if (ev.type === "approval_resolved") {
        check("G. 收到 approval_resolved(拒绝)", ev.allowed === false);
      }
      if (ev.type === "agent_end") {
        clearTimeout(timer);
        resolve();
      }
    });
    ws.on("error", reject);
  });
  ws.close();
  const content = readFileSync(TESTFILE, "utf8");
  check("G. 拒绝后文件未变化", content === "original\n", JSON.stringify(content));
  // turn 未卡死：agent_end 已收到即证明
  check("G. 拒绝后 turn 正常结束", true);
}

/** H. 审批挂起时 abort（模拟用户关闭面板） */
let approvalStuck = null;
{
  const ws = new WebSocket(`ws://127.0.0.1:44811/ws?token=${TOKEN}`);
  let gotEnd = false;
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("H 超时")), 90000);
    ws.on("open", () =>
      void api("POST", "/api/prompt", { message: "用 write 工具把 m1-reject.txt 写成 'payload A'" }),
    );
    ws.on("message", (raw) => {
      const ev = JSON.parse(String(raw));
      if (ev.type === "approval_requested") {
        approvalStuck = ev.id;
        // 模拟面板关闭：发 cancel（daemon 侧 abort + rejectAll）
        void api("POST", "/api/abort");
      }
      if (ev.type === "approval_resolved" && ev.id === approvalStuck) {
        check("H. abort 触发审批被拒绝", ev.allowed === false);
      }
      if (ev.type === "agent_end") {
        gotEnd = true;
        clearTimeout(timer);
        resolve();
      }
    });
    ws.on("error", reject);
  });
  ws.close();
  check("H. abort 后 turn 结束（未卡死）", gotEnd);
}

/** I. kill daemon 重启 → 恢复最近会话 */
{
  const before = (await api("GET", "/api/status")).json.status.sessionId;
  // kill 由外部脚本执行（本测试由配套脚本驱动）
  const { execFileSync } = await import("node:child_process");
  execFileSync("pkill", ["-f", "node dist/main.js"]);
  await sleep(1500);
  execFileSync("node", ["dist/main.js"], { cwd: new URL("..", import.meta.url).pathname, stdio: "ignore", detached: true });
  await sleep(2500);
  const after = (await api("GET", "/api/status")).json.status.sessionId;
  check("I. 重启后恢复最近会话", after === before, `before=${before} after=${after}`);
}

rmSync(TESTFILE, { force: true });
console.log(`\n== 结果: ${failed === 0 ? "全部通过" : `${failed} 项失败`} ==`);
process.exit(failed > 0 ? 1 : 0);