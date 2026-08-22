/**
 * http.ts — REST API（控制面，请求/响应）
 *
 * 鉴权：所有请求校验 `Authorization: Bearer <token>`。
 */
import type { ServerResponse, IncomingMessage } from "node:http";
import type { AgentBridge } from "./agent.js";
import type { KairoSessionManager } from "./session-manager.js";
import type { KairoMode } from "./modes.js";

export interface HttpDeps {
  agent: AgentBridge;
  sessions: KairoSessionManager;
  token: string;
}

interface KairoHttpError extends Error {
  status: number;
}

function error(status: number, message: string): KairoHttpError {
  const err = new Error(message) as KairoHttpError;
  err.status = status;
  return err;
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(data),
  });
  res.end(data);
}

async function readBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const text = Buffer.concat(chunks).toString("utf8");
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw error(400, "请求体不是合法 JSON");
  }
}

export function startHttpApi(deps: HttpDeps): (req: IncomingMessage, res: ServerResponse) => void {
  const { agent, sessions, token } = deps;

  async function handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    // 鉴权
    const auth = req.headers.authorization ?? "";
    if (auth !== `Bearer ${token}`) {
      sendJson(res, 401, { error: "unauthorized" });
      return;
    }
    const url = new URL(req.url ?? "/", "http://kairo.local");
    const path = url.pathname;
    const method = req.method ?? "GET";
    const body = method === "GET" ? {} : ((await readBody(req)) as Record<string, unknown>);

    try {
      switch (true) {
        // ---------- 健康检查 ----------
        case method === "GET" && path === "/api/health":
          sendJson(res, 200, {
            ok: true,
            status: agent.status(),
          });
          break;

        // ---------- 会话 ----------
        case method === "GET" && path === "/api/sessions":
          sendJson(res, 200, { sessions: await sessions.list() });
          break;

        case method === "POST" && path === "/api/sessions":
          sendJson(res, 200, await agent.newSession(typeof body.name === "string" ? body.name : undefined));
          break;

        case method === "POST" && /\/api\/sessions\/[^/]+\/activate$/.test(path): {
          const id = decodeURIComponent(path.split("/")[3]!);
          const target = await sessions.findPathById(id);
          if (!target) throw error(404, `会话不存在: ${id}`);
          sendJson(res, 200, await agent.switchSession(target));
          break;
        }

        case method === "DELETE" && /\/api\/sessions\/[^/]+$/.test(path): {
          const id = decodeURIComponent(path.split("/")[3]!);
          if (agent.status().sessionId === id) {
            throw error(409, "不能删除当前活动会话，请先切换或新建会话");
          }
          const deleted = await sessions.deleteById(id);
          if (!deleted) throw error(404, `会话不存在: ${id}`);
          sendJson(res, 200, { deleted: true, id });
          break;
        }

        // ---------- 对话 ----------
        case method === "POST" && path === "/api/prompt": {
          const message = body.message;
          if (typeof message !== "string" || message.trim() === "") {
            throw error(400, "message 字段必填（非空字符串）");
          }
          await agent.prompt(message);
          sendJson(res, 200, { accepted: true });
          break;
        }

        case method === "POST" && path === "/api/abort":
          await agent.abort();
          sendJson(res, 200, { aborted: true });
          break;

        // ---------- 模式 ----------
        case method === "POST" && path === "/api/mode": {
          const mode = body.mode;
          if (mode !== "chat" && mode !== "command") {
            throw error(400, "mode 字段必须为 chat 或 command");
          }
          await agent.setMode(mode as KairoMode);
          sendJson(res, 200, { mode });
          break;
        }

        case method === "GET" && path === "/api/status":
          sendJson(res, 200, { status: agent.status() });
          break;

        default:
          throw error(404, `未找到路由: ${method} ${path}`);
      }
    } catch (err) {
      const status = (err as KairoHttpError)?.status ?? 500;
      const message = err instanceof Error ? err.message : String(err);
      if (status >= 500) console.error("[http] 处理失败:", err);
      sendJson(res, status, { error: message });
    }
  }

  return (req, res) => {
    void handle(req, res);
  };
}