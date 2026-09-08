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
    movedIds: movedIds,
    barModsCommands: barModsCommands
  }
}
