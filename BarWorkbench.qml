pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The workbench: the bar, laid out in the shape of the bar. A rail across the
// top shows what the fitting actually looks like; under it sit the three
// section bins, each an equal third of the rail and tethered to the stretch it
// governs; under those, one inventory pane the full width of the rail holding
// everything that is off.
//
// Bar mods uses three bins (LEFT, CENTER, RIGHT), but the bins are data, so
// another slot could open a workbench of its own with as many columns.
//
// Mouse: drag a tile into a bin, between two tiles, or back to the inventory.
// Hovering the rail moves the cursor. Keyboard: ← → walk the whole bar and
// wrap at its ends, ↑ ↓ cross between the bins and the inventory, 1 2 3 send
// the tile to a bin, BACKSPACE benches it, SHIFT+← → nudge it along, SPACE
// toggles. The host handles ENTER (fit), ESC (cancel) and D around it.
Item {
  id: root

  property var host: null
  // [{ id, label }] in order; the inventory is implicit.
  property var bins: [
    { id: "left",   label: "LEFT" },
    { id: "center", label: "CENTER" },
    { id: "right",  label: "RIGHT" }
  ]

  readonly property var layout: (host && host.previewBarLayout) || ({})
  readonly property var widgets: (host && host.inventory && host.inventory.barWidgets) || []
  readonly property var byId: {
    var m = {}
    var ws = root.widgets
    for (var i = 0; i < ws.length; i++) if (ws[i] && ws[i].id) m[ws[i].id] = ws[i]
    return m
  }
  function nameOf(id) {
    var w = root.byId[id]
    return (w && w.name) ? String(w.name) : String(id)
  }
  // Tiles only exist for catalogue widgets: the layout string may carry
  // entries (the spacer) that have no tile and stay where they are.
  function tilesIn(binId) {
    var ids = (root.layout && root.layout[binId]) || []
    var map = root.byId
    return ids.filter(function(id) { return map[id] !== undefined })
  }
  readonly property var benchIds: {
    var placed = {}
    var bs = root.bins || []
    for (var b = 0; b < bs.length; b++) {
      var ids = (root.layout && root.layout[bs[b].id]) || []
      for (var i = 0; i < ids.length; i++) placed[ids[i]] = true
    }
    var out = root.widgets.filter(function(w) { return w && w.id && !placed[w.id] })
                          .map(function(w) { return w.id })
    out.sort(function(a, b) { return root.nameOf(a).localeCompare(root.nameOf(b)) })
    return out
  }

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  // ---- Geometry --------------------------------------------------------
  // One width governs the rail, the bins and the inventory, so all three read
  // as the same object seen three ways.
  readonly property real railWidth: Math.min(root.width, Style.space(1500))
  readonly property real binGap: Style.space(12)
  readonly property real binWidth: (root.railWidth - (root.bins.length - 1) * root.binGap) / Math.max(1, root.bins.length)

  readonly property real gap: Style.space(8)
  readonly property real framePad: Style.space(10)
  readonly property real headHeight: Style.space(18)
  readonly property real railHeight: Style.space(46)
  readonly property real tetherHeight: Style.space(16)
  readonly property real sectionGap: Style.space(14)
  // What the item data band at the foot of the group takes, so the shrink
  // loop sizes tiles against the room actually left over.
  readonly property real bottomReserve: itemBand.height + root.sectionGap

  readonly property real railBlockHeight: root.headHeight + Style.space(6) + root.railHeight

  // Tiles shrink until the rail, the bins, the inventory and their gaps fit
  // the body: the workbench is a whole arrangement and must never scroll.
  // Width drives this as much as height — a bin is a third of the rail, so
  // every widget it cannot fit on one row costs a row of height everywhere.
  readonly property real tileFull: Style.space(64)
  readonly property real tileFloor: Style.space(38)
  function rowsFor(count, inner, t) {
    var perRow = Math.max(1, Math.floor((inner + root.gap) / (t + root.gap)))
    return Math.max(1, Math.ceil(Math.max(1, count) / perRow))
  }
  function paneHeight(rows, t) { return rows * t + (rows - 1) * root.gap + 2 * root.framePad }
  readonly property real tile: {
    var h = root.height - root.bottomReserve, w = root.railWidth
    if (h <= 0 || w <= 0) return root.tileFull
    var binInner = root.binWidth - 2 * root.framePad
    var benchInner = root.railWidth - 2 * root.framePad
    var counts = []
    for (var b = 0; b < root.bins.length; b++) counts.push(root.listFor(root.bins[b].id).length)
    var benchCount = root.listFor("bench").length
    for (var t = root.tileFull; t > root.tileFloor; t -= 1) {
      var binRows = 1
      for (var i = 0; i < counts.length; i++) binRows = Math.max(binRows, root.rowsFor(counts[i], binInner, t))
      var total = root.railBlockHeight + root.tetherHeight
        + root.headHeight + root.paneHeight(binRows, t) + root.sectionGap
        + root.headHeight + root.paneHeight(root.rowsFor(benchCount, benchInner, t), t)
      if (total <= h) return t
    }
    return root.tileFloor
  }

  readonly property real binsRowHeight: {
    var binInner = root.binWidth - 2 * root.framePad
    var rows = 1
    for (var b = 0; b < root.bins.length; b++)
      rows = Math.max(rows, root.rowsFor(root.listFor(root.bins[b].id).length, binInner, root.tile))
    return root.headHeight + root.paneHeight(rows, root.tile)
  }
  readonly property real benchHeight: {
    var inner = root.railWidth - 2 * root.framePad
    return root.headHeight + root.paneHeight(root.rowsFor(root.listFor("bench").length, inner, root.tile), root.tile)
  }

  // Where a tile's centre falls across the workbench's width. The bins and
  // the inventory are laid out by the same numbers the shrink loop uses, so
  // this can be worked out from the model rather than read off the delegates
  // — which is what lets ↑ ↓ land on whatever is actually above or below.
  function binPerRow() {
    return Math.max(1, Math.floor(((root.binWidth - 2 * root.framePad) + root.gap) / (root.tile + root.gap)))
  }
  function benchPerRow() {
    return Math.max(1, Math.floor(((root.railWidth - 2 * root.framePad) + root.gap) / (root.tile + root.gap)))
  }
  function centreOf(zone, index) {
    if (zone === "bench")
      return root.framePad + (index % root.benchPerRow()) * (root.tile + root.gap) + root.tile / 2
    var b = 0
    for (var i = 0; i < root.bins.length; i++) if (root.bins[i].id === zone) b = i
    return b * (root.binWidth + root.binGap) + root.framePad
      + (index % root.binPerRow()) * (root.tile + root.gap) + root.tile / 2
  }
  function nearestIn(zone, x) {
    var l = root.listFor(zone)
    if (!l.length) return ""
    var best = 0, bestD = Infinity
    for (var i = 0; i < l.length; i++) {
      var d = Math.abs(root.centreOf(zone, i) - x)
      if (d < bestD) { bestD = d; best = i }
    }
    return l[best]
  }
  // The bin standing over a point, then its neighbours outwards: coming up
  // out of the inventory under an empty bin should still land somewhere.
  function crossToBins(x) {
    var start = Math.max(0, Math.min(root.bins.length - 1, Math.floor(x / (root.binWidth + root.binGap))))
    var order = []
    for (var i = 0; i < root.bins.length; i++) order.push(i)
    order.sort(function(a, b) { return Math.abs(a - start) - Math.abs(b - start) })
    for (var k = 0; k < order.length; k++) {
      var id = root.nearestIn(root.bins[order[k]].id, x)
      if (id) return id
    }
    return ""
  }

  // ---- Cursor ----------------------------------------------------------
  property string cursorId: ""

  function zones() {
    var out = []
    var bs = root.bins || []
    for (var b = 0; b < bs.length; b++) out.push(bs[b].id)
    out.push("bench")
    return out
  }
  function listFor(zone) { return zone === "bench" ? root.benchIds : root.tilesIn(zone) }
  // The bar reads left to right as one line of tiles, whatever section a
  // tile happens to be in — which is how ← → walk it.
  function barSequence() {
    var out = []
    for (var b = 0; b < root.bins.length; b++) {
      var l = root.listFor(root.bins[b].id)
      for (var i = 0; i < l.length; i++) out.push(l[i])
    }
    return out
  }
  function whereIs(id) {
    if (!id) return null
    var zs = root.zones()
    for (var z = 0; z < zs.length; z++) {
      var idx = root.listFor(zs[z]).indexOf(id)
      if (idx >= 0) return { zone: zs[z], index: idx }
    }
    return null
  }
  function firstTile() {
    var zs = root.zones()
    for (var z = 0; z < zs.length; z++) {
      var l = root.listFor(zs[z])
      if (l && l.length) return l[0]
    }
    return ""
  }
  // A cursor is valid as long as it names a catalogue widget: every widget is
  // either in a bin or on the bench, so there is nowhere else for it to be.
  // Asking whereIs() instead would drop the cursor whenever a move fires this
  // before the derived lists have caught up — benching a tile would strand the
  // cursor back at the head of the first bin.
  function ensureCursor() {
    if (root.cursorId && root.byId[root.cursorId]) return
    root.cursorId = root.firstTile()
  }
  // Keep the host's cursor on the same widget so item data follows.
  function syncHostCursor() {
    if (!root.host || !root.cursorId) return
    var items = root.host.itemsFor("barMods")
    for (var i = 0; i < items.length; i++) if (items[i].id === root.cursorId) { root.host.modsCursor = i; return }
  }
  onLayoutChanged: root.ensureCursor()
  onWidgetsChanged: root.ensureCursor()
  Component.onCompleted: root.ensureCursor()
  onCursorIdChanged: root.syncHostCursor()
  // Reopening keeps the cursor where it was left, which fires no change, so
  // the host's cursor has to be pushed again or item data opens on whatever
  // widget it last described.
  onVisibleChanged: if (visible) { root.ensureCursor(); root.syncHostCursor() }

  // ← → walk the whole bar — off the end of LEFT into CENTER, off the end of
  // RIGHT back to the start — because that is what the eye does along the
  // rail, and what SHIFT+← → already did when nudging. In the inventory they
  // walk the inventory. ↑ ↓ cross between the bar and the inventory, landing
  // on whatever tile stands nearest in the column the cursor is in.
  function moveCursor(dx, dy) {
    root.ensureCursor()
    var at = root.whereIs(root.cursorId)
    if (!at) return
    if (dy !== 0) {
      var x = root.centreOf(at.zone, at.index)
      var to = at.zone === "bench" ? root.crossToBins(x) : root.nearestIn("bench", x)
      if (to) root.cursorId = to
      return
    }
    var list = at.zone === "bench" ? root.benchIds : root.barSequence()
    if (!list.length) return
    var i = list.indexOf(root.cursorId)
    if (i < 0) return
    root.cursorId = list[(i + dx + list.length) % list.length]
  }

  function handleKey(key, modifiers) {
    if (!root.host) return false
    var shift = (modifiers & Qt.ShiftModifier) !== 0
    root.ensureCursor()
    var id = root.cursorId
    if (key === Qt.Key_Left || key === Qt.Key_H) { if (shift && id) root.host.nudgeMod(id, -1); else root.moveCursor(-1, 0); return true }
    if (key === Qt.Key_Right || key === Qt.Key_L) { if (shift && id) root.host.nudgeMod(id, 1); else root.moveCursor(1, 0); return true }
    if (key === Qt.Key_Up || key === Qt.Key_K) { root.moveCursor(0, -1); return true }
    if (key === Qt.Key_Down || key === Qt.Key_J) { root.moveCursor(0, 1); return true }
    if (!id) return false
    if (key >= Qt.Key_1 && key < Qt.Key_1 + root.bins.length) { root.host.placeMod(id, root.bins[key - Qt.Key_1].id, -1); return true }
    if (key === Qt.Key_Backspace || key === Qt.Key_Delete || key === Qt.Key_0) { root.host.benchMod(id); return true }
    if (key === Qt.Key_Space) { root.host.toggleModId(id); return true }
    return false
  }

  // ---- Layout ----------------------------------------------------------
  // The rail, its bins and the inventory are one object, so they are centred
  // as one: a tall screen gives the group even margins rather than stranding
  // it under the header with a screen's worth of nothing beneath.
  Item {
    id: column
    width: root.railWidth
    anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
    height: root.railBlockHeight + root.tetherHeight + root.binsRowHeight
      + root.sectionGap + root.benchHeight + root.bottomReserve

    // -- The rail: the fitting, drawn as a bar ---------------------------
    Item {
      id: railBlock
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: root.railBlockHeight

      Text {
        id: railLabel
        anchors { left: parent.left; top: parent.top }
        text: "BAR"
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 2
      }

      Rectangle {
        anchors {
          left: railLabel.right; leftMargin: Style.space(10)
          right: railTag.left; rightMargin: Style.space(10)
          verticalCenter: railLabel.verticalCenter
        }
        height: 1
        color: root.line
      }

      // The chassis the arrangement hangs on. A vertical bar still reads as
      // a horizontal rail here — LEFT / CENTER / RIGHT are the bar's own
      // section names, not directions on the screen — so the tag says which
      // edge it is really on.
      Text {
        id: railTag
        anchors { right: parent.right; top: parent.top }
        text: (root.host ? String(root.host.previewBarPosition || "top") : "top").toUpperCase()
          + "  ·  " + (root.host && root.host.previewBarTransparent ? "CLEAR" : "SOLID")
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }

      TechFrame {
        id: railFrame
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.railHeight
        chamfer: Style.space(8)
        fill: "transparent"
        stroke: root.line
        strokeWidth: 1

        // The bar's own surface, painted opaque so nothing on this layer
        // has to composite against the backdrop: the previewed wallpaper
        // shows through a CLEAR bar exactly as it would on the desktop, and
        // a SOLID one covers it.
        Item {
          id: railBody
          anchors { fill: parent; margins: Style.space(3) }
          clip: true

          Rectangle {
            anchors.fill: parent
            color: root.railColor("background", "#101315")
          }

          Image {
            id: railWall
            anchors.fill: parent
            source: root.host && root.host.previewWallpaper ? "file://" + root.host.previewWallpaper : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
          }

          Rectangle {
            anchors.fill: parent
            visible: !(root.host && root.host.previewBarTransparent)
            color: root.railColor("dark_background", root.railColor("background", "#101315"))
          }

          BarRail {
            anchors.fill: parent
            layout: root.layout
            glyphs: root.host ? root.host.widgetGlyphs : ({})
            horizontal: true
            interactive: true
            highlightId: root.cursorId
            u: railBody.height / 7
            t: (railBody.height / 7) * (root.host ? root.host.previewFontScale : 1)
            fontFamily: root.host ? root.host.previewFont : "monospace"
            fg: root.railColor("foreground", "#cacccc")
            dimFg: root.railColor("dark_foreground", "#707880")
            accent: root.railColor("accent", "#7aa2f7")
            green: root.railColor("green", "#a6e3a1")
            yellow: root.railColor("yellow", "#f9e2af")
            blue: root.railColor("blue", "#89b4fa")
            onTokenHovered: function(id) { if (root.byId[id]) root.cursorId = id }
          }
        }
      }
    }

    // -- Tethers: each bin to the stretch of rail it governs -------------
    Repeater {
      model: root.bins
      delegate: Item {
        id: tether
        required property var modelData
        required property int index
        readonly property bool hot: root.cursorId !== "" && root.listFor(tether.modelData.id).indexOf(root.cursorId) >= 0

        x: tether.index * (root.binWidth + root.binGap) + root.binWidth / 2
        y: root.railBlockHeight
        width: 1
        height: root.tetherHeight

        Rectangle {
          anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
          width: 1
          color: tether.hot ? root.accent : root.line
        }
        Rectangle {
          anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
          width: Style.space(3); height: Style.space(3)
          color: tether.hot ? root.accent : root.line
        }
      }
    }

    // -- The bins: equal thirds of the rail ------------------------------
    Row {
      id: binsRow
      anchors { left: parent.left; top: parent.top; topMargin: root.railBlockHeight + root.tetherHeight }
      spacing: root.binGap

      Repeater {
        model: root.bins
        delegate: Zone {
          required property var modelData
          zoneId: modelData.id
          label: modelData.label
          width: root.binWidth
          height: root.binsRowHeight
        }
      }
    }

    // -- The inventory: everything that is off ---------------------------
    Zone {
      id: benchZone
      zoneId: "bench"
      label: "INVENTORY"
      anchors {
        left: parent.left; right: parent.right
        top: parent.top
        topMargin: root.railBlockHeight + root.tetherHeight + root.binsRowHeight + root.sectionGap
      }
      height: root.benchHeight
    }

    // Whatever the cursor is on, spelled out — the same panel the slot column
    // carries, run the rail's full width at the foot of the group.
    ItemData {
      id: itemBand
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: implicitHeight
      host: root.host
    }
  }

  // The previewed theme's palette, so the rail is the preview and not more
  // chrome. Falls back per key: user themes don't all define every colour.
  function railColor(key, fallback) {
    var t = root.host ? root.host.stagedThemeObject : null
    var v = (t && t.colors) ? t.colors[key] : undefined
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  // One bin, or the inventory: a header rule with the zone's name and count,
  // a frame, tiles flowing inside it. A DropArea over the frame takes dragged
  // tiles; the drop index comes from where the pointer was.
  component Zone: Item {
    id: zone
    property string zoneId: ""
    property string label: ""
    readonly property bool isBench: zoneId === "bench"
    readonly property var ids: root.listFor(zoneId)
    readonly property bool hot: root.cursorId !== "" && ids.indexOf(root.cursorId) >= 0

    Item {
      id: head
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: root.headHeight

      Text {
        id: zoneLabel
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: zone.label
        color: zone.hot ? root.accent : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.bold: zone.hot
        font.letterSpacing: 2
      }

      Rectangle {
        anchors {
          left: zoneLabel.right; leftMargin: Style.space(10)
          right: zoneCount.left; rightMargin: Style.space(10)
          verticalCenter: parent.verticalCenter
        }
        height: 1
        color: zone.hot ? root.accent : root.line
        opacity: zone.hot ? 0.8 : 1
      }

      Text {
        id: zoneCount
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: String(zone.ids.length).padStart(2, "0") + (zone.isBench ? "  OFF" : "")
        color: zone.hot ? root.accent : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }
    }

    TechFrame {
      id: frame
      anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
      chamfer: Style.space(8)
      fill: drop.containsDrag
        ? (root.host ? root.host.paneBgFocused : "transparent")
        : (root.host ? root.host.paneBg : "transparent")
      stroke: drop.containsDrag ? root.accent : (zone.hot ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : root.line)
      strokeWidth: 1
      dashed: zone.isBench
      edge: zone.isBench ? "" : "top"
      edgeColor: zone.hot ? root.accent : root.line
      edgeWidth: Style.space(2)

      Text {
        anchors.centerIn: parent
        visible: zone.ids.length === 0
        text: zone.isBench
          ? "EVERYTHING IS ON THE BAR"
          : "EMPTY  ·  DROP A TILE OR PRESS " + (root.bins.map(function(b) { return b.id }).indexOf(zone.zoneId) + 1)
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }

      Flow {
        id: flow
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.framePad }
        spacing: root.gap

        Repeater {
          model: zone.ids
          delegate: Tile {
            required property string modelData
            widgetId: modelData
            zoneId: zone.zoneId
          }
        }
      }

      DropArea {
        id: drop
        anchors.fill: parent
        onDropped: function(event) {
          if (!root.host || !event.source || !event.source.widgetId) return
          var id = event.source.widgetId
          if (zone.isBench) { root.host.benchMod(id); root.cursorId = id; return }
          // Index: tiles that end before the pointer, reading order.
          var p = drop.mapToItem(flow, event.x, event.y)
          var index = 0
          for (var i = 0; i < flow.children.length; i++) {
            var c = flow.children[i]
            if (!c.widgetId || c.widgetId === id) continue
            if (p.y > c.y + c.height || (p.y >= c.y && p.x > c.x + c.width / 2)) index++
          }
          root.host.placeMod(id, zone.zoneId, index)
          root.cursorId = id
        }
      }
    }
  }

  // A tile: glyph over short name, cursor brackets, a settings marker. The
  // visual sits in a wrapper the Flow positions; only the visual drags, and
  // snaps back when dropped because the model, not the drag, moves it.
  component Tile: Item {
    id: wrap
    property string widgetId: ""
    property string zoneId: ""
    readonly property var w: root.byId[widgetId] || ({})
    readonly property bool isCursor: root.cursorId === widgetId
    readonly property bool changed: {
      if (!root.host) return false
      var items = root.host.itemsFor("barMods")
      for (var i = 0; i < items.length; i++) if (items[i].id === wrap.widgetId) return items[i].changed === true
      return false
    }

    width: root.tile
    height: root.tile

    Item {
      id: visual
      width: root.tile
      height: root.tile
      z: tileMouse.drag.active ? 100 : 0
      property string widgetId: wrap.widgetId

      Drag.active: tileMouse.drag.active
      Drag.source: visual
      Drag.hotSpot.x: width / 2
      Drag.hotSpot.y: height / 2

      TechFrame {
        anchors.fill: parent
        chamfer: Style.space(6)
        cuts: ["tr", "bl"]
        fill: wrap.isCursor
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.selectedFillAlpha)
          : (root.host ? root.host.paneBgFocused : "transparent")
        stroke: wrap.isCursor ? root.accent : (tileMouse.containsMouse ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18))
        strokeWidth: 1
        brackets: wrap.isCursor
        bracketColor: root.accent
        bracketLength: Style.space(9)
        bracketWidth: 2
        bracketInset: 2

        Column {
          anchors.centerIn: parent
          spacing: Style.space(3)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.host ? (root.host.widgetGlyphs[wrap.widgetId] || "▪") : "▪"
            color: wrap.isCursor ? root.accent : root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.iconLarge
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: wrap.w.short || ""
            color: wrap.isCursor ? root.accent : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption - 1
            font.bold: true
            font.letterSpacing: 1
          }
        }

        // Carries settings: benching it discards them.
        Rectangle {
          visible: wrap.w.settings === true
          anchors { right: parent.right; top: parent.top; rightMargin: Style.space(5); topMargin: Style.space(5) }
          width: Style.space(5); height: Style.space(5)
          color: root.warn
        }

        // Changed against live: a foot in the warning colour.
        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(3)
          height: Style.space(3)
          color: root.warn
          visible: wrap.changed
        }
      }

      MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: visual
        drag.threshold: 6
        onPressed: root.cursorId = wrap.widgetId
        onReleased: {
          if (drag.active) visual.Drag.drop()
          visual.x = 0
          visual.y = 0
        }
        onDoubleClicked: if (root.host) root.host.toggleModId(wrap.widgetId)
      }
    }
  }
}
