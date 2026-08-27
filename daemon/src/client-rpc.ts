/**
 * client-rpc.ts — 客户端事件处理（WS 与 panel-socket 共用）
 *
 * 除 approve/reject/cancel 外，面板控制类（prompt/mode/sessions/status）
 * 也通过事件通道处理，同一套逻辑对 WS 客户端与 Unix socket 客户端生效。
 */
import type { AgentBridge } from "./agent.js";
import type { ApprovalRegistry } from "./approval.js";
import type { KairoSessionManager } from "./session-manager.js";
import type { BroadcastFn, LocaleStore, WsClientEvent } from "./ws-types.js";
import { isLang, localizeError, t, type Lang } from "./i18n.js";

export interface ClientRpcDeps {
  approvals: ApprovalRegistry;
  agent: AgentBridge;
  sessions: KairoSessionManager;
  broadcast: BroadcastFn;
  /** 主题持久化（settings.json 的 theme 字段） */
  themeStore: { get: () => string; set: (theme: string) => void };
  /** 语言持久化（settings.json 的 locale 字段） */
  localeStore: LocaleStore;
}

export async function handleClientEvent(
  msg: WsClientEvent,
  deps: ClientRpcDeps,
): Promise<void> {
  const { approvals, agent, sessions, broadcast, themeStore, localeStore } = deps;
  // 当前生效语言（未设置时默认 zh，与历史行为一致）
  const lang: Lang = localeStore.get() === "en" ? "en" : "zh";
  switch (msg.type) {
    case "approve":
    case "reject":
      approvals.respond(msg.id, msg.type === "approve");
      break;
    case "cancel":
      await agent.abort();
      break;
    case "prompt": {
      if (typeof msg.message !== "string" || msg.message.trim() === "") return;
      // 面板隐藏时中止当前流式；发送新消息走 prompt
      await agent.prompt(msg.message);
      break;
    }
    case "mode": {
      if (msg.mode === "chat" || msg.mode === "command") {
        await agent.setMode(msg.mode);
      }
      break;
    }
    case "sessions_new": {
      const { id } = await agent.newSession(
        typeof msg.name === "string" && msg.name ? msg.name : undefined,
      );
      broadcast({ type: "session_list", sessions: await sessions.listWithActive(agent.activeSessionInfo()) });
      void id;
      break;
    }
    case "sessions_activate": {
      const target = await sessions.findPathById(msg.id);
      if (!target) {
        broadcast({ type: "error", code: "session_not_found", message: t(lang, "session_not_found", { id: msg.id }) });
        return;
      }
      await agent.abort(); // 切换前停止当前流式
      await agent.switchSession(target);
      broadcast({ type: "session_list", sessions: await sessions.listWithActive(agent.activeSessionInfo()) });
      break;
    }
    case "sessions_delete": {
      const active = agent.sessionId;
      if (active === msg.id) {
        broadcast({ type: "error", code: "active_session", message: t(lang, "active_session") });
        return;
      }
      const deleted = await sessions.deleteById(msg.id);
      if (!deleted) {
        broadcast({ type: "error", code: "session_not_found", message: t(lang, "session_not_found", { id: msg.id }) });
        return;
      }
      broadcast({ type: "session_list", sessions: await sessions.listWithActive(agent.activeSessionInfo()) });
      break;
    }
    case "theme_set": {
      if (msg.theme === "dark" || msg.theme === "light") {
        themeStore.set(msg.theme);
        broadcast({ type: "theme_changed", theme: msg.theme });
      }
      break;
    }
    case "theme_get":
      broadcast({ type: "theme_changed", theme: themeStore.get() });
      break;
    case "locale_set": {
      if (isLang(msg.locale)) {
        localeStore.set(msg.locale);
        broadcast({ type: "locale_changed", locale: msg.locale });
      }
      break;
    }
    case "locale_get": {
      // 未设置过时不应返回——面板保持按 locale 自动检测
      const v = localeStore.get();
      if (isLang(v)) {
        broadcast({ type: "locale_changed", locale: v });
      }
      break;
    }
    case "models_list":
      broadcast({ type: "models_response", models: agent.listModels() });
      break;
    case "model_set": {
      if (typeof msg.provider === "string" && typeof msg.model === "string") {
        try {
          await agent.setModel(msg.provider, msg.model);
          const cur = agent.currentModelLabel();
          broadcast({
            type: "model_changed",
            provider: cur.provider,
            model: cur.model,
            thinkingLevel: cur.thinkingLevel,
            thinkingLevels: cur.thinkingLevels,
          });
        } catch (err) {
          broadcast({
            type: "error",
            code: "model_set_failed",
            message: localizeError(err, lang),
          });
        }
      }
      break;
    }
    case "thinking_set": {
      if (typeof msg.level === "string") {
        try {
          await agent.setThinkingLevel(msg.level);
          const cur = agent.currentModelLabel();
          broadcast({
            type: "model_changed",
            provider: cur.provider,
            model: cur.model,
            thinkingLevel: cur.thinkingLevel,
            thinkingLevels: cur.thinkingLevels,
          });
        } catch (err) {
          broadcast({
            type: "error",
            code: "thinking_set_failed",
            message: localizeError(err, lang),
          });
        }
      }
      break;
    }
    case "skills_list":
      broadcast({ type: "skills_response", skills: agent.listSkills() });
      break;
    case "plugins_list":
      broadcast({ type: "plugins_response", plugins: agent.listPlugins() });
      break;
    case "plugins_install": {
      const src = typeof msg.source === "string" ? msg.source.trim() : "";
      if (!src) break;
      try {
        await agent.installPlugin(src);
      } catch (err) {
        console.error("[plugins] 安装失败:", err);
        broadcast({
          type: "error",
          code: "plugins_install_failed",
          message: t(lang, "plugin_install_failed", { err: localizeError(err, lang) }),
        });
      }
      break;
    }
    case "plugins_remove": {
      const src = typeof msg.source === "string" ? msg.source.trim() : "";
      if (!src) break;
      try {
        await agent.removePlugin(src);
      } catch (err) {
        console.error("[plugins] 移除失败:", err);
        broadcast({
          type: "error",
          code: "plugins_remove_failed",
          message: t(lang, "plugin_remove_failed", { err: localizeError(err, lang) }),
        });
      }
      break;
    }
    case "providers_list":
      broadcast({ type: "providers_response", providers: agent.listProviders() });
      break;
    case "provider_add": {
      if (typeof msg.id === "string" && typeof msg.apiKey === "string") {
        try {
          const r = await agent.addProvider(msg.id, msg.apiKey, typeof msg.baseUrl === "string" ? msg.baseUrl : undefined);
          console.log(`[providers] 已添加 ${msg.id.trim()}，探测到 ${r.models.length} 个模型`);
        } catch (err) {
          console.error("[providers] 添加失败:", err);
          broadcast({
            type: "error",
            code: "provider_add_failed",
            message: t(lang, "provider_add_failed", { err: localizeError(err, lang) }),
          });
        }
      }
      break;
    }
    case "provider_remove": {
      if (typeof msg.id === "string") {
        try {
          await agent.removeProvider(msg.id);
          console.log(`[providers] 已移除 ${msg.id}`);
        } catch (err) {
          console.error("[providers] 移除失败:", err);
          broadcast({
            type: "error",
            code: "provider_remove_failed",
            message: t(lang, "provider_remove_failed", { err: localizeError(err, lang) }),
          });
        }
      }
      break;
    }
    case "get_status":
      broadcast({ type: "status", status: agent.status() });
      // 同步当前会话状态与历史（重连/主动拉取后 UI 恢复完整视图）
      {
        const active = agent.activeSessionInfo();
        broadcast({ type: "session_active", id: active.id, name: active.name });
        const history = agent.currentHistory();
        if (history.length > 0) broadcast({ type: "session_history", messages: history });
        broadcast({ type: "session_list", sessions: await sessions.listWithActive(active) });
      }
      break;
  }
}