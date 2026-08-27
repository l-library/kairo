import Quickshell
import Quickshell.Io
import QtQuick

/**
 * KairoClient.qml — daemon 面板客户端（Unix socket，换行分隔 JSON）
 *
 * 事件：message_start/update/end、tool_execution_*、approval_*、mode_changed、
 *       session_active/session_list、agent_start/end、status、error
 * 请求：prompt / mode / sessions_new / sessions_activate / sessions_delete / get_status
 */
Item {
  id: client

  // ---- 公共状态 ----
  property string mode: "command"
  property string theme: "dark"
  property string appLanguage: "" // daemon 持久化的语言（zh/en；空 = 未设置）
  property string sessionId: ""
  property string sessionName: ""
  property bool connected: false
  property bool streaming: false
  property bool agentsRunning: false
  property var pendingApproval: null // { id, toolName, target, diff, command, cwd }
  property var sessions: [] // [{id, name, path, ...}]
  // 模型 / 思维等级 / 技能 / 插件
  property string modelLabel: "" // provider/id
  property string thinkingLevel: ""
  property var thinkingLevels: []
  property var models: [] // [{provider, id, name, reasoning, authed, current}]
  property var skills: [] // [{name, description, path}]
  property var plugins: [] // [{source, scope, installedPath}]
  property var providers: [] // [{id, authed, modelCount, removable}]
  // 安装/添加进行中（UI 反馈用）
  property bool providerBusy: false
  property bool pluginBusy: false

  // ---- 信号（供 UI 订阅） ----
  signal connectionChanged(var state)
  signal sessionEvent(var ev) // message_*/tool_*/agent_*/turn_*
  signal approvalsChanged(var approval) // 新审批请求
  signal approvalResolved(var id, bool allowed)
  signal themePaletteChanged(string palette)
  // 语言变化信号 = appLanguage 的自动生成信号 appLanguageChanged（赋值即触发）

  function connectToDaemon() {
    var home = ""
    try {
      home = String(Quickshell.env("HOME"))
    } catch (e) {
      home = ""
    }
    sock.path = home + "/.local/state/kairo/panel.sock"
    sock.connected = true
  }

  function send(obj) {
    if (sock.connected) sock.write(JSON.stringify(obj) + "\n")
  }

  // ---- UI 调用的请求 ----
  function sendText(text) {
    client.streaming = true
    send({ type: "prompt", message: text })
  }

  function setMode(m) {
    send({ type: "mode", mode: m })
  }

  function newSession(name) {
    send({ type: "sessions_new", name: name || undefined })
  }

  function activateSession(id) {
    send({ type: "sessions_activate", id: id })
  }

  function deleteSession(id) {
    send({ type: "sessions_delete", id: id })
  }

  function respondApproval(allowed) {
    if (!client.pendingApproval) return
    send({ type: allowed ? "approve" : "reject", id: client.pendingApproval.id })
    client.pendingApproval = null
  }

  function abort() {
    send({ type: "cancel" })
  }

  function setTheme(p) {
    if (p !== "dark" && p !== "light") return
    send({ type: "theme_set", theme: p })
  }

  // ---- 模型 / 思维等级 ----
  function requestModels() {
    send({ type: "models_list" })
  }

  function setModel(provider, model) {
    send({ type: "model_set", provider: provider, model: model })
  }

  function setThinkingLevel(level) {
    send({ type: "thinking_set", level: level })
  }

  // ---- 技能 / 插件 ----
  function requestSkills() {
    send({ type: "skills_list" })
  }

  function requestPlugins() {
    send({ type: "plugins_list" })
  }

  function installPlugin(source) {
    send({ type: "plugins_install", source: source })
  }

  function removePlugin(source) {
    send({ type: "plugins_remove", source: source })
  }

  // ---- 提供商 ----
  function requestProviders() {
    send({ type: "providers_list" })
  }

  function addProvider(id, apiKey, baseUrl) {
    send({ type: "provider_add", id: id, apiKey: apiKey, baseUrl: baseUrl })
  }

  function removeProvider(id) {
    send({ type: "provider_remove", id: id })
  }

  // ---- 语言 ----
  function setLocale(l) {
    if (l !== "zh" && l !== "en") return
    send({ type: "locale_set", locale: l })
  }

  // ---- 协议处理 ----
  QtObject {
    id: protocol
    property string buffer: ""

    function consume(line) {
      var ev
      try {
        ev = JSON.parse(line)
      } catch (e) {
        return
      }
      switch (ev.type) {
        case "status":
          client.mode = ev.status.mode
          client.sessionId = ev.status.sessionId
          client.sessionName = ev.status.sessionName || ""
          client.streaming = ev.status.streaming
          client.agentsRunning = ev.status.streaming
          client.modelLabel = ev.status.model || client.modelLabel
          client.thinkingLevel = ev.status.thinkingLevel || client.thinkingLevel
          client.connectionChanged(true)
          break
        case "theme_changed":
          if (ev.theme !== client.theme) {
            client.theme = ev.theme
            client.themePaletteChanged(ev.theme)
          } else {
            // 连接后被动的同值事件也要触发一次，确保面板初始应用
            client.themePaletteChanged(ev.theme)
          }
          break
        case "locale_changed":
          if (ev.locale !== client.appLanguage) {
            client.appLanguage = ev.locale // 赋值自动触发 appLanguageChanged
          }
          break
        case "mode_changed":
          client.mode = ev.mode
          client.sessionEvent(ev)
          break
        case "session_active":
          client.sessionId = ev.id
          client.sessionName = ev.name || ""
          client.sessionEvent(ev)
          break
        case "session_list":
          client.sessions = ev.sessions || []
          client.sessionEvent(ev)
          break
        case "model_changed":
          client.modelLabel = ev.provider ? ev.provider + "/" + (ev.model || "") : (ev.model || "")
          client.thinkingLevel = ev.thinkingLevel || ""
          client.thinkingLevels = ev.thinkingLevels || client.thinkingLevels
          client.sessionEvent(ev)
          break
        case "models_response":
          client.models = ev.models || []
          client.sessionEvent(ev)
          break
        case "skills_response":
          client.skills = ev.skills || []
          client.sessionEvent(ev)
          break
        case "plugins_response":
        case "plugins_changed":
          client.plugins = ev.plugins || []
          client.pluginBusy = false
          client.sessionEvent(ev)
          break
        case "providers_response":
        case "providers_changed":
          client.providers = ev.providers || []
          client.providerBusy = false
          client.sessionEvent(ev)
          break
        case "approval_requested":
          client.pendingApproval = ev
          client.approvalsChanged(ev)
          break
        case "approval_resolved":
          if (client.pendingApproval && client.pendingApproval.id === ev.id) client.pendingApproval = null
          client.approvalResolved(ev.id, ev.allowed)
          client.sessionEvent(ev)
          break
        case "agent_start":
          client.agentsRunning = true
          client.streaming = true
          client.sessionEvent(ev)
          break
        case "agent_end":
          client.agentsRunning = false
          client.streaming = false
          client.sessionEvent(ev)
          break
        case "error":
          client.providerBusy = false
          client.pluginBusy = false
          client.sessionEvent(ev)
          break
        default:
          client.sessionEvent(ev)
      }
    }
  }

  // ---- 断线重连（2s 间隔 + 上限） ----
  property int reconnectAttempts: 0
  Timer {
    id: reconnectTimer
    interval: 2000
    repeat: true
    running: !sock.connected && client.reconnectAttempts < 30
    onTriggered: {
      client.reconnectAttempts++
      if (!sock.connected) sock.connected = true // 触发重连
    }
  }

  Socket {
    id: sock

    // 数据流按换行分片：SplitParser 自动缓冲，read(data) 每次一个完整 JSON 行
    parser: SplitParser {
      splitMarker: "\n"
      onRead: (data) => {
        if (!data || !String(data).trim()) return
        protocol.consume(String(data).trim())
      }
    }

    onConnectionStateChanged: {
      client.connected = sock.connected
      if (sock.connected) {
        client.reconnectAttempts = 0
        // 连接成功：请求当前状态 + 模型清单（模型选择器数据）
        client.send({ type: "get_status" })
        client.send({ type: "theme_get" })
        client.send({ type: "locale_get" })
        client.send({ type: "models_list" })
        client.send({ type: "providers_list" })
      } else {
        client.connected = false
      }
      client.connectionChanged({
        connected: sock.connected,
        path: sock.path,
      })
    }

    onError: (error) => {
      if (sock.path) console.log("[KairoClient] socket 错误，2s 后重连:", error)
    }
  }
}