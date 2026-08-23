# kairo

Hyprland 上的即用型桌面 AI 助手：**quickshell 浮窗（QML）** + **PI SDK（Node daemon）**。

- **Chat 模式**：纯对话，无工具调用。
- **Command 模式**：完整 agentic（读文件/写文件/执行命令），写操作先弹 diff 确认、跑命令先确认。

## 快速开始

```bash
# 1. 安装（构建 daemon → systemd 单元 → 导入密钥 → 写入 Hyprland 片段）
./scripts/install.sh

# 2. 唤起浮窗（Super+A，或手动）
./scripts/toggle-kairo.sh

# 3. 管理
kairoctl status      # 模式/会话/待审批
kairoctl restart     # 重启 daemon（自动恢复最近会话）
kairoctl logs        # 实时日志
```

## 架构

```
Hyprland
├─ keybind Super+A ──→ scripts/toggle-kairo.sh ──→ quickshell (shell/config.qml)
│                                                     └─ IPC: quickshell ipc call kairo toggle
├─ quickshell 面板（QML，右上角 overlay 层）
└─ kairo-daemon（systemd --user，Node 24）
     ├─ HTTP :44811  REST 控制面（Bearer token 鉴权）
     ├─ WebSocket /ws 事件流（脚本/其他客户端用）
     └─ panel.sock    Unix socket（面板专用，0600 文件权限鉴权）
```

## 目录

| 路径 | 说明 |
|------|------|
| `daemon/` | Node + TS 守护进程（`npm run build` → `dist/main.js`） |
| `daemon/src/approval.ts` | 确认门：edit/write 生成 diff、bash 命令全文，approval 注册表统一持有审批 Promise |
| `daemon/src/agent.ts` | AgentSession 封装、事件归一化、`setRebindSession` 会话重绑 |
| `daemon/src/panel-socket.ts` | 面板 Unix socket（quickshell 无 TCP 支持的原生替代通道） |
| `shell/` | quickshell QML 项目（`config.qml` 入口） |
| `shell/qml/` | 组件：ChatPanel / MessageBubble / ToolCard / ApprovalDialog / SessionSidebar / InputBar / KairoClient / TitleBar |
| `scripts/` | setup.sh（密钥导入）/ install.sh / toggle-kairo.sh / kairoctl |
| `skills/` | 内置技能（kairo-skills：教模型自行安装技能，随安装同步） |
| `docs/` | 配置参考与使用说明（含 `docs/skills.md` 技能手动安装指南） |

## 与宿主隔离

kairo 使用独立 PI 配置目录 `~/.config/kairo/agent`（mcp/skills/plugins/会话均与 `~/.pi` 无关），
密钥由 `scripts/setup.sh` 一次性导入后独立演进；Command 模式工作目录为中性目录
`~/.local/share/kairo/workdir`（不放置任何 AGENTS.md/.pi），避免加载宿主项目资源。

## 里程碑状态

M0 技术验证 ✅ · M1 daemon 骨架 ✅ · M2 浮窗+聊天 ✅ · M3 Command 模式 ✅ · M4 会话与打磨 ✅

完整方案与决策记录见 [PLAN.md](PLAN.md)。