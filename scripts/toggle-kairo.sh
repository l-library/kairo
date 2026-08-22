#!/usr/bin/env bash
# toggle-kairo.sh — 唤起/隐藏 kairo 浮窗
#
# 已运行：quickshell ipc call kairo toggle（原生 IPC，优于 DBus）
# 未运行：启动 quickshell 实例后再显示（首次唤起）
set -euo pipefail

CONFIG_PATH="${KAIRO_SHELL_DIR:-$HOME/Documents/kairo/shell}/config.qml"

# exec-once 启动模式：只启动不显示（保持隐藏，等 Super+A）
if [[ "${1:-}" == "--start-safe" ]]; then
  if quickshell ipc -p "$CONFIG_PATH" call kairo isVisible >/dev/null 2>&1; then
    exit 0
  fi
  quickshell -p "$CONFIG_PATH" >/dev/null 2>&1 &
  exit 0
fi

ipc_call() {
  quickshell ipc -p "$CONFIG_PATH" call "$@" >/dev/null 2>&1
}

if ipc_call kairo isVisible; then
  # 实例在跑：直接切换可见性
  ipc_call kairo toggle
  exit 0
fi

# 实例未启动：拉起（保持隐藏），等待 IPC 就绪后显示
quickshell -p "$CONFIG_PATH" >/dev/null 2>&1 &
QS_PID=$!

for _ in $(seq 1 40); do
  if ipc_call kairo isVisible; then
    ipc_call kairo show
    exit 0
  fi
  sleep 0.1
done

# IPC 未就绪（启动失败或过慢）：至少保证进程存在
kill -0 "$QS_PID" 2>/dev/null || echo "kairo 浮窗启动失败（检查 quickshell 是否可用）" >&2
wait "$QS_PID" 2>/dev/null || true