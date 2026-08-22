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
  property string sessionId: ""
  property string sessionName: ""
  property bool connected: false
  property bool streaming: false
  property bool agentsRunning: false
  property var pendingApproval: null // { id, toolName, target, diff, command, cwd }
  property var sessions: [] // [{id, name, path, ...}]

  // ---- 信号（供 UI 订阅） ----
  signal connectionChanged(var state)
  signal sessionEvent(var ev) // message_*/tool_*/agent_*/turn_*
  signal approvalsChanged(var approval) // 新审批请求
  signal approvalResolved(var id, bool allowed)

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
          client.connectionChanged(true)
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
        // 连接成功：请求当前状态
        client.send({ type: "get_status" })
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