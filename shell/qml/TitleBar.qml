import QtQuick

/**
 * TitleBar.qml — 会话名 + 模式徽标 + 连接状态 + 主题切换 + 隐藏按钮
 */
Item {
  id: tb
  implicitHeight: 34
  width: parent?.width ?? 0

  property var theme: null
  property string sessionName: ""
  property string mode: "command"
  property bool connected: false
  property bool streaming: false
  signal hideRequested()
  signal themeToggleRequested()

  readonly property bool isLight: theme && theme.palette === "light"

  Rectangle {
    width: parent.width
    height: 34
    color: tb.theme ? tb.theme.bgAlt : "#181825"

    Row {
      id: leftRow
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      Rectangle {
        width: 8
        height: 8
        radius: 4
        anchors.verticalCenter: parent.verticalCenter
        color: tb.connected ? (tb.streaming ? tb.theme.yellow : tb.theme.green) : tb.theme.red
      }

      Text {
        text: tb.sessionName !== "" ? tb.sessionName : "kairo"
        color: tb.theme ? tb.theme.text : "#cdd6f4"
        font.pixelSize: 13
        font.bold: true
        elide: Text.ElideMiddle
        width: 210
      }
    }

    // 模式徽标
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: inner.implicitWidth + 18
      height: 20
      radius: 10
      color: tb.mode === "command" ? tb.theme.surface : tb.theme.surfaceAlt
      border.color: tb.mode === "command" ? tb.theme.accent : tb.theme.muted

      Text {
        id: inner
        anchors.centerIn: parent
        text: tb.mode === "command" ? "⚡ Command" : "💬 Chat"
        color: tb.mode === "command" ? tb.theme.accent : tb.theme.subtext
        font.pixelSize: 10
        font.bold: true
      }
    }

    // 主题切换
    Rectangle {
      id: themeBtn
      anchors.right: closeBtn.left
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      width: 22
      height: 22
      radius: 5
      color: "transparent"
      Text {
        anchors.centerIn: parent
        text: tb.isLight ? "☀️" : "🌙"
        color: tb.theme ? tb.theme.subtext : "#a6adc8"
        font.pixelSize: 12
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: tb.themeToggleRequested()
        onEntered: themeBtn.color = tb.theme.surface
        onExited: themeBtn.color = "transparent"
      }
    }

    // 隐藏按钮
    Rectangle {
      id: closeBtn
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      width: 22
      height: 22
      radius: 5
      color: "transparent"
      Text {
        anchors.centerIn: parent
        text: "✕"
        color: tb.theme ? tb.theme.subtext : "#a6adc8"
        font.pixelSize: 13
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: tb.hideRequested()
        onEntered: closeBtn.color = tb.theme.surface
        onExited: closeBtn.color = "transparent"
      }
    }
  }
}