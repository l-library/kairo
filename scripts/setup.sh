#!/usr/bin/env bash
# kairo setup.sh — 一次性导入宿主 ~/.pi/agent 的 provider 配置到 kairo 独立 agentDir。
#
# 导入内容：
#   - auth.json           （provider 密钥）
#   - models-store.json   （模型目录缓存）
#   - settings.json       （字段级拷贝 provider 相关字段：defaultProvider / defaultModel /
#                         defaultThinkingLevel / providers，不覆盖 kairo 自身的其它设置）
# 之后 kairo 与宿主完全独立演进；可随时用 `kairoctl reimport` 重新同步。
set -euo pipefail

HOST_AGENT_DIR="${KAIRO_HOST_AGENT_DIR:-$HOME/.pi/agent}"
KAIRO_AGENT_DIR="${KAIRO_AGENT_DIR:-$HOME/.config/kairo/agent}"

echo "==> 源目录: $HOST_AGENT_DIR"
echo "==> 目标目录: $KAIRO_AGENT_DIR"

if [[ ! -d "$HOST_AGENT_DIR" ]]; then
  echo "!! 宿主 agent 目录不存在: $HOST_AGENT_DIR（可设置 KAIRO_HOST_AGENT_DIR 覆盖）" >&2
  echo "    kairo 会继续完成安装；之后任选一种方式配置密钥：" >&2
  echo "      1) 在本机安装 pi 并登录 provider 后执行: kairoctl reimport" >&2
  echo "      2) 手动放置密钥到: $KAIRO_AGENT_DIR/auth.json" >&2
  exit 0
fi

mkdir -p "$KAIRO_AGENT_DIR"

# --- auth.json（整体拷贝） ---
if [[ -f "$HOST_AGENT_DIR/auth.json" ]]; then
  cp -f "$HOST_AGENT_DIR/auth.json" "$KAIRO_AGENT_DIR/auth.json"
  chmod 600 "$KAIRO_AGENT_DIR/auth.json"
  echo "==> 已导入 auth.json"
else
  echo "警告: 源目录没有 auth.json（无密钥，模型调用将无法鉴权）" >&2
fi

# --- models-store.json（整体拷贝，模型目录缓存） ---
if [[ -f "$HOST_AGENT_DIR/models-store.json" ]]; then
  cp -f "$HOST_AGENT_DIR/models-store.json" "$KAIRO_AGENT_DIR/models-store.json"
  chmod 600 "$KAIRO_AGENT_DIR/models-store.json"
  echo "==> 已导入 models-store.json"
fi

# --- settings.json（字段级拷贝 provider 相关字段） ---
merge_provider_settings() {
  node <<'EOF'
const fs = require("fs");
const hostPath = process.env.KAIRO_HOST_AGENT_DIR + "/settings.json";
const kairoPath = process.env.KAIRO_AGENT_DIR + "/settings.json";
if (!hostPath.startsWith("/") || !kairoPath.startsWith("/")) {
  console.error("错误: 环境变量 KAIRO_HOST_AGENT_DIR / KAIRO_AGENT_DIR 未正确传入");
  process.exit(1);
}
if (!fs.existsSync(hostPath)) {
  console.error("警告: 源目录没有 settings.json，跳过 provider 字段导入");
  process.exit(0);
}
const host = JSON.parse(fs.readFileSync(hostPath, "utf8"));
const kairo = fs.existsSync(kairoPath) ? JSON.parse(fs.readFileSync(kairoPath, "utf8")) : {};
const PROVIDER_KEYS = ["defaultProvider", "defaultModel", "defaultThinkingLevel", "providers"];
let changed = false;
for (const key of PROVIDER_KEYS) {
  if (host[key] !== undefined) {
    if (JSON.stringify(kairo[key]) !== JSON.stringify(host[key])) {
      kairo[key] = host[key];
      changed = true;
    }
  }
}
if (changed) {
  fs.writeFileSync(kairoPath, JSON.stringify(kairo, null, 2) + "\n");
}
console.log("==> settings.json provider 字段已同步");
EOF
}
KAIRO_HOST_AGENT_DIR="$HOST_AGENT_DIR" KAIRO_AGENT_DIR="$KAIRO_AGENT_DIR" merge_provider_settings

# --- 最终校验 ---
if [[ -f "$KAIRO_AGENT_DIR/auth.json" ]]; then
  echo "==> 完成。kairo agentDir 就绪: $KAIRO_AGENT_DIR"
  ls -la "$KAIRO_AGENT_DIR"
else
  echo "!! 未找到可用密钥。kairo 可继续安装，但模型调用将无法鉴权。" >&2
  echo "    稍后任选一种方式配置：" >&2
  echo "      1) 在本机完成 pi 的 provider 登录后执行: kairoctl reimport" >&2
  echo "      2) 手动将密钥放入 $KAIRO_AGENT_DIR/auth.json，然后 kairoctl restart" >&2
fi