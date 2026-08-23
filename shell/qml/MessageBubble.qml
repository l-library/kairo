import QtQuick
import QtQuick.Layouts
import "Markdown.js" as Md

pragma ComponentBehavior: Bound

/**
 * MessageBubble.qml — 单条消息（用户/助手），含思考折叠块 + 工具卡
 *
 * 数据：{ id, role, text, thinking, thinkingOpen, tools: [], status }
 *
 * v2 变更：
 *  - 正文由 Text 改为只读 TextEdit（selectByMouse + readOnly）——支持
 *    鼠标拖选 + Ctrl+C 复制（Text 元素不支持选中）。
 *  - 每条消息右上角悬停显示 📋 复制按钮，一键复制原始 Markdown。
 *
 * v3 变更：
 *  - 助手消息正文按空行切“段”渲染：对话段（说话人：内容）→ 聊天气泡
 *    卡片（DialogueCard，左右交替），普通段 → Markdown（段间仅留白）。
 *  - 用户/助手都包气泡：用户 = surface，助手 = surfaceAlt + 细边框。
 *  - 用户消息保持整段单气泡。
 */
Item {
  id: bubble
  implicitHeight: column.implicitHeight
  implicitWidth: parent?.width ?? 0

  required property var row
  property var theme: null
  property bool copied: false

  readonly property bool isUser: bubble.row ? bubble.row.role === "user" : false
  // 助手消息按空行分“段”（代码块内不切）；用户消息不切，整段显示
  readonly property var segments: bubble.isUser ? [] : Md.splitSegments(bubble.row ? bubble.row.text || "" : "")

  // Markdown → HTML（palette 跟随主题），供正文/段内普通行共用
  function mdHtml(md) {
    var palette = {
      codeBg: bubble.theme ? bubble.theme.codeBg : "#171720",
      codeText: bubble.theme ? bubble.theme.text : "#cdd6f4",
      accent: bubble.theme ? bubble.theme.accent : "#89b4fa",
      muted: bubble.theme ? bubble.theme.muted : "#a6adc8",
      border: bubble.theme ? bubble.theme.border : "#45475a",
    }
    return Md.mdToHtml(md || "", palette)
  }

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
      width: parent.width
      radius: 8
      // 用户/助手都包气泡：用户 = 蓝调 userBubble，助手 = surfaceAlt + 细边框
      color: bubble.isUser
        ? (bubble.theme ? bubble.theme.userBubble : "#4b597a")
        : (bubble.theme ? bubble.theme.surfaceAlt : "#242437")
      border.color: bubble.isUser
        ? "transparent"
        : (bubble.theme ? bubble.theme.border : "#45475a")
      border.width: bubble.isUser ? 0 : 1
      implicitHeight: contentColumn.implicitHeight + 14

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

        // ---- 正文 ----
        // 助手消息：按空行切“段”渲染——对话段 → 聊天气泡卡片，普通段 →
        // Markdown（段间仅留白，不再画分割线）；用户消息整段单气泡。
        Repeater {
          id: segRepeater
          visible: !bubble.isUser
          width: parent.width
          model: bubble.isUser ? [] : bubble.segments

          delegate: Column {
            id: seg
            required property var modelData
            width: parent.width
            spacing: 0

            // 段间距：非首段上方留白（对话段 8px / 普通段 6px）
            Item {
              width: parent.width
              height: seg.modelData.first
                ? 0
                : (seg.modelData.kind === "dialogue" ? 8 : 6)
            }

            // 对话段 → 聊天气泡卡片
            DialogueCard {
              id: segCard
              visible: seg.modelData.kind === "dialogue"
              width: parent.width
              text: seg.modelData.text
              theme: bubble.theme
            }

            // 普通段 → Markdown 富文本（可选中复制）
            TextEdit {
              id: narrText
              visible: seg.modelData.kind !== "dialogue"
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
              text: bubble.mdHtml(seg.modelData.text)
              onLinkActivated: function (link) {
                // 拖选时不应误触发；仅在未产生选择时打开链接
                if (!selectedText) Qt.openUrlExternally(link)
              }
            }
          }
        }

        // 用户消息正文（整段 Markdown，可选中复制）
        TextEdit {
          id: userBody
          visible: bubble.isUser
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
          text: bubble.mdHtml(bubble.row ? bubble.row.text || "" : "")
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