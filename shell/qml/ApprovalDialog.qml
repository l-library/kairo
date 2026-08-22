import QtQuick
import QtQuick.Layouts

/**
 * ApprovalDialog.qml — 确认弹窗（写文件 diff / 命令确认）
 *
 * 数据：client.pendingApproval = { id, toolName, target, diff, command, cwd }
 */
Item {
  id: dialog
  anchors.fill: parent
  visible: approval !== null
  z: 100

  required property var approval
  property bool allowKeyboard: true

  Rectangle {
    anchors.fill: parent
    color: "#80000000"
    z: 1
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - 60, 420)
    height: Math.min(parent.height - 80, content.implicitHeight + 36)
    radius: 10
    color: "#1e1e2e"
    border.color: "#45475a"
    border.width: 1
    z: 2

    Column {
      id: content
      x: 16
      y: 14
      width: parent.width - 32
      spacing: 10

      Row {
        width: parent.width
        spacing: 8
        Text {
          text: "⚠"
          color: "#f9e2af"
          font.pixelSize: 16
        }
        Text {
          width: parent.width - 30
          text: "确认操作"
          color: "#cdd6f4"
          font.pixelSize: 15
          font.bold: true
        }
      }

      // 命令类
      Rectangle {
        visible: dialog.approval && (dialog.approval.command || "")
        width: parent.width
        radius: 6
        color: "#242437"
        implicitHeight: col.implicitHeight + 12
        Column {
          id: col
          x: 8
          y: 6
          width: parent.width - 16
          spacing: 4
          Text {
            visible: dialog.approval && !!dialog.approval.cwd
            text: "cwd: " + ((dialog.approval && dialog.approval.cwd) || "")
            color: "#6c7086"
            font.pixelSize: 11
            font.family: "monospace"
          }
          Text {
            text: "$ " + ((dialog.approval && dialog.approval.command) || "")
            width: parent.width
            color: "#f9e2af"
            font.pixelSize: 13
            font.family: "monospace"
            wrapMode: Text.WrapAnywhere
          }
        }
      }

      // 文件类：目标 + diff
      Rectangle {
        visible: dialog.approval && (dialog.approval.diff || "")
        width: parent.width
        color: "transparent"
        implicitHeight: dcol.implicitHeight
        Column {
          id: dcol
          width: parent.width
          spacing: 6
          Text {
            text: "文件: " + ((dialog.approval && dialog.approval.target) || "")
            color: "#a6adc8"
            font.pixelSize: 11
            font.family: "monospace"
            elide: Text.ElideMiddle
            width: parent.width
          }
          Rectangle {
            width: parent.width
            radius: 6
            color: "#171720"
            implicitHeight: Math.min(diffText.implicitHeight, 300)
            clip: true
            Text {
              id: diffText
              x: 8
              y: 6
              width: parent.width - 16
              text: colorizeDiff((dialog.approval && dialog.approval.diff) || "")
              textFormat: Text.RichText
              font.pixelSize: 11
              font.family: "monospace"
              wrapMode: Text.WrapAnywhere
            }
          }
        }
      }

      // 按钮区
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        Rectangle {
          width: 110
          height: 32
          radius: 6
          color: "#a6e3a1"
          Text {
            anchors.centerIn: parent
            text: "批准 (Enter)"
            color: "#1e1e2e"
            font.pixelSize: 12
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent
            onClicked: dialog.finish(true)
          }
        }
        Rectangle {
          width: 110
          height: 32
          radius: 6
          color: "#f38ba8"
          Text {
            anchors.centerIn: parent
            text: "拒绝 (Esc)"
            color: "#1e1e2e"
            font.pixelSize: 12
            font.bold: true
          }
          MouseArea {
            anchors.fill: parent
            onClicked: dialog.finish(false)
          }
        }
      }

      Text {
        id: hint
        width: parent.width
        visible: dialog.approval && dialog.approval.toolName === "bash"
        text: "命令将在宿主环境执行，请确认命令内容安全"
        color: "#6c7086"
        font.pixelSize: 10
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  // diff 双色渲染（增绿删红）
  function colorizeDiff(diff) {
    if (!diff) return ""
    var out = ""
    var lines = String(diff).split("\n")
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i]
      if (l.startsWith("+")) out += '<span style="color:#a6e3a1;">' + escapeTags(l) + "</span>\n"
      else if (l.startsWith("-")) out += '<span style="color:#f38ba8;">' + escapeTags(l) + "</span>\n"
      else out += '<span style="color:#a6adc8;">' + escapeTags(l) + "</span>\n"
    }
    return out
  }

  function escapeTags(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  signal responded(bool allowed)

  function finish(allowed) {
    dialog.responded(allowed)
  }
}