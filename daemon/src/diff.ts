/**
 * diff.ts — 工具入参 → unified diff（写操作确认卡预览用）
 *
 * 公共 API 仅导出 generateDiffString / generateUnifiedPatch（SDK 的
 * computeEditsDiff 为内部实现），故 edit 预览采用"逐条精确替换 + 标注未命中"，
 * 足够 v1 确认卡使用。
 */
import { readFileSync } from "node:fs";
import { join, isAbsolute } from "node:path";
import { generateDiffString } from "@earendil-works/pi-coding-agent";

export interface Edit {
  oldText: string;
  newText: string;
}

/** 相对路径 → 绝对路径（以 workdir 为基准） */
export function resolveTargetPath(target: string, workdir: string): string {
  return isAbsolute(target) ? target : join(workdir, target);
}

/** 逐条精确替换；未命中的编辑单独标注（不产生误导性 diff） */
export function applyEditsExact(
  oldContent: string,
  edits: Edit[],
): { content: string; unmatched: Edit[] } {
  let content = oldContent;
  const unmatched: Edit[] = [];
  for (const e of edits) {
    if (content.includes(e.oldText)) {
      content = content.split(e.oldText).join(e.newText);
    } else {
      unmatched.push(e);
    }
  }
  return { content, unmatched };
}

/** edit 工具：计算多个替换操作的目标 diff（不落盘） */
export function computeEditDiff(target: string, edits: Edit[], workdir: string): string {
  const abs = resolveTargetPath(target, workdir);
  let old: string;
  try {
    old = readFileSync(abs, "utf8");
  } catch {
    return "(新文件)";
  }
  const { content, unmatched } = applyEditsExact(old, edits);
  const notes = unmatched.map(
    (e) => `(⚠ 未能定位原文: ${JSON.stringify(e.oldText.slice(0, 60))})`,
  );
  const diff = generateDiffString(old, content).diff;
  return notes.length > 0 ? [...notes, "", diff].join("\n") : diff;
}

/** write 工具：旧文件 vs 新内容（文件不存在时输出新建预览） */
export function computeWriteDiff(target: string, newContent: string, workdir: string): string {
  const abs = resolveTargetPath(target, workdir);
  try {
    const old = readFileSync(abs, "utf8");
    return generateDiffString(old, newContent).diff;
  } catch {
    const lines = newContent.replace(/\n$/, "").split("\n");
    return `(新建文件)\n${lines.slice(0, 60).map((l) => `+ ${l}`).join("\n")}`;
  }
}