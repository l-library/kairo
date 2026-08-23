import QtQuick

/**
 * ThinkingBlock.qml — 思考过程折叠块
 */
Item {
  id: block
  implicitHeight: visible ? (row.height + 6 + (open ? thoughtText.implicitHeight : 0)) : 0
  width: parent.width

  property string text: ""
  property bool open: false
  property var theme: null
  signal toggle()

  Row {
    id: row
    width: parent.width
    spacing: 6

    Text {
      text: block.open ? "▾" : "▸"
      color: block.theme ? block.theme.subtext : "#a6adc8"
      font.pixelSize: 11
    }

    Text {
      text: "思考过程"
      color: block.theme ? block.theme.subtext : "#a6adc8"
      font.pixelSize: 11
      font.bold: true
      MouseArea {
        anchors.fill: parent
        onClicked: block.toggle()
      }
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 96
      height: 1
      color: block.theme ? block.theme.divider : "#2a2b3a"
    }
  }

  Text {
    id: thoughtText
    visible: block.open
    anchors.top: row.bottom
    anchors.topMargin: 4
    width: parent.width
    text: block.text
    color: block.theme ? block.theme.muted : "#6c7086"
    font.pixelSize: 11
    font.italic: true
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
}