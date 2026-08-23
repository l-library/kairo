# kairo — Hyprland 上的 PI 桌面 AI 助手 · 实现方案

> 状态：**M0–M4 全部实施完成并通过验收**。本文档汇总三轮需求问答的全部决策，为后期维护的唯一依据；实施偏差见 §13。

---

## 1. 定位

kairo 是一个运行在 Hyprland 下、基于 **quickshell**（QML 浮窗）与 **PI SDK**（Node 守护进程）的随叫随用桌面 AI 助手：

- **Chat 模式**：纯对话，不启用任何工具，适合问答、闲聊、翻译、总结。
- **Command 模式**：完整 agentic，可调用 SDK 内置工具集（read/write/edit/bash/grep/find/ls，共 7 个），**写操作先弹 diff、跑命令先确认**。
- 使用与宿主 `~/.pi` **完全隔离**的配置目录（独立 mcp / skills / plugins / 会话）。
- 快捷键唤起浮动面板，随叫随用。

---

## 2. 已确定决策（三轮问答汇总）

| # | 决策点 | 选择 |
|---|--------|------|
| 1 | PI 后端形态 | **Node 守护进程 + SDK**（`@earendil-works/pi-coding-agent` 内嵌 `AgentSession`，对外暴露 HTTP/WS API） |
| 2 | 隔离强度 | **配置级隔离**（`agentDir` / `PI_CODING_AGENT_DIR` + 独立会话目录，进程跑在宿主） |
| 3 | 文件权限 | **全权访问 + 每步确认** |
| 4 | UI 形态 | **浮动面板**（quickshell `PopupWindow`，快捷键唤起） |
| 5 | 模式划分 | **双模式手动切换**（UI 按钮或 `/chat`、`/cmd` 命令；Chat 无工具，Command 全工具） |
| 6 | v1 功能范围 | 流式 Markdown 渲染 · 工具卡 + 确认 · 会话列表与切换（**截图/图片输入推后**） |
| 7 | 确认策略 | **只读放行 + diff 确认**（只读工具自动执行；写文件先看 diff 再批准；跑命令弹确认卡） |
| 8 | 会话管理 | **单活跃会话 + 历史会话列表**（同一时刻只有一个活跃会话；列表可浏览/新建/切换/删除历史 JSONL 会话） |
| 9 | 部署形态 | **systemd --user 管 daemon + hyprland 管浮窗**（exec-once 启动，keybind 唤起） |
| 10 | 技术栈 | **Node + 原生 TS**（`node:http` + `ws`，不引框架） |
| 11 | 密钥配置 | **一次性导入**宿主 `~/.pi/agent` 的 provider 配置（auth.json / settings.json 中 provider 部分），之后独立演进 |
| 12 | 开发节奏 | **里程碑推进**（M0→M4，每阶段在真实 Hyprland 里验收，可随时停下讨论） |

---

## 3. 总体架构

```
┌─────────────────────────────── Hyprland ───────────────────────────────┐
│                                                                        │
│  keybind (Super+A) ──→ qdbus toggle ──→  quickshell 实例 (kairo.qs)    │
│  exec-once 启动                        └──────────────┬───────────────┘
│                                                       │  HTTP + WebSocket
│  ┌───────────────────────────  kairo-daemon (systemd --user)  ────────┐
│  │  Node 24 + TS                                                      │
│  │  ┌───────────────────────────────┐   ┌──────────────────────────┐  │
│  │  │ HTTP API (控制面)             │   │ WS (事件流/双向)          │  │
│  │  │ · /api/sessions·/api/prompt   │   │ · 文本/思考流式增量       │  │
│  │  │ · /api/mode ·/api/abort       │   │ · 工具执行 start/update/end│ │
│  │  └───────────────────────────────┘   │ · approval 请求/应答     │  │
│  │  ┌────────────────────────────────────────────────────────────┐  │
│  │  │ pi SDK: AgentSession (AgentSessionRuntime 管理生命周期)     │  │
│  │  │ · tools 白名单（双模式切换）· on("tool_call") 确认门         │  │
│  │  │ · 事件流 message_update / tool_execution_* / turn_* / agent_*│ │
│  │  │ · SessionManager → JSONL 持久化                             │  │
│  │  └────────────────────────────────────────────────────────────┘  │
│  │  agentDir=~/.config/kairo/agent   sessions=~/.local/share/kairo/ │
│  └───────────────────────────────────────────────────────────────────┘
│            ▲                                                    ▲
│     LLM providers (api keys 一次性导入)             宿主文件系统（全权访问+确认）
└───────────────────────────────────────────────────────────────────────┘
```

数据流：QML 浮窗（纯 UI）⇄ HTTP/WS ⇄ Node daemon（pi SDK 会话、确认门、事件转发）⇄ LLM / 宿主文件系统。

---

## 4. 项目目录结构（monorepo，位于本仓库）

```
kairo/
├── PLAN.md                  # 本文档
├── daemon/                  # Node + TS 守护进程
│   ├── package.json         # 依赖: @earendil-works/pi-coding-agent, ws
│   ├── tsconfig.json
│   ├── src/
│   │   ├── main.ts          # 入口：HTTP + WS 服务器，生命周期
│   │   ├── session-manager.ts   # 会话列表/新建/激活（SessionManager + createAgentSessionRuntime）
│   │   ├── agent.ts         # AgentSession 封装：prompt/abort/steer、事件转发
│   │   ├── modes.ts         # chat/command 模式：tools 白名单 + 提示语
│   │   ├── approval.ts      # 确认门：tool_call 分类、diff 生成、pending 注册表（abort/断连时统一拒绝）
│   │   ├── diff.ts          # unified diff 计算（edit/write 前后对比）
│   │   ├── ws.ts            # WebSocket 协议：客户端事件 + 服务端广播
│   │   ├── http.ts          # REST API
│   │   └── config.ts        # 路径/端口/默认值解析
│   └── systemd/kairo-daemon.service
├── shell/                   # quickshell QML 项目
│   ├── config.qml           # 入口：PopupWindow + 组件装配
│   ├── qml/
│   │   ├── ChatPanel.qml        # 浮窗主面板
│   │   ├── MessageList.qml      # 消息流（流式渲染）
│   │   ├── MessageBubble.qml    # 单条消息（markdown/代码块）
│   │   ├── ToolCard.qml         # 工具执行卡片
│   │   ├── ApprovalDialog.qml   # 确认弹窗（含 diff 预览）
│   │   ├── SessionBar.qml       # 会话列表/新建/切换
│   │   ├── InputBar.qml         # 输入框 + 模式切换
│   │   ├── KairoClient.js       # WS/HTTP 客户端 + 状态机
│   │   └── Markdown.js          # 轻量 markdown → 富文本
│   └── hyprland.conf.snippet
├── scripts/
│   ├── setup.sh             # 一次性导入宿主 provider 配置 → kairo agentDir
│   ├── install.sh           # 构建 daemon、安装 systemd 单元、写入 hyprland 片段
│   └── kairoctl             # CLI 辅助（status/restart/logs）
└── docs/                    # 使用说明、配置参考
```

---

## 5. 配置与隔离

### 5.1 kairo 自己的目录

| 用途 | 路径 | 实现方式 |
|------|------|----------|
| PI 配置目录 | `~/.config/kairo/agent/` | `createAgentSession({ agentDir })`；等价于 `PI_CODING_AGENT_DIR` |
| 会话存储 | `~/.local/share/kairo/sessions/` | `SessionManager` + `PI_CODING_AGENT_SESSION_DIR` |
| 状态/缓存 | `~/.local/state/kairo/` | daemon PID、日志 |
| 运行时配置 | `~/.config/kairo/settings.json` | 端口、默认 cwd、默认模型、模式记忆 |

`agentDir` 下与宿主 `~/.pi/agent` 同级布局：`settings.json`、`auth.json`、`models.json`、`extensions/`、`skills/`、`prompts/`。**mcp / skills / 插件/主题对宿主完全不可见**——kairo 的 PI 是独立实例（注意：`cwd` 下的项目级资源仍会被发现，隔离对策见 §5.3）。

### 5.2 一次性导入（setup.sh）

首次运行时从 `~/.pi/agent` 复制：
- `auth.json`（provider 密钥）
- `settings.json` 中 provider/模型相关字段（如 `defaultModel`、`providers`）

之后两边独立演进。可手动 `kairoctl reimport` 重新同步。

### 5.3 默认 cwd

Command 模式的工具以 `cwd` 为工作目录（读取 AGENTS.md、定位项目）。

**隔离注意**：`agentDir` 隔离只覆盖全局资源；`DefaultResourceLoader` 仍会从 `cwd` 向上发现项目级资源（`.pi/extensions/`、`.pi/skills/`、`.agents/skills/`、`.pi/prompts/`、`AGENTS.md`）。因此**默认 `cwd` 不用 `$HOME`**，改用中性工作目录 `~/.local/share/kairo/workdir/`（该目录内不放置任何 `.pi`/`.agents`/`AGENTS.md`），确保与宿主完全隔离；可在 `settings.json` 配置，会话建立时也可指定其他项目目录（此时该目录下的项目级资源按预期正常加载）。

---

## 6. 守护进程设计（daemon/）

### 6.1 技术栈

- Node 24 + TypeScript，依赖仅：`@earendil-works/pi-coding-agent`、`ws`（HTTP 用 `node:http`）。
- 编译产物 `dist/main.js`，由 systemd `ExecStart=/usr/bin/node ...` 运行。
- 监听 `127.0.0.1:44811`（端口可配）。仅本机回环。
- **鉴权（M1 实现）**：启动时生成随机 token，写入 `~/.local/state/kairo/token`（权限 0600）；HTTP 请求带 `Authorization: Bearer <token>`，WS 握手时校验。否则任何本机进程都可直连并代发 `approve`，绕过“每步确认”。

### 6.2 API 设计

**HTTP（控制面，请求/响应）**

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 存活 + 模式/会话概要 |
| GET | `/api/sessions` | 历史会话列表（id、名称、时间、消息数） |
| POST | `/api/sessions` | 新建会话 `{name?}` |
| POST | `/api/sessions/:id/activate` | 激活历史会话（重建 runtime） |
| DELETE | `/api/sessions/:id` | 删除会话 |
| POST | `/api/prompt` | `{message, images?}` 发送消息（按当前模式处理） |
| POST | `/api/abort` | 中止当前流式/工具执行 |
| POST | `/api/mode` | `{mode: "chat"\|"command"}` 切换模式 |
| GET | `/api/status` | 模式、会话 id、是否 streaming、pending 确认数 |

**WebSocket `/ws`（事件流 + 确认交互）**

客户端 → 服务端：

```json
{"type":"approve","id":"<approvalId>"}
{"type":"reject","id":"<approvalId>"}
{"type":"cancel"}            // 取消/隐藏面板时中止当前流式
```

服务端 → 客户端（核心事件）：

```json
{"type":"message_update","messageId":"...","kind":"text_delta","delta":"..."}
{"type":"message_update","messageId":"...","kind":"thinking_delta","delta":"..."}
{"type":"message_start","messageId":"..."}
{"type":"message_end","messageId":"..."}
{"type":"agent_start"} / {"type":"agent_end"}
{"type":"turn_start"} / {"type":"turn_end","toolResults":[...]}
{"type":"tool_execution_start","toolCallId":"...","toolName":"edit","args":{...}}
{"type":"tool_execution_update","toolCallId":"...","chunk":"..."}
{"type":"tool_execution_end","toolCallId":"...","isError":false,"result":"..."}
{"type":"approval_requested","id":"...","toolName":"edit","args":{...},"diff":"...","target":"path"}
{"type":"approval_resolved","id":"...","allowed":true}
{"type":"mode_changed","mode":"command"}
{"type":"session_active","id":"...","name":"..."}
{"type":"session_list","sessions":[...]}
{"type":"error","code":"...","message":"..."}
```

### 6.3 双模式实现

- **Chat**：`session.setActiveToolsByName([])` → 纯 LLM 对话，无任何工具事件。
- **Command**：`session.setActiveToolsByName(["read","bash","edit","write","grep","find","ls"])`（SDK 内置工具仅此 7 个）+ 启用确认门。
- 切换 = 调用 `setActiveToolsByName()`（比裸改 `agent.state.tools` 完整：会同步重建系统提示，Chat 模式下不残留工具描述）。
- 模式提示语：无公开 systemPrompt setter，以**会话消息**方式注入（切换后发送一条消息：“你现在处于 Command 模式，可以读写文件、执行命令”），不改系统提示。
- 每次会话替换（新建/切换）后需按当前模式重新调用 `setActiveToolsByName`（见 §6.5 `setRebindSession`）。
- UI：输入框旁的 Chat/Command 切换按钮 + `/chat`、`/cmd` 输入命令；模式选择持久化到 `settings.json`。

### 6.4 工具确认状态机（核心）

确认门以内联扩展实现（`DefaultResourceLoader.extensionFactories`，参考 `examples/sdk/06-extensions.ts`），挂载 `pi.on("tool_call")`——该钩子**可以阻塞执行**并可修改入参：

```
tool_call 事件
   │
   ├─ 只读工具 (read/grep/find/ls)
   │      └─► 自动放行（记录到卡片，不阻塞）
   │
   ├─ 写工具 (edit/write)
   │      └─► 读取目标文件当前内容 → 生成 unified diff → approval_requested(diff)
   │             ├─ 批准 → 放行
   │             ├─ 拒绝 → return { block: true, reason: "用户拒绝了写操作" }
   │             └─ 超时/中止 → 拒绝
   │
   └─ 执行类工具 (bash)
          └─► approval_requested(命令全文 + cwd)
                 ├─ 批准 → 放行
                 ├─ 拒绝 → block
                 └─ 超时/中止 → 拒绝
```

- `approval_requested` 发出后钩子 `await` 一个 Promise，直到 UI 应答（或 abort 解除）。
- **审批 Promise 由 daemon 侧注册表持有**：该 Promise 只有 daemon 自己能 resolve——abort、WS 断开、会话切换时，daemon 必须主动将全部 pending approval 置为拒绝，否则该 turn 永久卡死。
- **拒绝的 reason 会作为工具结果回传给 LLM**：reason 文案须清晰（如“用户拒绝了写操作”），agent 会据此调整行为；需整个 turn 终止时用 `{ block: true, reason, terminate: true }`。
- 并行工具调用的 preflight 是顺序的，同一 turn 实际最多一个 pending approval，UI 按单卡设计即可。
- diff 计算：`edit`/`write` 工具入参含目标路径与新内容，读旧文件 → 用主包导出的 `generateDiffString` / `generateUnifiedPatch` 生成标准 diff，零额外依赖（M0 验证）。
- SDK 内置工具仅 read/bash/edit/write/grep/find/ls 7 个（无 glob/apply_patch/web 工具）；如需 web 搜索等能力，v1 后以 `defineTool()` 注册自定义工具并纳入本分类表。
- 只读放行名单、超时时长在 `settings.json` 可配。

### 6.5 会话管理

- 所有会话以 pi 原生 JSONL 持久化在 `~/.local/share/kairo/sessions/`。
- 单活跃会话：daemon 持有当前 `AgentSessionRuntime`；切换会话时销毁重建（`createAgentSessionRuntime`，参考 `docs/sessions.md` 与 example 11/13）。
- **会话替换后必须重绑**：事件订阅绑定在具体 `AgentSession` 上，替换后自动失效。用 `runtime.setRebindSession(cb)` 注册回调，cb 内完成：①重订阅事件流；②按当前模式重设工具（`setActiveToolsByName`）；③清空该会话的 pending 审批并通知 UI。确认门（内联扩展）随会话重建自动重新挂载，无需手动处理。
- daemon 重启后：恢复最近活跃会话（`SessionManager.listAll(sessionDir)` 按 mtime 排序取最新；不用 `continueRecent(cwd)`——后者只查单一 cwd 子目录，多 cwd 时会漏）。

### 6.6 事件转发与缓冲

- 所有 SDK 事件归一化为上述 WS 事件，原样转发，QML 侧只做渲染。
- 流式期间如果 WS 断开，daemon 缓冲最近事件，重连后补发 `session_state` 快照（模式、会话、最近消息摘要），QML 刷新。

---

## 7. 前端设计（shell/，quickshell）

### 7.1 组件树

```
PopupWindow (kairo)
└── ChatPanel (Column)
    ├── TitleBar        # 会话名 + 模式徽标 + 隐藏按钮
    ├── SessionBar      # 会话列表（下拉/侧滑）：新建、切换、删除
    ├── MessageList     # 滚动消息流（ListView + 流式尾部）
    │   ├── MessageBubble (用户 / 助手)
    │   ├── ThinkingBlock (思考过程，折叠)
    │   └── ToolCard (工具执行：命令/输出/耗时/成功/失败)
    ├── ApprovalDialog  # 确认弹窗：工具卡 + diff 预览 + [批准][拒绝]
    └── InputBar        # 多行输入 + Chat/Command 切换 + [发送][中止]
```

### 7.2 渲染方案

- **流式渲染**：`text_delta` 增量 append 到当前助手消息缓冲；渲染采用"增量更新 + 尾部防抖"策略（如 30ms 合并），避免每 token 全量重排。
- **Markdown**：优先尝试 QML `Text` 的 Markdown 支持（Qt ≥ 6.5 的 `Text.MarkdownText`）；若表格/代码块渲染不满足，则用自带轻量 JS 渲染器（`Markdown.js`）转成富文本片段。**代码块 v1 要求：等宽字体 + 底色块，逐语言高亮作为打磨项。**
- **工具卡**：状态机 `pending → running → succeeded/failed`，运行中显示输出尾部（`tool_execution_update`），失败红标原因。
- **确认弹窗**：diff 以等宽字体双色显示（增绿删红）；命令类显示命令 + cwd；提供 [批准] [拒绝]，Enter=批准，Esc=拒绝。
- **会话列表**：点击切换时先 `POST /api/abort` 停止当前流式，再 `activate`。

### 7.3 交互

| 操作 | 行为 |
|------|------|
| Super+A | 唤起/隐藏浮窗（默认键，可配） |
| Enter | 发送；Shift+Enter 换行 |
| Esc | 隐藏面板；确认弹窗打开时 = 拒绝 |
| `/chat` `/cmd` | 输入框命令切换模式 |
| 消息区 | 自动滚到底（用户上滚时暂停跟随） |

### 7.4 唤起机制

- hyprland `exec-once` 启动 quickshell kairo 项目。
- keybind 执行小脚本：若 quickshell 未运行则启动，否则通过 **DBus 调用** `Toggle`（QML 注册 `org.kairo.Shell` 服务）；M2 阶段验证 quickshell 是否有更原生的 IPC 可用（如有则优先）。

---

## 8. 系统集成

### 8.1 systemd 单元（daemon/）

```ini
# ~/.config/systemd/user/kairo-daemon.service
[Unit]
Description=kairo PI assistant daemon
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/node /home/liborui/Documents/kairo/daemon/dist/main.js
Environment=PI_CODING_AGENT_DIR=%h/.config/kairo/agent
Environment=PI_CODING_AGENT_SESSION_DIR=%h/.local/share/kairo/sessions
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

### 8.2 hyprland 片段

```
exec-once = quickshell -p /home/liborui/Documents/kairo/shell
bind = SUPER, A, exec, /home/liborui/Documents/kairo/scripts/toggle-kairo.sh
```

### 8.3 安装

`scripts/install.sh`：`npm ci && npm run build` → 安装 systemd 单元并 enable → 写入 hyprland 片段（提示用户确认）→ `setup.sh` 导入密钥 → `systemctl --user start kairo-daemon`。后续可打包 AUR。

---

## 9. 里程碑与验收

| 里程碑 | 内容 | 验收标准（真实环境） |
|--------|------|----------------------|
| **M0 技术验证** (spike) | 用 SDK 跑通：建会话、流式事件、工具事件、`tool_call` 阻塞钩子（可行性已验证，落地实现）、`setActiveToolsByName` 模式切换、`generateUnifiedPatch` diff 计算 | 3 个小脚本演示：①流式文本；②工具事件链 + 钩子阻塞一个 edit 并在批准后执行；③模式切换（chat 无工具 / command 全工具） |
| **M1 daemon 骨架** | HTTP/WS API、双模式切换、会话新建/激活/列表、确认队列与 diff | curl + 简易 WS 客户端（`wscat`/脚本）手动跑通全流程；`systemctl --user status` 稳定 |
| **M2 浮窗 + 聊天** | quickshell PopupWindow、输入、流式 Markdown 渲染、唤起键、DBus toggle | Hyprland 里按 Super+A 唤起，与 kairo 纯聊天（Chat 模式），流式渲染流畅 |
| **M3 Command Mode** | 工具卡、确认弹窗（diff 预览）、只读放行、中止 | 让它修改一个测试文件：出现 diff 确认卡→批准→文件更新；拒绝时不落盘；跑 `bash` 命令有确认卡 |
| **M4 会话与打磨** | 会话列表 UI、断线重连、错误处理、install.sh 全自动化、文档 | 完整流程走通：多会话切换不丢上下文；kill daemon 后自动恢复；journalctl 无异常 |

每阶段结束向用户演示验收，可随时停下调整。

---

## 10. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 审批 Promise 生命周期（abort/断连/切会话时未解锁会卡死 turn） | 确认门可靠性 | 审批注册表统一持有并主动拒绝；M0 覆盖“审批中 abort”用例 |
| SDK 嵌入模式 `ctx.hasUI=false`（`ui.confirm` 不可用） | 确认 UI 实现 | 确认门不走 `ctx.ui`，走 daemon 自建 WS 审批流；M0 验证 `ctx.mode` 取值 |
| QML Markdown/流式渲染性能 | 聊天体验 | 防抖增量渲染；代码高亮降级为等宽+底色 |
| WS 断线 / daemon 崩溃 | 会话丢失 | JSONL 天然持久化；重连补发快照；systemd Restart=on-failure |
| quickshell（nix-profile 安装）与 Qt 版本兼容性 | 浮窗渲染 | M2 早验证；必要时改用系统包/AUR 版本 |
| 一次性导入的密钥字段漂移（pi 版本升级） | setup 失效 | setup.sh 做字段级拷贝 + 校验，失败时给出手动指引 |

---

## 11. 默认值与可调项（settings.json）

| 项 | 默认 | 说明 |
|----|------|------|
| 端口 | 44811 | 127.0.0.1 回环 |
| 唤起键 | Super+A | hyprland bind 可改 |
| 默认模式 | command | 持久化上次选择 |
| 默认 cwd | `~/.local/share/kairo/workdir` | 工具工作目录（中性目录，与宿主隔离，见 §5.3） |
| 只读自动放行名单 | read/grep/find/ls（SDK 内置仅此 7 工具，见 §6.4） | 可增删 |
| 确认超时 | 10 分钟 | 超时自动拒绝 |
| 代码高亮 | v1 关闭（等宽+底色） | 打磨项 |
| 界面语言 | 中文 | 跟随系统提示语 |

---

## 12. 开放问题（均已关闭）

1. ~~内联 `extensionFactories` 的 `tool_call` 钩子阻塞 + 修改入参~~ —— 已验证关闭：`{ block: true, reason, terminate }` + `event.input` 可变（`docs/extensions.md` "tool_call"）。
2. ~~quickshell 是否有原生 IPC（优于 DBus toggle）~~ —— **已关闭**：quickshell 0.3 内置 `quickshell ipc call <target> <fn>`（`IpcHandler`，`Quickshell.Io`），toggle-kairo.sh 直接使用，无需 DBus。
3. ~~QML `Text.MarkdownText`（Qt 版本）对表格/代码块的支持程度~~ —— **已关闭（自主实现）**：改用自带轻量 `Markdown.js` 渲染 HTML 到 `Text.RichText`（标题/代码块/列表/引用/表格/链接），Qt 版本差异不敏感。
4. ~~diff 计算~~ —— 已关闭：主包导出 `generateDiffString` / `generateUnifiedPatch`，零依赖。
5. ~~SDK 嵌入模式下 `ctx.mode` / `ctx.hasUI` 的实际取值~~ —— **已关闭**：确认门完全不走 `ctx.ui`，审批 diff/命令经 WS/panel 通道转发，daemon 自建 approval 注册表驱动；`ctx.mode` 未使用。
6. ~~会话显示名读写 API~~ —— **已关闭**：`SessionManager.appendSessionInfo(name)` 写、`getSessionName()` 读，新建会话时经 `newSession({setup})` 注入。
7. 截图/图片输入、模型切换 UI、会话树分支、web 搜索自定义工具 —— 明确推后，不进 v1。

## 13. 实施偏差（M0–M4 落地记录）

| 项 | 计划 | 实施 | 原因/替代 |
|----|------|------|----------|
| 浮窗类型 | PopupWindow | **PanelWindow**（layer-shell，右上角 anchors，exclusiveZone 0、aboveWindows） | PopupWindow 是 xdg_popup，必须附着父窗口；独立随叫随用面板用 layer overlay 更合适 |
| 唤起机制 | DBus toggle | **quickshell 原生 IPC**（`IpcHandler` target=kairo + `quickshell ipc call`） | 优于 DBus，见问题 #2 |
| 面板通道 | WebSocket | **Unix domain socket**（`~/.local/state/kairo/panel.sock`，0600 权限鉴权，换行 JSON） | quickshell 的 `Socket` 是 QLocalSocket（仅本地域套接字），无 TCP/WS 能力；HTTP/WS 仍保留给脚本与测试客户端 |
| 面板控制 API | 纯 HTTP | 面板侧复用事件通道（prompt/mode/sessions_new/activate/delete/get_status 经 `handleClientEvent` 统一处理） | 与 socket 通道一致，WS 客户端同样可用 |
| 浮窗位置 | 右上角（M2 实现） | **左边缘垂直居中**（anchors.left + margins 12） | layer-shell 未锚定维度自动居中；用户要求 |
| 浮窗动画 | 无 | **QML 滑入/滑出**（显示 OutCubic 280ms + 淡入，隐藏 160ms；translate 在屏幕外起止） | Hyprland 窗口动画（windowsIn/windowrule）不作用于 layer 窗口；snippet 保留了改用普通窗口时的 `animation slide` 规则 |
| 主题 | 固定深色 | **深/浅双主题**（`Theme.qml` 双色板；标题栏 🌙/☀️ 按钮 + IPC setTheme/getTheme；daemon 持久化到 settings.json `theme` 字段，重启自动恢复） | 用户要求；浅色板为 GitHub 风格（accent #0969da） |
| daemon 运行 | `/usr/bin/node` | **Node ≥ 24**（pi SDK 要求；`command -v node`） | 宿主 /usr/bin/node 为 v20，undici 报错 |
| 默认 cwd | `$HOME`（§11） | `~/.local/share/kairo/workdir` 中性目录 | 与 §5.3 隔离策略一致，§11 表格同步更正 |
| 会话历史回放（M4 修复） | 切换/新建后回放（`session_history`） | **连接快照也补发 `session_active` + `session_history`**（panel-socket/ws 连接时、`get_status` 响应时），并新增 `session_list` 注入当前活动会话（`listWithActive`），`SessionListItem` 透传 `firstMessage`；**SessionBar 改用固定算术定位**（x=8+56+6，宽=父宽-78），弃用 `RowLayout` + `width: parent.width - newBtn.width - 16` | ①面板重连时 `session_history` 已在 rebindSession（启动/新建/切换）时广播完毕，导致打开面板永远是空白消息区；②SDK `newSession` 推迟落盘（首条助手消息前不写文件），新建会话在磁盘列表中缺失、UI 无活动高亮，且 chip 只显示 8 位 UUID 不可读；③**根因：ListView 宽度绑定在 RowLayout 布局期求值为 0（缺测 `listGeo` 实为 [477,4,0,24]），宽度 0 → 无可见 delegate → 会话栏从未真正渲染过（M4 起一直存在）**。修复后实测：激活 110 条会话→消息区回放 54 条可渲染消息，活动 chip 蓝色高亮 |

## 14. 里程碑状态

| 里程碑 | 状态 | 验收摘要 |
|--------|------|----------|
| M0 技术验证 | ✅ | 3 个演示脚本：流式 / 工具链+审批门 / 模式切换（`daemon/dev-m0/`） |
| M1 daemon 骨架 | ✅ | 15/15 协议验收（`daemon/dev-m1/`）：鉴权/流式/只读放行/审批批准落盘/拒绝不落盘/审批中 abort/会话增删改/重启恢复 |
| M2 浮窗 + 聊天 | ✅ | 真实 Hyprland：Super+A 唤起、流式 Markdown、Socket 通道全流程 0 QML 错误 |
| M3 Command 模式 | ✅ | bash 确认卡（命令+cwd）、edit diff 确认、拒绝不落盘、中止不卡死 4/4 |
| M4 会话与打磨 | ✅ | systemd --user 部署、面板断线自动重连、install.sh/kairoctl/文档 |
