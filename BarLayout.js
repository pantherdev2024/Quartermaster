// A bar layout: the encoding, the operations on one, and the diff between
// two. "left:a,b|center:c|right:d" is the whole bar in order, which is what
// lets staging, saved loadouts and "is it live" stay string compares like
// every other slot in the fitting.
//
// Nothing here touches QML. Loadout.qml imports it, BarWorkbench.qml and
// BarRail.qml reach it through their host, and node --test requires it.

var SECTIONS = ["left", "center", "right"]

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
  for (var i = 0; i < SECTIONS.length; i++) {
    var sec = SECTIONS[i]
    parts.push(sec + ":" + ((l && l[sec]) || []).join(","))
  }
  return parts.join("|")
}

function findInLayout(l, id) {
  for (var i = 0; i < SECTIONS.length; i++) {
    var idx = (l[SECTIONS[i]] || []).indexOf(id)
    if (idx >= 0) return { section: SECTIONS[i], index: idx }
  }
  return null
}

function flattenLayout(l) {
  return [].concat(l.left || [], l.center || [], l.right || [])
}

function removeFromLayout(l, id) {
  var at = findInLayout(l, id)
  if (at) l[at.section].splice(at.index, 1)
}

// The four edits the workbench makes. Each takes a layout and returns a new
// one, or null when the edit is a no-op, which is what tells the caller not
// to stage anything. Returning a copy rather than mutating is what lets the
// caller hand in the object from a property binding without having to know
// whether that object is safe to write to.
function cloneLayout(l) {
  var out = {}
  for (var i = 0; i < SECTIONS.length; i++) {
    var sec = SECTIONS[i]
    out[sec] = ((l && l[sec]) || []).slice()
  }
  return out
}

// Put a widget at `index` of `section`; -1 appends. The index is clamped
// against the section as it stands once the widget has been lifted out of
// wherever it was, which is the position a drag is aiming at.
function place(layout, id, section, index) {
  if (!layout || !layout[section]) return null
  var next = cloneLayout(layout)
  removeFromLayout(next, id)
  var arr = next[section]
  var i = index < 0 ? arr.length : Math.max(0, Math.min(arr.length, index))
  arr.splice(i, 0, id)
  return next
}

function bench(layout, id) {
  if (!findInLayout(layout, id)) return null
  var next = cloneLayout(layout)
  removeFromLayout(next, id)
  return next
}

// On the bar, take it off; off the bar, put it back where it belongs.
function toggle(layout, id, defaultSection) {
  if (findInLayout(layout, id)) return bench(layout, id)
  return place(layout, id, defaultSection || "center", -1)
}

// One place along the bar, crossing into the next section at either end and
// stopping at the two ends of the bar itself.
function nudge(layout, id, delta) {
  var at = findInLayout(layout, id)
  if (!at) return null
  var si = SECTIONS.indexOf(at.section)
  var ni = at.index + delta
  var next = cloneLayout(layout)
  var arr = next[at.section]
  if (ni < 0) {
    if (si === 0) return null
    arr.splice(at.index, 1)
    next[SECTIONS[si - 1]].push(id)
  } else if (ni >= arr.length) {
    if (si === SECTIONS.length - 1) return null
    arr.splice(at.index, 1)
    next[SECTIONS[si + 1]].unshift(id)
  } else {
    arr.splice(at.index, 1)
    arr.splice(ni, 0, id)
  }
  return next
}

// Widgets that sit somewhere else in the fitting than live: a different
// section, or both neighbours changed among the widgets common to both.
function movedIds(live, want) {
  var liveIds = flattenLayout(live), wantIds = flattenLayout(want)
  var shared = wantIds.filter(function(id) { return liveIds.indexOf(id) >= 0 })
  var liveSeq = liveIds.filter(function(id) { return shared.indexOf(id) >= 0 })
  var out = {}
  for (var i = 0; i < shared.length; i++) {
    var id = shared[i]
    var a = findInLayout(live, id), b = findInLayout(want, id)
    if (a.section !== b.section) { out[id] = true; continue }
    var li = liveSeq.indexOf(id)
    var predSame = (li > 0 ? liveSeq[li - 1] : "") === (i > 0 ? shared[i - 1] : "")
    var succSame = (li < liveSeq.length - 1 ? liveSeq[li + 1] : "") === (i < shared.length - 1 ? shared[i + 1] : "")
    if (!predSame && !succSame) out[id] = true
  }
  return out
}

// The command list that turns the bar described by `liveString` into the one
// described by `value`: disables first, then a left-to-right walk of the
// wanted layout that enables or moves whatever is not already in its final
// place. Indices are as the shell counts them: insert position after the
// source entry is removed.
//
// Every argv[0] here is a literal. Widget ids only ever arrive as later
// elements of the array, which is what makes a hostile layout string
// uninjectable; do not parameterise the program name.
function barModsCommands(liveString, value) {
  var live = decodeLayout(liveString)
  var want = decodeLayout(value)
  var wantIds = flattenLayout(want)
  var cmds = [], sim = {}
  for (var s = 0; s < SECTIONS.length; s++) {
    var sec = SECTIONS[s]
    sim[sec] = []
    for (var i = 0; i < live[sec].length; i++) {
      var id = live[sec][i]
      if (wantIds.indexOf(id) >= 0) sim[sec].push(id)
      else cmds.push(["omarchy-plugin-disable", id])
    }
  }
  for (var t = 0; t < SECTIONS.length; t++) {
    var target = SECTIONS[t]
    for (var j = 0; j < want[target].length; j++) {
      var wid = want[target][j]
      var at = findInLayout(sim, wid)
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

if (typeof module !== "undefined") {
  module.exports = {
    SECTIONS: SECTIONS,
    decodeLayout: decodeLayout,
    encodeLayout: encodeLayout,
    findInLayout: findInLayout,
    flattenLayout: flattenLayout,
    removeFromLayout: removeFromLayout,
    place: place,
    bench: bench,
    toggle: toggle,
    nudge: nudge,
    movedIds: movedIds,
    barModsCommands: barModsCommands
  }
}
