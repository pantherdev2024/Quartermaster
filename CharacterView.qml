pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The character: the mock desktop, large and quiet, with every slot's current
// fitting named around it — style down the left, cyberware down the right,
// shell along the foot. The names hang off one hairline rail per column;
// nothing is boxed, nothing glows, and nothing is drawn between a tag and the
// desktop: the tag the cursor is on turns its stretch of rail to the accent,
// and the desktop itself shows the change. Tags read from the same
// preview/fitted/live state as the slot list, so browsing on the left
// re-labels the character at once.
//
// The arrangement is sized to take more slots than it has: a side column holds
// what fits beside the viewport and the rest spills to the foot, which wraps
// and may use the pane's full width. A pane too narrow to flank at all stacks
// the tags into a grid underneath instead.
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
  readonly property color backdrop: host ? host.backdrop : Color.background
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
  readonly property real gutter: Style.space(20)
  readonly property real tagHeight: Style.space(46)
  readonly property real tagGap: Style.space(12)
  // The narrowest a tag may be drawn: a name elides past this, and the
  // layout would rather shrink the viewport than the tags.
  readonly property real minTagWidth: Style.space(124)
  readonly property real viewportShare: 0.66
  // The nameplate sits above the viewport, so the viewport starts below it.
  readonly property real plateRoom: Style.space(30 + 16)

  // Flanking costs, on each side, a gutter and a tag at its floor; whatever
  // is left is the most the viewport may take. On a laptop panel that is
  // less than its usual share, and the viewport gives way rather than the
  // arrangement: the tags surround the character on every screen that can
  // still show a character worth the name.
  readonly property real minViewportWidth: Style.space(380)
  readonly property real flankViewportWidth: width - 2 * (root.gutter + root.minTagWidth)
  readonly property bool flanked: root.flankViewportWidth >= root.minViewportWidth && height >= Style.space(300)
  // The narrowest pane that still flanks. The host sizes the slot column
  // against this, so widening that column never tips the character into
  // the stack by accident.
  readonly property real minFlankWidth: 2 * (root.gutter + root.minTagWidth) + root.minViewportWidth
  readonly property bool stacked: !root.flanked

  readonly property real sideWidth: Math.max(root.minTagWidth, (width - viewport.width) / 2 - root.gutter)

  // ---- Buckets ----------------------------------------------------------
  // How many tags a side column holds for free: a column is centred on the
  // viewport and may reach a little past it, but no further.
  readonly property int sideCapacity: {
    var room = viewport.height + 2 * Style.space(40)
    return Math.max(1, Math.floor((room + root.tagGap) / (root.tagHeight + root.tagGap)))
  }

  // Style keeps the left, Cyberware the right and Shell the foot. What a
  // side column cannot hold spills into the foot.
  readonly property var leftSlots: root.styleSlots.slice(0, root.sideCapacity)
  readonly property var rightSlots: root.cyberSlots.slice(0, root.sideCapacity)
  readonly property var bottomSlots: root.shellSlots
    .concat(root.styleSlots.slice(root.sideCapacity))
    .concat(root.cyberSlots.slice(root.sideCapacity))

  // The foot sits under the viewport by default, but may run out to the
  // pane's full width and wrap rather than squeeze its tags below the floor.
  // When the row has to wrap, the rows are balanced: eight tags on a pane
  // that fits six become four and four, not six and two.
  readonly property int bottomColumns: {
    var n = root.bottomSlots.length
    if (n <= 0) return 1
    var fit = Math.max(1, Math.floor((root.width + root.tagGap) / (root.minTagWidth + root.tagGap)))
    var rows = Math.ceil(n / fit)
    return Math.max(1, Math.ceil(n / rows))
  }
  readonly property real bottomRowWidth: {
    var cols = root.bottomColumns
    var floorWidth = cols * root.minTagWidth + (cols - 1) * root.tagGap
    return Math.min(root.width, Math.max(viewport.width, floorWidth))
  }
  readonly property real bottomTagWidth:
    (root.bottomRowWidth - root.tagGap * (root.bottomColumns - 1)) / root.bottomColumns

  // How far the taller side column reaches past the viewport, top and foot.
  readonly property real sideOverhang: root.stacked ? 0
    : Math.max(0, (Math.max(leftColumn.height, rightColumn.height) - viewport.height) / 2)
  // What has to clear above the viewport: the nameplate, or a column's overhang.
  readonly property real topRoom: Math.max(root.sideOverhang, root.plateRoom)

  // Where the foot row sits, measured from the viewport's own top.
  readonly property real footOffset: {
    var under = viewport.height + Style.space(28)
    var channel = root.width - 2 * (root.sideWidth + root.gutter)
    if (root.bottomRowWidth <= channel) return under
    return Math.max(under, viewport.height + root.sideOverhang + root.tagGap)
  }

  // ---- Viewport ------------------------------------------------------
  TechFrame {
    id: viewport
    anchors.horizontalCenter: parent.horizontalCenter
    // Everything the arrangement occupies, measured from the viewport's top.
    readonly property real groupHeight: root.stacked
      ? height + Style.space(24) + grid.height
      : root.footOffset + bottomRow.height
    // Centre the union of that and what sits above the viewport.
    y: root.topRoom + Math.max(Style.space(8), (parent.height - root.topRoom - groupHeight) / 2)
    width: root.stacked
      ? Math.min(parent.width * 0.86,
                 Math.max(Style.space(180), (parent.height - root.plateRoom - Style.space(8 + 24) - grid.height)) * (16 / 9))
      : Math.min(parent.width * root.viewportShare, root.flankViewportWidth, (parent.height * 0.60) * (16 / 9))
    height: width * (9 / 16)
    chamfer: Style.space(14)
    cuts: ["tl", "tr", "bl", "br"]
    fill: root.backdrop
    stroke: root.line
    strokeWidth: 1
    brackets: true
    bracketColor: root.accent
    bracketLength: Style.space(24)
    bracketWidth: 2
    bracketInset: 7

    MiniDesktop {
      id: preview
      anchors { fill: parent; margins: Style.space(5) }
      colors: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.colors : ({})
      wallpaper: root.host ? root.host.previewWallpaper : ""
      fontFamily: root.host ? root.host.previewFont : "monospace"
      themeName: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.name : ""
      terminalName: root.host ? root.host.previewTerminal : ""
      editorName: root.host ? root.host.previewEditor : ""
      browserName: root.host ? root.host.previewBrowser : ""
      agentName: root.host ? root.host.previewAgent : ""
      barPosition: root.host ? root.host.previewBarPosition : "top"
      barTransparent: root.host ? root.host.previewBarTransparent : false
      barLayout: root.host ? root.host.previewBarLayout : ({})
      glyphs: root.host ? root.host.widgetGlyphs : ({})
      fontScale: root.host ? root.host.previewFontScale : 1
      gapsIn: root.host ? root.host.previewLook.gapsIn : 5
      gapsOut: root.host ? root.host.previewLook.gapsOut : 10
      borderSize: root.host ? root.host.previewLook.borderSize : 2
      rounding: root.host ? root.host.previewLook.rounding : 0
      blurOn: root.host ? root.host.previewLook.blur : false
      shadowOn: root.host ? root.host.previewLook.shadow : false
    }
  }

  // Nameplate above the viewport: the staged theme, and whether the
  // character matches what is actually worn.
  Item {
    id: nameplate
    anchors { bottom: viewport.top; bottomMargin: Style.space(16); horizontalCenter: viewport.horizontalCenter }
    width: viewport.width - Style.space(8)
    height: Style.space(30)

    Text {
      id: plateName
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.name.toUpperCase() : ""
      color: root.fg
      font.family: root.uiFont
      font.pixelSize: Style.font.heading
      font.bold: true
      font.letterSpacing: 5
    }

    Text {
      anchors { left: plateName.right; leftMargin: Style.space(16); right: parent.right }
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: {
        if (!root.host) return ""
        var name = root.host.activeLoadoutName
        var state = root.host.previewing
          ? root.host.previewTag(root.host.previewSlot) + "  ·  ENTER FITS"
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

  // ---- Compact grid ----------------------------------------------------
  Grid {
    id: grid
    visible: root.stacked
    anchors { top: viewport.bottom; topMargin: Style.space(24); left: parent.left; right: parent.right }
    columns: Math.max(2, Math.min(5, Math.floor((root.width + root.tagGap) / (root.minTagWidth + root.tagGap))))
    columnSpacing: root.tagGap
    rowSpacing: Style.space(16)

    Repeater {
      model: root.stacked ? root.gridSlots : []
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "bottom"
        ownRule: true
        width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
      }
    }
  }

  // ---- Tag columns, each on one rail ---------------------------------------
  Column {
    id: leftColumn
    visible: root.flanked
    anchors { left: parent.left; verticalCenter: viewport.verticalCenter }
    width: root.sideWidth
    spacing: root.tagGap

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
  Rectangle {
    visible: root.flanked && root.leftSlots.length > 0
    x: leftColumn.x + leftColumn.width - 1
    y: leftColumn.y
    width: 1
    height: leftColumn.height
    color: root.line
  }

  Column {
    id: rightColumn
    visible: root.flanked
    anchors { right: parent.right; verticalCenter: viewport.verticalCenter }
    width: root.sideWidth
    spacing: root.tagGap

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
  Rectangle {
    visible: root.flanked && root.rightSlots.length > 0
    x: rightColumn.x
    y: rightColumn.y
    width: 1
    height: rightColumn.height
    color: root.line
  }

  Grid {
    id: bottomRow
    visible: root.flanked
    anchors.horizontalCenter: parent.horizontalCenter
    y: viewport.y + root.footOffset
    columns: root.bottomColumns
    spacing: root.tagGap

    Repeater {
      model: root.flanked ? root.bottomSlots : []
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "bottom"
        // Wrapped rows below the first carry their own rule.
        ownRule: index >= bottomRow.columns
        required property int index
        width: root.bottomTagWidth
      }
    }
  }
  Rectangle {
    visible: root.flanked && root.bottomSlots.length > 0
    x: bottomRow.x
    y: bottomRow.y
    width: bottomRow.width
    height: 1
    color: root.line
  }

  // ---- One tag ------------------------------------------------------------
  // No box. The slot's name in small caps, the fitted item's name under it,
  // and a word for its state only when the state is worth a word: PREVIEW
  // or FITTED. Equipped is the quiet default. The focused tag turns its
  // stretch of the rail to the accent. Text on the left column is set flush
  // right, toward the rail.
  component Callout: Item {
    id: card
    property var def: ({})
    property string side: "left"
    // A tag draws its own rule when it is not sitting on a shared rail.
    property bool ownRule: false

    readonly property var item: root.host ? root.host.selectedItem(def.id) : null
    readonly property bool focused: root.host && root.host.currentSlot && root.host.currentSlot.id === def.id
    readonly property bool staged: root.host && root.host.staged[def.id] ? true : false
    // Previewed: the cursor is trying something on that differs from what
    // the slot holds (fitted, else live).
    readonly property bool previewed: root.host && root.host.preview[def.id] !== undefined
      && root.host.preview[def.id] !== (root.host.staged[def.id] || root.host.equippedId(def.id))
    readonly property bool multi: def.multi === true
    readonly property string tag: previewed ? (root.host ? root.host.previewTag(def.id) : "PREVIEW")
      : staged ? "FITTED" : ""
    readonly property color tagColor: previewed ? root.accent : root.warn
    readonly property bool rightAligned: side === "left"
    readonly property bool hot: focused || mouse.containsMouse

    height: root.tagHeight

    // The rule: the tag's own when it has no rail, and the focused tag's
    // accent stretch either way.
    Rectangle {
      visible: card.side !== "bottom" && (card.ownRule || card.focused)
      anchors { top: parent.top; bottom: parent.bottom }
      x: card.side === "left" ? parent.width - width : 0
      width: card.focused ? 2 : 1
      color: card.focused ? root.accent : root.line
    }
    Rectangle {
      visible: card.side === "bottom" && (card.ownRule || card.focused)
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: card.focused ? 2 : 1
      color: card.focused ? root.accent : root.line
    }

    Column {
      anchors {
        left: parent.left; right: parent.right
        leftMargin: card.side === "right" ? Style.space(16) : Style.space(4)
        rightMargin: card.side === "left" ? Style.space(16) : Style.space(4)
        verticalCenter: parent.verticalCenter
        verticalCenterOffset: card.side === "bottom" ? Style.space(4) : 0
      }
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: labelText.implicitHeight

        // The name yields to the state word rather than running under it:
        // both are anchored, and the name elides.
        Text {
          id: labelText
          anchors.left: card.rightAligned ? (tagText.visible ? tagText.right : parent.left) : parent.left
          anchors.right: card.rightAligned ? parent.right : (tagText.visible ? tagText.left : parent.right)
          anchors.leftMargin: card.rightAligned && tagText.visible ? Style.space(8) : 0
          anchors.rightMargin: !card.rightAligned && tagText.visible ? Style.space(8) : 0
          horizontalAlignment: card.rightAligned ? Text.AlignRight : Text.AlignLeft
          elide: Text.ElideRight
          text: card.def.label || ""
          color: card.hot ? root.accent : root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 2
        }

        Text {
          id: tagText
          anchors.left: card.rightAligned ? parent.left : undefined
          anchors.right: card.rightAligned ? undefined : parent.right
          text: card.tag
          color: card.tagColor
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
          visible: text !== ""
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: card.rightAligned ? Text.AlignRight : Text.AlignLeft
        text: card.multi && root.host ? root.host.barModsSummary : (card.item ? card.item.name : "—")
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (!root.host) return
        root.host.slotIndex = root.host.slotDefs.findIndex(function(d) { return d.id === card.def.id })
      }
    }
  }
}
