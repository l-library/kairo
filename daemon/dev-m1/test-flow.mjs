/**
 * M1 验收脚本：HTTP 控制面 + WS 事件流 + 确认门全流程
 *
 * 场景：
 *   A. chat 模式流式回复
 *   B. command 模式 read（只读自动放行）
 *   C. command 模式 edit → approval_requested → WS approve → 落盘
 *   D. 模式切换 chat（禁止写，工具集为空）
 *   E. 会话 新建/列表/激活/删除
 *   F. WS 鉴权（错误 token 应被拒绝）
 */
import { WebSocket } from "ws";
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";

const BASE = "http://127.0.0.1:44811";
const TOKEN = readFileSync(join(process.env.HOME, ".local/state/kairo/token"), "utf8").trim();
const WS_URL = `ws://127.0.0.1:44811/ws?token=${TOKEN}`;

const WORKDIR = process.env.KAIRO_WORKDIR ?? join(process.env.HOME, ".local/share/kairo/workdir");
const TESTFILE = join(WORKDIR, "m1-test.txt");

const results = [];
function check(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "✅" : "❌"} ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) process.exitCode = 1;
}

async function api(method, path, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, json };
}

/** 建立 WS 连接，收集事件直到 predicate 满足 */
function wsCollect(predicate, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    const events = [];
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error("WS 收集超时，收到事件: " + JSON.stringify(events.map((e) => e.type))));
    }, timeoutMs);
    ws.on("open", () => {});
    ws.on("message", (raw) => {
      const ev = JSON.parse(String(raw));
      events.push(ev);
      if (predicate(ev, events)) {
        clearTimeout(timer);
        ws.close();
        resolve(events);
      }
    });
    ws.on("error", (e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- F. 鉴权 ----------
{
  const res = await fetch(BASE + "/api/status", { headers: { Authorization: "Bearer wrong-token" } });
  check("F. 错误 token 返回 401", res.status === 401, `status=${res.status}`);
  const wsBad = await new Promise((resolve) => {
    const ws = new WebSocket("ws://127.0.0.1:44811/ws?token=nope");
    ws.on("close", (code) => resolve(code));
    ws.on("error", () => {});
  });
  check("F. WS 错误 token 被拒绝", wsBad === 1006, `closeCode=${wsBad}`);
}

// ---------- A. chat 流式 ----------
await api("POST", "/api/mode", { mode: "chat" });
{
  const stream = wsCollect((ev) => ev.type === "agent_end");
  await api("POST", "/api/prompt", { message: "用一句话说明你是 kairo 助手（不超过 30 字）" });
  const events = await stream;
  const text = events.filter((e) => e.type === "message_update" && e.kind === "text_delta")
    .map((e) => e.delta).join("");
  const toolRuns = events.filter((e) => e.type === "tool_execution_start");
  check("A. chat 流式文本回复", text.length > 0, `回复 ${text.slice(0, 40)}…`);
  check("A. chat 模式无工具执行", toolRuns.length === 0, `tools=${toolRuns.length}`);
}

// ---------- B. command 只读 ----------
await api("POST", "/api/mode", { mode: "command" });
{
  writeFileSync(TESTFILE, "第一行\n第二行\n", "utf8");
  const stream = wsCollect((ev) => ev.type === "agent_end");
  await api("POST", "/api/prompt", { message: "用 read 工具读取 m1-test.txt 的内容" });
  const events = await stream;
  const reads = events.filter((e) => e.type === "tool_execution_start" && e.toolName === "read");
  const approvals = events.filter((e) => e.type === "approval_requested");
  check("B. read 只读自动放行", reads.length >= 1, `reads=${reads.length}`);
  check("B. read 不触发审批", approvals.length === 0, `approvals=${approvals.length}`);
}

// ---------- C. edit → 审批 → 批准 → 落盘 ----------
{
  writeFileSync(TESTFILE, "Hello kairo\n第二行\n", "utf8");
  const ws = new WebSocket(WS_URL);
  const seen = [];
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("C 超时")), 90000);
    ws.on("open", () => {
      // 连接建立后再发送 prompt
      void api("POST", "/api/prompt", { message: "用 edit 工具把 m1-test.txt 中的 'Hello kairo' 改成 'Hello kairo M1'" });
    });
    ws.on("message", (raw) => {
      const ev = JSON.parse(String(raw));
      seen.push(ev.type);
      if (ev.type === "approval_requested" && ev.toolName === "edit") {
        check("C. 收到 edit 审批请求（带 diff）", typeof ev.diff === "string" && ev.diff.length > 0, `diff=${ev.diff.split("\n")[0] ?? ""}`);
        ws.send(JSON.stringify({ type: "approve", id: ev.id }));
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
  check("C. 批准后文件已更新", content.includes("Hello kairo M1"), content.split("\n")[0]);
  check("C. 事件链含 tool_execution_start/end", seen.includes("tool_execution_start") && seen.includes("tool_execution_end"), seen.join(","));
}

// ---------- D. 切回 chat：禁止写 ----------
await api("POST", "/api/mode", { mode: "chat" });
{
  const { json } = await api("GET", "/api/status");
  check("D. 模式切换生效", json.status.mode === "chat", `mode=${json.status.mode}`);
}

// ---------- E. 会话管理 ----------
{
  const before = await api("GET", "/api/sessions");
  const count0 = before.json.sessions.length;
  const { json: created } = await api("POST", "/api/sessions", { name: "M1 验收会话" });
  const newId = created.id;

  // 新会话在收到首条消息后才落盘，先发一条消息使其持久化
  const stream = wsCollect((ev) => ev.type === "agent_end");
  await api("POST", "/api/prompt", { message: "你好，简短回复（不超过 10 字）" });
  await stream;
  await sleep(300); // 等待 JSONL 落盘

  const after = await api("GET", "/api/sessions");
  const createdEntry = after.json.sessions.find((s) => s.id === newId);
  check("E. 新建会话出现在列表", after.json.sessions.length === count0 + 1, `count=${after.json.sessions.length}`);
  check("E. 新会话名生效", createdEntry?.name === "M1 验收会话", `name=${createdEntry?.name}`);

  // 激活回第一个会话
  const firstId = before.json.sessions[0]?.id;
  if (firstId) {
    const act = await api("POST", `/api/sessions/${firstId}/activate`);
    check("E. 激活历史会话", act.status === 200, `id=${firstId}`);
  } else {
    check("E. 激活历史会话", true, "（无历史会话，跳过）");
  }

  // 删除 A 会话（非活动）
  const delTarget = after.json.sessions.find((s) => s.id !== firstId);
  if (delTarget) {
    const del = await api("DELETE", `/api/sessions/${delTarget.id}`);
    check("E. 删除历史会话", del.status === 200 && del.json.deleted === true, `id=${delTarget.id}`);
  } else {
    check("E. 删除历史会话", true, "（无可删会话，跳过）");
  }

  // 删除活动会话应 409
  const activeId = (await api("GET", "/api/status")).json.status.sessionId;
  const delActive = await api("DELETE", `/api/sessions/${activeId}`);
  check("E. 删除活动会话被拒绝(409)", delActive.status === 409, `status=${delActive.status}`);
}

// ---------- 清理 ----------
rmSync(TESTFILE, { force: true });
const failed = results.filter((r) => !r.ok).length;
console.log(`\n== 结果: ${results.length - failed}/${results.length} 通过 ==`);
process.exit(failed > 0 ? 1 : 0);