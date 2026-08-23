import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Markdown.js" as Md

/**
 * ChatPanel.qml — 主面板：标题 + 会话栏 + 消息流 + 确认弹窗 + 输入区
 *
 * 消息模型（ListModel rows）：
 *   { id, role, text, thinking, thinkingOpen, tools: [], status }
 *
 * 流式期间用 JS 累加器（streamAcc）持有当前助手消息的 text/thinking/tools，
 * 防抖（30ms）后将完整快照 set 回 ListModel——避免 ListModel 对 JS 数组的
 * 类型转换问题，也避免每 token 全量重排。
 */
Rectangle {
  id: chat
  color: theme.bg
  width: parent?.width ?? 0
  height: parent?.height ?? 0

  property var client: null // KairoClient 注入
  property var theme: null // Theme 实例注入
  signal hideRequested()
  signal themeToggleRequested()

  // ---- 消息模型 ----
  ListModel {
    id: messageModel
  }

  // 流式累加器；{ row, text, thinking, thinkingOpen, tools: [], status }
  property var streamAcc: null
  // 工具执行中的卡名册：toolCallId → card（指向 streamAcc.tools 内的对象）
  property var toolIndex: ({})
  // 当前视图对应的会话 id（防御同会话的重复 session_active，如自动命名）
  property string _shownSessionId: ""
  // 防抖标记
  property bool dirty: false

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    TitleBar {
      id: titleBar
      Layout.fillWidth: true
      theme: chat.theme
      sessionName: chat.client ? chat.client.sessionName : ""
      mode: chat.client ? chat.client.mode : "command"
      connected: chat.client ? chat.client.connected : false
      streaming: chat.client ? chat.client.streaming : false
      modelLabel: chat.client ? chat.client.modelLabel : ""
      thinkingLevel: chat.client ? chat.client.thinkingLevel : ""
      thinkingLevels: chat.client ? chat.client.thinkingLevels : []
      models: chat.client ? chat.client.models : []
      onHideRequested: chat.hideRequested()
      onThemeToggleRequested: chat.themeToggleRequested()
      onListToggleRequested: sessionSidebar.open = !sessionSidebar.open
      onModelRequested: chat.client.requestModels()
      onModelSelected: function (provider, model) { chat.client.setModel(provider, model) }
      onThinkingSelected: function (level) { chat.client.setThinkingLevel(level) }
    }

    // 消息流：占据剩余高度
    Rectangle {
      id: listArea
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "transparent"

      ListView {
        id: messageList
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        spacing: 8
        model: messageModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: MessageBubble {
          width: messageList.width
          theme: chat.theme
          row: model
          required property var model
        }

        onCountChanged: if (chat._atBottom) positionViewAtEnd()
      }

      // 空状态提示
      Text {
        anchors.centerIn: parent
        visible: messageModel.count === 0
        text: chat.client && chat.client.mode === "chat"
          ? "Chat 模式 · 纯对话\n输入 `/cmd` 切换 Command 模式"
          : "Command 模式 · 可读写文件/执行命令\n输入 `/chat` 切换 Chat 模式"
        color: chat.theme ? chat.theme.emptyHint : "#45475a"
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
      }
    }

    InputBar {
      id: inputBar
      Layout.fillWidth: true
      theme: chat.theme
      mode: chat.client ? chat.client.mode : "command"
      streaming: chat.client ? chat.client.streaming : false
      onSendRequested: function (text) {
        chat.pushUserMessage(text)
        if (text === "/chat") { chat.client.setMode("chat"); return }
        if (text === "/cmd") { chat.client.setMode("command"); return }
        chat.client.sendText(text)
      }
      onModeRequested: function (mode) { chat.client.setMode(mode) }
      onAbortRequested: chat.client.abort()
    }
  }

  // ---- 会话侧边栏（覆盖在消息区上方，☰ 呼出） ----
  // 定位用 x/y 显式传参，不能靠 anchors（anchors 会覆盖滑出动画用的 x）
  SessionSidebar {
    id: sessionSidebar
    topOffset: titleBar.height
    bottomOffset: inputBar.implicitHeight
    theme: chat.theme
    sessions: chat.client ? chat.client.sessions : []
    activeSessionId: chat.client ? chat.client.sessionId : ""
    skills: chat.client ? chat.client.skills : []
    plugins: chat.client ? chat.client.plugins : []
    providers: chat.client ? chat.client.providers : []
    currentProvider: chat.client && chat.client.modelLabel ? chat.client.modelLabel.split("/")[0] : ""
    providerBusy: chat.client ? chat.client.providerBusy : false
    pluginBusy: chat.client ? chat.client.pluginBusy : false
    open: false
    onNewSessionRequested: chat.client.newSession()
    onActivateRequested: function (id) {
      sessionSidebar.open = false
      chat.client.activateSession(id)
    }
    onDeleteRequested: function (id) { chat.client.deleteSession(id) }
    onSkillsRequested: chat.client.requestSkills()
    onPluginsRequested: chat.client.requestPlugins()
    onInstallRequested: function (src) { chat.client.installPlugin(src) }
    onRemoveRequested: function (src) { chat.client.removePlugin(src) }
    onProvidersRequested: chat.client.requestProviders()
    onProviderAddRequested: function (id, key, url) { chat.client.addProvider(id, key, url) }
    onProviderRemoveRequested: function (id) { chat.client.removeProvider(id) }
  }

  // ---- 确认弹窗 ----
  ApprovalDialog {
    id: approval
    anchors.fill: parent
    theme: chat.theme
    approval: chat.client ? chat.client.pendingApproval : null
    allowKeyboard: true
    onResponded: function (allowed) {
      chat.client.respondApproval(allowed)
    }
  }

  // ---- 客户端事件接线 ----
  Connections {
    target: chat.client

    function onSessionEvent(ev) {
      chat.routeEvent(ev)
    }

    function onApprovalsChanged(approval) {
      // 未命中的工具卡标记为等待确认
      var card = chat.toolIndex[approval.id]
      if (card && card.status === "running") {
        card.status = "pending"
        chat.dirty = true
        chat.flush()
      }
    }

    function onApprovalResolved(id, allowed) {
      var card = chat.toolIndex[id]
      if (card) {
        card.status = allowed ? "running" : "rejected"
        if (!allowed) card.output = "（用户拒绝）"
        chat.dirty = true
        chat.flush()
      }
    }
  }

  // ---- 事件路由 ----
  function routeEvent(ev) {
    switch (ev.type) {
      case "message_update": {
        chat.ensureStream()
        if (ev.kind === "text_delta") chat.streamAcc.text += ev.delta
        else if (ev.kind === "thinking_delta") chat.streamAcc.thinking += ev.delta
        else return
        chat.dirty = true
        break
      }
      case "message_end": {
        chat.finishStream()
        break
      }
      case "tool_execution_start": {
        chat.ensureStream()
        var card = {
          id: ev.toolCallId,
          name: ev.toolName,
          args: ev.args || {},
          status: "running",
          output: "",
        }
        chat.streamAcc.tools.push(card)
        chat.toolIndex[ev.toolCallId] = card
        chat.dirty = true
        chat.flush()
        break
      }
      case "tool_execution_update": {
        var cardU = chat.toolIndex[ev.toolCallId]
        if (cardU) {
          var chunk = ev.chunk
          if (typeof chunk === "string" || typeof chunk === "number") {
            cardU.output = (cardU.output + chunk).slice(-3000)
            chat.dirty = true
            chat.flush()
          }
        }
        break
      }
      case "tool_execution_end": {
        var cardE = chat.toolIndex[ev.toolCallId]
        if (cardE) {
          cardE.status = ev.isError ? "error" : "done"
          var res = ev.result
          if (res && typeof res === "object" && "content" in res) {
            cardE.output = String(res.content || "").slice(0, 2000)
          } else if (typeof res === "string") {
            cardE.output = res.slice(0, 2000)
          } else if (res) {
            cardE.output = JSON.stringify(res).slice(0, 2000)
          }
          chat.dirty = true
          chat.flush()
        }
        break
      }
      case "agent_end":
        chat.finishStream()
        chat.flush()
        break
      case "mode_changed":
        chat.pushSystemMessage(ev.mode === "chat" ? "已切换到 Chat 模式（纯对话）" : "已切换到 Command 模式（可读写文件/执行命令）")
        break
      case "session_active":
        // 只有会话真的切换（id 变化）才清屏；同 id 的重复事件（如自动命名）不清，
        // 否则刚完成的对话会突然消失
        if (ev.id !== chat._shownSessionId) {
          chat._shownSessionId = ev.id
          chat.resetMessages()
        }
        break
      case "session_history": {
        // 激活/切换后的历史回放（紧跟在 session_active 后）
        chat._shownSessionId = chat.client ? chat.client.sessionId : ev.id
        chat.resetMessages()
        var msgs = ev.messages || []
        for (var k = 0; k < msgs.length; k++) {
          messageModel.append({
            id: "h" + k,
            role: msgs[k].role,
            text: msgs[k].text,
            thinking: "",
            thinkingOpen: false,
            tools: [],
            status: "done",
          })
        }
        break
      }
      case "error":
        chat.pushSystemMessage(ev.message || "发生错误")
        break
      default:
        break
    }
  }

  // ---- 流式累加器 ----
  function ensureStream() {
    if (chat.streamAcc) return
    var row = messageModel.count
    messageModel.append({
      id: "m" + Date.now(),
      role: "assistant",
      text: "",
      thinking: "",
      thinkingOpen: false,
      tools: [],
      status: "streaming",
    })
    chat.streamAcc = {
      row: row,
      text: "",
      thinking: "",
      thinkingOpen: false,
      tools: [],
      status: "streaming",
    }
    // streamAcc.row 必须等于实际追加行；row 在 append 后 = count-1
    chat.streamAcc.row = messageModel.count - 1
  }

  // 快照写入 ListModel
  function flush() {
    if (!chat.streamAcc) return
    // tools 必须复制为普通数组，ListModel 会做 QVariant 转换
    var toolsCopy = []
    for (var i = 0; i < chat.streamAcc.tools.length; i++) toolsCopy.push(chat.streamAcc.tools[i])
    var obj = {
      id: "m" + Date.now(),
      role: "assistant",
      text: chat.streamAcc.text,
      thinking: chat.streamAcc.thinking,
      thinkingOpen: chat.streamAcc.thinkingOpen,
      tools: toolsCopy,
      status: chat.streamAcc.status,
    }
    // 保留稳定 id：拿原行 id
    var old = messageModel.get(chat.streamAcc.row)
    if (old) obj.id = old.id
    messageModel.set(chat.streamAcc.row, obj)
    chat.dirty = false
  }

  function finishStream() {
    if (!chat.streamAcc) return
    var toolsCopy = []
    for (var i = 0; i < chat.streamAcc.tools.length; i++) toolsCopy.push(chat.streamAcc.tools[i])
    var old = messageModel.get(chat.streamAcc.row)
    messageModel.set(chat.streamAcc.row, {
      id: old ? old.id : "m" + Date.now(),
      role: "assistant",
      text: chat.streamAcc.text,
      thinking: chat.streamAcc.thinking,
      thinkingOpen: chat.streamAcc.thinkingOpen,
      tools: toolsCopy,
      status: "done",
    })
    chat.streamAcc = null
    chat.toolIndex = {}
    chat.dirty = false
  }

  // ---- 消息操作 ----
  function pushUserMessage(text) {
    messageModel.append({
      id: "u" + Date.now(),
      role: "user",
      text: text,
      thinking: "",
      thinkingOpen: false,
      tools: [],
      status: "done",
    })
  }

  function pushSystemMessage(text) {
    messageModel.append({
      id: "s" + Date.now(),
      role: "assistant",
      text: text,
      thinking: "",
      thinkingOpen: false,
      tools: [],
      status: "done",
    })
  }

  function resetMessages() {
    messageModel.clear()
    chat.streamAcc = null
    chat.toolIndex = {}
    chat.dirty = false
  }

  // ---- 防抖刷新 ----
  Timer {
    id: flusher
    interval: 30
    repeat: true
    running: chat.dirty
    onTriggered: chat.flush()
  }

  property bool _atBottom: true

  // 滚动位置跟随
  Connections {
    target: messageList
    function onContentYChanged() {
      chat._atBottom = messageList.contentY >= messageList.contentHeight - messageList.height - 20
    }
    function onContentHeightChanged() {
      if (chat._atBottom) messageList.positionViewAtEnd()
    }
  }

  // 面板级按键：Esc 依次关闭侧边栏/拒绝确认/隐藏面板
  Keys.onEscapePressed: {
    if (sessionSidebar.open) {
      sessionSidebar.open = false
    } else if (chat.client && chat.client.pendingApproval) {
      chat.client.respondApproval(false)
    } else {
      chat.hideRequested()
    }
    event.accepted = true
  }

  function focusEditor() {
    inputBar.focusInput()
  }

  // 临时调试：侧边栏开合状态
  function getSidebarOpen() {
    return sessionSidebar ? sessionSidebar.open : false
  }

  function setSidebarOpen(open) {
    if (sessionSidebar) sessionSidebar.open = open
  }

  // 布局诊断（IPC getDebugInfo 用）
  function getLayoutDebug() {
    return JSON.stringify({
      window: parent ? parent.height : -1,
      title: titleBar.height,
      sidebar: sessionSidebar ? sessionSidebar.height : 0,
      list: listArea.height,
      input: inputBar.height,
      inputImplicit: inputBar.implicitHeight,
    })
  }
}