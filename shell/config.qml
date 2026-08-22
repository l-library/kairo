import Quickshell
import Quickshell.Io
import QtQuick
import "qml"

/**
 * config.qml — kairo 浮窗入口
 *
 * 唤起：Hyprland keybind 执行 scripts/toggle-kairo.sh
 *   - 未运行时：quickshell -p <config>
 *   - 已运行时：quickshell ipc call kairo toggle（原生 IPC，无需 DBus）
 */
PanelWindow {
  id: panel
  visible: false
  implicitWidth: 500
  implicitHeight: 680
  color: "transparent"

  // 右上角浮动 overlay（不占工作区、不被输入焦点抢占）
  anchors {
    top: true
    right: true
  }
  margins {
    top: 12
    right: 12
  }
  exclusiveZone: 0
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  focusable: true

  KairoClient {
    id: client
  }

  ChatPanel {
    id: chat
    anchors.fill: parent
    radius: 12
    client: client
    focus: true
    onHideRequested: {
      // 隐藏时中止当前流式（daemon 侧会拒绝 pending 审批）
      if (client.streaming) client.abort()
      panel.visible = false
    }
  }

  // 原生 IPC：quickshell ipc call kairo toggle
  IpcHandler {
    target: "kairo"

    function toggle(): void {
      panel.visible = !panel.visible
      if (panel.visible) Qt.callLater(chat.focusEditor)
    }

    function show(): void {
      panel.visible = true
      Qt.callLater(chat.focusEditor)
    }

    function hide(): void {
      panel.visible = false
    }

    function isVisible(): bool {
      return panel.visible
    }
  }

  Component.onCompleted: {
    client.connectToDaemon()
  }
}