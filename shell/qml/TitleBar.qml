import QtQuick

/**
 * TitleBar.qml — 会话名 + 模式徽标 + 连接状态 + 隐藏按钮
 */
Item {
  id: tb
  implicitHeight: 34
  width: parent?.width ?? 0

  property string sessionName: ""
  property string mode: "command"
  property bool connected: false
  property bool streaming: false
  signal hideRequested()

  Rectangle {
    width: parent.width
    height: 34
    color: "#181825"

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
        color: tb.connected ? (tb.streaming ? "#f9e2af" : "#a6e3a1") : "#f38ba8"
      }

      Text {
        text: tb.sessionName !== "" ? tb.sessionName : "kairo"
        color: "#cdd6f4"
        font.pixelSize: 13
        font.bold: true
        elide: Text.ElideMiddle
        width: 240
      }
    }

    // 模式徽标
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: inner.implicitWidth + 18
      height: 20
      radius: 10
      color: tb.mode === "command" ? "#313244" : "#242437"
      border.color: tb.mode === "command" ? "#89b4fa" : "#a6adc8"

      Text {
        id: inner
        anchors.centerIn: parent
        text: tb.mode === "command" ? "⚡ Command" : "💬 Chat"
        color: tb.mode === "command" ? "#89b4fa" : "#a6adc8"
        font.pixelSize: 10
        font.bold: true
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
        color: "#a6adc8"
        font.pixelSize: 13
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: tb.hideRequested()
        onEntered: closeBtn.color = "#313244"
        onExited: closeBtn.color = "transparent"
      }
    }
  }
}