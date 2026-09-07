pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The description panel: whatever the cursor is on, spelled out. A theme
// shows its palette, a font its specimen, a saved loadout what it recorded,
// and everything shows where it comes from and how it is applied.
TechFrame {
  id: root

  property var host: null

  readonly property var slot: host ? host.currentSlot : ({})
  readonly property var item: host ? host.selectedItem(slot.id) : null
  readonly property bool staged: host && host.staged[slot.id] && host.staged[slot.id] !== "__new" ? true : false
  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property string kind: slot.id === "theme" ? "theme"
    : slot.multi ? "mod"
    : slot.id === "font" ? "font"
    : slot.id === "loadouts" ? "loadout"
    : slot.id === "background" ? "background"
    : "plain"

  readonly property var palette: {
    if (kind !== "theme" || !item || !item.colors) return []
    var keys = ["background", "foreground", "accent", "red", "yellow", "green", "cyan", "blue", "magenta"]
    var out = []
    for (var i = 0; i < keys.length; i++) if (item.colors[keys[i]]) out.push(item.colors[keys[i]])
    return out
  }

  readonly property string source: {
    if (!item) return ""
    if (item.isNew) return "S  or  ENTER here  ·  records the fitting as it stands"
    if (kind === "loadout") {
      var n = 0
      for (var k in item.slots) n++
      return n + " slots recorded  ·  " + String(item.savedAt || "").replace("T", " ").substring(0, 16)
    }
    if (item.path) return item.path
    if (kind === "mod") return (host ? host.barModsSummary : "") + "  ·  omarchy plugin enable / disable  ·  omarchy bar move"
    if (slot.apply) return slot.apply.map(function(a) { return a.split("/").pop() }).join(" ") + "  " + item.id
    return ""
  }

  chamfer: Style.space(12)
  cuts: ["tr", "bl"]
  fill: host ? host.paneBg : "transparent"
  stroke: host ? host.line : Color.muted
  edge: "left"
  edgeColor: staged ? warn : (item && item.equipped ? good : (host ? host.line : Color.muted))
  edgeWidth: Style.space(3)

  implicitHeight: body.implicitHeight + Style.space(32)

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(16) }
    anchors.leftMargin: Style.space(22)
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: kicker.implicitHeight

      Text {
        id: kicker
        anchors.left: parent.left
        text: "ITEM DATA  //  " + (root.slot.label || "")
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 2
      }

      Text {
        anchors.right: parent.right
        text: root.staged ? "STAGED" : (root.item && root.item.equipped ? "EQUIPPED" : "")
        color: root.staged ? root.warn : root.good
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 2
      }
    }

    Text {
      width: parent.width
      text: root.item ? root.item.name : "Nothing here"
      color: root.fg
      font.family: root.kind === "font" && root.item ? root.item.id : root.uiFont
      font.pixelSize: Style.font.heading
      font.bold: true
      elide: Text.ElideRight
    }

    // Kind-specific line: swatches, specimen, or the loadout's recorded slots.
    Row {
      visible: root.kind === "theme" && root.palette.length > 0
      spacing: Style.space(4)
      Repeater {
        model: root.palette
        Rectangle {
          required property var modelData
          width: Style.space(26); height: Style.space(12)
          color: modelData
          border.width: 1
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
        }
      }
    }

    // A bar widget: where it sits, what it does, and a warning when its
    // layout entry carries settings that turning it off would discard.
    Text {
      visible: root.kind === "mod" && root.item
      width: parent.width
      text: {
        if (!root.item) return ""
        var where = root.item.on
          ? String(root.item.section).toUpperCase() + " " + String(root.item.index + 1).padStart(2, "0")
          : "BENCH"
        var parts = [where]
        if (root.item.category) parts.push(root.item.category.toUpperCase())
        if (root.item.description) parts.push(root.item.description)
        return parts.join("  ·  ")
      }
      color: root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      visible: root.kind === "mod" && root.item && root.item.settings === true
      width: parent.width
      text: "CARRIES SETTINGS  ·  turning it off discards them; back on means defaults"
      color: root.warn
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      elide: Text.ElideRight
    }

    Text {
      visible: root.kind === "font" && root.item
      width: parent.width
      text: "The quick brown fox jumps over the lazy dog  0123456789  {}[]<>=>"
      color: root.fg
      font.family: root.item ? root.item.id : root.uiFont
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: root.kind === "loadout" && root.item && !root.item.isNew
      width: parent.width
      text: {
        if (!root.item || !root.item.slots) return ""
        var parts = []
        for (var k in root.item.slots) {
          var v = String(root.item.slots[k])
          if (k === "background") v = v.split("/").pop().replace(/\.[^.]+$/, "")
          parts.push(k.toUpperCase() + " " + v)
        }
        return parts.join("   ")
      }
      color: root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: root.source
      color: root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }
  }
}
