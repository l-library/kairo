# kairo 配置参考

所有配置位于 `~/.config/kairo/`，环境变量可覆盖路径。

## settings.json（daemon 运行时）

| 键 | 默认 | 说明 |
|----|------|------|
| `port` | 44811 | HTTP/WS 端口（仅 127.0.0.1） |
| `host` | 127.0.0.1 | 监听地址 |
| `defaultMode` | command | 启动时的模式（切换后自动持久化） |
| `workdir` | `~/.local/share/kairo/workdir` | Command 模式工具工作目录 |
| `readOnlyAutoApprove` | read/grep/find/ls | 只读自动放行名单 |
| `approvalTimeoutMs` | 600000 (10min) | 审批超时自动拒绝 |

```json
{
  "port": 44811,
  "defaultMode": "command",
  "workdir": "/home/me/projects",
  "readOnlyAutoApprove": ["read", "grep", "find", "ls"],
  "approvalTimeoutMs": 600000
}
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `KAIRO_AGENT_DIR` | PI 配置目录（默认 `~/.config/kairo/agent`） |
| `KAIRO_SESSION_DIR` | 会话目录（默认 `~/.local/share/kairo/sessions`） |
| `KAIRO_STATE_DIR` | 状态目录：token / panel.sock / 日志（默认 `~/.local/state/kairo`） |
| `KAIRO_HOST_AGENT_DIR` | setup.sh 的密钥来源（默认 `~/.pi/agent`） |

## 目录

| 路径 | 用途 |
|------|------|
| `~/.config/kairo/agent/` | kairo 独立 PI 配置（auth.json / models-store.json / settings.json） |
| `~/.config/kairo/settings.json` | daemon 运行时配置 |
| `~/.local/share/kairo/sessions/` | 会话 JSONL（pi 原生格式，可被宿主 pi 读取） |
| `~/.local/share/kairo/workdir/` | Command 模式默认工作目录 |
| `~/.local/state/kairo/token` | HTTP/WS 鉴权 token（0600） |
| `~/.local/state/kairo/panel.sock` | 面板 Unix socket |

## Hyprland 集成

`shell/hyprland.conf.snippet`：

```ini
exec-once = /home/liborui/Documents/kairo/scripts/toggle-kairo.sh --start-safe
bind = SUPER, A, exec, /home/liborui/Documents/kairo/scripts/toggle-kairo.sh
```

更换唤起键直接改 `bind` 行即可。

## 故障排查

| 症状 | 处理 |
|------|------|
| daemon 反复退出 | `journalctl --user -u kairo-daemon -e` 查看原因 |
| 面板连不上 | `quickshell ipc -p ~/Documents/kairo/shell/config.qml call kairo getDebugInfo` 看 connected 字段 |
| 面板唤不起（日志报 `EGL not available`） | GDM→Hyprland 的 exec 环境没有 nix mesa 的 `__EGL_VENDOR_LIBRARY_DIRS`；toggle-kairo.sh 已自动注入（从 store 选最新含 egl_vendor.d 的 mesa），若 nix 升级后仍异常可手动重跑 `./scripts/toggle-kairo.sh` |
| 密钥失效 | `kairoctl reimport` 重新导入 |
| 端口被占 | 改 settings.json 的 port 后 `kairoctl restart` |