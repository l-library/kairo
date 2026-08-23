#!/usr/bin/env bash
# toggle-kairo.sh — 唤起/隐藏 kairo 浮窗
#
# 已运行：quickshell ipc call kairo toggle（原生 IPC，优于 DBus）
# 未运行：启动 quickshell 实例后再显示（首次唤起）
set -euo pipefail

CONFIG_PATH="${KAIRO_SHELL_DIR:-$HOME/Documents/kairo/shell}/config.qml"

# ---------------------------------------------------------------
# EGL 修补：Hyprland exec 环境（GDM 会话）不继承 zshrc 里的
# __EGL_VENDOR_LIBRARY_DIRS。nix 版 mesa 需要它才能被 glvnd 发现
# （否则 QML 面板报 EGL not available、显示即崩溃）。
# 策略与 ~/.zshrc 的 update-mesa-egl-path 一致：从 store 选出最新且
# 确实包含 egl_vendor.d 的 mesa（目录名形如 <hash>-mesa-26.1.5）。
# ---------------------------------------------------------------
ensure_egl_env() {
  if [[ -n "${__EGL_VENDOR_LIBRARY_DIRS:-}" ]]; then return 0; fi
  local p=""
  p="$(ls -td /nix/store/*-mesa-*/share/glvnd/egl_vendor.d 2>/dev/null | head -1 || true)"
  if [[ -n "$p" ]]; then
    export __EGL_VENDOR_LIBRARY_DIRS="$p"
  fi
}
ensure_egl_env

# ---------------------------------------------------------------
# IME 修补：fcitx5 是系统 apt 包，其 Qt6 前端插件在
#   /usr/lib/x86_64-linux-gnu/qt6/plugins/platforminputcontexts/
# nix Qt 默认不扫描该路径；插件还依赖 libFcitx5Qt6DBusAddons.so.1
# （系统库目录）。注入后面板内可正常弹出 fcitx 输入法打中文。
# 均追加到末尾，不抢 nix 库/插件优先级。
# ---------------------------------------------------------------
ensure_ime_env() {
  # fcitx5 输入上下文插件的来源优先级：
  #  1. KAIRO_QT_PLUGIN_DIR 手动覆盖
  #  2. 缓存文件 ~/.local/state/kairo/qt-plugin-dir（首次 nix eval 解析后写入，
  #     避免每次 toggle 都跑 nix eval——那会让脚本慢 1.4s）
  #  3. nix eval 解析 nixpkgs#qt6Packages.fcitx5-qt（与 quickshell 同 Qt 6.11.1，
  #     ABI 匹配；nix 更新后缓存失效自动重解析）
  # 插件依赖自带 RUNPATH，无需库路径 hack；注意不要把系统库目录加进
  # LD_LIBRARY_PATH（系统 glibc 会污染 nix 二进制直接崩溃）。
  local plugin_dir="${KAIRO_QT_PLUGIN_DIR:-}"
  local cache_file="$HOME/.local/state/kairo/qt-plugin-dir"
  if [[ -z "$plugin_dir" && -f "$cache_file" ]]; then
    local cached="$(cat "$cache_file" 2>/dev/null || true)"
    if [[ -n "$cached" && -d "$cached/lib/qt-6/plugins" ]]; then
      plugin_dir="$cached/lib/qt-6/plugins"
    fi
  fi
  if [[ -z "$plugin_dir" ]]; then
    local p=""
    p="$(nix eval --raw 'nixpkgs#qt6Packages.fcitx5-qt.outPath' 2>/dev/null || true)"
    if [[ -n "$p" && -d "$p/lib/qt-6/plugins" ]]; then
      plugin_dir="$p/lib/qt-6/plugins"
      mkdir -p "$(dirname "$cache_file")" 2>/dev/null || true
      echo "$p" > "$cache_file" 2>/dev/null || true
    fi
  fi
  if [[ -n "$plugin_dir" ]]; then
    export QT_PLUGIN_PATH="$plugin_dir"
  fi
}
ensure_ime_env

# ---------------------------------------------------------------
# 直接使用真正的 quickshell 二进制：用户 ~/.local/bin/quickshell 是
# nix eval 包装器（每次调用约 0.9s 的 nix eval 开销，keybind 路径因此
# 从 60ms 变 1.9s）。上面的 EGL/IME 注入已覆盖其功能。
# ---------------------------------------------------------------
if [[ -n "${KAIRO_QS_BIN:-}" ]]; then
  QS_BIN="$KAIRO_QS_BIN"
elif [[ -x "$HOME/.nix-profile/bin/quickshell" ]]; then
  QS_BIN="$HOME/.nix-profile/bin/quickshell"
else
  QS_BIN="$(command -v quickshell || echo quickshell)"
fi

ipc_call() {
  "$QS_BIN" ipc -p "$CONFIG_PATH" call "$@" >/dev/null 2>&1
}

start_panel() {
  # setsid + nohup：脱离调用方进程组（Hyprland exec / 终端环境退出时不误杀）
  setsid nohup "$QS_BIN" -p "$CONFIG_PATH" >/dev/null 2>&1 < /dev/null &
  disown 2>/dev/null || true
}

# exec-once 启动模式：只启动不显示（保持隐藏，等 Super+A）
if [[ "${1:-}" == "--start-safe" ]]; then
  if ipc_call kairo isVisible; then
    exit 0
  fi
  start_panel
  exit 0
fi

if ipc_call kairo isVisible; then
  # 实例在跑：直接切换可见性
  ipc_call kairo toggle
  exit 0
fi

# 实例未启动：拉起（保持隐藏），等待 IPC 就绪后显示
start_panel

for _ in $(seq 1 40); do
  if ipc_call kairo isVisible; then
    ipc_call kairo show
    exit 0
  fi
  sleep 0.1
done

# IPC 未就绪（启动失败或过慢）：提示
if ! pgrep -f "$QS_BIN" >/dev/null 2>&1; then
  echo "kairo 浮窗启动失败（检查 quickshell 是否可用）" >&2
fi