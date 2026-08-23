import QtQuick
import QtQuick.Layouts
import "Markdown.js" as Md

/**
 * MessageBubble.qml — 单条消息（用户/助手），含思考折叠块 + 工具卡
 *
 * 数据：{ id, role, text, thinking, thinkingOpen, tools: [], status }
 *
 * v2 变更：
 *  - 正文由 Text 改为只读 TextEdit（selectByMouse + readOnly）——支持
 *    鼠标拖选 + Ctrl+C 复制（Text 元素不支持选中）。
 *  - 每条消息右上角悬停显示 📋 复制按钮，一键复制原始 Markdown。
 */
Item {
  id: bubble
  implicitHeight: column.implicitHeight
  implicitWidth: parent?.width ?? 0

  required property var row
  property var theme: null
  property bool copied: false

  // 复制原始 Markdown 到剪贴板（隐藏 TextEdit + selectAll + copy，兼容各 Qt 版本）
  function copyText(t) {
    copyHelper.text = t
    copyHelper.selectAll()
    copyHelper.copy()
    bubble.copied = true
    copiedTimer.restart()
  }

  TextEdit {
    id: copyHelper
    visible: false
  }
  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: bubble.copied = false
  }

  Column {
    id: column
    width: parent.width
    spacing: 4

    Rectangle {
      readonly property bool isUser: row.role === "user"
      width: parent.width
      radius: 8
      color: isUser ? (bubble.theme ? bubble.theme.surface : "#313244") : "transparent"
      implicitHeight: contentColumn.implicitHeight + 12

      // 气泡级悬停检测：用 HoverHandler（被动指针处理器，即使子项 TextEdit
      // 消费了鼠标事件也能感知悬停）——之前用 MouseArea.containsMouse 受 z 序
      // 影响，悬停文字上时按钮消失。
      HoverHandler {
        id: bubbleHover
      }
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
          theme: bubble.theme
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
            theme: bubble.theme
            card: modelData
          }
        }

        // 正文（Markdown 富文本，可选中复制）
        TextEdit {
          id: bodyText
          width: parent.width
          // TextEdit 不自动撑高——显式跟随内容高度
          height: contentHeight
          readOnly: true
          selectByMouse: true
          textFormat: Text.RichText
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          color: bubble.theme ? bubble.theme.text : "#cdd6f4"
          selectionColor: bubble.theme ? bubble.theme.accent : "#89b4fa"
          selectedTextColor: bubble.theme ? bubble.theme.onAccent : "#1e1e2e"
          text: {
            var palette = {
              codeBg: bubble.theme ? bubble.theme.codeBg : "#171720",
              codeText: bubble.theme ? bubble.theme.text : "#cdd6f4",
              accent: bubble.theme ? bubble.theme.accent : "#89b4fa",
              muted: bubble.theme ? bubble.theme.muted : "#a6adc8",
              border: bubble.theme ? bubble.theme.border : "#45475a",
            }
            return Md.mdToHtml(row.text || "", palette)
          }
          onLinkActivated: function (link) {
            // 拖选时不应误触发；仅在未产生选择时打开链接
            if (!selectedText) Qt.openUrlExternally(link)
          }
        }
      }

      // 复制按钮：悬停气泡时显示在右上角（HoverHandler 检测，悬停文字上
      // 也不会消失）；平时隐藏不遮挡文字。复制成功短暂变绿「已复制」。
      Rectangle {
        id: copyBtn
        visible: bubbleHover.hovered || copyBtnArea.containsMouse || bubble.copied
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        anchors.topMargin: 4
        width: copyTxt.implicitWidth + 14
        height: 20
        radius: 4
        color: bubble.copied
          ? (bubble.theme ? bubble.theme.green : "#a6e3a1")
          : (copyBtnArea.containsMouse ? (bubble.theme ? bubble.theme.surfaceHover : "#3b4261") : (bubble.theme ? bubble.theme.surfaceAlt : "#242437"))
        Text {
          id: copyTxt
          anchors.centerIn: parent
          text: bubble.copied ? "已复制" : "COPY"
          color: bubble.copied ? (bubble.theme ? bubble.theme.onAccent : "#1e1e2e") : (bubble.theme ? bubble.theme.subtext : "#a6adc8")
          font.pixelSize: 9
          font.bold: true
        }
        MouseArea {
          id: copyBtnArea
          anchors.fill: parent
          hoverEnabled: true
          onClicked: bubble.copyText(row.text || "")
        }
      }
    }
  }
}