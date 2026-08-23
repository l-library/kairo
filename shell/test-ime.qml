import Quickshell
import QtQuick
import QtQuick.Controls

// 一次性 IME 冒烟测试：聚焦一个 TextEdit，观察 fcitx 输入上下文是否创建
FloatingWindow {
  visible: true
  width: 300
  height: 100

  TextArea {
    id: editor
    anchors.fill: parent
    placeholderText: "中文输入测试"
    Component.onCompleted: editor.forceActiveFocus()
  }

  Component.onCompleted: {
    // 等待焦点稳定后由外部读日志判断
    console.log("IME-TEST editor focused, IM module env =", Qt.platform.pluginName)
  }
}