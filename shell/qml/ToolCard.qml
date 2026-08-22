import QtQuick
import QtQuick.Layouts

/**
 * ToolCard.qml — 工具执行卡片
 *
 * card = { id, name, args, status: "pending"|"running"|"rejected"|"done"|"error", output }
 */
Item {
  implicitHeight: body.implicitHeight + 10
  implicitWidth: parent?.width ?? 0

  required property var card

  readonly property string toolName: {
    if (!card) return ""
    var n = card.name
    var args = card.args || {}
    if (n === "bash") return "bash $" + (args.command || "")
    if (n === "edit" || n === "write") return n + " " + (args.path || "")
    if (n === "read") return "read " + (args.path || "")
    if (n === "grep" || n === "find" || n === "ls") return n
    return n || ""
  }

  readonly property bool isError: card.status === "error"
  readonly property bool isRejected: card.status === "rejected"
  readonly property color stateColor: {
    if (isError) return "#f38ba8"
    if (isRejected) return "#f9e2af"
    if (card.status === "done") return "#a6e3a1"
    return "#89b4fa"
  }

  readonly property string stateIcon: {
    if (isError) return "✗"
    if (isRejected) return "⛔"
    if (card.status === "done") return "✓"
    if (card.status === "pending") return "⏳"
    return "◌" // running
  }

  Rectangle {
    width: parent.width
    height: body.implicitHeight + 10
    radius: 6
    color: "#242437"
    border.color: stateColor
    border.width: 1

    Column {
      id: body
      x: 8
      y: 5
      width: parent.width - 16
      spacing: 4

      Row {
        width: parent.width
        spacing: 6
        Text {
          text: stateIcon
          color: stateColor
          font.pixelSize: 11
        }
        Text {
          text: toolName
          color: stateColor
          font.pixelSize: 11
          font.family: "monospace"
          elide: Text.ElideMiddle
          width: parent.width - 22
        }
      }

      // 输出尾部
      Text {
        visible: (card.output || "") !== ""
        width: parent.width
        text: card.output || ""
        color: "#a6adc8"
        font.family: "monospace"
        font.pixelSize: 11
        wrapMode: Text.WrapAnywhere
        elide: Text.ElideRight
        maximumLineCount: 6
      }
    }
  }
}