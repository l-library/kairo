#!/usr/bin/env bash
# install.sh — kairo 全自动化安装
#   1) 构建 daemon（npm ci + tsc）
#   2) 安装并启用 systemd --user 单元
#   3) setup.sh 一次性导入 provider 密钥
#   4) 写入 Hyprland 片段（需确认）
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON_DIR="$REPO_DIR/daemon"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="kairo-daemon.service"
HYPR_CONF="${HYPRLAND_CONF:-$HOME/.config/hypr/hyprland.conf}"

echo "==> [1/4] 构建 daemon…"
cd "$DAEMON_DIR"
if [[ ! -d node_modules ]]; then npm ci; fi
npm run build

echo "==> [2/4] 安装 systemd 单元…"
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

echo "==> [3/4] 导入 provider 密钥…"
"$REPO_DIR/scripts/setup.sh"

echo "==> [3b] 同步内置技能（kairo-skills）…"
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
  { echo ""; cat "$REPO_DIR/shell/hyprland.conf.snippet"; } >> "$HYPR_CONF"
  echo "    已追加（备份: $HYPR_CONF.kairo.bak）"
  echo "    提示：重启 Hyprland 或执行 'hyprctl reload' 生效"
else
  echo "    跳过。可手动复制 shell/hyprland.conf.snippet 内容。"
fi

echo ""
echo "安装完成 ✅"
echo "  - 唤起浮窗：Super+A"
echo "  - 管理：     kairoctl status|restart|logs"