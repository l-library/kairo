import QtQuick
import QtQuick.Layouts
import "Markdown.js" as Md

/**
 * MessageBubble.qml — 单条消息（用户/助手），含思考折叠块 + 工具卡
 *
 * 数据：{ id, role, text, thinking, thinkingOpen, tools: [], status }
 */
Item {
  id: bubble
  implicitHeight: column.implicitHeight
  implicitWidth: parent?.width ?? 0

  required property var row

  readonly property color userBg: "#313244"
  readonly property color assistantBg: "transparent"
  readonly property color userText: "#cdd6f4"

  Column {
    id: column
    width: parent.width
    spacing: 4

    // 角色标签（非必要省略，靠气泡对齐区分）
    // ---- 正文 ----
    Rectangle {
      readonly property bool isUser: row.role === "user"
      width: parent.width
      radius: 8
      color: isUser ? "#313244" : "transparent"
      implicitHeight: contentColumn.implicitHeight + 12

      Column {
        id: contentColumn
        x: 8
        y: 6
        width: parent.width - 16

        // 思考块（可折叠）
        ThinkingBlock {
          id: think
          visible: (row.thinking || "") !== ""
          text: row.thinking || ""
          open: row.thinkingOpen
          onToggle: {
            var obj = bubble.row
            obj.thinkingOpen = !obj.thinkingOpen
            bubble.row = obj // 触发更新
          }
        }

        // 工具卡
        Repeater {
          model: row.tools || []
          delegate: ToolCard {
            required property var modelData
            width: parent.width
            card: modelData
          }
        }

        // 正文（Markdown 富文本）
        Text {
          id: bodyText
          width: parent.width
          textFormat: Text.RichText
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          color: userText
          font.pixelSize: 13
          text: {
            var palette = { codeBg: "#171720", accent: "#89b4fa", muted: "#a6adc8" }
            return Md.mdToHtml(row.text || "", palette)
          }
          onLinkActivated: function (link) {
            Qt.openUrlExternally(link)
          }
        }
      }
    }
  }
}