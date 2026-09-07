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
// Three steps, on purpose. Browsing PREVIEWS: the character repaints and
// nothing else moves. ENTER FITS the preview into the slot: the fitting is
// what you are building, still touching nothing. D DEPLOYS the fitting: the
// omarchy commands run, detached from the shell, and the screen closes.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var inventory: ({})
  property bool applying: false
  property string statusText: ""

  // Cell size: the inventory cells shrink until the tallest category fits
  // its column with the item data panel, so no screen ever has to scroll a
  // slot list. The column's fixed costs are the tabs, the margins around the
  // list, the item data panel, and every slot's header row and frame padding.
  readonly property int maxSlotsPerCategory: {
    var counts = {}, m = 0
    for (var i = 0; i < slotDefs.length; i++) {
      var c = slotDefs[i].cat
      if (c === "*") continue
      counts[c] = (counts[c] || 0) + 1
      m = Math.max(m, counts[c])
    }
    return m
  }
  // The item data panel is a caption to whatever the cursor is on, so it is
  // sized to the tallest thing it says and no more. Fixed, because the slots
  // above it must not shift as the cursor moves.
  readonly property int itemDataHeight: Style.space(102)
  readonly property int cellSize: {
    var full = Style.space(64)
    var column = leftColumn.height
    if (column <= 0) return full
    var n = root.maxSlotsPerCategory
    var fixed = Style.space(36 + 22 + 24) + root.itemDataHeight + Style.space(42) * n + Style.space(16) * (n - 1)
    var fit = Math.floor((column - fixed) / n)
    // Cells are square and six of them set the column's width, so cap by
    // what the body can spare for that column as well as by its height:
    // freeing height here must not quietly take width from the character.
    var byWidth = body.leftCeiling > 0
      ? Math.floor((body.leftCeiling - Style.space(12) - Style.space(7)
          - (root.maxVisibleCells - 1) * Style.space(8)) / root.maxVisibleCells)
      : full
    return Math.max(Style.space(40), Math.min(full, fit, byWidth))
  }

  // An inventory row shows at most this many cells at once; the rest are
  // reached by cycling with ← →, which the row already scrolls to follow.
  // Capping the row is what keeps the left column narrow, so the character
  // gets the width back — on a laptop panel most of all.
  readonly property int maxVisibleCells: 6
  readonly property real slotRowWidth: Style.space(12) + Style.space(7)
    + root.maxVisibleCells * root.cellSize
    + (root.maxVisibleCells - 1) * Style.space(8)

  // Compact tier (laptop panels): the screen's own chrome tightens — slot
  // spacing and the hint row close up. The character decides separately
  // whether it can flank, from its own pane rather than the whole screen.
  readonly property bool compact: panel.width < Style.space(1500)

  // Resolved from the QML file's own location so a rename or clone still works.
  readonly property string pluginDir: {
    var u = Qt.resolvedUrl(".").toString()
    return u.replace(/^file:\/\//, "").replace(/\/$/, "")
  }

  // ---- Categories and slots ------------------------------------------
  // STYLE is what the desktop wears, SHELL is the frame it hangs on, and
  // CYBERWARE is the tooling wired into it. (The ids keep their original
  // names; they are keys in saved loadouts.) A slot's `apply` is the command
  // prefix; the fitted item id is appended as the final argument. `order` is
  // the deploy order: theme first because the background depends on it, the
  // font last because it restarts the shell. Adding a slot means one entry
  // here and a matching branch in itemsFor().
  readonly property var categories: [
    { id: "outfit",    label: "STYLE",     icon: "󰩻" },
    { id: "chassis",   label: "SHELL",     icon: "󰕮" },
    { id: "cyberware", label: "CYBERWARE", icon: "󰘚" }
  ]

  readonly property var slotDefs: [
    { id: "theme",          cat: "outfit",    label: "THEME",        icon: "󰏘", order: 10, apply: ["omarchy-theme-set"] },
    { id: "background",     cat: "outfit",    label: "BACKGROUND",   icon: "󰸉", order: 20, apply: ["omarchy-theme-bg-set"] },
    { id: "font",           cat: "outfit",    label: "FONT",         icon: "󰛖", order: 90, apply: ["omarchy-font-set"] },
    { id: "textSize",       cat: "outfit",    label: "TEXT SIZE",    icon: "󰉡", order: 40, apply: ["omarchy-display-text-size"] },
    { id: "barPosition",    cat: "chassis",   label: "BAR POSITION", icon: "󰍹", order: 30, apply: ["omarchy-bar", "position"] },
    { id: "barTransparent", cat: "chassis",   label: "BAR SURFACE",  icon: "󰗌", order: 31, apply: ["omarchy-bar", "transparent"] },
    // The bar's widget layout: a multi-select slot. `apply` is only a marker;
    // deployCommands() asks barModsCommands() for the real command list.
    { id: "barMods",        cat: "chassis",   label: "BAR MODS",     icon: "󰐱", order: 32, apply: ["omarchy-bar"], multi: true },
    { id: "terminal",       cat: "cyberware", label: "TERMINAL",     icon: "󰆍", order: 50, apply: ["omarchy-default-terminal"] },
    { id: "editor",         cat: "cyberware", label: "EDITOR",       icon: "󰅩", order: 51, apply: ["omarchy-default-editor"] },
    { id: "browser",        cat: "cyberware", label: "BROWSER",      icon: "󰖟", order: 52, apply: ["omarchy-default-browser"] },
    { id: "agent",          cat: "cyberware", label: "AGENT",        icon: "󰚩", order: 53, apply: [pluginDir + "/agent-set.sh"] },
    // Saved loadouts: present in every category as the last slot. No apply
    // command of its own — picking one stages every slot it recorded.
    { id: "loadouts",       cat: "*",         label: "SAVED LOADOUTS", icon: "󰆓", apply: null, wide: true }
  ]
  readonly property int loadoutsSlotIndex: slotDefs.length - 1
  readonly property bool onLoadouts: currentSlot.id === "loadouts"

  // ---- Bar mods --------------------------------------------------------
  // The slot's value is the whole bar in order, "left:a,b|center:c|right:d",
  // so staging, saved loadouts and "is it live" stay string compares like
  // every other slot. The cursor is separate: browsing this slot moves the
  // cursor and stages nothing; SPACE and SHIFT+arrows change the layout.
  property int modsCursor: 0
  readonly property var sections: ["left", "center", "right"]

  function decodeLayout(str) {
    var out = { left: [], center: [], right: [] }
    var parts = String(str || "").split("|")
    for (var i = 0; i < parts.length; i++) {
      var colon = parts[i].indexOf(":")
      if (colon < 0) continue
      var sec = parts[i].substring(0, colon)
      var ids = parts[i].substring(colon + 1)
      if (out[sec] === undefined) continue
      out[sec] = ids ? ids.split(",") : []
    }
    return out
  }
  function encodeLayout(l) {
    var parts = []
    for (var i = 0; i < root.sections.length; i++) {
      var sec = root.sections[i]
      parts.push(sec + ":" + ((l && l[sec]) || []).join(","))
    }
    return parts.join("|")
  }
  function findInLayout(l, id) {
    for (var i = 0; i < root.sections.length; i++) {
      var idx = (l[root.sections[i]] || []).indexOf(id)
      if (idx >= 0) return { section: root.sections[i], index: idx }
    }
    return null
  }
  function flattenLayout(l) {
    return [].concat(l.left || [], l.center || [], l.right || [])
  }

  readonly property string liveLayoutString: root.encodeLayout((root.inventory && root.inventory.barLayout) || {})
  readonly property string effectiveLayoutString: root.preview["barMods"] || root.staged["barMods"] || root.liveLayoutString
  readonly property var previewBarLayout: root.decodeLayout(root.effectiveLayoutString)

  // Widget glyphs, shared by the mock bar and the workbench tiles.
  readonly property var widgetGlyphs: ({
    "omarchy.menu": "󰍜", "omarchy.audio": "󰕾", "omarchy.network": "󰖩",
    "omarchy.bluetooth": "󰂯", "omarchy.power": "󰁹", "omarchy.monitor": "󰍹",
    "omarchy.keyboard-layout": "󰌌", "omarchy.weather": "󰖐", "omarchy.system-update": "󰚰",
    "omarchy.agents": "󰚩", "omarchy.indicators": "󰔡", "omarchy.media": "󰎈",
    "omarchy.microphone": "󰍬", "omarchy.active-window": "󰖯", "omarchy.dropbox": "󰇣",
    "omarchy.tailscale": "󰖂", "37signals.hey": "󰇮", "omaplug": "󰐱", "crmne.hyprmoncfg": "󰍺",
    "omarchy.workspaces": "󰕰", "omarchy.clock": "󰥔", "omarchy.tray": "󰇙"
  })

  // ---- Workbench ----------------------------------------------------------
  // ENTER on BAR MODS opens the workbench in place of the slot list; inside
  // it, ENTER fits the arrangement and ESC drops the preview. These helpers
  // move one widget by id and re-preview the layout.
  property bool workbenchOpen: false
  function openWorkbench() {
    if (!root.currentSlot.multi) return
    root.workbenchOpen = true
  }
  function closeWorkbench(fit) {
    if (fit) root.fitPreview(); else root.clearPreview()
    root.workbenchOpen = false
  }
  function widgetById(id) {
    var widgets = (root.inventory && root.inventory.barWidgets) || []
    for (var i = 0; i < widgets.length; i++) if (widgets[i].id === id) return widgets[i]
    return null
  }
  function removeFromLayout(l, id) {
    var at = root.findInLayout(l, id)
    if (at) l[at.section].splice(at.index, 1)
  }
  // Put a widget at `index` of `section`; -1 appends.
  function placeMod(id, section, index) {
    var l = root.previewBarLayout
    if (!l[section]) return
    root.removeFromLayout(l, id)
    var arr = l[section]
    var i = index < 0 ? arr.length : Math.max(0, Math.min(arr.length, index))
    arr.splice(i, 0, id)
    root.stageLayout(l, id)
  }
  function benchMod(id) {
    var l = root.previewBarLayout
    if (!root.findInLayout(l, id)) return
    root.removeFromLayout(l, id)
    root.stageLayout(l, id)
  }
  function toggleModId(id) {
    if (root.findInLayout(root.previewBarLayout, id)) { root.benchMod(id); return }
    var w = root.widgetById(id)
    root.placeMod(id, (w && w.defaultSection) || "center", -1)
  }
  // One place along the bar, crossing into the next section at either end.
  function nudgeMod(id, delta) {
    var l = root.previewBarLayout
    var at = root.findInLayout(l, id)
    if (!at) return
    var arr = l[at.section]
    var si = root.sections.indexOf(at.section)
    var ni = at.index + delta
    if (ni < 0) {
      if (si === 0) return
      arr.splice(at.index, 1)
      l[root.sections[si - 1]].push(id)
    } else if (ni >= arr.length) {
      if (si === root.sections.length - 1) return
      arr.splice(at.index, 1)
      l[root.sections[si + 1]].unshift(id)
    } else {
      arr.splice(at.index, 1)
      arr.splice(ni, 0, id)
    }
    root.stageLayout(l, id)
  }

  // Widgets that sit somewhere else in the fitting than live: a different
  // section, or both neighbours changed among the widgets common to both.
  function movedIds(live, want) {
    var liveIds = root.flattenLayout(live), wantIds = root.flattenLayout(want)
    var shared = wantIds.filter(function(id) { return liveIds.indexOf(id) >= 0 })
    var liveSeq = liveIds.filter(function(id) { return shared.indexOf(id) >= 0 })
    var out = {}
    for (var i = 0; i < shared.length; i++) {
      var id = shared[i]
      var a = root.findInLayout(live, id), b = root.findInLayout(want, id)
      if (a.section !== b.section) { out[id] = true; continue }
      var li = liveSeq.indexOf(id)
      var predSame = (li > 0 ? liveSeq[li - 1] : "") === (i > 0 ? shared[i - 1] : "")
      var succSame = (li < liveSeq.length - 1 ? liveSeq[li + 1] : "") === (i < shared.length - 1 ? shared[i + 1] : "")
      if (!predSame && !succSame) out[id] = true
    }
    return out
  }

  // The slot's items: catalogue widgets in the fitting's bar order, then the
  // bench of widgets that are off. Unknown layout entries (the spacer) are
  // kept in the layout string but get no cell.
  function modItems(layoutString) {
    var widgets = (root.inventory && root.inventory.barWidgets) || []
    if (widgets.length === 0) return []
    var byId = {}
    for (var i = 0; i < widgets.length; i++) byId[widgets[i].id] = widgets[i]
    var live = root.decodeLayout(root.liveLayoutString)
    var want = root.decodeLayout(layoutString)
    var moved = root.movedIds(live, want)
    var out = [], seen = {}
    function push(w, section, index, first) {
      var on = section !== ""
      var liveOn = root.findInLayout(live, w.id) !== null
      out.push({
        id: w.id, name: w.name, short: w.short, category: w.category,
        description: w.description, defaultSection: w.defaultSection,
        settings: w.settings === true, section: section, index: index,
        on: on, equipped: on, changed: on !== liveOn || moved[w.id] === true,
        sectionStart: first
      })
      seen[w.id] = true
    }
    for (var s = 0; s < root.sections.length; s++) {
      var sec = root.sections[s], first = true
      for (var j = 0; j < want[sec].length; j++) {
        var w = byId[want[sec][j]]
        if (!w) continue
        push(w, sec, j, first)
        first = false
      }
    }
    var bench = widgets.filter(function(w) { return !seen[w.id] })
    bench.sort(function(a, b) { return a.name.localeCompare(b.name) })
    for (var k = 0; k < bench.length; k++) push(bench[k], "", -1, k === 0)
    return out
  }

  function stageLayout(l, followId) {
    root.previewItem(root.encodeLayout(l))
    var items = root.itemsFor("barMods")
    for (var i = 0; i < items.length; i++) if (items[i].id === followId) { root.modsCursor = i; return }
  }

  // "LEFT 06 · CENTER 03 · RIGHT 08 · BENCH 05": how the fitting is
  // distributed, for the item data panel while the workbench is closed and
  // there is no single widget under the cursor to describe.
  readonly property string barModsBreakdown: {
    var want = root.decodeLayout(root.effectiveLayoutString)
    var total = ((root.inventory && root.inventory.barWidgets) || []).length
    var parts = [], on = 0
    for (var i = 0; i < root.sections.length; i++) {
      var sec = root.sections[i]
      var n = (want[sec] || []).filter(function(id) { return id !== "omarchy.spacer" }).length
      on += n
      parts.push(sec.toUpperCase() + " " + String(n).padStart(2, "0"))
    }
    parts.push("BENCH " + String(Math.max(0, total - on)).padStart(2, "0"))
    // Tight separators: four groups have to fit a narrow panel unelided.
    return parts.join(" · ")
  }

  // "17 ON  +1  −2  ↔1": what the callout and item data say about the fitting.
  readonly property string barModsSummary: {
    var live = root.decodeLayout(root.liveLayoutString)
    var want = root.decodeLayout(root.effectiveLayoutString)
    var liveIds = root.flattenLayout(live), wantIds = root.flattenLayout(want)
    var on = wantIds.filter(function(id) { return id !== "omarchy.spacer" }).length
    var added = wantIds.filter(function(id) { return liveIds.indexOf(id) < 0 }).length
    var removed = liveIds.filter(function(id) { return wantIds.indexOf(id) < 0 }).length
    var moved = Object.keys(root.movedIds(live, want)).length
    var text = on + " ON"
    if (added) text += "  +" + added
    if (removed) text += "  −" + removed
    if (moved) text += "  ↔" + moved
    return text
  }

  // The command list that turns the live bar into `value`: disables first,
  // then a left-to-right walk of the wanted layout that enables or moves
  // whatever is not already in its final place. Indices are as the shell
  // counts them: insert position after the source entry is removed.
  function barModsCommands(value) {
    var live = root.decodeLayout(root.liveLayoutString)
    var want = root.decodeLayout(value)
    var wantIds = root.flattenLayout(want)
    var cmds = [], sim = {}
    for (var s = 0; s < root.sections.length; s++) {
      var sec = root.sections[s]
      sim[sec] = []
      for (var i = 0; i < live[sec].length; i++) {
        var id = live[sec][i]
        if (wantIds.indexOf(id) >= 0) sim[sec].push(id)
        else cmds.push(["omarchy-plugin-disable", id])
      }
    }
    for (var t = 0; t < root.sections.length; t++) {
      var target = root.sections[t]
      for (var j = 0; j < want[target].length; j++) {
        var wid = want[target][j]
        var at = root.findInLayout(sim, wid)
        if (at && at.section === target && at.index === j) continue
        if (!at) {
          cmds.push(["omarchy-plugin-enable", wid, "--section", target, "--index", String(j)])
        } else {
          cmds.push(["omarchy-bar", "move", wid, "--section", target, "--index", String(j)])
          sim[at.section].splice(at.index, 1)
        }
        sim[target].splice(j, 0, wid)
      }
    }
    return cmds
  }

  // The fitting: fitted item per slot id. Empty means "unchanged from live".
  property var staged: ({})
  // The preview: what the cursor is on, for one slot, or for every slot a
  // saved loadout recorded. Cleared when the cursor leaves that slot.
  property var preview: ({})
  property string previewSlot: ""
  readonly property bool previewing: previewSlot !== ""

  // The cursor is a single index into slotDefs; the active category is
  // whatever category that slot belongs to, so there is no second piece of
  // state to keep in sync.
  property int slotIndex: 0
  readonly property var currentSlot: slotDefs[Math.max(0, Math.min(slotDefs.length - 1, slotIndex))]
  // The dock belongs to no category, so while the cursor sits on it the tabs
  // keep showing whichever category the cursor came from.
  property string pinnedCategory: "outfit"
  onSlotIndexChanged: {
    if (currentSlot.cat !== "*") pinnedCategory = currentSlot.cat
    root.workbenchOpen = false
    root.clearPreview()
  }
  readonly property string currentCategory: currentSlot.cat === "*" ? pinnedCategory : currentSlot.cat
  readonly property int currentCategoryIndex: {
    for (var i = 0; i < categories.length; i++)
      if (categories[i].id === currentCategory) return i
    return 0
  }
  readonly property var visibleSlots: slotDefs.filter(function(d) { return d.cat === root.currentCategory })

  // The equipped item id for a slot, ignoring anything staged.
  function equippedId(slotId) {
    if (slotId === "barMods") return root.liveLayoutString
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
    if (slotId === "barMods") return root.modItems(root.effectiveLayoutString)
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
    if (slotId === "barMods") return root.effectiveLayoutString
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

  // ---- Preview and fit ---------------------------------------------------
  function isLiveValue(slotId, id) {
    if (slotId === "background") {
      // The live background resolves through a different path from the
      // theme's own folder, so compare file names.
      var live = String((root.inventory && root.inventory.currentBackground) || "").split("/").pop()
      return String(id).split("/").pop() === live
    }
    return root.equippedId(slotId) === id
  }

  // Browsing: the cursor's choice for the current slot, on the character only.
  function previewItem(itemId) {
    if (root.currentSlot.id === "loadouts") { root.previewLoadout(itemId); return }
    var next = {}
    next[root.currentSlot.id] = itemId
    root.preview = next
    root.previewSlot = root.currentSlot.id
  }

  // A saved loadout previews as a whole: every slot it recorded.
  function previewLoadout(loadoutId) {
    var items = root.itemsFor("loadouts")
    var item = null
    for (var i = 0; i < items.length; i++) if (items[i].id === loadoutId) item = items[i]
    if (!item) return
    var next = { loadouts: loadoutId }
    if (!item.isNew) for (var slot in item.slots) next[slot] = item.slots[slot]
    root.preview = next
    root.previewSlot = "loadouts"
  }

  function clearPreview() {
    root.hoverOwnsPreview = false
    if (root.previewSlot === "") return
    root.preview = ({})
    root.previewSlot = ""
  }

  // ENTER: the preview becomes part of the fitting.
  function fitPreview() {
    if (root.promptOpen || root.confirmOpen || root.applying) return
    if (root.previewSlot === "") {
      // Nothing previewed. On the loadouts row ENTER takes the card under
      // the cursor; on a slot the cursor already sits on the fitted item.
      if (!root.onLoadouts) return
      var sel = root.selectedItem("loadouts")
      if (!sel) return
      if (sel.isNew) { root.openSavePrompt(); return }
      root.previewLoadout(sel.id)
    }
    if (root.previewSlot === "loadouts" && root.preview["loadouts"] === "__new") {
      root.openSavePrompt()
      return
    }
    var next = {}
    for (var k in root.staged) next[k] = root.staged[k]
    if (root.previewSlot === "loadouts") {
      for (var p in root.preview)
        next[p] = p === "loadouts" || !root.isLiveValue(p, root.preview[p]) ? root.preview[p] : ""
    } else {
      var id = root.preview[root.previewSlot]
      next[root.previewSlot] = root.isLiveValue(root.previewSlot, id) ? "" : id
      // Changing theme invalidates a background fitted from the old theme.
      if (root.previewSlot === "theme") next["background"] = ""
      // A hand-picked change means the fitting is no longer exactly a saved one.
      next["loadouts"] = ""
    }
    root.staged = next
    root.clearPreview()
    root.statusText = ""
  }

  // The loadout cards: hovering previews and leaving puts things back,
  // unless the keyboard already had a preview going; clicking moves the
  // cursor onto the card.
  property bool hoverOwnsPreview: false
  function hoverLoadout(loadoutId) {
    if (root.promptOpen || root.confirmOpen || root.applying) return
    var owns = root.previewSlot === "" || root.hoverOwnsPreview
    root.previewLoadout(loadoutId)
    root.hoverOwnsPreview = owns
  }
  function unhoverLoadout() {
    if (root.hoverOwnsPreview) root.clearPreview()
  }
  function pickLoadout(loadoutId) {
    if (root.promptOpen || root.confirmOpen || root.applying) return
    root.slotIndex = root.loadoutsSlotIndex
    root.previewLoadout(loadoutId)
  }

  // The fitting as shown: previewed where previewed, fitted where fitted,
  // live otherwise. Saving records what is on screen.
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

  // Deleting asks first: X on the row, or the card's own delete button.
  property string deleteTargetId: ""
  property string deleteTargetName: ""
  function requestDeleteLoadout(loadoutId) {
    if (root.promptOpen || root.applying) return
    var items = root.itemsFor("loadouts")
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === loadoutId && !items[i].isNew) {
        root.deleteTargetId = items[i].id
        root.deleteTargetName = items[i].name
        root.openConfirm("delete")
        return
      }
    }
  }
  function deleteCurrentLoadout() {
    if (!root.onLoadouts) return
    var item = root.selectedItem("loadouts")
    if (!item || item.isNew) return
    root.requestDeleteLoadout(item.id)
  }
  function deleteLoadoutNow() {
    if (!root.deleteTargetId) return
    deleteProc.command = [root.pluginDir + "/loadouts.sh", "delete", root.deleteTargetId]
    deleteProc.running = true
    var next = {}
    for (var k in root.staged) next[k] = root.staged[k]
    next["loadouts"] = ""
    root.staged = next
    root.clearPreview()
    root.statusText = "deleted " + root.deleteTargetName
    root.deleteTargetId = ""
    root.deleteTargetName = ""
  }

  // One confirm prompt, two questions.
  property string confirmAction: ""
  readonly property bool confirmOpen: confirmAction !== ""
  function openConfirm(action) { root.confirmAction = action }
  function confirmAccept() {
    var action = root.confirmAction
    root.confirmAction = ""
    if (action === "discard") root.discardAndClose()
    else if (action === "delete") root.deleteLoadoutNow()
  }
  function confirmCancel() { root.confirmAction = "" }

  // Name of the saved loadout the character currently represents, if any.
  readonly property string activeLoadoutName: {
    var items = root.itemsFor("loadouts")
    var stagedId = root.preview["loadouts"] || root.staged["loadouts"]
    for (var i = 0; i < items.length; i++) {
      if (items[i].isNew) continue
      if (stagedId ? items[i].id === stagedId : items[i].equipped) return items[i].name
    }
    return ""
  }

  function selectedIndexFor(slotId) {
    var items = root.itemsFor(slotId)
    if (slotId === "barMods") return items.length ? Math.max(0, Math.min(items.length - 1, root.modsCursor)) : 0
    var wanted = root.preview[slotId] || root.staged[slotId]
    for (var i = 0; i < items.length; i++) {
      if (wanted ? items[i].id === wanted : items[i].equipped) return i
    }
    return 0
  }

  function moveWithinSlot(delta) {
    // A workbench slot has no row to browse; ENTER opens it instead.
    if (root.currentSlot.multi) return
    var items = root.itemsFor(root.currentSlot.id)
    if (items.length === 0) return
    var i = root.selectedIndexFor(root.currentSlot.id) + delta
    if (i < 0) i = items.length - 1
    if (i >= items.length) i = 0
    root.previewItem(items[i].id)
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
    root.preview = ({})
    root.previewSlot = ""
    root.hoverOwnsPreview = false
    root.confirmAction = ""
    root.workbenchOpen = false
    root.slotIndex = 0
    root.modsCursor = 0
    root.statusText = ""
    scanProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // ESC and the backdrop: a fitting that was never deployed is work, so ask.
  function requestClose() {
    if (root.dirty) { root.openConfirm("discard"); return }
    root.dismiss()
  }
  function discardAndClose() {
    root.staged = ({})
    root.clearPreview()
    root.dismiss()
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

  // ---- Deploying -------------------------------------------------------
  // The fitting's commands in deploy order (see slotDefs): theme first, the
  // quick shell-side changes, the defaults, and last anything that restarts
  // the shell, because a command after a restart would find no shell.
  function deployCommands() {
    var defs = root.slotDefs.slice().sort(function(a, b) { return (a.order || 0) - (b.order || 0) })
    var cmds = []
    for (var i = 0; i < defs.length; i++) {
      var def = defs[i]
      var value = root.staged[def.id]
      if (!def.apply || !value) continue
      if (def.multi) cmds = cmds.concat(root.barModsCommands(value))
      else cmds.push(def.apply.concat([value]))
    }
    return cmds
  }

  // D: run the fitting for real and leave. deploy.sh runs detached from the
  // shell, so a font change (which restarts the shell) cannot cut it short;
  // it reports back with a notification and a result file scan.sh reads.
  function deploy() {
    if (!root.dirty || root.applying || root.promptOpen || root.confirmOpen) return
    var cmds = root.deployCommands()
    if (cmds.length === 0) return
    root.applying = true
    root.statusText = "deploying…"
    deployProc.command = ["setsid", "-f", root.pluginDir + "/deploy.sh", JSON.stringify(cmds)]
    deployProc.running = true
  }

  readonly property var lastDeploy: (root.inventory && root.inventory.lastDeploy) || null
  readonly property bool lastDeployFailed: root.lastDeploy && Number(root.lastDeploy.failed) > 0 ? true : false

  Process {
    id: deployProc
    running: false
    onExited: function(code) {
      root.applying = false
      if (code !== 0) { root.statusText = "deploy did not start"; return }
      root.staged = ({})
      root.clearPreview()
      root.dismiss()
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
      root.clearPreview()
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
      onClicked: root.requestClose()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.promptOpen) return   // the name prompt owns the keyboard
        var k = event.key
        if (root.confirmOpen) {
          if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y) root.confirmAccept()
          else if (k === Qt.Key_Escape || k === Qt.Key_N) root.confirmCancel()
          event.accepted = true
          return
        }
        if (root.workbenchOpen) {
          if (k === Qt.Key_Escape) root.closeWorkbench(false)
          else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.closeWorkbench(true)
          else if (k === Qt.Key_D) { root.closeWorkbench(true); root.deploy() }
          else if (!workbench.handleKey(k, event.modifiers)) return
          event.accepted = true
          return
        }
        if (k === Qt.Key_Escape) {
          root.requestClose()
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
          if (root.currentSlot.multi) root.openWorkbench()
          else root.fitPreview()
        } else if (k === Qt.Key_D) {
          root.deploy()
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

      // ---- Confirm prompt (discard fitting / delete loadout) -----------
      Item {
        anchors.fill: parent
        visible: root.confirmOpen
        z: 10

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(root.backdrop.r, root.backdrop.g, root.backdrop.b, 0.72)
          MouseArea { anchors.fill: parent; onClicked: root.confirmCancel() }
        }

        TechFrame {
          anchors.centerIn: parent
          width: Style.space(460)
          height: discardColumn.implicitHeight + Style.space(48)
          chamfer: Style.space(14)
          fill: root.paneBgFocused
          stroke: root.warn
          brackets: true
          bracketColor: root.warn
          bracketLength: Style.space(18)
          bracketInset: 5
          edge: "left"
          edgeColor: root.warn
          edgeWidth: Style.space(4)

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: discardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(24) }
            anchors.leftMargin: Style.space(30)
            spacing: Style.space(12)

            Text {
              text: root.confirmAction === "delete" ? "DELETE LOADOUT?" : "DISCARD FITTING?"
              color: root.warn
              font.family: root.uiFont
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 4
            }

            Text {
              width: parent.width
              text: {
                if (root.confirmAction === "delete")
                  return "Remove \"" + root.deleteTargetName + "\" from the saved loadouts. The desktop keeps whatever it is wearing."
                var n = 0
                for (var k in root.staged) if (k !== "loadouts" && root.staged[k]) n++
                return n + (n === 1 ? " slot is" : " slots are") + " fitted but not deployed. Leave without deploying?"
              }
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              text: root.confirmAction === "delete" ? "ENTER  delete       ESC  keep" : "ENTER  discard       ESC  keep fitting"
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
          height: Style.space(64)

          Row {
            id: titleRow
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
              text: "EQUIP SYSTEM // " + (root.workbenchOpen
                ? "BAR MODS"
                : root.categories[root.currentCategoryIndex].label)
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.letterSpacing: 2.5
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // The saved loadouts, across the top centre. The workbench takes
          // the whole body and its own row is unreachable there, so it goes.
          Item {
            visible: !root.workbenchOpen
            anchors {
              left: titleRow.right; leftMargin: Style.space(40)
              right: statusPill.left; rightMargin: Style.space(40)
              top: parent.top; bottom: parent.bottom
            }

            Text {
              id: dockKicker
              anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
              text: {
                var saved = ((root.inventory && root.inventory.loadouts) || []).length
                return "SAVED LOADOUTS  " + String(saved).padStart(2, "0")
              }
              color: root.onLoadouts ? root.accent : root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: root.onLoadouts
              font.letterSpacing: 2.5
            }

            LoadoutDock {
              anchors { top: dockKicker.bottom; topMargin: Style.space(6); left: parent.left; right: parent.right }
              height: implicitHeight
              host: root
            }
          }

          TechFrame {
            id: statusPill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: statusLabel.implicitWidth + Style.space(28)
            height: Style.space(26)
            chamfer: Style.space(8)
            fill: root.dirty && pillMouse.containsMouse ? root.paneBgFocused : root.paneBg
            stroke: root.dirty || root.lastDeployFailed ? root.warn : root.line
            edge: "left"
            edgeColor: root.dirty || root.lastDeployFailed ? root.warn : root.good
            edgeWidth: Style.space(3)

            Text {
              id: statusLabel
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: Style.space(2)
              text: (root.statusText
                || (root.dirty ? "D  DEPLOY LOADOUT"
                  : root.lastDeployFailed ? "LAST DEPLOY FAILED · " + String(root.lastDeploy.names || "")
                  : "SYNCED")).toUpperCase()
              color: root.dirty || root.lastDeployFailed ? root.warn : root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 2
            }

            // The pill is also the button.
            MouseArea {
              id: pillMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.dirty ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.deploy()
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
          // The most this column may take. The character has to keep enough
          // width to flank its callouts, and with room to spare rather than
          // to the pixel, so a theme at a different spacing scale does not
          // tip it into the stacked fallback.
          readonly property real leftCeiling: width <= 0 ? 0
            : Math.min(width * 0.40,
                       width - gutter - character.minFlankWidth - Style.space(60))
          // Sized from the inventory row rather than from a share of the
          // screen: six cells wide, floored at what the category tabs need
          // and ceilinged at what the character can spare.
          readonly property real leftWidth: Math.max(Style.space(320),
            Math.min(root.slotRowWidth, leftCeiling))

          // -- Left column: category tabs, then the slot list -----------
          Item {
            id: leftColumn
            visible: !root.workbenchOpen
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

            // Item data: what the cursor is on, spelled out — the reference's
            // description panel, pinned to the foot of the column at a fixed
            // height so the slots above it never shift as the cursor moves.
            ItemData {
              id: itemData
              anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
              height: root.itemDataHeight
              host: root
              // Only ever hidden as a last resort: every slot shows before
              // any item data does.
              readonly property real roomForSlots: leftColumn.height - tabs.height - Style.space(22)
              readonly property real slotsNeed: slotList.slotHeights + slotList.minSpacing * Math.max(0, slotList.count - 1)
              visible: roomForSlots - height - Style.space(24) >= slotsNeed
            }

            // Slots scroll if a small screen can't fit the whole category.
            Flickable {
              id: slotScroll
              visible: !root.workbenchOpen
              anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: itemData.visible ? itemData.top : parent.bottom }
              anchors.topMargin: Style.space(22)
              anchors.bottomMargin: itemData.visible ? Style.space(24) : 0
              contentWidth: width
              contentHeight: slotList.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              // Keep the focused slot in view when the category is taller
              // than the column; when everything fits, sit at the top.
              function revealCurrent() {
                if (contentHeight <= height) { contentY = 0; return }
                for (var i = 0; i < slotList.children.length; i++) {
                  var c = slotList.children[i]
                  if (!c.slotDef || c.slotDef.id !== root.currentSlot.id) continue
                  if (c.y < contentY) contentY = c.y
                  else if (c.y + c.height > contentY + height) contentY = Math.min(c.y + c.height - height, contentHeight - height)
                  return
                }
              }
              onContentHeightChanged: Qt.callLater(revealCurrent)
              onHeightChanged: Qt.callLater(revealCurrent)
              Connections {
                target: root
                function onSlotIndexChanged() { Qt.callLater(slotScroll.revealCurrent) }
              }

              Column {
                id: slotList
                width: slotScroll.width
                // Spread the category's slots down the column when there is
                // room, the way the reference spaces slots around the body,
                // but never so far that they stop reading as one list.
                readonly property int count: root.visibleSlots.length
                readonly property real minSpacing: Style.space(root.compact ? 16 : 24)
                readonly property real slotHeights: {
                  var h = 0
                  for (var i = 0; i < children.length; i++) if (children[i].slotDef) h += children[i].implicitHeight
                  return h
                }
                spacing: count > 1
                  ? Math.max(minSpacing, Math.min(Style.space(64), (slotScroll.height - slotHeights) / count))
                  : 0

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

          // -- The workbench: a takeover, not a panel ---------------------
          // BAR MODS edits the whole bar, so it gets the whole body: the slot
          // column and the character stand down while it is open.
          BarWorkbench {
            id: workbench
            visible: root.workbenchOpen
            anchors {
              left: parent.left; right: parent.right
              top: parent.top; bottom: hints.top; bottomMargin: Style.space(12)
            }
            host: root
          }

          // -- Right column: the character and its fittings --------------
          CharacterView {
            id: character
            visible: !root.workbenchOpen
            anchors {
              left: leftColumn.right; leftMargin: body.gutter
              right: parent.right; top: parent.top; bottom: hints.top; bottomMargin: Style.space(12)
            }
            host: root
          }

          // Game-style key prompts: keycap + action.
          readonly property var hintModel: {
            var sel = root.onLoadouts ? root.selectedItem("loadouts") : null
            var tail = root.dirty
              ? [["D", "deploy"], ["S", "save loadout"], ["ESC", "discard"]]
              : [["S", "save"], ["ESC", "close"]]
            if (root.workbenchOpen) {
              var wb = [["←→", "along the bar"], ["↑↓", "inventory"], ["1 2 3", "to section"],
                        ["⌫", "bench"], ["⇧←→", "nudge"], ["ENTER", "fit"]]
              if (!root.compact) wb.push(["D", "fit + deploy"])
              return wb.concat([["ESC", "cancel"]])
            }
            if (sel && sel.isNew) return [["ENTER", "save fitting"], ["ESC", root.dirty ? "discard" : "close"]]
            if (root.onLoadouts) return [["←→", "browse"], ["ENTER", "fit loadout"]].concat(tail)
            if (root.currentSlot.multi) return [["TAB", "category"], ["↑↓", "slot"], ["ENTER", "open workbench"]].concat(tail)
            if (root.previewing) return [["←→", "browse"], ["ENTER", "fit"]].concat(tail)
            return [["TAB", "category"], ["↑↓", "slot"], ["←→", "browse"], ["ENTER", "fit"]].concat(tail)
          }

          Row {
            id: hints
            anchors { horizontalCenter: character.horizontalCenter; bottom: parent.bottom }
            spacing: root.compact ? Style.space(12) : Style.space(22)

            Repeater {
              model: body.hintModel
              delegate: Row {
                id: hint
                required property var modelData
                spacing: Style.space(8)

                TechFrame {
                  width: keyText.implicitWidth + Style.space(16)
                  height: Style.space(22)
                  chamfer: Style.space(5)
                  cuts: ["tl", "br"]
                  fill: root.paneBgFocused
                  stroke: root.line
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: hint.modelData[0]
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                }
                Text {
                  text: hint.modelData[1].toUpperCase()
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1.5
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }
    }
  }
}
