/**
 * session-manager.ts — 历史会话列表 / 删除（基于 pi 原生 SessionManager）
 *
 * 会话以 JSONL 平面存储于 sessionDir（文件名 `<timestamp>_<sessionId>.jsonl`）。
 * 列表：SessionManager.listAll(sessionDir) 按 mtime 倒序。
 * 删除：按 id 定位文件后 unlink（活动会话不允许删除）。
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
    }));
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