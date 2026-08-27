import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * InputBar.qml — 输入区：模式切换 + 多行输入 + 发送/中止
 */
Item {
  id: inputBar
  width: parent?.width ?? 0

  property var theme: null
  property var i18n: null // I18n 实例注入
  property string mode: "command"
  property bool streaming: false
  signal sendRequested(string text)
  signal modeRequested(string mode)
  signal abortRequested()

  // 真实内容高度：工具条(24) + 间距(1) + 输入框(editor.implicitHeight + 10)
  implicitHeight: 35 + editor.implicitHeight

  Column {
    anchors.fill: parent
    spacing: 1

    // 底部工具条：模式切换 + 快捷键提示
    RowLayout {
      width: parent.width
      height: 24
      spacing: 8

      // Chat / Command 切换
      Item {
        width: 44
        height: 20
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
          id: chatSegWrap
          anchors.fill: parent
          readonly property bool selected: inputBar.mode === "chat"
          radius: 4
          color: chatSegWrap.selected ? inputBar.theme.surface : "transparent"
          border.color: chatSegWrap.selected ? inputBar.theme.subtext : inputBar.theme.border
          Text {
            anchors.centerIn: parent
            text: "Chat"
            color: chatSegWrap.selected ? inputBar.theme.subtext : inputBar.theme.muted
            font.pixelSize: 10
          }
          MouseArea {
            anchors.fill: parent
            onClicked: inputBar.modeRequested("chat")
          }
        }
      }

      Item {
        width: 60
        height: 20
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
          id: cmdSegWrap
          anchors.fill: parent
          readonly property bool selected: inputBar.mode === "command"
          radius: 4
          color: cmdSegWrap.selected ? inputBar.theme.surface : "transparent"
          border.color: cmdSegWrap.selected ? inputBar.theme.accent : inputBar.theme.border
          Text {
            anchors.centerIn: parent
            text: "Command"
            color: cmdSegWrap.selected ? inputBar.theme.accent : inputBar.theme.muted
            font.pixelSize: 10
          }
          MouseArea {
            anchors.fill: parent
            onClicked: inputBar.modeRequested("command")
          }
        }
      }

      Text {
        text: inputBar.i18n ? inputBar.i18n.tr("input.enterHint") : "Enter 发送 · Shift+Enter 换行"
        color: inputBar.theme ? inputBar.theme.faint : "#585b70"
        font.pixelSize: 9
        Layout.alignment: Qt.AlignVCenter
      }

      Item { Layout.fillWidth: true }

      // 发送 / 中止
      Item {
        width: 56
        height: 20
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
          id: sendBtn
          anchors.fill: parent
          readonly property bool actAsStop: inputBar.streaming
          width: actAsStop ? 44 : 56
          height: 22
          radius: 5
          color: actAsStop ? inputBar.theme.red : inputBar.theme.accent
          Text {
            anchors.centerIn: parent
            text: sendBtn.actAsStop
              ? (inputBar.i18n ? inputBar.i18n.tr("input.stop") : "■ 中止")
              : (inputBar.i18n ? inputBar.i18n.tr("input.send") : "发送")
            color: inputBar.theme.onAccent
            font.pixelSize: 10
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (sendBtn.actAsStop) inputBar.abortRequested()
              else inputBar.submit()
            }
          }
        }
      }
    }

    // 输入区
    Rectangle {
      width: parent.width
      height: editor.implicitHeight + 10
      radius: 8
      color: inputBar.theme ? inputBar.theme.surfaceAlt : "#242437"
      TextArea {
        id: editor
        anchors.fill: parent
        anchors.margins: 6
        // Quick Controls TextArea 自带系统浅色默认背景，暗色模式下会盖住外层
        // surfaceAlt 深色底并让浅色文字难以辨认——必须移除，改用外层 Rectangle
        background: null
        color: inputBar.theme ? inputBar.theme.text : "#cdd6f4"
        selectionColor: inputBar.theme ? inputBar.theme.accent : "#89b4fa"
        selectedTextColor: inputBar.theme ? inputBar.theme.onAccent : "#1e1e2e"
        placeholderText: inputBar.streaming
          ? (inputBar.i18n ? inputBar.i18n.tr("input.placeholderStreaming") : "助手回复中…（发送将排队）")
          : (inputBar.i18n ? inputBar.i18n.tr("input.placeholder") : "输入消息…")
        placeholderTextColor: inputBar.theme ? inputBar.theme.faint : "#585b70"
        font.pixelSize: 12
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        Keys.onReturnPressed: function (event) {
          if (event.modifiers & Qt.ShiftModifier) {
            // Shift+Enter 换行：显式插入换行并吞掉事件。
            // 不能依赖默认 fall-through——Quick Controls TextArea 的键盘
            // 事件不会在 Keys 未 accept 时回落到默认换行（fcitx/IME 下
            // 尤其明显），只会什么都不做。
            editor.insert(editor.cursorPosition, "\n")
            event.accepted = true
            return
          }
          event.accepted = true
          inputBar.submit()
        }
      }
    }
  }

  function submit() {
    var text = editor.text.trim()
    if (text === "") return
    editor.text = ""
    inputBar.sendRequested(text)
  }

  function focusInput() {
    editor.forceActiveFocus()
  }
}