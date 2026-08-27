/**
 * http.ts — REST API（控制面，请求/响应）
 *
 * 鉴权：所有请求校验 `Authorization: Bearer <token>`。
 */
import type { ServerResponse, IncomingMessage } from "node:http";
import type { AgentBridge } from "./agent.js";
import type { KairoSessionManager } from "./session-manager.js";
import type { KairoMode } from "./modes.js";
import type { LocaleStore } from "./ws-types.js";
import { t, type Lang } from "./i18n.js";

export interface HttpDeps {
  agent: AgentBridge;
  sessions: KairoSessionManager;
  token: string;
  /** 语言持久化（错误文案按当前语言输出） */
  localeStore: LocaleStore;
}

interface KairoHttpError extends Error {
  status: number;
  /** 文案键（存在则在 catch 中按当前语言格式化；否则透传 message） */
  key?: string;
  params?: Record<string, string | number>;
}

function error(
  status: number,
  key: string,
  params?: Record<string, string | number>,
): KairoHttpError {
  const err = new Error(key) as KairoHttpError;
  err.status = status;
  err.key = key;
  err.params = params;
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
    throw error(400, "bad_json");
  }
}

export function startHttpApi(deps: HttpDeps): (req: IncomingMessage, res: ServerResponse) => void {
  const { agent, sessions, token, localeStore } = deps;
  // 语言按每次请求惰性求值：面板切语言后 HTTP 错误文案即时跟随
  const lang = (): Lang => (localeStore.get() === "en" ? "en" : "zh");

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
    // 注意：readBody 抛出的 400 必须在 try 内——否则未捕获异常会杀掉整个 daemon
    let body: Record<string, unknown> = {};

    try {
      body = method === "GET" ? {} : ((await readBody(req)) as Record<string, unknown>);
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
          sendJson(res, 200, { sessions: await sessions.listWithActive(agent.activeSessionInfo()) });
          break;

        case method === "POST" && path === "/api/sessions":
          sendJson(res, 200, await agent.newSession(typeof body.name === "string" ? body.name : undefined));
          break;

        case method === "POST" && /\/api\/sessions\/[^/]+\/activate$/.test(path): {
          const id = decodeURIComponent(path.split("/")[3]!);
          const target = await sessions.findPathById(id);
          if (!target) throw error(404, "session_not_found", { id });
          sendJson(res, 200, await agent.switchSession(target));
          break;
        }

        case method === "DELETE" && /\/api\/sessions\/[^/]+$/.test(path): {
          const id = decodeURIComponent(path.split("/")[3]!);
          if (agent.status().sessionId === id) {
            throw error(409, "active_session_http");
          }
          const deleted = await sessions.deleteById(id);
          if (!deleted) throw error(404, "session_not_found", { id });
          sendJson(res, 200, { deleted: true, id });
          break;
        }

        // ---------- 对话 ----------
        case method === "POST" && path === "/api/prompt": {
          const message = body.message;
          if (typeof message !== "string" || message.trim() === "") {
            throw error(400, "message_required");
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
            throw error(400, "mode_invalid");
          }
          await agent.setMode(mode as KairoMode);
          sendJson(res, 200, { mode });
          break;
        }

        case method === "GET" && path === "/api/status":
          sendJson(res, 200, { status: agent.status() });
          break;

        default:
          throw error(404, "route_not_found", { method, path });
      }
    } catch (err) {
      const status = (err as KairoHttpError)?.status ?? 500;
      const e = err as KairoHttpError | null;
      const message = e?.key
        ? t(lang(), e.key, e.params ?? {})
        : err instanceof Error
          ? err.message
          : String(err);
      if (status >= 500) console.error("[http] 处理失败:", err);
      sendJson(res, status, { error: message });
    }
  }

  return (req, res) => {
    void handle(req, res);
  };
}