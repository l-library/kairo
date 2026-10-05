/**
 * ui-state.ts — 面板 UI 状态持久化（每会话的滚动停留位置）
 *
 * 面板 Super+A 关闭时上报当前会话的滚动位置，写入
 * ~/.local/state/kairo/ui-state.json；下次打开/面板重启后按会话恢复。
 * 只保留最近 MAX_SESSIONS 个会话（qa 轮换会产生大量一次性会话，
 * 防止文件无限增长）。
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";

export interface ScrollPos {
  /** 关闭时的 contentY（贴底时无意义） */
  y: number;
  /** 关闭时是否贴底 */
  atBottom: boolean;
  savedAt: number;
}

const MAX_SESSIONS = 50;

export class UiStateStore {
  private scroll: Record<string, ScrollPos> = {};

  constructor(private readonly filePath: string) {
    this.scroll = this.load();
  }

  private load(): Record<string, ScrollPos> {
    try {
      if (existsSync(this.filePath)) {
        const parsed = JSON.parse(readFileSync(this.filePath, "utf8")) as {
          scroll?: Record<string, ScrollPos>;
        };
        if (parsed.scroll && typeof parsed.scroll === "object") return parsed.scroll;
      }
    } catch {
      /* 文件损坏时按空状态重建 */
    }
    return {};
  }

  private persist(): void {
    try {
      writeFileSync(this.filePath, JSON.stringify({ scroll: this.scroll }, null, 2) + "\n");
    } catch (err) {
      console.error("[ui-state] 保存失败:", err);
    }
  }

  getScroll(sessionId: string): ScrollPos | null {
    return this.scroll[sessionId] ?? null;
  }

  setScroll(sessionId: string, y: number, atBottom: boolean): void {
    const existing = this.scroll[sessionId];
    if (!existing && Object.keys(this.scroll).length >= MAX_SESSIONS) {
      // 淘汰最旧的一条
      let oldest = Object.keys(this.scroll)[0];
      if (oldest) {
        for (const id of Object.keys(this.scroll)) {
          if ((this.scroll[id]?.savedAt ?? 0) < (this.scroll[oldest]?.savedAt ?? 0)) oldest = id;
        }
        delete this.scroll[oldest];
      }
    }
    this.scroll[sessionId] = { y, atBottom, savedAt: Date.now() };
    this.persist();
  }
}
