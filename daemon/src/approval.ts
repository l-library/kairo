/**
 * approval.ts — 确认门（核心安全机制）
 *
 * 以"内联扩展 + tool_call 钩子"实现。钩子可按工具分类：
 *   - 只读工具（read/grep/find/ls）：直接放行，不阻塞
 *   - 写工具（edit/write）：生成 unified diff → 挂起等审批
 *   - 执行工具（bash）：命令全文 + cwd → 挂起等审批
 *
 * 审批 Promise 由 daemon 侧 ApprovalRegistry 统一持有：只有 daemon 自己能
 * resolve/reject——abort、WS 断连、会话切换时必须主动拒绝全部 pending，
 * 否则该 turn 永久卡死。
 */
import {
  isToolCallEventType,
  type InlineExtension,
} from "@earendil-works/pi-coding-agent";
import type { KairoConfig } from "./config.js";
import { computeEditDiff, computeWriteDiff } from "./diff.js";

export type ApprovalKind = "edit" | "write" | "bash";

export interface ApprovalRequest {
  id: string;
  toolName: ApprovalKind;
  input: Record<string, unknown>;
  target?: string; // edit/write 目标路径
  diff?: string; // edit/write 的 unified diff
  command?: string; // bash 命令全文
  cwd?: string;
  requestedAt: number;
}

export interface ApprovalEvents {
  onRequest: (req: ApprovalRequest) => void;
  onResolved: (id: string, allowed: boolean) => void;
}

interface PendingEntry {
  request: ApprovalRequest;
  resolve: (allowed: boolean) => void;
  timer: NodeJS.Timeout;
}

/** 审批注册表：单活跃会话，全局最多一个 pending（并行工具 preflight 是顺序的） */
export class ApprovalRegistry {
  private pending = new Map<string, PendingEntry>();

  constructor(
    private config: KairoConfig,
    private events: ApprovalEvents,
  ) {}

  /** 钩子调用：挂起直到批准/拒绝/超时 */
  requestApproval(request: ApprovalRequest): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => {
        this.pending.delete(request.id);
        this.events.onResolved?.(request.id, false);
        resolve(false); // 超时自动拒绝
      }, this.config.approvalTimeoutMs);
      this.pending.set(request.id, { request, resolve, timer });
      this.events.onRequest?.(request);
    });
  }

  /** UI 应答 */
  respond(id: string, allowed: boolean): boolean {
    const entry = this.pending.get(id);
    if (!entry) return false;
    clearTimeout(entry.timer);
    this.pending.delete(id);
    entry.resolve(allowed);
    this.events.onResolved?.(id, allowed);
    return true;
  }

  /** 全部拒绝（abort / WS 断开 / 会话切换时调用） */
  rejectAll(reason: string): string[] {
    const ids = [...this.pending.keys()];
    for (const id of ids) {
      const entry = this.pending.get(id);
      if (!entry) continue;
      clearTimeout(entry.timer);
      this.pending.delete(id);
      entry.resolve(false);
      this.events.onResolved?.(id, false);
    }
    return ids;
  }

  /** 是否仍有待审批（agent 空闲且无 pending 才允许删除当前会话） */
  get size(): number {
    return this.pending.size;
  }
}

/**
 * 确认门内联扩展。传入 createAgentSessionServices 的
 * resourceLoaderOptions.extensionFactories（随每个新会话自动重新挂载）。
 */
export function createApprovalGateExtension(
  registry: ApprovalRegistry,
  config: KairoConfig,
): InlineExtension {
  return (pi) => {
    pi.on("tool_call", async (event) => {
      // 只读工具：直接放行
      if (config.readOnlyAutoApprove.includes(event.toolName)) {
        return undefined;
      }

      let request: ApprovalRequest;
      if (isToolCallEventType("edit", event)) {
        const { input } = event;
        const target = String(input.path);
        const diff = computeEditDiff(target, input.edits ?? [], config.workdir);
        request = {
          id: event.toolCallId,
          toolName: "edit",
          input: input as unknown as Record<string, unknown>,
          target,
          diff,
          requestedAt: Date.now(),
        };
      } else if (isToolCallEventType("write", event)) {
        const { input } = event;
        const target = String(input.path);
        request = {
          id: event.toolCallId,
          toolName: "write",
          input: input as unknown as Record<string, unknown>,
          target,
          diff: computeWriteDiff(target, String(input.content ?? ""), config.workdir),
          requestedAt: Date.now(),
        };
      } else if (isToolCallEventType("bash", event)) {
        const { input } = event;
        request = {
          id: event.toolCallId,
          toolName: "bash",
          input: input as unknown as Record<string, unknown>,
          command: String(input.command ?? ""),
          cwd: config.workdir,
          requestedAt: Date.now(),
        };
      } else {
        // 未知工具（扩展/自定义工具）：默认要求确认
        request = {
          id: event.toolCallId,
          toolName: "bash",
          input: event.input as unknown as Record<string, unknown>,
          command: event.toolName,
          cwd: config.workdir,
          requestedAt: Date.now(),
        };
      }

      const allowed = await registry.requestApproval(request);
      if (!allowed) {
        return { block: true, reason: "该操作被用户拒绝" };
      }
      return undefined;
    });
  };
}