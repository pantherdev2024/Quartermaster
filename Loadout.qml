pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

// Loadout — an RPG equip screen for Omarchy.
//
// Left and right columns hold equipment slots; the centre shows a miniature
// mock desktop painted in whatever is currently staged; the bottom strip is
// the character sheet, reading real system metrics.
//
// Staging is separate from applying on purpose: moving the cursor repaints the
// preview instantly and touches nothing, and only APPLY runs the omarchy
// commands that change the real system.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var inventory: ({})
  property var stats: ({})
  property bool applying: false
  property string statusText: ""

  // Resolved from the QML file's own location so a rename or clone still works.
  readonly property string pluginDir: {
    var u = Qt.resolvedUrl(".").toString()
    return u.replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  // ---- Slot definitions ----------------------------------------------
  // Each slot knows how to find its items, what is currently equipped, and
  // which command applies it. Adding a slot means adding one entry here.
  readonly property var slotDefs: [
    { id: "theme",      label: "THEME",      side: "left",  apply: "omarchy-theme-set" },
    { id: "background", label: "BACKGROUND", side: "left",  apply: "omarchy-theme-bg-set" },
    { id: "font",       label: "FONT",       side: "right", apply: "omarchy-font-set" },
    { id: "terminal",   label: "TERMINAL",   side: "right", apply: "omarchy-default-terminal" }
  ]

  // Staged selection per slot id. Empty means "unchanged from what's live".
  property var staged: ({})

  property int slotIndex: 0
  readonly property var currentSlot: slotDefs[Math.max(0, Math.min(slotDefs.length - 1, slotIndex))]

  function itemsFor(slotId) {
    var inv = root.inventory
    if (!inv) return []
    if (slotId === "theme") return inv.themes || []
    if (slotId === "font") return inv.fonts || []
    if (slotId === "terminal") return inv.terminals || []
    if (slotId === "background") {
      // Backgrounds belong to whichever theme is staged, so this slot's
      // contents change as the theme cursor moves.
      var t = root.stagedThemeObject
      if (!t || !t.backgrounds) return []
      return t.backgrounds.map(function(p) {
        return { id: p, name: p.split("/").pop().replace(/\.[^.]+$/, ""), path: p }
      })
    }
    return []
  }

  // The theme object driving the whole preview: staged if the user has moved
  // the cursor, otherwise whatever is actually equipped.
  readonly property var stagedThemeObject: {
    var themes = (root.inventory && root.inventory.themes) || []
    var wanted = root.staged["theme"]
    for (var i = 0; i < themes.length; i++) {
      if (wanted ? themes[i].id === wanted : themes[i].equipped) return themes[i]
    }
    return themes.length > 0 ? themes[0] : null
  }

  readonly property string previewWallpaper: {
    var staged = root.staged["background"]
    if (staged) return staged
    var t = root.stagedThemeObject
    if (t && t.backgrounds && t.backgrounds.length > 0) return t.backgrounds[0]
    return ""
  }

  readonly property string previewFont: {
    var staged = root.staged["font"]
    if (staged) return staged
    var fonts = (root.inventory && root.inventory.fonts) || []
    for (var i = 0; i < fonts.length; i++) if (fonts[i].equipped) return fonts[i].id
    return "monospace"
  }

  // True when anything is staged that differs from the live system.
  readonly property bool dirty: {
    for (var k in root.staged) if (root.staged[k]) return true
    return false
  }

  function stageCurrent(itemId) {
    var next = {}
    for (var k in root.staged) next[k] = root.staged[k]
    next[root.currentSlot.id] = itemId
    // Changing theme invalidates a background staged from the old theme.
    if (root.currentSlot.id === "theme") next["background"] = ""
    root.staged = next
  }

  function selectedIndexFor(slotId) {
    var items = root.itemsFor(slotId)
    var wanted = root.staged[slotId]
    for (var i = 0; i < items.length; i++) {
      if (wanted ? items[i].id === wanted : items[i].equipped) return i
    }
    return 0
  }

  function moveWithinSlot(delta) {
    var items = root.itemsFor(root.currentSlot.id)
    if (items.length === 0) return
    var i = root.selectedIndexFor(root.currentSlot.id) + delta
    if (i < 0) i = items.length - 1
    if (i >= items.length) i = 0
    root.stageCurrent(items[i].id)
  }

  function moveSlot(delta) {
    var n = root.slotDefs.length
    root.slotIndex = (root.slotIndex + delta + n) % n
  }

  // ---- Lifecycle ------------------------------------------------------
  // Which output to take over. Resolved once per open rather than bound, so
  // the screen doesn't slide out from under the user if focus moves while
  // they're browsing. Null falls back to Quickshell's default placement.
  property var targetScreen: null

  function resolveTargetScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (!name) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === name) return screens[i]
    }
    return null
  }

  function open(payloadJson) {
    root.targetScreen = root.resolveTargetScreen()
    root.opened = true
    root.staged = ({})
    root.slotIndex = 0
    root.statusText = ""
    scanProc.running = true
    statsProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.pantherdev2024.loadout")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadInventory(raw) {
    try {
      root.inventory = JSON.parse(raw)
    } catch (e) {
      root.statusText = "inventory scan failed"
    }
  }

  function loadStats(raw) {
    try {
      root.stats = JSON.parse(raw)
    } catch (e) {
      // A dropped sample is not worth surfacing; the next poll recovers.
    }
  }

  // ---- Applying -------------------------------------------------------
  function applyStaged() {
    if (!root.dirty || root.applying) return
    var cmds = []
    for (var i = 0; i < root.slotDefs.length; i++) {
      var def = root.slotDefs[i]
      var value = root.staged[def.id]
      if (!value) continue
      cmds.push([def.apply, value])
    }
    if (cmds.length === 0) return
    root.applying = true
    root.statusText = "applying…"
    applyQueue.queue = cmds
    applyQueue.step()
  }

  QtObject {
    id: applyQueue
    property var queue: []
    property int index: 0

    function step() {
      if (applyQueue.index >= applyQueue.queue.length) {
        applyQueue.index = 0
        applyQueue.queue = []
        root.applying = false
        root.staged = ({})
        root.statusText = "equipped"
        scanProc.running = true
        return
      }
      applyProc.command = applyQueue.queue[applyQueue.index]
      applyQueue.index += 1
      applyProc.running = true
    }
  }

  Process {
    id: applyProc
    running: false
    onExited: function(code) {
      if (code !== 0) root.statusText = "apply failed: " + applyProc.command.join(" ")
      applyQueue.step()
    }
  }

  Process {
    id: scanProc
    command: [root.pluginDir + "/scan.sh"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.loadInventory(this.text)
    }
  }

  Process {
    id: statsProc
    command: [root.pluginDir + "/stats.sh"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.loadStats(this.text)
    }
  }

  // Only poll while the screen is actually up — this plugin shares the
  // long-running shell process, so an idle poll would be a permanent tax.
  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: if (!statsProc.running) statsProc.running = true
  }

  // ---- Palette of the previewed theme ---------------------------------
  function pc(key, fallback) {
    var t = root.stagedThemeObject
    var v = (t && t.colors) ? t.colors[key] : undefined
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  readonly property color previewBg: pc("background", Color.background)
  readonly property color previewFg: pc("foreground", Color.foreground)
  readonly property color previewAccent: pc("accent", Color.accent)
  readonly property color previewMuted: pc("dark_foreground", Color.muted)
  readonly property string uiFont: Style.font.menuFamily

  // Panels are the background with a little foreground mixed in, rather than a
  // fixed black wash. Themes ship both light and dark modes, and a black wash
  // silently collapses to grey-on-grey under a light theme like Lupine.
  function lift(amount) {
    return Qt.tint(root.previewBg,
      Qt.rgba(root.previewFg.r, root.previewFg.g, root.previewFg.b, amount))
  }
  readonly property color paneBg: lift(0.07)
  readonly property color paneBgFocused: lift(0.13)
  readonly property color paneBorder: lift(0.22)

  // Input is kibibytes: 1G is 1024*1024 KiB, 1T is 1024 times that again.
  function fmtBytes(kb) {
    if (kb >= 1073741824) return (kb / 1073741824).toFixed(1) + "T"
    if (kb >= 1048576) return (kb / 1048576).toFixed(1) + "G"
    if (kb >= 1024) return (kb / 1024).toFixed(0) + "M"
    return kb + "K"
  }

  function fmtRate(bytesPerSec) {
    if (bytesPerSec >= 1048576) return (bytesPerSec / 1048576).toFixed(1) + "M/s"
    if (bytesPerSec >= 1024) return (bytesPerSec / 1024).toFixed(0) + "K/s"
    return bytesPerSec + "B/s"
  }

  // ====================================================================
  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-loadout"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Opaque on purpose. A translucent backdrop is both wrong for the genre
    // (equip screens take over the display) and unreliable here: a partially
    // transparent child on this layer surface has its alpha dropped and paints
    // nothing, while an opaque one composites correctly. Painting it in the
    // previewed theme's own darkest tone means the backdrop re-themes too.
    Rectangle {
      anchors.fill: parent
      color: root.previewBg
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.moveSlot(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.moveSlot(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          root.moveWithinSlot(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
          root.moveWithinSlot(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.applyStaged()
          event.accepted = true
        }
      }

      // Swallow clicks on the content so they don't reach the dismiss layer.
      MouseArea { anchors.fill: content; onClicked: {} }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: Math.min(48, parent.width * 0.04)

        // ---- Header ----------------------------------------------------
        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: 44

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "LOADOUT"
            color: root.previewAccent
            font.family: root.uiFont
            font.pixelSize: 26
            font.bold: true
            font.letterSpacing: 6
          }

          Text {
            anchors.centerIn: parent
            text: root.stagedThemeObject ? root.stagedThemeObject.name.toUpperCase() : ""
            color: root.previewFg
            font.family: root.uiFont
            font.pixelSize: 15
            font.letterSpacing: 3
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText || (root.dirty ? "UNAPPLIED CHANGES" : "SYNCED")
            color: root.dirty ? root.pc("yellow", "#f9e2af") : root.previewMuted
            font.family: root.uiFont
            font.pixelSize: 12
            font.letterSpacing: 2
          }
        }

        // ---- Stats strip (bottom) --------------------------------------
        Rectangle {
          id: statsStrip
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: 108
          color: root.paneBg
          radius: 6
          border.width: 1
          border.color: root.paneBorder

          Row {
            anchors { fill: parent; margins: 18 }
            spacing: 26

            Gauge {
              width: 88; height: parent.height
              label: "CPU"
              value: root.stats.cpu ? root.stats.cpu.percent : -1
              readout: (root.stats.cpu ? root.stats.cpu.percent : 0) + "%"
              sub: root.stats.cpu ? root.stats.cpu.cores + "c · " +
                   (root.stats.cpu.temp >= 0 ? root.stats.cpu.temp + "°" : "—") : ""
              ringColor: root.pc("green", "#a6e3a1")
              trackColor: Qt.rgba(root.previewFg.r, root.previewFg.g, root.previewFg.b, 0.12)
              textColor: root.previewFg
              mutedColor: root.previewMuted
              fontFamily: root.uiFont
            }

            Gauge {
              width: 88; height: parent.height
              label: "GPU"
              value: root.stats.gpu ? root.stats.gpu.percent : -1
              readout: (root.stats.gpu && root.stats.gpu.percent >= 0 ? root.stats.gpu.percent : 0) + "%"
              sub: root.stats.gpu && root.stats.gpu.temp >= 0 ? root.stats.gpu.temp + "°" : ""
              ringColor: root.pc("magenta", "#f5c2e7")
              trackColor: Qt.rgba(root.previewFg.r, root.previewFg.g, root.previewFg.b, 0.12)
              textColor: root.previewFg
              mutedColor: root.previewMuted
              fontFamily: root.uiFont
            }

            Column {
              width: 200
              anchors.verticalCenter: parent.verticalCenter
              spacing: 12

              Meter {
                width: parent.width; height: 30
                label: "MEMORY"
                value: root.stats.memory ? root.stats.memory.percent : 0
                readout: root.stats.memory
                  ? root.fmtBytes(root.stats.memory.usedKb) + " / " + root.fmtBytes(root.stats.memory.totalKb)
                  : "—"
                fillColor: root.pc("blue", "#89b4fa")
                trackColor: Qt.rgba(root.previewFg.r, root.previewFg.g, root.previewFg.b, 0.12)
                textColor: root.previewFg
                mutedColor: root.previewMuted
                fontFamily: root.uiFont
              }

              Meter {
                width: parent.width; height: 30
                label: "DISK"
                value: root.stats.disk ? root.stats.disk.percent : 0
                readout: root.stats.disk
                  ? root.fmtBytes(root.stats.disk.usedKb) + " / " + root.fmtBytes(root.stats.disk.totalKb)
                  : "—"
                fillColor: root.pc("cyan", "#94e2d5")
                trackColor: Qt.rgba(root.previewFg.r, root.previewFg.g, root.previewFg.b, 0.12)
                textColor: root.previewFg
                mutedColor: root.previewMuted
                fontFamily: root.uiFont
              }
            }

            Column {
              width: 150
              anchors.verticalCenter: parent.verticalCenter
              spacing: 12

              Meter {
                width: parent.width; height: 30
                label: "SWAP"
                value: root.stats.swap ? root.stats.swap.percent : 0
                readout: root.stats.swap ? root.stats.swap.percent + "%" : "—"
                fillColor: root.pc("yellow", "#f9e2af")
                trackColor: Qt.rgba(root.previewFg.r, root.previewFg.g, root.previewFg.b, 0.12)
                textColor: root.previewFg
                mutedColor: root.previewMuted
                fontFamily: root.uiFont
              }

              Item {
                width: parent.width; height: 30

                Text {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  text: "NETWORK"
                  color: root.previewMuted
                  font.family: root.uiFont
                  font.pixelSize: 9
                  font.letterSpacing: 1
                }

                Text {
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  text: root.stats.network
                    ? "↓ " + root.fmtRate(root.stats.network.rxBytesPerSec) +
                      "   ↑ " + root.fmtRate(root.stats.network.txBytesPerSec)
                    : "—"
                  color: root.previewFg
                  font.family: root.uiFont
                  font.pixelSize: 11
                  font.bold: true
                }
              }
            }
          }
        }

        // ---- Slot columns + preview ------------------------------------
        Item {
          anchors {
            top: header.bottom; topMargin: 16
            bottom: statsStrip.top; bottomMargin: 16
            left: parent.left; right: parent.right
          }

          readonly property real columnWidth: Math.max(230, width * 0.22)

          Column {
            id: leftColumn
            width: parent.columnWidth
            anchors { left: parent.left; top: parent.top }
            spacing: 14

            Repeater {
              model: root.slotDefs.filter(function(d) { return d.side === "left" })
              delegate: SlotPanel {
                required property var modelData
                width: leftColumn.width
                slotDef: modelData
                host: root
                alignRight: false
              }
            }
          }

          Column {
            id: rightColumn
            width: parent.columnWidth
            anchors { right: parent.right; top: parent.top }
            spacing: 14

            Repeater {
              model: root.slotDefs.filter(function(d) { return d.side === "right" })
              delegate: SlotPanel {
                required property var modelData
                width: rightColumn.width
                slotDef: modelData
                host: root
                alignRight: true
              }
            }
          }

          // The centrepiece: a live mock of the desktop as staged.
          Item {
            anchors {
              left: leftColumn.right; leftMargin: 28
              right: rightColumn.left; rightMargin: 28
              top: parent.top; bottom: parent.bottom
            }

            MiniDesktop {
              id: preview
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height * (16 / 9))
              height: width * (9 / 16)

              colors: root.stagedThemeObject ? root.stagedThemeObject.colors : ({})
              wallpaper: root.previewWallpaper
              fontFamily: root.previewFont
              themeName: root.stagedThemeObject ? root.stagedThemeObject.name : ""
            }

            Text {
              anchors { horizontalCenter: preview.horizontalCenter; top: preview.bottom; topMargin: 18 }
              text: root.dirty
                ? "ENTER  apply for real       ESC  discard"
                : "↑↓ slot     ←→ browse     ENTER apply     ESC close"
              color: root.previewMuted
              font.family: root.uiFont
              font.pixelSize: 11
              font.letterSpacing: 2
            }
          }
        }
      }
    }
  }
}
