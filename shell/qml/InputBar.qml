import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * InputBar.qml — 输入区：模式切换 + 多行输入 + 发送/中止
 */
Item {
  id: inputBar
  width: parent?.width ?? 0

  property string mode: "command"
  property bool streaming: false
  signal sendRequested(string text)
  signal modeRequested(string mode)
  signal abortRequested()

  implicitHeight: 20 + editor.implicitHeight

  Column {
    anchors.fill: parent
    spacing: 1

    // 底部工具条：模式切换 + 快捷键提示
    RowLayout {
      width: parent.width
      height: 24
      spacing: 8

      // Chat / Command 切换（Item 包装以在 RowLayout 内垂直居中）
      Item {
        width: 44
        height: 20
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
          id: chatSegWrap
          anchors.fill: parent
          readonly property bool selected: inputBar.mode === "chat"
          radius: 4
          color: chatSegWrap.selected ? "#313244" : "transparent"
          border.color: chatSegWrap.selected ? "#a6adc8" : "#3b4261"
          Text {
            anchors.centerIn: parent
            text: "Chat"
            color: chatSegWrap.selected ? "#a6adc8" : "#6c7086"
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
          color: cmdSegWrap.selected ? "#313244" : "transparent"
          border.color: cmdSegWrap.selected ? "#89b4fa" : "#3b4261"
          Text {
            anchors.centerIn: parent
            text: "Command"
            color: cmdSegWrap.selected ? "#89b4fa" : "#6c7086"
            font.pixelSize: 10
          }
          MouseArea {
            anchors.fill: parent
            onClicked: inputBar.modeRequested("command")
          }
        }
      }

      Text {
        text: "Enter 发送 · Shift+Enter 换行"
        color: "#585b70"
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
          color: actAsStop ? "#f38ba8" : "#89b4fa"
          Text {
            anchors.centerIn: parent
            text: sendBtn.actAsStop ? "■ 中止" : "发送"
            color: "#1e1e2e"
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
      color: "#242437"
      TextArea {
        id: editor
        anchors.fill: parent
        anchors.margins: 6
        color: "#cdd6f4"
        placeholderText: inputBar.streaming ? "助手回复中…（发送将排队）" : "输入消息…"
        placeholderTextColor: "#585b70"
        font.pixelSize: 12
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        Keys.onReturnPressed: function (event) {
          if (event.modifiers & Qt.ShiftModifier) {
            return // 换行
          }
          inputBar.submit()
          event.accepted = true
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