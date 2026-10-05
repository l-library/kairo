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
  property var i18n: null // I18n 实例注入
  signal hideRequested()
  signal themeToggleRequested()

  // ---- 消息模型 ----
  ListModel {
    id: messageModel
  }

  // 流式累加器；{ row, text, thinking, tools: [], status }
  // thinkingOpen 是纯 UI 状态（用户点击展开/折叠），保存在消息行本身，
  // 不进流式快照——否则 30ms 防抖刷新会把它盖回 false（思考中点开即弹回）。
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
      radius: chat.radius
      theme: chat.theme
      i18n: chat.i18n
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

      // 消息流：Flickable + 全量 Repeater（不用 ListView）。
      // ListView 按已实例化的代理估算 contentHeight，滚动时估算不断修正 →
      // 滚动条长度跳变、难以拖拽；重开面板后估算回退还会让停留位置漂移。
      // 这里 contentHeight = 消息列实际高度，滚动条长度稳定，contentY 原样保留。
      Flickable {
        id: messageList
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: messageColumn.height

        Column {
          id: messageColumn
          width: messageList.width
          spacing: 12

          Repeater {
            model: messageModel
            delegate: MessageBubble {
              width: messageColumn.width
              theme: chat.theme
              i18n: chat.i18n
              row: model
              required property var model
              required property int index
              onThinkingToggleRequested: chat.toggleThinking(index)
            }
          }
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }

      // 空状态提示
      Text {
        anchors.centerIn: parent
        visible: messageModel.count === 0
        text: !chat.client || chat.client.mode === "command"
          ? (chat.i18n ? chat.i18n.tr("chat.emptyHint.command") : "Command 模式 · 可读写文件/执行命令\n输入 `/chat` 切换 Chat 模式")
          : chat.client.mode === "qa"
            ? (chat.i18n ? chat.i18n.tr("chat.emptyHint.qa") : "问答模式 · 一问一答，不留记录\n输入 `/cmd` 切换 Command 模式")
            : (chat.i18n ? chat.i18n.tr("chat.emptyHint.chat") : "Chat 模式 · 纯对话\n输入 `/cmd` 切换 Command 模式")
        color: chat.theme ? chat.theme.emptyHint : "#45475a"
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
      }
    }

    InputBar {
      id: inputBar
      Layout.fillWidth: true
      theme: chat.theme
      i18n: chat.i18n
      mode: chat.client ? chat.client.mode : "command"
      streaming: chat.client ? chat.client.streaming : false
      onSendRequested: function (text) {
        chat.pushUserMessage(text)
        if (text === "/chat") { chat.client.setMode("chat"); return }
        if (text === "/cmd") { chat.client.setMode("command"); return }
        if (text === "/qa") { chat.client.setMode("qa"); return }
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
    i18n: chat.i18n
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
    i18n: chat.i18n
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
        if (!allowed) card.output = chat.i18n ? chat.i18n.tr("chat.userRejected") : "（用户拒绝）"
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
        if (ev.mode === "chat")
          chat.pushSystemMessage(chat.i18n ? chat.i18n.tr("chat.modeSwitchedChat") : "已切换到 Chat 模式（纯对话）")
        else if (ev.mode === "qa")
          chat.pushSystemMessage(chat.i18n ? chat.i18n.tr("chat.modeSwitchedQa") : "已切换到问答模式（一问一答，不留记录）")
        else
          chat.pushSystemMessage(chat.i18n ? chat.i18n.tr("chat.modeSwitchedCommand") : "已切换到 Command 模式（可读写文件/执行命令）")
        break
      case "session_active":
        // 只有会话真的切换（id 变化）才清屏；同 id 的重复事件（如自动命名）不清，
        // 否则刚完成的对话会突然消失。问答模式的“清屏后回填本轮提问”由 daemon
        // 在轮换后紧跟着广播 session_history 完成，UI 不记忆任何待回填消息。
        if (ev.id !== chat._shownSessionId) {
          // 切走前把旧会话的停留位置存起来（切回来时能恢复）
          chat.saveScrollFor(chat._shownSessionId)
          chat._shownSessionId = ev.id
          chat.resetMessages()
        }
        break
      case "session_history": {
        // 重放前先把当前视图的位置存回本会话（daemon 重启重连时位置不回退；
        // 首连/切换时模型为空，saveScrollFor 内部会跳过）
        chat.saveScrollFor(chat._shownSessionId)
        // 激活/切换后的历史回放（紧跟在 session_active 后；问答轮换时含本轮提问）
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
        // 回放完成后按会话恢复上次的滚动停留位置
        chat.beginScrollRestore()
        break
      }
      case "error":
        chat.pushSystemMessage(ev.message || (chat.i18n ? chat.i18n.tr("chat.errorGeneric") : "发生错误"))
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
    var old = messageModel.get(chat.streamAcc.row)
    var obj = {
      id: old ? old.id : "m" + Date.now(),
      role: "assistant",
      text: chat.streamAcc.text,
      thinking: chat.streamAcc.thinking,
      // 保留用户当前的展开状态（UI 状态，不被流式快照覆盖）
      thinkingOpen: old ? old.thinkingOpen : false,
      tools: toolsCopy,
      status: chat.streamAcc.status,
    }
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
      // 保留用户当前的展开状态（UI 状态，不被流式快照覆盖）
      thinkingOpen: old ? old.thinkingOpen : false,
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

  // 思考块展开/折叠：写回消息行（而非临时改代理对象），流式刷新后才不会弹回。
  function toggleThinking(idx) {
    var r = messageModel.get(idx)
    if (!r) return
    messageModel.setProperty(idx, "thinkingOpen", !r.thinkingOpen)
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

  // ---- 滚动停留位置记忆：关闭/切会话时保存，历史回放后恢复 ----
  property string _restoreSession: "" // 待恢复的会话 id（校验 scroll_state 响应）
  property real _restoreY: 0
  property bool _restoreAtBottom: false
  property bool restorePending: false // true = 等内容高度稳定后一次性落位

  function scrollToEnd() {
    messageList.contentY = Math.max(0, messageList.contentHeight - messageList.height)
  }

  // 滚动位置跟随：贴底时新内容/高度变化都保持贴底；非贴底时 contentY 原样保留
  Connections {
    target: messageList
    function onContentYChanged() {
      chat._atBottom = messageList.contentY >= messageList.contentHeight - messageList.height - 20
    }
    function onContentHeightChanged() {
      // 恢复期间不跟随，等高度稳定后由 restoreSettle 一次性落位
      if (chat.restorePending) { restoreSettle.restart(); return }
      if (chat._atBottom) chat.scrollToEnd()
    }
    // 面板隐藏/重开时视图高度可能经过 0——贴底状态在高度恢复后重新贴底
    function onHeightChanged() {
      if (chat.restorePending) { restoreSettle.restart(); return }
      if (chat._atBottom) chat.scrollToEnd()
    }
    // 用户手动滚动 = 取消待恢复，不抢用户的操作
    function onMovementStarted() {
      chat.restorePending = false
    }
  }

  // 把指定会话的当前停留位置上报 daemon 持久化（关闭面板 / 切换会话时调用）
  function saveScrollFor(sessionId) {
    if (!chat.client || !sessionId || messageModel.count === 0) return
    chat.client.saveScrollState(sessionId, messageList.contentY, chat._atBottom)
  }

  // 历史回放完成后：向 daemon 拉取该会话上次的停留位置
  function beginScrollRestore() {
    if (!chat.client || !chat.client.sessionId) return
    chat.restorePending = false // 作废旧会话的待恢复，防止迟到响应串台
    chat._restoreSession = chat.client.sessionId
    chat.client.requestScrollState(chat.client.sessionId)
  }

  // 应用恢复：贴底回到底部，否则回到保存的 contentY（夹紧到有效范围）。
  // pos 为 null（该会话从没保存过）→ 保持回放后的顶部，与旧行为一致。
  function applyScrollRestore() {
    if (!chat.restorePending) return
    chat.restorePending = false
    var maxY = Math.max(0, messageList.contentHeight - messageList.height)
    if (chat._restoreAtBottom) {
      messageList.contentY = maxY
    } else if (chat._restoreY > 0) {
      messageList.contentY = Math.min(chat._restoreY, maxY)
    }
  }

  // 内容高度稳定 150ms 后应用恢复（代理逐个实例化，contentHeight 分多次到位）
  Timer {
    id: restoreSettle
    interval: 150
    onTriggered: chat.applyScrollRestore()
  }

  Connections {
    target: chat.client
    function onScrollStateReceived(state) {
      if (!state || state.sessionId !== chat._restoreSession) return
      if (!state.pos) { chat.restorePending = false; return }
      chat._restoreY = Number(state.pos.y) || 0
      chat._restoreAtBottom = state.pos.atBottom === true
      chat.restorePending = true
      restoreSettle.restart()
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
      scroll: {
        y: Math.round(messageList.contentY * 10) / 10,
        contentH: Math.round(messageList.contentHeight * 10) / 10,
        viewH: Math.round(messageList.height * 10) / 10,
        atBottom: chat._atBottom,
        count: messageModel.count,
      },
    })
  }

  // 调试/测试辅助：消息列表与消息行原始状态（getDebugInfo 同源）
  function getMessageList() { return messageList }
  function getMessageRow(i) { return messageModel.get(i) }
  function getMessageCount() { return messageModel.count }
}