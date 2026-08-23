import QtQuick
import "Markdown.js" as Md

pragma ComponentBehavior: Bound

/**
 * DialogueCard.qml — 对话段渲染卡片
 *
 * 把一段"说话人：内容"的连续行渲染成左右交替的聊天气泡：
 *  - 说话人名牌（accent 色）置于气泡上方，与气泡同侧
 *  - 连续同说话人的行合并进同一气泡（多行）
 *  - 段内的叙述/动作行（如"小红转身离开"）作为普通 Markdown 整行渲染
 *
 * 数据：text（原始对话段文本）、theme
 */
Item {
  id: card
  width: parent.width
  implicitHeight: column.implicitHeight

  property string text: ""
  property var theme: null

  readonly property var groups: Md.dialogueGroups(card.text)

  function mdHtml(md) {
    var palette = {
      codeBg: card.theme ? card.theme.codeBg : "#171720",
      codeText: card.theme ? card.theme.text : "#cdd6f4",
      accent: card.theme ? card.theme.accent : "#89b4fa",
      muted: card.theme ? card.theme.muted : "#a6adc8",
      border: card.theme ? card.theme.border : "#45475a",
    }
    return Md.mdToHtml(md || "", palette)
  }

  Column {
    id: column
    width: parent.width
    spacing: 6

    Repeater {
      model: card.groups

      delegate: Item {
        id: g
        required property var modelData
        width: parent.width
        implicitHeight: modelData.kind === "group"
          ? groupCol.implicitHeight
          : plainText.implicitHeight

        // ---- 说话人气泡组 ----
        Column {
          id: groupCol
          visible: g.modelData.kind === "group"
          width: parent.width
          spacing: 2

          // 说话人名牌（与气泡同侧）
          Text {
            id: nameLabel
            anchors.left: g.modelData.side === "left" ? parent.left : undefined
            anchors.right: g.modelData.side === "right" ? parent.right : undefined
            text: g.modelData.name || ""
            color: card.theme ? card.theme.accent : "#89b4fa"
            font.pixelSize: 10
            font.bold: true
          }

          // 气泡：内容自然宽度收缩，最长不超过行宽 78%
          Rectangle {
            id: bubble
            anchors.left: g.modelData.side === "left" ? parent.left : undefined
            anchors.right: g.modelData.side === "right" ? parent.right : undefined
            width: Math.min(parent.width * 0.78, contentTxt.implicitWidth + 20)
            height: contentTxt.height + 10
            radius: 8
            // 对话气泡的“嘴”角：左气泡收左下角，右气泡收右下角
            topLeftRadius: g.modelData.side === "left" ? 4 : 10
            bottomLeftRadius: g.modelData.side === "left" ? 4 : 10
            topRightRadius: g.modelData.side === "right" ? 4 : 10
            bottomRightRadius: g.modelData.side === "right" ? 4 : 10
            color: card.theme ? card.theme.surface : "#313244"
            border.color: card.theme ? card.theme.border : "#45475a"
            border.width: 1

            Text {
              id: contentTxt
              x: 10
              y: 5
              width: parent.width - 20
              height: contentHeight
              text: (g.modelData.texts || []).join("\n")
              color: card.theme ? card.theme.text : "#cdd6f4"
              font.pixelSize: 13
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }
          }
        }

        // ---- 段内普通行（叙述/动作），整行 Markdown ----
        TextEdit {
          id: plainText
          visible: g.modelData.kind !== "group"
          width: parent.width
          height: contentHeight
          readOnly: true
          selectByMouse: true
          textFormat: Text.RichText
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          color: card.theme ? card.theme.text : "#cdd6f4"
          selectionColor: card.theme ? card.theme.accent : "#89b4fa"
          selectedTextColor: card.theme ? card.theme.onAccent : "#1e1e2e"
          text: card.mdHtml(g.modelData.text || "")
          onLinkActivated: function (link) {
            if (!selectedText) Qt.openUrlExternally(link)
          }
        }
      }
    }
  }
}
