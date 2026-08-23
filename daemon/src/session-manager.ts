/**
 * session-manager.ts — 历史会话列表 / 删除（基于 pi 原生 SessionManager）
 *
 * 会话以 JSONL 平面存储于 sessionDir（文件名 `<timestamp>_<sessionId>.jsonl`）。
 * 列表：SessionManager.listAll(sessionDir) 按 mtime 倒序。
 * 删除：按 id 定位文件后 unlink（活动会话不允许删除）。
 *
 * 注意：SDK 的 newSession() 推迟落盘——会话在收到第一条助手消息前不写文件
 * （flushed=false，_persist 的 no-assistant 保护）。因此新建的空会话在磁盘上
 * 不存在，list() 会漏掉它；listWithActive() 将当前活动会话合成注入，保证
 * UI 列表始终可见并高亮当前会话（磁盘上已有则优先用磁盘条目）。
 */
import { unlink } from "node:fs/promises";
import { existsSync } from "node:fs";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import type { SessionListItem } from "./ws-types.js";

export interface KairoSessionManagerOptions {
  sessionDir: string;
}

export class KairoSessionManager {
  constructor(private opts: KairoSessionManagerOptions) {}

  async list(): Promise<SessionListItem[]> {
    const sessions = await SessionManager.listAll(this.opts.sessionDir);
    return sessions.map((s) => ({
      id: s.id,
      path: s.path,
      name: s.name,
      cwd: s.cwd,
      createdAt: s.created?.toISOString(),
      modifiedAt: s.modified?.toISOString(),
      messageCount: s.messageCount,
      firstMessage: s.firstMessage ?? "",
    }));
  }

  /**
   * 会话列表 + 当前活动会话（磁盘已有则优先用磁盘条目，否则用合成的 active 项），
   * 活动会话始终置顶。
   */
  async listWithActive(active: SessionListItem): Promise<SessionListItem[]> {
    const list = await this.list();
    const idx = list.findIndex((s) => s.id === active.id);
    if (idx >= 0) {
      const cur = list[idx]!;
      list.splice(idx, 1);
      return [cur, ...list];
    }
    return [active, ...list];
  }

  /** 按 id 定位会话文件路径（列表中的 id 与文件名一致） */
  async findPathById(id: string): Promise<string | undefined> {
    const all = await this.list();
    return all.find((s) => s.id === id)?.path;
  }

  /** 删除会话文件（活动会话由调用方在 http.ts 拦截） */
  async deleteById(id: string): Promise<boolean> {
    const path = await this.findPathById(id);
    if (!path || !existsSync(path)) return false;
    await unlink(path);
    return true;
  }
}