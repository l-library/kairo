import QtQuick

/**
 * SessionBar.qml — 会话列表（横向 chips）：当前会话 + 历史切换 + 新建 + 删除
 *
 * 注意：不用 RowLayout + `width: parent.width - newBtn.width - 16` 的写法——
 * 该表达式在布局期会求值为 0（ListView 宽度 0，delegate 全部不可渲染）。
 * 改用固定算术定位（8 边距 + 56 按钮 + 6 间距）。
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

  // chip 标签：会话名 > 首条消息摘要 > “新会话”占位（不再显示难以辨认的 id）
  function chipLabel(s) {
    if (s.name && s.name !== "") return s.name
    var fm = String(s.firstMessage || "").trim().replace(/\s+/g, " ")
    if (fm !== "") return fm.length > 16 ? fm.slice(0, 16) + "…" : fm
    return "新会话"
  }

  Rectangle {
    width: parent.width
    height: parent.height
    color: bar.theme ? bar.theme.bg : "#1e1e2e"
    visible: bar.sessions.length > 0

    // 新建
    Rectangle {
      id: newBtn
      x: 8
      y: (parent.height - 24) / 2
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

    // 会话 chips
    ListView {
      id: list
      x: 8 + 56 + 6
      y: (parent.height - 24) / 2
      width: parent.width - (8 + 56 + 6) - 8
      height: 24
      orientation: ListView.Horizontal
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
            text: bar.chipLabel(modelData)
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