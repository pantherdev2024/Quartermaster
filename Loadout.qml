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
// Equipment is grouped into categories, picked from a row of glyph pills
// across the top of the left column. Below the pills, the active category's
// slots stack down the left; the right column shows a miniature mock desktop
// painted in whatever is currently staged, plus a detail card for the item
// under the cursor. The bottom strip is the character sheet: real metrics.
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

  // ---- Categories and slots ------------------------------------------
  // OUTFIT is what the desktop wears, CHASSIS is the frame it hangs on, and
  // CYBERWARE is the tooling wired into it. A slot's `apply` is the command
  // prefix; the staged item id is appended as the final argument. Adding a
  // slot means one entry here and a matching branch in itemsFor().
  readonly property var categories: [
    { id: "outfit",    label: "OUTFIT",    icon: "󰩻" },
    { id: "chassis",   label: "CHASSIS",   icon: "󰕮" },
    { id: "cyberware", label: "CYBERWARE", icon: "󰘚" }
  ]

  readonly property var slotDefs: [
    { id: "theme",          cat: "outfit",    label: "THEME",        icon: "󰏘", apply: ["omarchy-theme-set"] },
    { id: "background",     cat: "outfit",    label: "BACKGROUND",   icon: "󰸉", apply: ["omarchy-theme-bg-set"] },
    { id: "font",           cat: "outfit",    label: "FONT",         icon: "󰛖", apply: ["omarchy-font-set"] },
    { id: "barPosition",    cat: "chassis",   label: "BAR POSITION", icon: "󰍹", apply: ["omarchy-bar", "position"] },
    { id: "barTransparent", cat: "chassis",   label: "BAR SURFACE",  icon: "󰗌", apply: ["omarchy-bar", "transparent"] },
    { id: "textSize",       cat: "chassis",   label: "TEXT SIZE",    icon: "󰉡", apply: ["omarchy-display-text-size"] },
    { id: "terminal",       cat: "cyberware", label: "TERMINAL",     icon: "󰆍", apply: ["omarchy-default-terminal"] },
    { id: "editor",         cat: "cyberware", label: "EDITOR",       icon: "󰅩", apply: ["omarchy-default-editor"] },
    { id: "browser",        cat: "cyberware", label: "BROWSER",      icon: "󰖟", apply: ["omarchy-default-browser"] },
    { id: "agent",          cat: "cyberware", label: "AGENT",        icon: "󰚩", apply: [pluginDir + "/agent-set.sh"] }
  ]

  // Staged selection per slot id. Empty means "unchanged from what's live".
  property var staged: ({})

  // The cursor is a single index into slotDefs; the active category is
  // whatever category that slot belongs to, so there is no second piece of
  // state to keep in sync.
  property int slotIndex: 0
  readonly property var currentSlot: slotDefs[Math.max(0, Math.min(slotDefs.length - 1, slotIndex))]
  readonly property string currentCategory: currentSlot.cat
  readonly property int currentCategoryIndex: {
    for (var i = 0; i < categories.length; i++)
      if (categories[i].id === currentCategory) return i
    return 0
  }
  readonly property var visibleSlots: slotDefs.filter(function(d) { return d.cat === root.currentCategory })

  function itemsFor(slotId) {
    var inv = root.inventory
    if (!inv) return []
    if (slotId === "theme") return inv.themes || []
    if (slotId === "font") return inv.fonts || []
    if (slotId === "terminal") return inv.terminals || []
    if (slotId === "editor") return inv.editors || []
    if (slotId === "browser") return inv.browsers || []
    if (slotId === "agent") return inv.agents || []
    if (slotId === "barPosition") return inv.barPositions || []
    if (slotId === "barTransparent") return inv.barTransparency || []
    if (slotId === "textSize") return inv.textSizes || []
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

  // Selected item object for a slot (staged if any, else equipped, else first).
  function selectedItem(slotId) {
    var items = root.itemsFor(slotId)
    var i = root.selectedIndexFor(slotId)
    return i < items.length ? items[i] : null
  }

  function selectedId(slotId, fallback) {
    var it = root.selectedItem(slotId)
    return it ? it.id : fallback
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

  // The theme that is actually live, used to colour the chrome's gauges.
  readonly property var liveThemeObject: {
    var themes = (root.inventory && root.inventory.themes) || []
    for (var i = 0; i < themes.length; i++) if (themes[i].equipped) return themes[i]
    return null
  }

  readonly property string previewWallpaper: {
    var staged = root.staged["background"]
    if (staged) return staged
    var t = root.stagedThemeObject
    if (t && t.backgrounds && t.backgrounds.length > 0) return t.backgrounds[0]
    return ""
  }

  readonly property string previewFont: root.selectedId("font", "monospace")
  readonly property string previewBarPosition: root.selectedId("barPosition", "top")
  readonly property bool previewBarTransparent: root.selectedId("barTransparent", "false") === "true"
  readonly property real previewFontScale: Number(root.selectedId("textSize", "12")) / 12
  readonly property string previewTerminal: root.selectedId("terminal", "")

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

  // Up/down stays inside the active category and wraps.
  function moveSlot(delta) {
    var ids = []
    for (var i = 0; i < root.slotDefs.length; i++)
      if (root.slotDefs[i].cat === root.currentCategory) ids.push(i)
    var pos = ids.indexOf(root.slotIndex)
    if (pos < 0) pos = 0
    root.slotIndex = ids[(pos + delta + ids.length) % ids.length]
  }

  function selectCategory(catId) {
    for (var i = 0; i < root.slotDefs.length; i++) {
      if (root.slotDefs[i].cat === catId) { root.slotIndex = i; return }
    }
  }

  function moveCategory(delta) {
    var n = root.categories.length
    root.selectCategory(root.categories[(root.currentCategoryIndex + delta + n) % n].id)
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
      cmds.push(def.apply.concat([value]))
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

  // ---- Chrome palette --------------------------------------------------
  // The screen's own chrome follows the live Omarchy theme through the shared
  // Color/Style singletons, exactly like the stock menu and clipboard
  // overlays. Only the MiniDesktop repaints in the *staged* theme — that is
  // the preview, and the chrome around it should hold still while you browse.
  readonly property color fg: Color.menu.text
  readonly property color muted: Color.muted
  readonly property color accent: Color.accent
  readonly property color warn: Color.urgent
  readonly property string uiFont: Style.font.menuFamily

  // Gauge hues come from the live theme's full palette (the shared Color
  // singleton only carries the foundational four), falling back to accent.
  function lc(key, fallback) {
    var t = root.liveThemeObject
    var v = (t && t.colors) ? t.colors[key] : undefined
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }
  readonly property color good: lc("green", root.accent)

  // Opaque on purpose. A partially transparent child on this layer surface
  // has its alpha dropped and paints nothing, so the backdrop takes the
  // menu surface colour with its alpha companion forced to 1.
  readonly property color backdrop: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)

  // Panels are the background with a little foreground mixed in, rather than a
  // fixed black wash. Themes ship both light and dark modes, and a black wash
  // silently collapses to grey-on-grey under a light theme like Lupine. The
  // mix amounts are the theme's own control fill alphas, so a theme that
  // tunes [controls] in shell.toml tunes these too.
  function lift(amount) {
    return Qt.tint(root.backdrop, Qt.rgba(root.fg.r, root.fg.g, root.fg.b, amount))
  }
  readonly property color paneBg: lift(Style.normalFillAlpha)
  readonly property color paneBgFocused: lift(Style.hoverFillAlpha)
  readonly property color trackColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

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

    Rectangle {
      anchors.fill: parent
      color: root.backdrop
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
        var k = event.key
        var shift = event.modifiers & Qt.ShiftModifier
        if (k === Qt.Key_Escape) {
          root.dismiss()
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
          root.moveSlot(-1)
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
          root.moveSlot(1)
        } else if (k === Qt.Key_Left || k === Qt.Key_H) {
          root.moveWithinSlot(-1)
        } else if (k === Qt.Key_Right || k === Qt.Key_L) {
          root.moveWithinSlot(1)
        } else if (k === Qt.Key_Tab || k === Qt.Key_E || k === Qt.Key_BracketRight) {
          root.moveCategory(1)
        } else if (k === Qt.Key_Backtab || k === Qt.Key_Q || k === Qt.Key_BracketLeft) {
          root.moveCategory(-1)
        } else if (k >= Qt.Key_1 && k < Qt.Key_1 + root.categories.length) {
          root.selectCategory(root.categories[k - Qt.Key_1].id)
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
          root.applyStaged()
        } else {
          return
        }
        event.accepted = true
      }

      // Swallow clicks on the content so they don't reach the dismiss layer.
      MouseArea { anchors.fill: content; onClicked: {} }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: Math.min(Style.space(48), parent.width * 0.04)

        // ---- Header ----------------------------------------------------
        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: Style.space(44)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "LOADOUT"
            color: root.accent
            font.family: root.uiFont
            font.pixelSize: Style.font.display
            font.bold: true
            font.letterSpacing: 6
          }

          Text {
            anchors.centerIn: parent
            text: root.stagedThemeObject ? root.stagedThemeObject.name.toUpperCase() : ""
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.title
            font.letterSpacing: 3
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText || (root.dirty ? "UNAPPLIED CHANGES" : "SYNCED")
            color: root.dirty ? root.warn : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            font.letterSpacing: 2
          }
        }

        // ---- Stats strip (bottom) --------------------------------------
        BorderSurface {
          id: statsStrip
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: Style.space(108)
          color: root.paneBg
          radius: Style.cornerRadius
          borderSpec: Border.controlSpec("normal", root.fg, root.accent)

          Row {
            anchors { fill: parent; margins: Style.space(18) }
            spacing: Style.space(26)

            Gauge {
              width: Style.space(88); height: parent.height
              label: "CPU"
              value: root.stats.cpu ? root.stats.cpu.percent : -1
              readout: (root.stats.cpu ? root.stats.cpu.percent : 0) + "%"
              sub: root.stats.cpu ? root.stats.cpu.cores + "c · " +
                   (root.stats.cpu.temp >= 0 ? root.stats.cpu.temp + "°" : "—") : ""
              ringColor: root.lc("green", root.accent)
              trackColor: root.trackColor
              textColor: root.fg
              mutedColor: root.muted
              fontFamily: root.uiFont
            }

            Gauge {
              width: Style.space(88); height: parent.height
              label: "GPU"
              value: root.stats.gpu ? root.stats.gpu.percent : -1
              readout: (root.stats.gpu && root.stats.gpu.percent >= 0 ? root.stats.gpu.percent : 0) + "%"
              sub: root.stats.gpu && root.stats.gpu.temp >= 0 ? root.stats.gpu.temp + "°" : ""
              ringColor: root.lc("magenta", root.accent)
              trackColor: root.trackColor
              textColor: root.fg
              mutedColor: root.muted
              fontFamily: root.uiFont
            }

            Column {
              width: Style.space(200)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)

              Meter {
                width: parent.width; height: Style.space(30)
                label: "MEMORY"
                value: root.stats.memory ? root.stats.memory.percent : 0
                readout: root.stats.memory
                  ? root.fmtBytes(root.stats.memory.usedKb) + " / " + root.fmtBytes(root.stats.memory.totalKb)
                  : "—"
                fillColor: root.lc("blue", root.accent)
                trackColor: root.trackColor
                textColor: root.fg
                mutedColor: root.muted
                fontFamily: root.uiFont
              }

              Meter {
                width: parent.width; height: Style.space(30)
                label: "DISK"
                value: root.stats.disk ? root.stats.disk.percent : 0
                readout: root.stats.disk
                  ? root.fmtBytes(root.stats.disk.usedKb) + " / " + root.fmtBytes(root.stats.disk.totalKb)
                  : "—"
                fillColor: root.lc("cyan", root.accent)
                trackColor: root.trackColor
                textColor: root.fg
                mutedColor: root.muted
                fontFamily: root.uiFont
              }
            }

            Column {
              width: Style.space(150)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)

              Meter {
                width: parent.width; height: Style.space(30)
                label: "SWAP"
                value: root.stats.swap ? root.stats.swap.percent : 0
                readout: root.stats.swap ? root.stats.swap.percent + "%" : "—"
                fillColor: root.lc("yellow", root.accent)
                trackColor: root.trackColor
                textColor: root.fg
                mutedColor: root.muted
                fontFamily: root.uiFont
              }

              Item {
                width: parent.width; height: Style.space(30)

                Text {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  text: "NETWORK"
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }

                Text {
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  text: root.stats.network
                    ? "↓ " + root.fmtRate(root.stats.network.rxBytesPerSec) +
                      "   ↑ " + root.fmtRate(root.stats.network.txBytesPerSec)
                    : "—"
                  color: root.fg
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }
          }
        }

        // ---- Body: slots left, preview right ---------------------------
        Item {
          id: body
          anchors {
            top: header.bottom; topMargin: Style.space(16)
            bottom: statsStrip.top; bottomMargin: Style.space(16)
            left: parent.left; right: parent.right
          }

          readonly property real gutter: Style.space(32)
          readonly property real leftWidth: Math.max(Style.space(420), width * 0.42)

          // -- Left column: category pills, then the slot list -----------
          Item {
            id: leftColumn
            width: body.leftWidth
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }

            Row {
              id: tabs
              anchors { left: parent.left; top: parent.top }
              spacing: Style.spacing.md

              Repeater {
                model: root.categories
                delegate: Button {
                  required property var modelData
                  required property int index
                  readonly property bool isActive: modelData.id === root.currentCategory
                  iconText: modelData.icon
                  iconSize: Style.font.iconLarge
                  // Only the active pill spells out its name, like the tab
                  // strip in the reference; the rest stay as glyphs.
                  text: isActive ? modelData.label : ""
                  selected: isActive
                  bordered: true
                  foreground: root.fg
                  accent: root.accent
                  fontFamily: root.uiFont
                  fontSize: Style.font.body
                  horizontalPadding: isActive ? Style.spacing.controlPaddingX + Style.space(4) : Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                  tooltipText: isActive ? "" : modelData.label + "  [" + (index + 1) + "]"
                  onClicked: root.selectCategory(modelData.id)
                }
              }
            }

            Text {
              anchors { left: tabs.right; leftMargin: Style.space(14); verticalCenter: tabs.verticalCenter }
              text: (root.currentCategoryIndex + 1) + " / " + root.categories.length
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            // Slots scroll if a small screen can't fit the whole category.
            Flickable {
              id: slotScroll
              anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom }
              anchors.topMargin: Style.space(18)
              contentWidth: width
              contentHeight: slotList.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: slotList
                width: slotScroll.width
                spacing: Style.space(14)

                Repeater {
                  model: root.visibleSlots
                  delegate: SlotPanel {
                    required property var modelData
                    width: slotList.width
                    slotDef: modelData
                    host: root
                  }
                }
              }
            }
          }

          // -- Right column: the mock desktop, the item card, the hints --
          Item {
            id: rightColumn
            anchors {
              left: leftColumn.right; leftMargin: body.gutter
              right: parent.right; top: parent.top; bottom: parent.bottom
            }

            MiniDesktop {
              id: preview
              anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
              width: Math.min(parent.width, (parent.height * 0.68) * (16 / 9))
              height: width * (9 / 16)

              colors: root.stagedThemeObject ? root.stagedThemeObject.colors : ({})
              wallpaper: root.previewWallpaper
              fontFamily: root.previewFont
              themeName: root.stagedThemeObject ? root.stagedThemeObject.name : ""
              terminalName: root.previewTerminal
              barPosition: root.previewBarPosition
              barTransparent: root.previewBarTransparent
              fontScale: root.previewFontScale
            }

            // Detail card for the item under the cursor — the reference's
            // description panel, kept to what we can honestly say about it.
            BorderSurface {
              id: detail
              anchors {
                top: preview.bottom; topMargin: Style.space(18)
                left: preview.left; right: preview.right
              }
              height: detailColumn.implicitHeight + Style.space(28)
              color: root.paneBg
              radius: Style.cornerRadius
              borderSpec: Border.controlSpec("normal", root.fg, root.accent)

              readonly property var item: root.selectedItem(root.currentSlot.id)
              readonly property bool itemStaged: root.staged[root.currentSlot.id] ? true : false

              Column {
                id: detailColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(14) }
                spacing: Style.space(6)

                Row {
                  spacing: Style.space(10)
                  Text {
                    text: root.currentSlot.icon
                    color: root.accent
                    font.family: root.uiFont
                    font.pixelSize: Style.font.iconLarge
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.currentSlot.label
                    color: root.muted
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    visible: detail.item ? true : false
                    text: detail.itemStaged ? "STAGED" : (detail.item && detail.item.equipped ? "EQUIPPED" : "")
                    color: detail.itemStaged ? root.warn : root.good
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  width: parent.width
                  text: detail.item ? detail.item.name : "Nothing available"
                  color: root.fg
                  font.family: root.uiFont
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: {
                    var it = detail.item
                    if (!it) return ""
                    if (it.path) return it.path
                    return root.currentSlot.apply.join(" ") + " " + it.id
                  }
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideMiddle
                }
              }
            }

            Text {
              anchors { horizontalCenter: preview.horizontalCenter; bottom: parent.bottom }
              text: root.dirty
                ? "ENTER  apply for real       ESC  discard"
                : "TAB category     ↑↓ slot     ←→ browse     ENTER apply     ESC close"
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 2
            }
          }
        }
      }
    }
  }
}
