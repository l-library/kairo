import QtQuick
import QtQuick.Layouts

/**
 * SessionSidebar.qml — 会话侧边栏（点击标题栏 ☰ 呼出）
 *
 * - 纵向会话列表：AI/启发式命名或首条消息摘要 + 消息数
 * - 活动会话置顶并高亮（daemon listWithActive 保证）
 * - 删除：两步确认（第一次点击 🗑 变为“确认”，3 秒内再点才删除），防误删
 * - 交互命中顺序：整行 MouseArea 声明在底层，删除按钮 MouseArea 在 RowLayout
 *   上方（后声明 = 更上层），修复 M4 遗留的“chip 点击区吞掉删除按钮”bug
 */
Item {
  id: sb
  width: 260

  /** 由 ChatPanel 传入：y 起点（标题栏下方）与可用高度（到输入栏上方） */
  property real topOffset: 34
  property real bottomOffset: 65
  y: topOffset
  height: Math.max(0, (parent ? parent.height : 0) - topOffset - bottomOffset)

  property var theme: null
  property var sessions: []
  property string activeSessionId: ""
  property bool open: false
  signal newSessionRequested()
  signal activateRequested(string id)
  signal deleteRequested(string id)

  // 滑入滑出：x 为负时整体移出面板左缘，由面板 clip 裁掉
  // （注意：不能用 anchors 定位，anchors 会覆盖 x，导致侧边栏常驻）
  x: open ? 0 : -(width + 12)
  Behavior on x {
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
  }

  // 会话显示名：会话名 > 首条消息摘要 > “新会话”
  function sessionLabel(s) {
    if (s.name && s.name !== "") return s.name
    var fm = String(s.firstMessage || "").trim().replace(/\s+/g, " ")
    if (fm !== "") return fm.length > 16 ? fm.slice(0, 16) + "…" : fm
    return "新会话"
  }

  Rectangle {
    anchors.fill: parent
    color: theme ? theme.bgAlt : "#181825"
    border.color: theme ? theme.border : "#45475a"
    border.width: 1

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      // 头部：标题 + 数量 + 关闭
      RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
          text: "会话"
          font.pixelSize: 13
          font.bold: true
          color: theme ? theme.text : "#cdd6f4"
        }
        Text {
          text: "(" + sb.sessions.length + ")"
          font.pixelSize: 10
          color: theme ? theme.muted : "#6c7086"
        }
        Item { Layout.fillWidth: true }
        Text {
          text: "✕"
          font.pixelSize: 13
          color: theme ? theme.muted : "#6c7086"
          MouseArea {
            anchors.fill: parent
            onClicked: sb.open = false
          }
        }
      }

      // 新建
      Rectangle {
        id: newBtn
        Layout.fillWidth: true
        height: 30
        radius: 6
        color: theme ? theme.surface : "#313244"
        Text {
          anchors.centerIn: parent
          text: "＋ 新建会话"
          color: theme ? theme.subtext : "#a6adc8"
          font.pixelSize: 12
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: sb.newSessionRequested()
          onEntered: newBtn.color = theme ? theme.surfaceHover : "#3b4261"
          onExited: newBtn.color = theme ? theme.surface : "#313244"
        }
      }

      // 会话列表
      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4
        model: sb.sessions
        delegate: Rectangle {
          id: row
          required property var modelData
          readonly property bool isActive: modelData.id === sb.activeSessionId
          property bool armed: false
          width: list.width
          height: 48
          radius: 8
          color: isActive
            ? (theme ? theme.accent : "#89b4fa")
            : (rowMA.containsMouse ? (theme ? theme.surfaceHover : "#3b4261") : (theme ? theme.surface : "#313244"))

          // 整行点击区：声明在最底层（z 最下），不遮挡删除按钮
          MouseArea {
            id: rowMA
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              // 处于确认态时点击行 = 取消确认，不切换会话
              if (row.armed) { row.armed = false; return }
              if (!isActive) sb.activateRequested(modelData.id)
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                Layout.fillWidth: true
                text: sb.sessionLabel(modelData)
                color: isActive ? "#ffffff" : (theme ? theme.text : "#cdd6f4")
                font.pixelSize: 12
                font.bold: isActive
                elide: Text.ElideRight
              }
              Text {
                visible: !isActive && modelData.firstMessage && String(modelData.firstMessage).trim() !== "" && modelData.name !== modelData.firstMessage
                Layout.fillWidth: true
                text: String(modelData.firstMessage || "").trim().replace(/\s+/g, " ")
                color: isActive ? "#ffffff" : (theme ? theme.muted : "#6c7086")
                font.pixelSize: 9
                elide: Text.ElideRight
              }
            }

            // 消息数
            Text {
              visible: !isActive && (modelData.messageCount || 0) > 0
              text: String(modelData.messageCount || 0)
              font.pixelSize: 9
              color: isActive ? "#ffffff" : (theme ? theme.faint : "#585b70")
            }

            // 删除按钮（两步确认）。后声明 = 在行点击区之上，点击优先到删除
            Rectangle {
              id: delBtn
              visible: !isActive
              width: row.armed ? 64 : 22
              height: 22
              radius: 5
              // 纯绑定：armed→红底；悬停→浅色。不用 onEntered 赋值（会破坏绑定）
              color: row.armed
                ? (theme ? theme.red : "#f38ba8")
                : (delMA.containsMouse ? (theme ? theme.surfaceHover : "#3b4261") : "transparent")
              Text {
                anchors.centerIn: parent
                text: row.armed ? "确认删除" : "🗑"
                color: row.armed ? "#ffffff" : (theme ? theme.muted : "#6c7086")
                font.pixelSize: row.armed ? 10 : 9
              }
              MouseArea {
                id: delMA
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  // 注意：armed 是 delegate 根（row）的属性——直接写 parent.armed 会
                  // 落到 delBtn 的动态属性上（两处 armed 不同源），确认态永远不可见。
                  if (row.armed) {
                    row.armed = false
                    sb.deleteRequested(modelData.id)
                  } else {
                    row.armed = true
                    disarmTimer.restart()
                  }
                }
              }
              Timer {
                id: disarmTimer
                interval: 3000
                onTriggered: row.armed = false
              }
            }
          }
        }
      }
    }
  }
}