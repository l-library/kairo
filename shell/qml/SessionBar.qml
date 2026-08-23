import QtQuick
import QtQuick.Layouts

/**
 * SessionBar.qml — 会话列表（横向 chips）：当前会话 + 历史切换 + 新建 + 删除
 */
Item {
  id: bar
  implicitHeight: 32
  width: parent?.width ?? 0

  property var theme: null
  property var sessions: []
  property string activeSessionId: ""
  signal newSessionRequested()
  signal activateRequested(string id)
  signal deleteRequested(string id)

  Rectangle {
    width: parent.width
    height: parent.height
    color: bar.theme ? bar.theme.bg : "#1e1e2e"
    visible: bar.sessions.length > 0

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      spacing: 6

      // 新建
      Rectangle {
        id: newBtn
        width: 56
        height: 24
        radius: 6
        color: bar.theme ? bar.theme.surface : "#313244"
        Text {
          anchors.centerIn: parent
          text: "＋ 新建"
          color: bar.theme ? bar.theme.subtext : "#a6adc8"
          font.pixelSize: 10
        }
        MouseArea {
          anchors.fill: parent
          onClicked: bar.newSessionRequested()
          hoverEnabled: true
          onEntered: newBtn.color = bar.theme ? bar.theme.surfaceHover : "#3b4261"
          onExited: newBtn.color = bar.theme ? bar.theme.surface : "#313244"
        }
      }

      ListView {
        id: list
        orientation: ListView.Horizontal
        height: 24
        width: parent.width - newBtn.width - 16
        Layout.alignment: Qt.AlignVCenter
        clip: true
        model: bar.sessions
        delegate: Rectangle {
          required property var modelData
          readonly property bool isActive: modelData.id === bar.activeSessionId
          width: chipRow.implicitWidth + 20
          height: 24
          radius: 6
          color: isActive ? bar.theme.accent : bar.theme.surfaceAlt
          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text {
              text: modelData.name && modelData.name !== ""
                ? modelData.name
                : (modelData.first_message || "").slice(0, 12) || modelData.id.slice(0, 8)
              color: isActive ? "#ffffff" : bar.theme.subtext
              font.pixelSize: 10
              elide: Text.ElideMiddle
              width: Math.min(implicitWidth, 130)
            }
            // 删除按钮
            Text {
              visible: !isActive
              text: "🗑"
              color: bar.theme ? bar.theme.muted : "#6c7086"
              font.pixelSize: 8
              MouseArea {
                anchors.fill: parent
                onClicked: bar.deleteRequested(modelData.id)
              }
            }
          }
          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (!isActive) bar.activateRequested(modelData.id)
            }
          }
        }
      }
    }
  }
}