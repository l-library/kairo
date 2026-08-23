#!/usr/bin/env bash
# install.sh — kairo 全自动化安装
#   1) 构建 daemon（npm ci + tsc）
#   2) 安装并启用 systemd --user 单元
#   3) setup.sh 一次性导入 provider 密钥
#   4) 写入 Hyprland 片段（需确认）
# 用法: ./scripts/install.sh [--skip-setup]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$REPO_DIR/daemon"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="kairo-daemon.service"
HYPR_CONF="${HYPRLAND_CONF:-$HOME/.config/hypr/hyprland.conf}"

# --- 参数 ---
SKIP_SETUP=0
for arg in "$@"; do
  case "$arg" in
    --skip-setup) SKIP_SETUP=1 ;;
    -h|--help)
      echo "用法: $(basename "$0") [--skip-setup]" >&2
      echo "  --skip-setup  跳过 provider 密钥导入（稍后可用 kairoctl reimport）" >&2
      exit 0
      ;;
    *)
      echo "未知参数: $arg（--help 查看用法）" >&2
      exit 1
      ;;
  esac
done

# --- 前置检查 ---
require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "!! 未找到 node。需要 Node ≥ 24（pi SDK 与 daemon 的运行时要求）。" >&2
    exit 1
  fi
  local major
  major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)"
  if [[ "$major" -lt 24 ]]; then
    echo "!! Node 版本过低: $(node --version)（需要 ≥ 24）" >&2
    exit 1
  fi
  echo "    node: $(node --version) ✅"
}
require_node

if ! command -v quickshell >/dev/null 2>&1 && [[ ! -x "$HOME/.nix-profile/bin/quickshell" ]]; then
  echo "!! 未检测到 quickshell——daemon 照常安装，但 Super+A 浮窗不可用。" >&2
  echo "    安装参考: nix profile install nixpkgs#quickshell（或发行版包 / AUR）" >&2
fi

echo "==> [1/4] 构建 daemon…"
cd "$DAEMON_DIR"
if [[ ! -d node_modules ]]; then npm ci; fi
npm run build

echo "==> [2/4] 安装 systemd 单元 + kairoctl CLI…"
mkdir -p "$SYSTEMD_DIR"
NODE_BIN="$(command -v node || echo /usr/bin/node)"
sed -e "s|/home/liborui/Documents/kairo|$REPO_DIR|g" \
    -e "s|ExecStart=/usr/local/bin/node|ExecStart=$NODE_BIN|" \
    "$DAEMON_DIR/systemd/$SERVICE_NAME" > "$SYSTEMD_DIR/$SERVICE_NAME"
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"
sleep 2
if ! systemctl --user is-active --quiet "$SERVICE_NAME"; then
  echo "!! kairo-daemon 启动失败，日志：" >&2
  journalctl --user -u "$SERVICE_NAME" -n 30 --no-pager >&2 || true
  exit 1
fi
echo "    kairo-daemon 运行中 ✅"

# kairoctl → PATH（默认 ~/.local/bin，可用 KAIRO_BIN_DIR 覆盖）
BIN_DIR="${KAIRO_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/scripts/kairoctl" "$BIN_DIR/kairoctl"
if [[ ":$PATH:" == *":$BIN_DIR:"* ]]; then
  echo "    kairoctl → $BIN_DIR/kairoctl ✅"
else
  echo "!! 已安装到 $BIN_DIR/kairoctl，但该目录不在当前 PATH 中" >&2
  echo "    请在 shell 配置中加入: export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
  echo "    或设置 KAIRO_BIN_DIR 指向已有 PATH 目录后重跑 install.sh" >&2
fi

echo "==> [3/4] 导入 provider 密钥 + 同步内置技能…"
if [[ "$SKIP_SETUP" -eq 1 ]]; then
  echo "    已跳过密钥导入（--skip-setup）。稍后可用: kairoctl reimport"
else
  "$REPO_DIR/scripts/setup.sh"
fi
KAIRO_SKILLS="$HOME/.config/kairo/agent/skills"
mkdir -p "$KAIRO_SKILLS"
cp -rn "$REPO_DIR/skills/kairo-skills" "$KAIRO_SKILLS/"
if [[ -f "$KAIRO_SKILLS/kairo-skills/SKILL.md" ]]; then
  echo "    kairo-skills 技能已就位 ✅"
else
  echo "!! 技能同步失败，请检查 $REPO_DIR/skills/kairo-skills" >&2
fi

echo "==> [4/4] 写入 Hyprland 片段…"
read -r -p "    将片段追加到 $HYPR_CONF？（y/N）" yes
if [[ "$yes" =~ ^[Yy]$ ]]; then
  if [[ -f "$HYPR_CONF" ]]; then cp -f "$HYPR_CONF" "$HYPR_CONF.kairo.bak"; fi
  { echo ""; sed -e "s|__KAIRO_REPO__|$REPO_DIR|g" "$REPO_DIR/shell/hyprland.conf.snippet"; } >> "$HYPR_CONF"
  echo "    已追加（备份: $HYPR_CONF.kairo.bak）"
  echo "    提示：重启 Hyprland 或执行 'hyprctl reload' 生效"
else
  echo "    跳过。可手动复制 shell/hyprland.conf.snippet 内容（将 __KAIRO_REPO__ 替换为 $REPO_DIR）"
fi

echo ""
echo "安装完成 ✅"
echo "  - 唤起浮窗：Super+A"
echo "  - 管理：     kairoctl status|restart|logs（已安装到 ${BIN_DIR:-$HOME/.local/bin}/kairoctl）"