/**
 * i18n.ts — daemon 用户可见文案双语（zh / en）
 *
 * 说明：daemon 内部日志/注释保持中文（非用户可见）；只有真正展示给用户
 * （广播 error / HTTP 响应 / 审批拒绝 reason / 会话命名提示 / 模式系统提示）
 * 的字符串走本模块。语言来源：UI 连接后上报（locale_set），持久化到
 * settings.json 的 locale 字段；未设置时默认 zh（与历史行为一致）。
 */

export type Lang = "zh" | "en";

const zhTable: Record<string, string> = {
  // ---- 通用 ----
  unknown_error: "未知错误: {err}",
  // ---- 审批（approval.ts） ----
  rejected_by_user: "该操作被用户拒绝",
  // ---- 会话（client-rpc.ts / http.ts） ----
  session_not_found: "会话不存在: {id}",
  active_session: "不能删除当前活动会话",
  active_session_http: "不能删除当前活动会话，请先切换或新建会话",
  // ---- HTTP 参数校验（http.ts） ----
  bad_json: "请求体不是合法 JSON",
  message_required: "message 字段必填（非空字符串）",
  mode_invalid: "mode 字段必须为 chat 或 command",
  route_not_found: "未找到路由: {method} {path}",
  // ---- 插件 / 提供商（client-rpc.ts / agent.ts） ----
  plugin_install_failed: "安装插件失败: {err}",
  plugin_remove_failed: "移除插件失败: {err}",
  provider_add_failed: "添加提供商失败: {err}",
  provider_remove_failed: "移除提供商失败: {err}",
  provider_id_invalid: "提供商 id 只能包含字母、数字、点、下划线、连字符",
  api_key_required: "api key 不能为空",
  reserved_id: "kairo 为保留 id",
  cannot_remove_active_provider: "不能移除当前正在使用的提供商，请先切换到其它提供商",
  // ---- 模型 / 思维等级（agent.ts） ----
  model_not_found: "模型不存在: {id}",
  thinking_unsupported: "当前模型不支持思维等级: {level}（可用: {levels}）",
  // ---- 模型目录探测（agent.ts） ----
  fetch_conn_failed: "无法连接 {url}，请检查 baseUrl",
  fetch_list_failed: "模型目录探测失败 {url}: HTTP {status}",
  fetch_list_empty: "模型目录探测返回空（{url} 不是 OpenAI 兼容端点？）",
  // ---- 会话命名（agent.ts 内联系统提示） ----
  naming_prompt_system: "你是 kairo 的会话命名助手，只输出简洁的中文短标题。",
  naming_prompt_user:
    "请为下面的对话生成一个简洁的中文标题（不超过 12 个字）。只输出标题本身，不要引号、标点或任何解释。\n\n对话开头：{text}",
};

const enTable: Record<string, string> = {
  // ---- 通用 ----
  unknown_error: "Unknown error: {err}",
  // ---- 审批（approval.ts） ----
  rejected_by_user: "This operation was rejected by the user.",
  // ---- 会话（client-rpc.ts / http.ts） ----
  session_not_found: "Session not found: {id}",
  active_session: "Cannot delete the active session",
  active_session_http: "Cannot delete the active session — switch to or create another session first",
  // ---- HTTP 参数校验（http.ts） ----
  bad_json: "Request body is not valid JSON",
  message_required: "The \"message\" field is required (non-empty string)",
  mode_invalid: "The \"mode\" field must be \"chat\" or \"command\"",
  route_not_found: "Route not found: {method} {path}",
  // ---- 插件 / 提供商（client-rpc.ts / agent.ts） ----
  plugin_install_failed: "Failed to install plugin: {err}",
  plugin_remove_failed: "Failed to remove plugin: {err}",
  provider_add_failed: "Failed to add provider: {err}",
  provider_remove_failed: "Failed to remove provider: {err}",
  provider_id_invalid: "Provider id may only contain letters, digits, periods, underscores and hyphens",
  api_key_required: "API key must not be empty",
  reserved_id: "\"kairo\" is a reserved id",
  cannot_remove_active_provider: "Cannot remove the provider in use — switch to another provider first",
  // ---- 模型 / 思维等级（agent.ts） ----
  model_not_found: "Model not found: {id}",
  thinking_unsupported: "Thinking level \"{level}\" is not supported by the current model (available: {levels})",
  // ---- 模型目录探测（agent.ts） ----
  fetch_conn_failed: "Cannot reach {url} — check the baseUrl",
  fetch_list_failed: "Model catalog probe failed {url}: HTTP {status}",
  fetch_list_empty: "Model catalog probe returned nothing ({url} is not an OpenAI-compatible endpoint?)",
  // ---- 会话命名（agent.ts 内联系统提示） ----
  naming_prompt_system: "You are kairo's session-naming assistant. Output only a short, concise English title.",
  naming_prompt_user:
    "Generate a concise English title for the conversation below (max 12 words). Output only the title itself — no quotes, punctuation or explanation.\n\nConversation start: {text}",
};

/** 取当前语言的文案（en 缺失回退 zh，再回退键名） */
export function t(lang: Lang, key: string, params?: Record<string, string | number>): string {
  const table = lang === "en" ? enTable : zhTable;
  let s = table[key];
  if (s === undefined) s = zhTable[key];
  if (s === undefined) s = key;
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      s = s.split(`{${k}}`).join(String(v));
    }
  }
  return s;
}

export function isLang(v: unknown): v is Lang {
  return v === "zh" || v === "en";
}

/**
 * 带文案键的错误：抛出时携带 key/params，展示时按当前语言格式化
 * （避免上游把已格式化的中文串透传给 UI）。
 */
export class KairoError extends Error {
  readonly key: string;
  readonly params: Record<string, string | number>;
  constructor(key: string, params?: Record<string, string | number>) {
    super(t("zh", key, params ?? {}));
    this.name = "KairoError";
    this.key = key;
    this.params = params ?? {};
  }
}

/** 统一错误文案：KairoError 按语言格式化；其余（SDK 等）透传原文 */
export function localizeError(err: unknown, lang: Lang): string {
  if (err instanceof KairoError) return t(lang, err.key, err.params);
  return err instanceof Error ? err.message : String(err);
}