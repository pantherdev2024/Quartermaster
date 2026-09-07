import QtQuick

// Radial ring gauge — the "Core Power Consumption" dial from the reference.
// Canvas rather than an image so it recolors with the theme for free.
Item {
  id: root

  property real value: 0          // 0..100; negative means "unavailable"
  property string label: ""
  property string readout: ""
  property string sub: ""
  property color ringColor: "#7aa2f7"
  property color trackColor: "#303030"
  property color textColor: "#cacccc"
  property color mutedColor: "#707880"
  property string fontFamily: "monospace"

  readonly property bool available: value >= 0
  readonly property real clamped: Math.max(0, Math.min(100, value))

  implicitWidth: 96
  implicitHeight: 96

  onClampedChanged: dial.requestPaint()
  onRingColorChanged: dial.requestPaint()
  onTrackColorChanged: dial.requestPaint()
  onAvailableChanged: dial.requestPaint()

  Canvas {
    id: dial
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      var cx = width / 2
      var cy = height / 2
      var lw = Math.max(3, Math.min(width, height) * 0.09)
      var r = Math.min(width, height) / 2 - lw

      // Leave a gap at the bottom so the arc reads as a dial, not a donut.
      var start = Math.PI * 0.75
      var sweep = Math.PI * 1.5

      ctx.lineCap = "round"
      ctx.lineWidth = lw

      ctx.beginPath()
      ctx.strokeStyle = root.trackColor
      ctx.arc(cx, cy, r, start, start + sweep)
      ctx.stroke()

      if (root.available && root.clamped > 0) {
        ctx.beginPath()
        ctx.strokeStyle = root.ringColor
        ctx.arc(cx, cy, r, start, start + sweep * (root.clamped / 100))
        ctx.stroke()
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.available ? root.readout : "—"
      color: root.available ? root.textColor : root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(10, root.height * 0.2)
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.sub
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: Math.max(7, root.height * 0.12)
      visible: text.length > 0 && root.available
    }
  }

  Text {
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
    text: root.label
    color: root.mutedColor
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, root.height * 0.13)
    font.letterSpacing: 1
  }
}
