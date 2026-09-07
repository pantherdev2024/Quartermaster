import QtQuick

// Horizontal bar readout — the Health / Stamina / Energy rows from the
// reference, reused for memory, disk and swap.
Item {
  id: root

  property real value: 0          // 0..100
  property string label: ""
  property string readout: ""
  property color fillColor: "#a6e3a1"
  property color trackColor: "#303030"
  property color textColor: "#cacccc"
  property color mutedColor: "#707880"
  property string fontFamily: "monospace"

  readonly property real clamped: Math.max(0, Math.min(100, value))

  implicitWidth: 150
  implicitHeight: 34

  Column {
    anchors.fill: parent
    spacing: Math.max(2, root.height * 0.12)

    Item {
      width: parent.width
      height: root.height * 0.42

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.mutedColor
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, root.height * 0.3)
        font.letterSpacing: 1
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.readout
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: Math.max(9, root.height * 0.32)
        font.bold: true
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(4, root.height * 0.2)
      radius: height / 2
      color: root.trackColor

      Rectangle {
        width: parent.width * (root.clamped / 100)
        height: parent.height
        radius: height / 2
        color: root.fillColor

        Behavior on width {
          NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
      }
    }
  }
}
