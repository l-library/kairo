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
  | { type: "get_status" };

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
  | { type: "session_active"; id: string; name?: string }
  | { type: "session_list"; sessions: SessionListItem[] }
  | { type: "status"; status: SessionStatus }
  | { type: "error"; code: string; message: string };

export interface SessionListItem {
  id: string;
  path: string;
  name?: string;
  cwd: string;
  createdAt?: string;
  modifiedAt?: string;
  messageCount?: number;
}

export interface SessionStatus {
  mode: string;
  sessionId: string;
  sessionName?: string;
  streaming: boolean;
  pendingApprovals: number;
}

export type BroadcastFn = (event: WsServerEvent) => void;