import QtQuick

/**
 * ThinkingBlock.qml — 思考过程折叠块
 */
Item {
  id: block
  implicitHeight: visible ? row.height + 6 : 0
  width: parent.width

  property string text: ""
  property bool open: false
  signal toggle()

  Row {
    id: row
    width: parent.width
    spacing: 6

    Text {
      text: block.open ? "▾" : "▸"
      color: "#a6adc8"
      font.pixelSize: 11
    }

    Text {
      text: "思考过程"
      color: "#a6adc8"
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
      color: "#2a2b3a"
    }
  }

  Text {
    visible: block.open
    anchors.top: row.bottom
    anchors.topMargin: 4
    width: parent.width
    text: block.text
    color: "#6c7086"
    font.pixelSize: 11
    font.italic: true
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
}