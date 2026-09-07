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
  readonly property bool previewed: host && host.preview[slot.id] !== undefined && host.preview[slot.id] !== "__new"
    && host.preview[slot.id] !== (host.staged[slot.id] || host.equippedId(slot.id))
  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property bool inWorkbench: host ? host.workbenchOpen : false
  readonly property string kind: slot.id === "theme" ? "theme"
    // A multi slot has a widget under the cursor only inside the workbench;
    // from the button outside it, the slot describes itself.
    : slot.multi ? (inWorkbench ? "mod" : "workbench")
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
    if (kind === "workbench") return (host ? host.barModsSummary : "") + "  ·  ENTER opens the workbench"
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
  edgeColor: previewed ? accent : staged ? warn : (item && item.equipped ? good : (host ? host.line : Color.muted))
  edgeWidth: Style.space(3)

  implicitHeight: body.implicitHeight + Style.space(20)
  clip: true

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(10) }
    anchors.leftMargin: Style.space(16)
    spacing: Style.space(4)

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
        text: root.previewed ? "PREVIEW" : root.staged ? "FITTED"
          : root.kind === "workbench" ? "LIVE"
          : (root.item && root.item.equipped ? "EQUIPPED" : "")
        color: root.previewed ? root.accent : root.staged ? root.warn : root.good
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 2
      }
    }

    Text {
      width: parent.width
      text: root.kind === "workbench" ? (root.slot.label || "").replace(/\b\w+/g, function(w) {
          return w.charAt(0) + w.substring(1).toLowerCase()
        })
        : root.item ? root.item.name : "Nothing here"
      color: root.fg
      font.family: root.kind === "font" && root.item ? root.item.id : root.uiFont
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    // Kind-specific line: swatches, specimen, or the loadout's recorded slots.
    Row {
      visible: root.kind === "theme" && root.palette.length > 0
      spacing: Style.space(3)
      Repeater {
        model: root.palette
        Rectangle {
          required property var modelData
          width: Style.space(20); height: Style.space(10)
          color: modelData
          border.width: 1
          border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
        }
      }
    }

    // The slot seen from its button: how the fitting is spread across the
    // bar, and the summary that the row's tag bars used to carry.
    Text {
      visible: root.kind === "workbench"
      width: parent.width
      text: root.host ? root.host.barModsBreakdown : ""
      color: root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
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
      maximumLineCount: 1
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
      maximumLineCount: 1
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
