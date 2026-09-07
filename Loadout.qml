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
    { id: "agent",          cat: "cyberware", label: "AGENT",        icon: "󰚩", apply: [pluginDir + "/agent-set.sh"] },
    // Saved loadouts: present in every category as the last slot. No apply
    // command of its own — picking one stages every slot it recorded.
    { id: "loadouts",       cat: "*",         label: "SAVED LOADOUTS", icon: "󰆓", apply: null, wide: true }
  ]
  readonly property int loadoutsSlotIndex: slotDefs.length - 1
  readonly property bool onLoadouts: currentSlot.id === "loadouts"

  // Staged selection per slot id. Empty means "unchanged from what's live".
  property var staged: ({})

  // The cursor is a single index into slotDefs; the active category is
  // whatever category that slot belongs to, so there is no second piece of
  // state to keep in sync.
  property int slotIndex: 0
  readonly property var currentSlot: slotDefs[Math.max(0, Math.min(slotDefs.length - 1, slotIndex))]
  // The dock belongs to no category, so while the cursor sits on it the tabs
  // keep showing whichever category the cursor came from.
  property string pinnedCategory: "outfit"
  onSlotIndexChanged: if (currentSlot.cat !== "*") pinnedCategory = currentSlot.cat
  readonly property string currentCategory: currentSlot.cat === "*" ? pinnedCategory : currentSlot.cat
  readonly property int currentCategoryIndex: {
    for (var i = 0; i < categories.length; i++)
      if (categories[i].id === currentCategory) return i
    return 0
  }
  readonly property var visibleSlots: slotDefs.filter(function(d) { return d.cat === root.currentCategory })

  // The equipped item id for a slot, ignoring anything staged.
  function equippedId(slotId) {
    var items = root.itemsFor(slotId)
    for (var i = 0; i < items.length; i++) if (items[i].equipped) return items[i].id
    return ""
  }

  // A saved loadout is "equipped" when every slot it recorded is live.
  function loadoutIsLive(slots) {
    for (var k in slots) {
      if (k === "background") {
        // Compare by file name for the same reason itemsFor does.
        var live = String(root.inventory.currentBackground || "").split("/").pop()
        if (String(slots[k]).split("/").pop() !== live) return false
      } else if (root.equippedId(k) !== slots[k]) {
        return false
      }
    }
    return true
  }

  function loadoutItems() {
    var inv = root.inventory
    var saved = (inv && inv.loadouts) || []
    var themes = (inv && inv.themes) || []
    var out = saved.map(function(l) {
      var theme = null
      for (var i = 0; i < themes.length; i++) if (themes[i].id === l.slots.theme) theme = themes[i]
      var parts = []
      if (theme) parts.push(theme.name)
      if (l.slots.terminal) parts.push(l.slots.terminal)
      if (l.slots.barPosition) parts.push("bar " + l.slots.barPosition)
      return {
        id: l.id, name: l.name, slots: l.slots, savedAt: l.savedAt,
        preview: theme && theme.preview ? theme.preview : "",
        meta: parts.join(" · "),
        equipped: root.loadoutIsLive(l.slots)
      }
    })
    out.push({ id: "__new", name: "NEW LOADOUT", meta: "save current fitting", isNew: true })
    return out
  }

  function itemsFor(slotId) {
    var inv = root.inventory
    if (!inv) return []
    if (slotId === "loadouts") return root.loadoutItems()
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
      // The live background resolves through ~/.local/state/omarchy/current/
      // theme, a different path from the theme's own folder, so match on
      // the file name rather than the full path.
      var live = String(inv.currentBackground || "").split("/").pop()
      return t.backgrounds.map(function(p) {
        var file = p.split("/").pop()
        return { id: p, name: file.replace(/\.[^.]+$/, ""), path: p, equipped: t.equipped && file === live }
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

  // True when anything is staged that differs from the live system. The
  // loadouts key is cursor state, not a change.
  readonly property bool dirty: {
    for (var k in root.staged) if (k !== "loadouts" && root.staged[k]) return true
    return false
  }

  function stageCurrent(itemId) {
    if (root.currentSlot.id === "loadouts") { root.stageLoadout(itemId); return }
    var next = {}
    for (var k in root.staged) next[k] = root.staged[k]
    next[root.currentSlot.id] = itemId
    // Changing theme invalidates a background staged from the old theme.
    if (root.currentSlot.id === "theme") next["background"] = ""
    // A hand-picked change means the fitting is no longer exactly a saved one.
    next["loadouts"] = ""
    root.staged = next
  }

  // Stage a saved loadout: every recorded slot that differs from what is
  // live. Moving onto the NEW cell stages nothing and keeps what was staged.
  function stageLoadout(loadoutId) {
    var items = root.itemsFor("loadouts")
    var item = null
    for (var i = 0; i < items.length; i++) if (items[i].id === loadoutId) item = items[i]
    var next = {}
    if (item && item.isNew) {
      for (var k in root.staged) next[k] = root.staged[k]
      next["loadouts"] = loadoutId
      root.staged = next
      return
    }
    if (!item) return
    for (var slot in item.slots) {
      var wanted = item.slots[slot]
      var live = slot === "background"
        ? String(root.inventory.currentBackground || "").split("/").pop()
        : root.equippedId(slot)
      var current = slot === "background" ? String(wanted).split("/").pop() : wanted
      next[slot] = current === live ? "" : wanted
    }
    next["loadouts"] = loadoutId
    root.staged = next
  }

  // The fitting as it would be after ENTER: staged where staged, live otherwise.
  function currentFitting() {
    var slots = {}
    for (var i = 0; i < root.slotDefs.length; i++) {
      var def = root.slotDefs[i]
      if (!def.apply) continue
      var id = root.selectedId(def.id, "")
      if (id) slots[def.id] = id
    }
    return slots
  }

  // ---- Saving and deleting loadouts ------------------------------------
  property bool promptOpen: false
  property string pendingLoadoutId: ""

  function openSavePrompt() {
    if (root.applying) return
    root.promptOpen = true
  }

  function saveLoadout(name) {
    name = String(name || "").replace(/^\s+|\s+$/g, "")
    if (!name) return
    saveProc.command = [root.pluginDir + "/loadouts.sh", "save", name, JSON.stringify(root.currentFitting())]
    saveProc.running = true
    root.promptOpen = false
    root.statusText = "saving…"
  }

  function deleteCurrentLoadout() {
    if (!root.onLoadouts) return
    var item = root.selectedItem("loadouts")
    if (!item || item.isNew) return
    deleteProc.command = [root.pluginDir + "/loadouts.sh", "delete", item.id]
    deleteProc.running = true
    var next = {}
    for (var k in root.staged) next[k] = root.staged[k]
    next["loadouts"] = ""
    root.staged = next
    root.statusText = "deleted " + item.name
  }

  // Name of the saved loadout the character currently represents, if any.
  readonly property string activeLoadoutName: {
    var items = root.itemsFor("loadouts")
    var stagedId = root.staged["loadouts"]
    for (var i = 0; i < items.length; i++) {
      if (items[i].isNew) continue
      if (stagedId ? items[i].id === stagedId : items[i].equipped) return items[i].name
    }
    return ""
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
      if (root.slotDefs[i].cat === root.currentCategory || root.slotDefs[i].cat === "*") ids.push(i)
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

  function screenNamed(name) {
    if (!name) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === name) return screens[i]
    }
    return null
  }

  // A summon payload may name the output ({"screen": "eDP-1"}); otherwise
  // the screen follows Hyprland's focused monitor.
  function resolveTargetScreen(payloadJson) {
    var wanted = ""
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && typeof payload.screen === "string") wanted = payload.screen
    } catch (e) {
      // Not JSON, or not ours: fall through to the focused monitor.
    }
    var explicit = root.screenNamed(wanted)
    if (explicit) return explicit
    var monitor = Hyprland.focusedMonitor
    return root.screenNamed(monitor ? String(monitor.name || "") : "")
  }

  function open(payloadJson) {
    root.targetScreen = root.resolveTargetScreen(payloadJson)
    root.opened = true
    root.staged = ({})
    root.slotIndex = 0
    root.statusText = ""
    scanProc.running = true
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

  // ---- Applying -------------------------------------------------------
  function applyStaged() {
    if (!root.dirty || root.applying) return
    var cmds = []
    for (var i = 0; i < root.slotDefs.length; i++) {
      var def = root.slotDefs[i]
      var value = root.staged[def.id]
      if (!def.apply || !value) continue
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
    id: saveProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.pendingLoadoutId = String(this.text || "").trim()
    }
    onExited: function(code) {
      if (code !== 0) { root.statusText = "save failed"; return }
      root.statusText = "loadout saved"
      // Land the cursor on the new card once the rescan brings it in.
      var next = {}
      for (var k in root.staged) next[k] = root.staged[k]
      next["loadouts"] = root.pendingLoadoutId
      root.staged = next
      root.slotIndex = root.loadoutsSlotIndex
      scanProc.running = true
    }
  }

  Process {
    id: deleteProc
    running: false
    onExited: scanProc.running = true
  }

  Process {
    id: scanProc
    command: [root.pluginDir + "/scan.sh"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.loadInventory(this.text)
    }
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

  // The "equipped" green comes from the live theme's full palette (the shared
  // Color singleton only carries the foundational four), falling back to accent.
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
  readonly property color line: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)

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

    // Faint scanlines. Painted once per size; children over it are opaque
    // or nested, so this is safe on the layer surface.
    Canvas {
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
        for (var y = 0; y < height; y += 4) ctx.fillRect(0, y, width, 1)
      }
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
        if (root.promptOpen) return   // the name prompt owns the keyboard
        var k = event.key
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
          var sel = root.onLoadouts ? root.selectedItem("loadouts") : null
          if (sel && sel.isNew) root.openSavePrompt()
          else root.applyStaged()
        } else if (k === Qt.Key_S) {
          root.openSavePrompt()
        } else if (k === Qt.Key_X || k === Qt.Key_Delete) {
          root.deleteCurrentLoadout()
        } else {
          return
        }
        event.accepted = true
      }

      // Swallow clicks on the content so they don't reach the dismiss layer.
      MouseArea { anchors.fill: content; onClicked: {} }

      // ---- Save prompt -------------------------------------------------
      Item {
        id: prompt
        anchors.fill: parent
        visible: root.promptOpen
        z: 10
        onVisibleChanged: {
          if (visible) { promptInput.text = ""; promptInput.forceActiveFocus() }
          else keyCatcher.forceActiveFocus()
        }

        // Scrim: opaque-safe because it is a nested child, but keep it
        // dark enough that the screen behind reads as parked.
        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(root.backdrop.r, root.backdrop.g, root.backdrop.b, 0.72)
          MouseArea { anchors.fill: parent; onClicked: root.promptOpen = false }
        }

        TechFrame {
          anchors.centerIn: parent
          width: Style.space(460)
          height: promptColumn.implicitHeight + Style.space(48)
          chamfer: Style.space(14)
          fill: root.paneBgFocused
          stroke: root.accent
          brackets: true
          bracketColor: root.accent
          bracketLength: Style.space(18)
          bracketInset: 5
          edge: "left"
          edgeColor: root.accent
          edgeWidth: Style.space(4)

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: promptColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(24) }
            anchors.leftMargin: Style.space(30)
            spacing: Style.space(12)

            Text {
              text: "SAVE LOADOUT"
              color: root.accent
              font.family: root.uiFont
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 4
            }

            Text {
              width: parent.width
              text: "Records the fitting as it stands — staged choices included — so it can be equipped again in one move."
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            TechFrame {
              width: parent.width
              height: Style.space(38)
              chamfer: Style.space(8)
              fill: root.backdrop
              stroke: promptInput.activeFocus ? root.accent : root.line

              TextInput {
                id: promptInput
                anchors { fill: parent; leftMargin: Style.space(14); rightMargin: Style.space(14) }
                verticalAlignment: TextInput.AlignVCenter
                color: root.fg
                selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                selectedTextColor: root.fg
                font.family: root.uiFont
                font.pixelSize: Style.font.subtitle
                clip: true
                maximumLength: 40
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.promptOpen = false; event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.saveLoadout(promptInput.text); event.accepted = true }
                }

                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  visible: promptInput.text.length === 0
                  text: "loadout name"
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.subtitle
                }
              }
            }

            Text {
              text: "ENTER  save       ESC  cancel"
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 2
            }
          }
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: Math.min(Style.space(48), parent.width * 0.04)

        // ---- Header ----------------------------------------------------
        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: Style.space(44)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Text {
              text: "LOADOUT"
              color: root.accent
              font.family: root.uiFont
              font.pixelSize: Style.font.display
              font.bold: true
              font.letterSpacing: 7
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              width: 1; height: Style.space(22)
              color: root.line
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "EQUIP SYSTEM // " + root.categories[root.currentCategoryIndex].label
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 2.5
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          TechFrame {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: statusLabel.implicitWidth + Style.space(28)
            height: Style.space(26)
            chamfer: Style.space(8)
            fill: root.paneBg
            stroke: root.dirty ? root.warn : root.line
            edge: "left"
            edgeColor: root.dirty ? root.warn : root.good
            edgeWidth: Style.space(3)

            Text {
              id: statusLabel
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: Style.space(2)
              text: (root.statusText || (root.dirty ? "UNAPPLIED CHANGES" : "SYNCED")).toUpperCase()
              color: root.dirty ? root.warn : root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 2
            }
          }
        }

        // ---- Body: slots left, character right -------------------------
        Item {
          id: body
          anchors {
            top: header.bottom; topMargin: Style.space(22)
            bottom: parent.bottom
            left: parent.left; right: parent.right
          }

          readonly property real gutter: Style.space(40)
          readonly property real leftWidth: Math.max(Style.space(420), width * 0.40)

          // -- Left column: category tabs, then the slot list -----------
          Item {
            id: leftColumn
            width: body.leftWidth
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }

            Row {
              id: tabs
              anchors { left: parent.left; top: parent.top }
              spacing: Style.space(6)

              Repeater {
                model: root.categories
                delegate: TechFrame {
                  id: tab
                  required property var modelData
                  required property int index
                  readonly property bool isActive: modelData.id === root.currentCategory
                  readonly property bool hot: isActive || tabMouse.containsMouse

                  width: tabRow.implicitWidth + Style.space(28)
                  height: Style.space(36)
                  chamfer: Style.space(9)
                  cuts: ["tl", "br"]
                  fill: isActive ? root.paneBgFocused : root.paneBg
                  stroke: isActive ? root.accent : (tabMouse.containsMouse ? root.fg : root.line)
                  strokeWidth: 1
                  edge: "bottom"
                  edgeColor: root.accent
                  edgeWidth: isActive ? Style.space(3) : 0

                  Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: Style.space(8)

                    Text {
                      text: tab.modelData.icon
                      color: tab.isActive ? root.accent : root.fg
                      font.family: root.uiFont
                      font.pixelSize: Style.font.iconLarge
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      visible: tab.isActive
                      text: tab.modelData.label
                      color: root.accent
                      font.family: root.uiFont
                      font.pixelSize: Style.font.body
                      font.bold: true
                      font.letterSpacing: 2.5
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectCategory(tab.modelData.id)
                  }
                }
              }
            }

            Text {
              anchors { left: tabs.right; leftMargin: Style.space(14); verticalCenter: tabs.verticalCenter }
              text: String(root.currentCategoryIndex + 1).padStart(2, "0") + " / " + String(root.categories.length).padStart(2, "0")
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.5
            }

            // The dock: saved loadouts, pinned to the foot of the column.
            SlotPanel {
              id: dock
              anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
              slotDef: root.slotDefs[root.loadoutsSlotIndex]
              host: root
            }

            Rectangle {
              anchors { left: parent.left; right: parent.right; bottom: dock.top; bottomMargin: Style.space(22) }
              height: 1
              color: root.line
            }

            // Slots scroll if a small screen can't fit the whole category.
            Flickable {
              id: slotScroll
              anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: dock.top }
              anchors.topMargin: Style.space(22)
              anchors.bottomMargin: Style.space(46)
              contentWidth: width
              contentHeight: slotList.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: slotList
                width: slotScroll.width
                spacing: Style.space(24)

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

          // -- Right column: the character and its fittings --------------
          CharacterView {
            id: character
            anchors {
              left: leftColumn.right; leftMargin: body.gutter
              right: parent.right; top: parent.top; bottom: hints.top; bottomMargin: Style.space(12)
            }
            host: root
          }

          Text {
            id: hints
            anchors { horizontalCenter: character.horizontalCenter; bottom: parent.bottom }
            text: root.onLoadouts && root.selectedItem("loadouts") && root.selectedItem("loadouts").isNew
              ? "ENTER  save current fitting as a loadout       ESC  " + (root.dirty ? "discard" : "close")
              : root.dirty
                ? "ENTER  apply for real       S  save as loadout       ESC  discard"
                : "TAB category     ↑↓ slot     ←→ browse     ENTER apply     S save     ESC close"
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
