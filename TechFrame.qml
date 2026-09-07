import QtQuick

// The screen's structural shape: a rectangle with chamfered corners, an
// optional heavy edge along one side, and optional corner brackets sitting
// just outside the outline. Drawn on a Canvas so it recolours with the theme
// and stays crisp at any size. Children go inside; the frame paints below.
//
// `cuts` names which corners are chamfered. The default cuts the top-left
// and bottom-right so panels read as angled rather than boxy, the way the
// reference equip screens do.
Item {
  id: root

  property color fill: "transparent"
  property color stroke: "transparent"
  property real strokeWidth: 1
  property real chamfer: 10
  property var cuts: ["tl", "br"]

  property bool brackets: false
  property color bracketColor: stroke
  property real bracketLength: 12
  property real bracketWidth: 2
  property real bracketInset: 3       // distance outside the outline

  property string edge: ""            // "left" | "right" | "top" | "bottom" | ""
  property color edgeColor: stroke
  property real edgeWidth: 3

  property bool dashed: false

  default property alias content: inner.data

  onFillChanged: canvas.requestPaint()
  onStrokeChanged: canvas.requestPaint()
  onStrokeWidthChanged: canvas.requestPaint()
  onChamferChanged: canvas.requestPaint()
  onCutsChanged: canvas.requestPaint()
  onBracketsChanged: canvas.requestPaint()
  onBracketColorChanged: canvas.requestPaint()
  onEdgeChanged: canvas.requestPaint()
  onEdgeColorChanged: canvas.requestPaint()
  onDashedChanged: canvas.requestPaint()

  function has(corner) {
    return root.cuts.indexOf(corner) >= 0
  }

  // Outline path inset by half the stroke so the line stays inside the item.
  function outline(ctx, x0, y0, x1, y1, c) {
    ctx.beginPath()
    if (has("tl")) { ctx.moveTo(x0 + c, y0) } else { ctx.moveTo(x0, y0) }
    if (has("tr")) { ctx.lineTo(x1 - c, y0); ctx.lineTo(x1, y0 + c) } else { ctx.lineTo(x1, y0) }
    if (has("br")) { ctx.lineTo(x1, y1 - c); ctx.lineTo(x1 - c, y1) } else { ctx.lineTo(x1, y1) }
    if (has("bl")) { ctx.lineTo(x0 + c, y1); ctx.lineTo(x0, y1 - c) } else { ctx.lineTo(x0, y1) }
    if (has("tl")) { ctx.lineTo(x0, y0 + c) }
    ctx.closePath()
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    // Brackets hang outside the outline, so give the canvas room to paint them.
    anchors.margins: -(root.bracketInset + root.bracketWidth + 1)
    antialiasing: true

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)

      var m = -anchors.margins
      var sw = root.strokeWidth
      var x0 = m + sw / 2, y0 = m + sw / 2
      var x1 = width - m - sw / 2, y1 = height - m - sw / 2
      var c = Math.min(root.chamfer, (x1 - x0) / 2, (y1 - y0) / 2)

      root.outline(ctx, x0, y0, x1, y1, c)
      if (root.fill.a > 0) {
        ctx.fillStyle = root.fill
        ctx.fill()
      }
      if (sw > 0 && root.stroke.a > 0) {
        if (ctx.setLineDash) ctx.setLineDash(root.dashed ? [4, 4] : [])
        ctx.lineWidth = sw
        ctx.strokeStyle = root.stroke
        ctx.lineJoin = "miter"
        ctx.stroke()
        if (ctx.setLineDash) ctx.setLineDash([])
      }

      // Heavy edge: a bar along one side, clipped to the outline so the
      // chamfer cuts through it too.
      if (root.edge !== "" && root.edgeColor.a > 0) {
        ctx.save()
        root.outline(ctx, x0, y0, x1, y1, c)
        ctx.clip()
        ctx.fillStyle = root.edgeColor
        var ew = root.edgeWidth
        if (root.edge === "left") ctx.fillRect(x0 - sw / 2, y0 - sw / 2, ew, y1 - y0 + sw)
        else if (root.edge === "right") ctx.fillRect(x1 - ew + sw / 2, y0 - sw / 2, ew, y1 - y0 + sw)
        else if (root.edge === "top") ctx.fillRect(x0 - sw / 2, y0 - sw / 2, x1 - x0 + sw, ew)
        else if (root.edge === "bottom") ctx.fillRect(x0 - sw / 2, y1 - ew + sw / 2, x1 - x0 + sw, ew)
        ctx.restore()
      }

      if (root.brackets && root.bracketColor.a > 0) {
        var i = root.bracketInset + sw / 2
        var bw = root.bracketWidth
        var L = Math.min(root.bracketLength, (x1 - x0) / 3, (y1 - y0) / 3)
        var bx0 = x0 - i, by0 = y0 - i, bx1 = x1 + i, by1 = y1 + i
        ctx.lineWidth = bw
        ctx.strokeStyle = root.bracketColor
        ctx.lineCap = "square"
        ctx.beginPath()
        ctx.moveTo(bx0, by0 + L); ctx.lineTo(bx0, by0); ctx.lineTo(bx0 + L, by0)
        ctx.moveTo(bx1 - L, by0); ctx.lineTo(bx1, by0); ctx.lineTo(bx1, by0 + L)
        ctx.moveTo(bx1, by1 - L); ctx.lineTo(bx1, by1); ctx.lineTo(bx1 - L, by1)
        ctx.moveTo(bx0 + L, by1); ctx.lineTo(bx0, by1); ctx.lineTo(bx0, by1 - L)
        ctx.stroke()
      }
    }
  }

  Item {
    id: inner
    anchors.fill: parent
  }
}
