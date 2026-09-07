pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The workbench: sort tiles into labelled bins. Bar mods uses it with three
// bins (LEFT, CENTER, RIGHT) and a bench of everything that is off, but the
// bins are data, so another slot could open a workbench of its own.
//
// Mouse: drag a tile into a bin, between two tiles, or back to the bench.
// Keyboard: arrows move the cursor across tiles; 1 2 3 send the tile to a
// bin; BACKSPACE benches it; SHIFT+← → nudge it within its bin; SPACE
// toggles. The host handles ENTER (fit) and ESC (cancel) around it.
Item {
  id: root

  property var host: null
  // [{ id, label }] in order; the bench is implicit.
  property var bins: [
    { id: "left",   label: "LEFT" },
    { id: "center", label: "CENTER" },
    { id: "right",  label: "RIGHT" }
  ]

  readonly property var layout: host ? host.previewBarLayout : ({})
  readonly property var widgets: (host && host.inventory && host.inventory.barWidgets) || []
  readonly property var byId: {
    var m = {}
    for (var i = 0; i < widgets.length; i++) m[widgets[i].id] = widgets[i]
    return m
  }
  // Tiles only exist for catalogue widgets: the layout string may carry
  // entries (the spacer) that have no tile and stay where they are.
  function tilesIn(binId) {
    var ids = (root.layout && root.layout[binId]) || []
    return ids.filter(function(id) { return root.byId[id] !== undefined })
  }
  readonly property var benchIds: {
    var placed = {}
    for (var b = 0; b < bins.length; b++) {
      var ids = (layout && layout[bins[b].id]) || []
      for (var i = 0; i < ids.length; i++) placed[ids[i]] = true
    }
    var out = widgets.filter(function(w) { return !placed[w.id] }).map(function(w) { return w.id })
    out.sort(function(a, b) { return root.byId[a].name.localeCompare(root.byId[b].name) })
    return out
  }

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property real tile: Style.space(54)
  readonly property real gap: Style.space(8)
  readonly property real labelWidth: Style.space(62)

  // ---- Cursor ----------------------------------------------------------
  property string cursorId: ""

  function zones() {
    var out = []
    for (var b = 0; b < root.bins.length; b++) out.push(root.bins[b].id)
    out.push("bench")
    return out
  }
  function listFor(zone) { return zone === "bench" ? root.benchIds : root.tilesIn(zone) }
  function whereIs(id) {
    var zs = zones()
    for (var z = 0; z < zs.length; z++) {
      var idx = listFor(zs[z]).indexOf(id)
      if (idx >= 0) return { zone: zs[z], index: idx }
    }
    return null
  }
  function firstTile() {
    var zs = zones()
    for (var z = 0; z < zs.length; z++) { var l = listFor(zs[z]); if (l.length) return l[0] }
    return ""
  }
  function ensureCursor() {
    if (!root.cursorId || !whereIs(root.cursorId)) root.cursorId = firstTile()
  }
  onLayoutChanged: ensureCursor()
  Component.onCompleted: ensureCursor()
  onCursorIdChanged: {
    // Keep the host's cursor on the same widget so item data follows.
    if (!root.host || !root.cursorId) return
    var items = root.host.itemsFor("barMods")
    for (var i = 0; i < items.length; i++) if (items[i].id === root.cursorId) { root.host.modsCursor = i; break }
  }

  // Up/down step between zones, keeping the column; left/right wrap in a zone.
  function moveCursor(dx, dy) {
    ensureCursor()
    var at = whereIs(root.cursorId)
    if (!at) return
    var zs = zones()
    if (dy !== 0) {
      var zi = zs.indexOf(at.zone)
      for (var step = 1; step <= zs.length; step++) {
        var nz = zs[(zi + dy * step + zs.length * step) % zs.length]
        var l = listFor(nz)
        if (l.length) { root.cursorId = l[Math.min(at.index, l.length - 1)]; return }
      }
      return
    }
    var list = listFor(at.zone)
    root.cursorId = list[(at.index + dx + list.length) % list.length]
  }

  function handleKey(key, modifiers) {
    if (!root.host) return false
    var shift = (modifiers & Qt.ShiftModifier) !== 0
    ensureCursor()
    var id = root.cursorId
    if (key === Qt.Key_Left || key === Qt.Key_H) { if (shift && id) root.host.nudgeMod(id, -1); else moveCursor(-1, 0); return true }
    if (key === Qt.Key_Right || key === Qt.Key_L) { if (shift && id) root.host.nudgeMod(id, 1); else moveCursor(1, 0); return true }
    if (key === Qt.Key_Up || key === Qt.Key_K) { moveCursor(0, -1); return true }
    if (key === Qt.Key_Down || key === Qt.Key_J) { moveCursor(0, 1); return true }
    if (!id) return false
    if (key >= Qt.Key_1 && key < Qt.Key_1 + root.bins.length) { root.host.placeMod(id, root.bins[key - Qt.Key_1].id, -1); return true }
    if (key === Qt.Key_Backspace || key === Qt.Key_Delete || key === Qt.Key_0) { root.host.benchMod(id); return true }
    if (key === Qt.Key_Space) { root.host.toggleModId(id); return true }
    return false
  }

  // ---- Layout ----------------------------------------------------------
  Column {
    id: column
    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: Style.space(10)

    Repeater {
      model: root.bins
      delegate: Zone {
        required property var modelData
        zoneId: modelData.id
        label: modelData.label
        width: column.width
      }
    }

    Zone {
      zoneId: "bench"
      label: "BENCH"
      width: column.width
    }
  }

  // One bin, or the bench: a label, a frame, tiles flowing inside it. A
  // DropArea over the frame takes dragged tiles; the drop index comes from
  // where the pointer was.
  component Zone: Item {
    id: zone
    property string zoneId: ""
    property string label: ""
    readonly property bool isBench: zoneId === "bench"
    readonly property var ids: root.listFor(zoneId)
    readonly property bool hot: root.cursorId !== "" && ids.indexOf(root.cursorId) >= 0

    height: Math.max(root.tile + Style.space(20), flow.implicitHeight + Style.space(20))

    Text {
      id: zoneLabel
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      width: root.labelWidth
      text: zone.label
      color: zone.hot ? root.accent : root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.bold: zone.hot
      font.letterSpacing: 2
    }

    TechFrame {
      id: frame
      anchors { left: zoneLabel.right; right: parent.right; top: parent.top; bottom: parent.bottom }
      chamfer: Style.space(8)
      fill: drop.containsDrag ? root.host.paneBgFocused : root.host.paneBg
      stroke: drop.containsDrag ? root.accent : (zone.hot ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6) : root.line)
      strokeWidth: 1
      dashed: zone.isBench
      edge: zone.isBench ? "" : "left"
      edgeColor: zone.hot ? root.accent : root.line
      edgeWidth: Style.space(2)

      Text {
        anchors.centerIn: parent
        visible: zone.ids.length === 0
        text: zone.isBench ? "EVERYTHING IS ON THE BAR" : "EMPTY  ·  DROP A TILE OR PRESS " + (root.bins.map(function(b) { return b.id }).indexOf(zone.zoneId) + 1)
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }

      Flow {
        id: flow
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(10) }
        anchors.leftMargin: Style.space(14)
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
