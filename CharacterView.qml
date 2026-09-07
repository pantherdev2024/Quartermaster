pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The character: the mock desktop in a bracketed viewport with every slot's
// current fitting called out around it — style down the left, cyberware down
// the right, shell along the foot — each tethered to the viewport by a
// leader line. Callouts read from the same preview/fitted/live state as the slot
// list, so browsing on the left re-labels the character on the right at once.
//
// The arrangement is sized to take more slots than it has: a side column holds
// what fits beside the viewport and the rest spills to the foot, which wraps
// and may use the pane's full width. A pane too narrow to flank at all stacks
// the callouts into a grid underneath instead.
Item {
  id: root

  property var host: null

  readonly property var defs: host ? host.slotDefs : []
  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  function slotsIn(cat) {
    return root.defs.filter(function(d) { return d.cat === cat })
  }
  readonly property var styleSlots: slotsIn("outfit")
  readonly property var shellSlots: slotsIn("chassis")
  readonly property var cyberSlots: slotsIn("cyberware")
  // Stacked order is category order, so the grid reads top to bottom the
  // way the tabs read left to right.
  readonly property var gridSlots: styleSlots.concat(shellSlots).concat(cyberSlots)

  // ---- Geometry ---------------------------------------------------------
  readonly property real gutter: Style.space(22)
  readonly property real calloutHeight: Style.space(58)
  readonly property real cardGap: Style.space(16)
  // The narrowest a callout may be drawn. Below this it stops being worth
  // the width it takes, and the layout should give up flanking instead.
  readonly property real minCardWidth: Style.space(132)
  readonly property real viewportShare: 0.58

  // Flanking costs the viewport's share of the width plus, on each side, a
  // gutter and a card at its floor. Deciding from that rather than from a
  // screen width means a roomier spacing scale, or a left column that grows,
  // falls back to the stack on its own instead of overlapping.
  // The width at which flanking stops being possible. Panes negotiate
  // against this so nothing has to know the constants behind it.
  readonly property real minFlankWidth: 2 * (root.gutter + root.minCardWidth) / (1 - root.viewportShare)
  readonly property bool flanked: width >= root.minFlankWidth && height >= Style.space(268)
  // No room to flank: the callouts form a grid under the viewport, each
  // tethered to the card above it (or to the nameplate).
  readonly property bool stacked: !root.flanked

  readonly property real sideWidth: Math.max(root.minCardWidth, (width - viewport.width) / 2 - root.gutter)

  // ---- Buckets ----------------------------------------------------------
  // How many callouts a side column holds for free: a column is centred on
  // the viewport and may reach a little past it, but no further, because
  // past that it starts pushing the foot row down. Beyond this a slot is
  // cheaper at the foot, where one row holds several.
  readonly property int sideCapacity: {
    var room = viewport.height + 2 * Style.space(56)
    return Math.max(1, Math.floor((room + root.cardGap) / (root.calloutHeight + root.cardGap)))
  }

  // Style keeps the left, Cyberware the right and Shell the foot, because
  // that grouping is the point. What a side column cannot hold spills into
  // the foot rather than pushing the column off the pane, so a category can
  // grow past the height without breaking the layout.
  readonly property var leftSlots: root.styleSlots.slice(0, root.sideCapacity)
  readonly property var rightSlots: root.cyberSlots.slice(0, root.sideCapacity)
  readonly property var bottomSlots: root.shellSlots
    .concat(root.styleSlots.slice(root.sideCapacity))
    .concat(root.cyberSlots.slice(root.sideCapacity))

  // The foot sits under the viewport by default, but it may run out to the
  // pane's full width and wrap rather than squeeze its cards below the
  // floor: it is the bucket that takes every spill.
  readonly property int bottomColumns: {
    var n = root.bottomSlots.length
    if (n <= 0) return 1
    var fit = Math.floor((root.width + root.cardGap) / (root.minCardWidth + root.cardGap))
    return Math.max(1, Math.min(n, fit))
  }
  readonly property real bottomRowWidth: {
    var cols = root.bottomColumns
    var floorWidth = cols * root.minCardWidth + (cols - 1) * root.cardGap
    return Math.min(root.width, Math.max(viewport.width, floorWidth))
  }
  readonly property real bottomCardWidth:
    (root.bottomRowWidth - root.cardGap * (root.bottomColumns - 1)) / root.bottomColumns

  // How far the taller side column reaches past the viewport, top and foot.
  // The group is centred on the union of the two, so a tall column pushes
  // the whole arrangement down instead of off the top of the pane.
  readonly property real sideOverhang: root.stacked ? 0
    : Math.max(0, (Math.max(leftColumn.height, rightColumn.height) - viewport.height) / 2)

  // Where the foot row sits, measured from the viewport's own top. It
  // normally sits under the nameplate in the viewport's channel, clear of
  // the side columns. Once it runs wider than that channel it has to start
  // below the taller column instead of beside it.
  readonly property real footOffset: {
    var underNameplate = viewport.height + Style.space(12 + 30 + 34)
    var channel = root.width - 2 * (root.sideWidth + root.gutter)
    if (root.bottomRowWidth <= channel) return underNameplate
    return Math.max(underNameplate, viewport.height + root.sideOverhang + root.cardGap)
  }

  function repaintLeaders() { leaders.requestPaint() }
  onWidthChanged: repaintLeaders()
  onHeightChanged: repaintLeaders()
  Component.onCompleted: Qt.callLater(repaintLeaders)

  Connections {
    target: root.host
    function onSlotIndexChanged() { root.repaintLeaders() }
    function onStagedChanged() { root.repaintLeaders() }
  }

  // ---- Viewport ------------------------------------------------------
  TechFrame {
    id: viewport
    anchors.horizontalCenter: parent.horizontalCenter
    // Everything the arrangement occupies, measured from the viewport's top.
    readonly property real groupHeight: root.stacked
      ? height + Style.space(12 + 30 + 24) + grid.height
      : root.footOffset + bottomRow.height
    // Centre the union of that and the side columns, not the stack alone:
    // the columns are centred on the viewport and reach above it.
    y: root.sideOverhang
      + Math.max(Style.space(16), (parent.height - root.sideOverhang - groupHeight) / 2)
    width: root.stacked
      ? Math.min(parent.width * 0.86,
                 Math.max(Style.space(180), parent.height - Style.space(16 + 12 + 30 + 24) - grid.height) * (16 / 9))
      : Math.min(parent.width * root.viewportShare, (parent.height * 0.50) * (16 / 9))
    height: width * (9 / 16)
    chamfer: Style.space(14)
    cuts: ["tl", "tr", "bl", "br"]
    fill: "transparent"
    stroke: root.line
    strokeWidth: 1
    brackets: true
    bracketColor: root.accent
    bracketLength: Style.space(22)
    bracketWidth: 2
    bracketInset: 6

    onXChanged: root.repaintLeaders()
    onYChanged: root.repaintLeaders()
    onWidthChanged: root.repaintLeaders()

    // A slow scan sweep over the viewport: the character is a projection.
    Rectangle {
      id: sweep
      anchors { left: parent.left; right: parent.right; margins: Style.space(6) }
      height: Style.space(28)
      z: 2
      visible: root.visible
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.85; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10) }
        GradientStop { position: 1.0; color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) }
      }
      SequentialAnimation on y {
        loops: Animation.Infinite
        running: root.visible && root.host && root.host.opened
        NumberAnimation { from: -sweep.height; to: viewport.height; duration: 5200; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 2600 }
      }
    }

    MiniDesktop {
      id: preview
      anchors { fill: parent; margins: Style.space(6) }
      colors: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.colors : ({})
      wallpaper: root.host ? root.host.previewWallpaper : ""
      fontFamily: root.host ? root.host.previewFont : "monospace"
      themeName: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.name : ""
      terminalName: root.host ? root.host.previewTerminal : ""
      barPosition: root.host ? root.host.previewBarPosition : "top"
      barTransparent: root.host ? root.host.previewBarTransparent : false
      barLayout: root.host ? root.host.previewBarLayout : ({})
      glyphs: root.host ? root.host.widgetGlyphs : ({})
      fontScale: root.host ? root.host.previewFontScale : 1
    }
  }

  // Nameplate under the viewport: the staged theme and whether the
  // character matches what is actually worn.
  Item {
    id: nameplate
    anchors { top: viewport.bottom; topMargin: Style.space(12); horizontalCenter: viewport.horizontalCenter }
    width: viewport.width
    height: Style.space(30)

    Text {
      id: plateName
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.name.toUpperCase() : ""
      color: root.fg
      font.family: root.uiFont
      font.pixelSize: Style.font.title
      font.bold: true
      font.letterSpacing: 4
    }

    Text {
      anchors { left: plateName.right; leftMargin: Style.space(16); right: parent.right }
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: {
        if (!root.host) return ""
        var name = root.host.activeLoadoutName
        var state = root.host.previewing ? "PREVIEW  ·  ENTER FITS"
          : root.host.dirty ? "FITTED  ·  D DEPLOYS" : "EQUIPPED"
        if (name) return "LOADOUT  " + name.toUpperCase() + "  ·  " + state
        return root.host.previewing || root.host.dirty ? state : "CURRENT CONFIGURATION"
      }
      color: root.host && root.host.previewing ? root.accent : (root.host && root.host.dirty ? root.warn : root.muted)
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.letterSpacing: 2
    }
  }

  // ---- Leader lines ----------------------------------------------------
  // One line per callout, from its inner edge to the nearest viewport edge,
  // ending in a small square on the viewport. The focused slot's line is
  // accent; a staged slot's line is the warning colour.
  Canvas {
    id: leaders
    anchors.fill: parent
    z: -1
    antialiasing: true

    function lineColorFor(def) {
      if (!root.host) return root.line
      if (root.host.currentSlot && root.host.currentSlot.id === def.id) return root.accent
      if (root.host.preview[def.id] !== undefined) return root.accent
      if (root.host.staged[def.id]) return root.warn
      return root.line
    }

    function drawLeader(ctx, from, to, color) {
      ctx.strokeStyle = color
      ctx.fillStyle = color
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(from.x, from.y)
      ctx.lineTo(to.x, to.y)
      ctx.stroke()
      ctx.fillRect(to.x - 2.5, to.y - 2.5, 5, 5)
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)

      function each(column, side) {
        for (var i = 0; i < column.children.length; i++) {
          var card = column.children[i]
          if (!card.def) continue
          var p = card.mapToItem(root, 0, 0)
          var color = lineColorFor(card.def)
          if (side === "left") {
            var y = p.y + card.height / 2
            drawLeader(ctx, { x: p.x + card.width, y: y }, { x: viewport.x, y: Math.max(viewport.y + 8, Math.min(viewport.y + viewport.height - 8, y)) }, color)
          } else if (side === "right") {
            var y2 = p.y + card.height / 2
            drawLeader(ctx, { x: p.x, y: y2 }, { x: viewport.x + viewport.width, y: Math.max(viewport.y + 8, Math.min(viewport.y + viewport.height - 8, y2)) }, color)
          } else {
            var x = p.x + card.width / 2
            drawLeader(ctx, { x: x, y: p.y }, { x: x, y: nameplate.y + nameplate.height }, color)
          }
        }
      }
      // Cards under the viewport chain upward: each tethers to the card
      // above it in the same column, and the top row to the nameplate. A
      // single row has nothing above it, so every card tethers straight up,
      // which is what the foot row does until it has to wrap.
      function chainUp(container, columns) {
        var cards = []
        for (var i = 0; i < container.children.length; i++)
          if (container.children[i].def) cards.push(container.children[i])
        for (var j = 0; j < cards.length; j++) {
          var c = cards[j]
          var cp = c.mapToItem(root, 0, 0)
          var cx = cp.x + c.width / 2
          var above = j >= columns ? cards[j - columns] : null
          var toY = above ? above.mapToItem(root, 0, 0).y + above.height : nameplate.y + nameplate.height
          drawLeader(ctx, { x: cx, y: cp.y }, { x: cx, y: toY }, lineColorFor(c.def))
        }
      }

      if (root.stacked) { chainUp(grid, grid.columns); return }
      each(leftColumn, "left")
      each(rightColumn, "right")
      chainUp(bottomRow, bottomRow.columns)
    }
  }

  // ---- Compact grid ----------------------------------------------------
  Grid {
    id: grid
    visible: root.stacked
    anchors { top: nameplate.bottom; topMargin: Style.space(24); left: parent.left; right: parent.right }
    columns: 3
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(20)
    onHeightChanged: root.repaintLeaders()

    Repeater {
      model: root.stacked ? root.gridSlots : []
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "bottom"
        width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
      }
    }
  }

  // ---- Callout columns -------------------------------------------------
  Column {
    id: leftColumn
    visible: root.flanked
    anchors { left: parent.left; verticalCenter: viewport.verticalCenter }
    width: root.sideWidth
    spacing: root.cardGap
    onHeightChanged: root.repaintLeaders()

    Repeater {
      model: root.flanked ? root.leftSlots : []
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "left"
        width: leftColumn.width
      }
    }
  }

  Column {
    id: rightColumn
    visible: root.flanked
    anchors { right: parent.right; verticalCenter: viewport.verticalCenter }
    width: root.sideWidth
    spacing: root.cardGap
    onHeightChanged: root.repaintLeaders()

    Repeater {
      model: root.flanked ? root.rightSlots : []
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "right"
        width: rightColumn.width
      }
    }
  }

  Grid {
    id: bottomRow
    visible: root.flanked
    anchors.horizontalCenter: parent.horizontalCenter
    y: viewport.y + root.footOffset
    columns: root.bottomColumns
    spacing: root.cardGap
    onWidthChanged: root.repaintLeaders()
    onHeightChanged: root.repaintLeaders()

    Repeater {
      model: root.flanked ? root.bottomSlots : []
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "bottom"
        width: root.bottomCardWidth
      }
    }
  }

  // ---- One callout card ------------------------------------------------
  component Callout: Item {
    id: card
    property var def: ({})
    property string side: "left"

    readonly property var item: root.host ? root.host.selectedItem(def.id) : null
    readonly property bool focused: root.host && root.host.currentSlot && root.host.currentSlot.id === def.id
    readonly property bool staged: root.host && root.host.staged[def.id] ? true : false
    // Previewed: the cursor is trying something on that differs from what
    // the slot holds (fitted, else live).
    readonly property bool previewed: root.host && root.host.preview[def.id] !== undefined
      && root.host.preview[def.id] !== (root.host.staged[def.id] || root.host.equippedId(def.id))
    // A multi slot is always worn: its value is the whole layout.
    readonly property bool multi: def.multi === true
    readonly property string tag: previewed ? "PREVIEW" : staged ? "FITTED" : (multi || (item && item.equipped) ? "EQUIPPED" : (item ? "" : "EMPTY"))
    readonly property color tagColor: previewed ? root.accent : staged ? root.warn : (multi || (item && item.equipped) ? root.good : root.muted)
    // No room for the tag word: compact, or a narrow card in the wide layout.
    readonly property bool tight: width < Style.space(170)

    height: root.calloutHeight

    TechFrame {
      anchors.fill: parent
      chamfer: Style.space(9)
      cuts: card.side === "left" ? ["tl", "bl"] : card.side === "right" ? ["tr", "br"] : ["bl", "br"]
      fill: root.host ? (card.focused ? root.host.paneBgFocused : root.host.paneBg) : "transparent"
      stroke: card.focused ? root.accent : root.line
      strokeWidth: 1
      brackets: card.focused
      bracketColor: root.accent
      bracketLength: Style.space(10)
      bracketWidth: 2
      bracketInset: 3
      edge: card.staged ? (card.side === "left" ? "right" : card.side === "right" ? "left" : "top") : ""
      edgeColor: root.warn
      edgeWidth: Style.space(3)

      Text {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: card.def.icon || ""
        color: card.focused ? root.accent : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.iconLarge
      }

      Column {
        anchors.left: icon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Item {
          width: parent.width
          height: labelText.implicitHeight

          Text {
            id: labelText
            anchors.left: parent.left
            anchors.right: tagText.visible ? tagText.left : (tagDot.visible ? tagDot.left : parent.right)
            anchors.rightMargin: tagText.visible || tagDot.visible ? Style.space(6) : 0
            elide: Text.ElideRight
            text: card.def.label || ""
            color: card.focused ? root.accent : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }

          Text {
            id: tagText
            anchors.right: parent.right
            text: card.tag
            color: card.tagColor
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            visible: text !== "" && !card.tight
          }

          // Compact cards have no room for the word, so the state is a
          // square in the tag colour, echoing the leader-line endpoint.
          Rectangle {
            id: tagDot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6); height: Style.space(6)
            color: card.tagColor
            visible: card.tight && card.tag !== ""
          }
        }

        Text {
          width: parent.width
          text: card.multi && root.host ? root.host.barModsSummary : (card.item ? card.item.name : "—")
          color: root.fg
          font.family: root.uiFont
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        if (!root.host) return
        root.host.slotIndex = root.host.slotDefs.findIndex(function(d) { return d.id === card.def.id })
      }
    }
  }
}
