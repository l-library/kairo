import QtQuick

/**
 * I18n.qml — kairo 双语支持（zh / en）
 *
 * 用法（与 Theme.qml 同样的注入模式）：
 *   - config.qml 实例化一份（id: i18n），传入 ChatPanel → 各子组件。
 *   - 文案绑定写成 `i18n.tr("key")`；语言切换时（i18n.lang 变化 → effective
 *     重新求值）所有引用 tr() 的绑定会自动重估，无需手动刷新。
 *
 * 语言状态：
 *   - lang 为空（""）= 未显式设置 → effective 按系统 locale 自动（zh* → zh，其余 → en）
 *   - 用户在 TitleBar 语言 chip 切换 → setLang() 发出 localeChanged 信号，
 *     config.qml 捕获后经 KairoClient.setLocale() 持久化到 daemon settings.json；
 *     daemon 回传 locale_changed → 同一信号路径 setLang()（幂等，不再发信号）。
 *
 * 占位符：tr("key", {"n": 3}) → 将文案中的 {n} 替换为参数（用于 "会话 (n)" 等）。
 * en 缺失的键自动回退中文，再回退键名本身。
 */
Item {
  id: i18n
  width: 0
  height: 0

  // 显式语言；"" = 未设置（自动检测）
  property string lang: ""

  // 实际生效语言（lang 有值优先，否则按系统 locale）
  readonly property string effective: i18n.lang !== ""
    ? i18n.lang
    : i18n.autoLang()

  // 用户主动切换（或 daemon 回传生效）语言时发出
  signal localeChanged(string l)

  function autoLang() {
    try {
      var name = String(Qt.locale().name || "").toLowerCase()
      if (name.indexOf("zh") === 0) return "zh"
    } catch (e) { /* ignore */ }
    return "en"
  }

  // ---------- 字典 ----------
  readonly property var zh: ({
    // TitleBar
    "titlebar.modelPlaceholder": "模型",
    "titlebar.thinking": "思维:",
    "titlebar.modelPopupNote": "模型（未鉴权不可选）",
    "titlebar.unauth": "未鉴权",
    // InputBar
    "input.enterHint": "Enter 发送 · Shift+Enter 换行",
    "input.stop": "■ 中止",
    "input.send": "发送",
    "input.placeholderStreaming": "助手回复中…（发送将排队）",
    "input.placeholder": "输入消息…",
    // ChatPanel
    "chat.emptyHint.chat": "Chat 模式 · 纯对话\n输入 `/cmd` 切换 Command 模式",
    "chat.emptyHint.command": "Command 模式 · 可读写文件/执行命令\n输入 `/chat` 切换 Chat 模式",
    "chat.userRejected": "（用户拒绝）",
    "chat.modeSwitchedChat": "已切换到 Chat 模式（纯对话）",
    "chat.modeSwitchedCommand": "已切换到 Command 模式（可读写文件/执行命令）",
    "chat.errorGeneric": "发生错误",
    // SessionSidebar
    "sidebar.newSession": "新会话",
    "sidebar.sessions": "会话 ({n})",
    "sidebar.settings": "设置 ({n})",
    "sidebar.newBtn": "＋ 新建会话",
    "sidebar.confirmDelete": "确认删除",
    "sidebar.providers": "提供商 ({n})",
    "sidebar.authed": "已鉴权",
    "sidebar.unauth": "未鉴权",
    "sidebar.modelsCount": "{n} 模型",
    "sidebar.addProviderNote": "添加提供商（baseUrl 留空则用 SDK 内置目录）",
    "sidebar.providerIdPlaceholder": "如 my-llm",
    "sidebar.baseUrlPlaceholder": "可选，OpenAI 兼容端点",
    "sidebar.adding": "添加中…",
    "sidebar.add": "添加",
    "sidebar.skills": "技能 ({n})",
    "sidebar.skillsManualNote": "手动安装技能见 docs/skills.md · 或直接问我",
    "sidebar.plugins": "插件 ({n})",
    "sidebar.scopeProject": "项目",
    "sidebar.scopeUser": "用户",
    "sidebar.pluginPlaceholder": "npm 包名 / git 地址…",
    "sidebar.installing": "安装中…",
    "sidebar.install": "安装",
    // ApprovalDialog
    "approval.title": "确认操作",
    "approval.file": "文件: ",
    "approval.approve": "批准 (Enter)",
    "approval.reject": "拒绝 (Esc)",
    "approval.commandHint": "命令将在宿主环境执行，请确认命令内容安全",
    // MessageBubble
    "bubble.copied": "已复制",
    // ThinkingBlock
    "thinking.title": "思考过程"
  })

  readonly property var en: ({
    // TitleBar
    "titlebar.modelPlaceholder": "Model",
    "titlebar.thinking": "Thinking:",
    "titlebar.modelPopupNote": "Models (auth required)",
    "titlebar.unauth": "unauthorized",
    // InputBar
    "input.enterHint": "Enter to send · Shift+Enter for newline",
    "input.stop": "■ Stop",
    "input.send": "Send",
    "input.placeholderStreaming": "Assistant replying… (send will queue)",
    "input.placeholder": "Type a message…",
    // ChatPanel
    "chat.emptyHint.chat": "Chat mode · conversation only\nType `/cmd` to switch to Command mode",
    "chat.emptyHint.command": "Command mode · read/write files & run commands\nType `/chat` to switch to Chat mode",
    "chat.userRejected": "(rejected by user)",
    "chat.modeSwitchedChat": "Switched to Chat mode (conversation only)",
    "chat.modeSwitchedCommand": "Switched to Command mode (files & commands enabled)",
    "chat.errorGeneric": "An error occurred",
    // SessionSidebar
    "sidebar.newSession": "New session",
    "sidebar.sessions": "Sessions ({n})",
    "sidebar.settings": "Settings ({n})",
    "sidebar.newBtn": "＋ New session",
    "sidebar.confirmDelete": "Confirm delete",
    "sidebar.providers": "Providers ({n})",
    "sidebar.authed": "authenticated",
    "sidebar.unauth": "unauthorized",
    "sidebar.modelsCount": "{n} models",
    "sidebar.addProviderNote": "Add provider (leave baseUrl empty to use the SDK built-in catalog)",
    "sidebar.providerIdPlaceholder": "e.g. my-llm",
    "sidebar.baseUrlPlaceholder": "optional, OpenAI-compatible endpoint",
    "sidebar.adding": "Adding…",
    "sidebar.add": "Add",
    "sidebar.skills": "Skills ({n})",
    "sidebar.skillsManualNote": "Manual skill install: see docs/skills.md · or just ask me",
    "sidebar.plugins": "Plugins ({n})",
    "sidebar.scopeProject": "project",
    "sidebar.scopeUser": "user",
    "sidebar.pluginPlaceholder": "npm package / git URL…",
    "sidebar.installing": "Installing…",
    "sidebar.install": "Install",
    // ApprovalDialog
    "approval.title": "Confirm action",
    "approval.file": "File: ",
    "approval.approve": "Approve (Enter)",
    "approval.reject": "Reject (Esc)",
    "approval.commandHint": "The command will run in your system environment — make sure it is safe.",
    // MessageBubble
    "bubble.copied": "Copied",
    // ThinkingBlock
    "thinking.title": "Thinking"
  })

  /** 取当前语言文案（en 缺失回退 zh，再回退键名） */
  function tr(key, params) {
    var table = i18n.effective === "en" ? i18n.en : i18n.zh
    var s = table[key]
    if (s === undefined) s = i18n.zh[key]
    if (s === undefined) s = key
    if (params) {
      for (var k in params) {
        s = s.split("{" + k + "}").join(String(params[k]))
      }
    }
    return s
  }

  /** 设置语言（zh/en）；变化时发出 localeChanged 供持久化 */
  function setLang(l) {
    if (l !== "zh" && l !== "en") return
    if (i18n.lang !== "" && i18n.lang === l) return
    i18n.lang = l
    i18n.localeChanged(l)
  }
}