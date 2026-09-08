const test = require("node:test")
const assert = require("node:assert/strict")

const BarLayout = require("../BarLayout.js")

// The programs the model is allowed to run. argv[0] is a hardcoded literal in
// every command it builds, and widget ids only ever arrive as later elements,
// which is what makes a hostile layout string uninjectable.
const PROGRAMS = ["omarchy-plugin-disable", "omarchy-plugin-enable", "omarchy-bar"]

function layout(left, center, right) {
  return { left: left || [], center: center || [], right: right || [] }
}

// ---- the encoding ----------------------------------------------------------

test("a layout survives a round trip through the string form", () => {
  const str = "left:a,b|center:c|right:d,e"
  assert.equal(BarLayout.encodeLayout(BarLayout.decodeLayout(str)), str)
})

test("an empty section round trips as an empty section, not a missing one", () => {
  const str = "left:|center:c|right:"
  const decoded = BarLayout.decodeLayout(str)
  assert.deepEqual(decoded, layout([], ["c"], []))
  assert.equal(BarLayout.encodeLayout(decoded), str)
})

test("an unknown section is dropped rather than carried along", () => {
  const decoded = BarLayout.decodeLayout("left:a|bogus:x|right:b")
  assert.deepEqual(decoded, layout(["a"], [], ["b"]))
  assert.equal(BarLayout.encodeLayout(decoded), "left:a|center:|right:b")
})

test("nothing at all decodes to an empty bar", () => {
  for (const value of ["", null, undefined]) {
    assert.deepEqual(BarLayout.decodeLayout(value), layout())
  }
  assert.equal(BarLayout.encodeLayout({}), "left:|center:|right:")
})

test("a widget is found by section and index, or not at all", () => {
  const l = layout(["a", "b"], ["c"], [])
  assert.deepEqual(BarLayout.findInLayout(l, "b"), { section: "left", index: 1 })
  assert.deepEqual(BarLayout.findInLayout(l, "c"), { section: "center", index: 0 })
  assert.equal(BarLayout.findInLayout(l, "zz"), null)
  assert.deepEqual(BarLayout.flattenLayout(l), ["a", "b", "c"])
})

// ---- the edits -------------------------------------------------------------

test("nudging off the end of LEFT arrives at the head of CENTER", () => {
  const before = layout(["a", "b"], ["c"], [])
  const after = BarLayout.nudge(before, "b", 1)
  assert.deepEqual(after, layout(["a"], ["b", "c"], []))
  assert.deepEqual(before, layout(["a", "b"], ["c"], []), "the input must not be touched")
})

test("nudging back off the head of CENTER arrives at the tail of LEFT", () => {
  assert.deepEqual(BarLayout.nudge(layout(["a"], ["c"], []), "c", -1),
                   layout(["a", "c"], [], []))
})

test("nudging off either end of the bar itself does nothing", () => {
  assert.equal(BarLayout.nudge(layout(["a", "b"], [], []), "a", -1), null)
  assert.equal(BarLayout.nudge(layout([], [], ["d", "e"]), "e", 1), null)
})

test("nudging within a section swaps with the neighbour", () => {
  assert.deepEqual(BarLayout.nudge(layout(["a", "b", "c"]), "a", 1),
                   layout(["b", "a", "c"]))
})

test("nudging a widget that is not on the bar does nothing", () => {
  assert.equal(BarLayout.nudge(layout(["a"]), "zz", 1), null)
})

test("benching takes a widget off the bar, and benching it again does nothing", () => {
  const before = layout(["a", "b"], ["c"], [])
  const after = BarLayout.bench(before, "b")
  assert.deepEqual(after, layout(["a"], ["c"], []))
  assert.deepEqual(before, layout(["a", "b"], ["c"], []), "the input must not be touched")
  assert.equal(BarLayout.bench(after, "b"), null)
})

test("placing appends at -1 and clamps an index past the end", () => {
  assert.deepEqual(BarLayout.place(layout(["a", "b"]), "z", "left", -1), layout(["a", "b", "z"]))
  assert.deepEqual(BarLayout.place(layout(["a", "b"]), "z", "left", 99), layout(["a", "b", "z"]))
  assert.deepEqual(BarLayout.place(layout(["a", "b"]), "z", "left", 0), layout(["z", "a", "b"]))
})

test("placing a widget that is already on the bar moves it, counting from after it is lifted out", () => {
  assert.deepEqual(BarLayout.place(layout(["a", "b", "c"]), "a", "left", 2), layout(["b", "c", "a"]))
  assert.deepEqual(BarLayout.place(layout(["a", "b"], ["c"], []), "a", "center", 1),
                   layout(["b"], ["c", "a"], []))
})

test("placing into a section that does not exist does nothing", () => {
  assert.equal(BarLayout.place(layout(["a"]), "a", "bogus", 0), null)
  assert.equal(BarLayout.place(null, "a", "left", 0), null)
})

test("toggling takes a widget off the bar, or puts it back in its default section", () => {
  const on = layout(["a"], ["c"], [])
  assert.deepEqual(BarLayout.toggle(on, "a", "left"), layout([], ["c"], []))
  assert.deepEqual(BarLayout.toggle(layout([], ["c"], []), "a", "right"), layout([], ["c"], ["a"]))
})

test("toggling a widget with no default section puts it in the centre", () => {
  assert.deepEqual(BarLayout.toggle(layout(), "a", ""), layout([], ["a"], []))
})

// ---- the diff --------------------------------------------------------------

test("a widget is moved when it changes section, or when both neighbours change", () => {
  const live = BarLayout.decodeLayout("left:a,b,c|center:|right:")
  assert.deepEqual(BarLayout.movedIds(live, BarLayout.decodeLayout("left:a,b|center:c|right:")),
                   { c: true }, "crossing a section counts as moved")
  assert.deepEqual(BarLayout.movedIds(live, BarLayout.decodeLayout("left:b,a,c|center:|right:")),
                   { a: true, b: true }, "a swap moves both of the pair")
  assert.deepEqual(BarLayout.movedIds(live, BarLayout.decodeLayout("left:a,b,c,z|center:|right:")),
                   {}, "an addition at the end moves nothing that was already there")
})

// ---- the commands ----------------------------------------------------------

test("a widget that is wanted nowhere is disabled", () => {
  assert.deepEqual(BarLayout.barModsCommands("left:a,b|center:|right:", "left:a|center:|right:"),
                   [["omarchy-plugin-disable", "b"]])
})

test("several disables are issued in the order the sections are walked", () => {
  assert.deepEqual(BarLayout.barModsCommands("left:a,b|center:c|right:d", "left:a|center:|right:"),
                   [["omarchy-plugin-disable", "b"],
                    ["omarchy-plugin-disable", "c"],
                    ["omarchy-plugin-disable", "d"]])
})

test("a widget that is not live is enabled with its section and index", () => {
  assert.deepEqual(BarLayout.barModsCommands("left:a|center:|right:", "left:a,z|center:|right:"),
                   [["omarchy-plugin-enable", "z", "--section", "left", "--index", "1"]])
})

test("a widget that changes section is moved, not disabled and re-enabled", () => {
  assert.deepEqual(BarLayout.barModsCommands("left:a,b|center:c|right:", "left:a|center:c,b|right:"),
                   [["omarchy-bar", "move", "b", "--section", "center", "--index", "1"]])
})

test("swapping two neighbours takes one move, because the other falls into place", () => {
  assert.deepEqual(BarLayout.barModsCommands("left:a,b|center:|right:", "left:b,a|center:|right:"),
                   [["omarchy-bar", "move", "b", "--section", "left", "--index", "0"]])
})

// The walk is left to right and each index is final when it is issued, so the
// order of these is part of the contract and not an implementation detail.
test("a disable, two moves and an enable are issued in the order the shell must run them", () => {
  assert.deepEqual(
    BarLayout.barModsCommands("left:a,b|center:c|right:d", "left:b|center:c,a|right:z"),
    [
      ["omarchy-plugin-disable", "d"],
      ["omarchy-bar", "move", "b", "--section", "left", "--index", "0"],
      ["omarchy-bar", "move", "a", "--section", "center", "--index", "1"],
      ["omarchy-plugin-enable", "z", "--section", "right", "--index", "0"]
    ])
})

test("a bar that is already the wanted one needs no commands at all", () => {
  assert.deepEqual(BarLayout.barModsCommands("left:a,b|center:c|right:d",
                                             "left:a,b|center:c|right:d"), [])
})

test("argv[0] is always one of the three literal programs, whatever the layout says", () => {
  const hostile = [
    "left:; rm -rf ~|center:|right:",
    "left:--section|center:$(id)|right:`id`",
    "left:-rf,--index|center:sudo|right:&& curl evil",
    "left:../../bin/sh|center:|right:'; drop table --",
    "left:\\u0000|center:  |right:omarchy-plugin-disable"
  ]
  for (const live of hostile) {
    for (const want of hostile) {
      for (const cmd of BarLayout.barModsCommands(live, want)) {
        assert.ok(PROGRAMS.includes(cmd[0]),
                  `argv[0] was ${JSON.stringify(cmd[0])} for ${live} -> ${want}`)
        assert.ok(cmd.every(part => typeof part === "string"),
                  "every argument must be a string, so nothing is re-parsed by a shell")
      }
    }
  }
})

test("a hostile widget id travels as one argument and is never spliced into another", () => {
  const id = "; rm -rf ~"
  const cmds = BarLayout.barModsCommands("left:|center:|right:", "left:" + id + "|center:|right:")
  assert.deepEqual(cmds, [["omarchy-plugin-enable", id, "--section", "left", "--index", "0"]])
})
