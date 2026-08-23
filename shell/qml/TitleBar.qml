import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts

/**
 * TitleBar.qml — ☰(左) + 会话名 + 模型/思维选择 + 连接状态 + 主题切换 + 隐藏按钮
 * 注：面板内容宽 625（layer 物理宽），元素按 625 布局；模式切换在底部 InputBar
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
  // 模型（GUI 修改模型）
  property string modelLabel: ""
  property string thinkingLevel: ""
  property var thinkingLevels: []
  property var models: []
  signal hideRequested()
  signal themeToggleRequested()
  signal listToggleRequested()
  signal modelRequested()
  signal modelSelected(string provider, string model)
  signal thinkingSelected(string level)

  readonly property bool isLight: theme && theme.palette === "light"

  Rectangle {
    width: parent.width
    height: 34
    color: tb.theme ? tb.theme.bgAlt : "#181825"

    Row {
      id: leftRow
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      // 会话列表（呼出左侧侧边栏）——放在最左侧，符合侧边栏从左滑出的直觉
      Rectangle {
        id: listBtn
        width: 24
        height: 24
        radius: 6
        anchors.verticalCenter: parent.verticalCenter
        color: listMA.containsMouse ? (tb.theme ? tb.theme.surface : "#313244") : "transparent"
        Text {
          anchors.centerIn: parent
          text: "☰"
          color: tb.theme ? tb.theme.subtext : "#a6adc8"
          font.pixelSize: 13
        }
        MouseArea {
          id: listMA
          anchors.fill: parent
          hoverEnabled: true
          onClicked: tb.listToggleRequested()
        }
      }

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
        width: 130
      }

      // 模型 chip：点击弹出模型选择器
      Rectangle {
        id: modelChip
        width: 128
        height: 20
        radius: 10
        anchors.verticalCenter: parent.verticalCenter
        color: tb.theme ? tb.theme.surface : "#313244"
        border.color: tb.theme ? tb.theme.border : "#45475a"
        Text {
          anchors.centerIn: parent
          text: tb.modelLabel !== "" ? tb.modelLabel : "模型"
          color: tb.theme ? tb.theme.subtext : "#a6adc8"
          font.pixelSize: 9
          elide: Text.ElideMiddle
          width: parent.width - 14
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            tb.modelRequested() // 拉取最新模型清单
            modelPopup.open()
          }
          onEntered: modelChip.color = tb.theme ? tb.theme.surfaceHover : "#3b4261"
          onExited: modelChip.color = tb.theme ? tb.theme.surface : "#313244"
        }
      }

      // 思维等级 chip：点击循环选等级
      Rectangle {
        id: thinkingChip
        visible: (tb.thinkingLevels || []).length > 1
        width: 54
        height: 20
        radius: 10
        anchors.verticalCenter: parent.verticalCenter
        color: tb.theme ? tb.theme.surface : "#313244"
        border.color: tb.theme ? tb.theme.border : "#45475a"
        Text {
          anchors.centerIn: parent
          text: "思维:" + (tb.thinkingLevel !== "" ? tb.thinkingLevel : "?")
          color: tb.theme ? tb.theme.subtext : "#a6adc8"
          font.pixelSize: 9
        }
        MouseArea {
          anchors.fill: parent
          onClicked: {
            var levels = tb.thinkingLevels || []
            if (levels.length === 0) return
            var cur = levels.indexOf(tb.thinkingLevel)
            var next = levels[(cur + 1) % levels.length]
            tb.thinkingSelected(next)
          }
        }
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

  // ---- 模型选择器 ----
  QC.Popup {
    id: modelPopup
    // x 钳制在面板内（chip 靠右时弹窗左移，避免溢出 500 宽面板）
    x: Math.min(modelChip.x, tb.width - width - 4)
    y: modelChip.y + modelChip.height + 4
    width: 300
    padding: 10
    closePolicy: QC.Popup.CloseOnPressOutside | QC.Popup.CloseOnEscape
    background: Rectangle {
      radius: 10
      color: tb.theme ? tb.theme.bgAlt : "#181825"
      border.color: tb.theme ? tb.theme.border : "#45475a"
    }
    contentItem: Column {
      spacing: 8

      // 思维等级
      Row {
        spacing: 4
        Text {
          text: "思维:"
          color: tb.theme ? tb.theme.muted : "#6c7086"
          font.pixelSize: 10
          anchors.verticalCenter: parent.verticalCenter
        }
        Repeater {
          model: tb.thinkingLevels || []
          delegate: Rectangle {
            required property var modelData
            readonly property bool sel: String(modelData) === tb.thinkingLevel
            width: levelTxt.implicitWidth + 14
            height: 20
            radius: 10
            color: sel ? (tb.theme ? tb.theme.accent : "#89b4fa") : (tb.theme ? tb.theme.surface : "#313244")
            Text {
              id: levelTxt
              anchors.centerIn: parent
              text: String(modelData)
              color: sel ? "#ffffff" : (tb.theme ? tb.theme.subtext : "#a6adc8")
              font.pixelSize: 9
            }
            MouseArea {
              anchors.fill: parent
              onClicked: {
                tb.thinkingSelected(String(modelData))
              }
            }
          }
        }
      }

      // 模型列表
      Text {
        text: "模型（未鉴权不可选）"
        color: tb.theme ? tb.theme.faint : "#585b70"
        font.pixelSize: 9
      }
      ListView {
        width: 280
        height: Math.min(340, Math.max(24, (tb.models || []).length * 27))
        clip: true
        model: tb.models || []
        delegate: Rectangle {
          required property var modelData
          readonly property bool cur: modelData.current
          readonly property bool ok: modelData.authed
          width: parent.width
          height: 25
          radius: 5
          color: cur ? (tb.theme ? tb.theme.accent : "#89b4fa") : (m.hovered ? (tb.theme ? tb.theme.surface : "#313244") : "transparent")
          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6
            Text {
              text: modelData.id
              color: cur ? "#ffffff" : (ok ? (tb.theme ? tb.theme.text : "#cdd6f4") : (tb.theme ? tb.theme.faint : "#585b70"))
              font.pixelSize: 11
              font.bold: cur
              elide: Text.ElideMiddle
              Layout.fillWidth: true
            }
            Text {
              visible: modelData.name && modelData.name !== modelData.id
              text: modelData.name
              color: cur ? "#ffffff" : (tb.theme ? tb.theme.muted : "#6c7086")
              font.pixelSize: 9
              elide: Text.ElideRight
              Layout.maximumWidth: 90
            }
            Text {
              text: ok ? (cur ? "" : "") : "未鉴权"
              color: "#f38ba8"
              font.pixelSize: 8
              visible: !ok
            }
          }
          MouseArea {
            id: m
            anchors.fill: parent
            hoverEnabled: true
            enabled: ok
            onClicked: {
              tb.modelSelected(modelData.provider, modelData.id)
              modelPopup.close()
            }
          }
        }
      }
    }
  }
}