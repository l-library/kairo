/**
 * ws-types.ts — WebSocket 协议类型（客户端 ⇄ 服务端）
 */

/** 客户端 → 服务端 */
export type WsClientEvent =
  | { type: "approve"; id: string }
  | { type: "reject"; id: string }
  | { type: "cancel" }
  // 面板控制（panel-socket 与 WS 共用同一事件族）
  | { type: "prompt"; message: string }
  | { type: "mode"; mode: "chat" | "command" }
  | { type: "sessions_new"; name?: string }
  | { type: "sessions_activate"; id: string }
  | { type: "sessions_delete"; id: string }
  | { type: "theme_set"; theme: "dark" | "light" }
  | { type: "theme_get" }
  | { type: "get_status" }
  // 模型/思维等级
  | { type: "models_list" }
  | { type: "model_set"; provider: string; model: string }
  | { type: "thinking_set"; level: string }
  // 技能（只读展示）/ pi 插件（安装/移除）
  | { type: "skills_list" }
  | { type: "plugins_list" }
  | { type: "plugins_install"; source: string }
  | { type: "plugins_remove"; source: string }
  // 提供商（添加/移除）
  | { type: "providers_list" }
  | { type: "provider_add"; id: string; apiKey: string; baseUrl?: string }
  | { type: "provider_remove"; id: string };

/** 服务端 → 客户端 */
export type WsServerEvent =
  | { type: "message_update"; messageId: string; kind: "text_delta" | "thinking_delta"; delta: string }
  | { type: "message_start"; messageId?: string }
  | { type: "message_end"; messageId?: string }
  | { type: "agent_start" }
  | { type: "agent_end" }
  | { type: "turn_start" }
  | { type: "turn_end"; toolResults: { toolCallId: string; toolName: string; content: unknown }[] }
  | { type: "tool_execution_start"; toolCallId: string; toolName: string; args: unknown }
  | { type: "tool_execution_update"; toolCallId: string; chunk: unknown }
  | { type: "tool_execution_end"; toolCallId: string; isError: boolean; result: unknown }
  | { type: "approval_requested"; id: string; toolName: "edit" | "write" | "bash"; target?: string; diff?: string; command?: string; cwd?: string }
  | { type: "approval_resolved"; id: string; allowed: boolean }
  | { type: "mode_changed"; mode: string }
  | { type: "theme_changed"; theme: string }
  | { type: "session_active"; id: string; name?: string }
  | { type: "session_history"; messages: { role: "user" | "assistant"; text: string }[] }
  | { type: "session_list"; sessions: SessionListItem[] }
  | { type: "status"; status: SessionStatus }
  | { type: "models_response"; models: ModelInfo[] }
  | { type: "model_changed"; provider: string; model: string; thinkingLevel: string; thinkingLevels: string[] }
  | { type: "skills_response"; skills: SkillInfo[] }
  | { type: "plugins_response"; plugins: PluginInfo[] }
  | { type: "plugins_changed"; plugins: PluginInfo[] }
  | { type: "providers_response"; providers: ProviderInfo[] }
  | { type: "providers_changed"; providers: ProviderInfo[] }
  | { type: "error"; code: string; message: string };

export interface SessionListItem {
  id: string;
  path: string;
  name?: string;
  cwd: string;
  createdAt?: string;
  modifiedAt?: string;
  messageCount?: number;
  /** 首条消息文本（用于 UI 列表摘要；未落盘的新会话为空字符串） */
  firstMessage?: string;
}

export interface SessionStatus {
  mode: string;
  sessionId: string;
  sessionName?: string;
  streaming: boolean;
  pendingApprovals: number;
  /** 当前模型标签 provider/id */
  model?: string;
  thinkingLevel?: string;
}

export interface ModelInfo {
  provider: string;
  id: string;
  name: string;
  reasoning: boolean;
  /** 是否已配置鉴权（未鉴权模型不可选） */
  authed: boolean;
  /** 是否为当前模型 */
  current: boolean;
}

export interface SkillInfo {
  name: string;
  description: string;
  path: string;
}

export interface PluginInfo {
  source: string;
  scope: "user" | "project";
  installedPath?: string;
}

export interface ProviderInfo {
  id: string;
  /** 是否已配置密钥（有密钥才可在模型选择器中选择） */
  authed: boolean;
  /** 该提供商下可用模型数 */
  modelCount: number;
}

export type BroadcastFn = (event: WsServerEvent) => void;