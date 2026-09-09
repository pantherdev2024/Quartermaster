pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// A miniature mock of the Omarchy desktop, painted entirely from a candidate
// theme's palette. Deliberately NOT a screen capture: the real screen can only
// show what is already applied, and this overlay covers it anyway. Mocking it
// is what makes "try before you equip" possible.
//
// Three windows tile the way Hyprland's dwindle layout would: a terminal with
// focus on the left, an editor and a browser stacked on the right. Their
// gaps, borders, corner rounding, blur and shadow are Hyprland's own look
// settings, in real pixels of a 1080-tall desktop scaled to this mock, so the
// look slots preview here the way every other slot does.
Item {
  id: root

  property var colors: ({})
  property string wallpaper: ""
  property string fontFamily: "monospace"
  property string themeName: ""
  property string terminalName: ""
  property string editorName: ""
  property string browserName: ""
  property string agentName: ""

  // Chassis: where the bar sits, whether it's see-through, and how big text
  // is relative to the 12px shell default.
  property string barPosition: "top"
  property bool barTransparent: false
  property real fontScale: 1.0
  // Which widgets sit where: { left: [ids], center: [ids], right: [ids] }.
  property var barLayout: ({ left: [], center: [], right: [] })
  // Glyph per widget id, handed in by the host so tiles and bar agree.
  property var glyphs: ({})

  // Look: Hyprland's window chrome, in real pixels.
  property int gapsIn: 5
  property int gapsOut: 10
  property int borderSize: 2
  property int rounding: 0
  property bool blurOn: false
  property bool shadowOn: false

  // Before the inventory lands the layout is empty; show a plausible bar
  // rather than a bare strip.
  readonly property var layoutOrDefault: {
    var l = root.barLayout || {}
    var n = (l.left || []).length + (l.center || []).length + (l.right || []).length
    return n > 0 ? l : { left: ["omarchy.workspaces"], center: ["omarchy.clock"], right: ["omarchy.tray"] }
  }

  // Palette accessor with fallback — user themes don't all define every key.
  function c(key, fallback) {
    var v = root.colors ? root.colors[key] : undefined
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  readonly property color bg: c("background", "#101315")
  readonly property color darkBg: c("dark_background", bg)
  readonly property color lighterBg: c("lighter_background", "#2a2a2a")
  readonly property color fg: c("foreground", "#cacccc")
  readonly property color dimFg: c("dark_foreground", "#707880")
  readonly property color accent: c("accent", "#7aa2f7")
  readonly property color red: c("red", "#f38ba8")
  readonly property color green: c("green", "#a6e3a1")
  readonly property color yellow: c("yellow", "#f9e2af")
  readonly property color blue: c("blue", "#89b4fa")
  readonly property color magenta: c("magenta", "#f5c2e7")
  readonly property color cyan: c("cyan", "#94e2d5")

  // Everything inside scales off the mock's own height so the preview stays
  // proportional at any panel size. `t` is the text unit: `u` times the
  // staged text-size scale, so TEXT SIZE previews as bigger type only. `px`
  // is one real pixel of a 1080-tall desktop, so gaps and borders preview
  // at their true proportion rather than as a suggestion.
  readonly property real u: height / 100
  readonly property real t: u * fontScale
  readonly property real px: root.u * (100 / 1080)
  readonly property real gapIn: root.gapsIn * root.px
  readonly property real gapOut: root.gapsOut * root.px
  readonly property real border: root.borderSize > 0 ? Math.max(1, root.borderSize * root.px) : 0
  readonly property real radius: root.rounding * root.px
  readonly property color inactiveBorder: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22)

  readonly property bool barHorizontal: barPosition === "top" || barPosition === "bottom"
  readonly property real barThickness: (barHorizontal ? u * 7 : u * 7.5) * Math.max(1, fontScale)

  // ---- Geometry: the bar, the desk it leaves, the three windows ---------
  readonly property real deskX: root.barPosition === "left" ? root.barThickness : 0
  readonly property real deskY: root.barPosition === "top" ? root.barThickness : 0
  readonly property real deskW: root.width - (root.barHorizontal ? 0 : root.barThickness)
  readonly property real deskH: root.height - (root.barHorizontal ? root.barThickness : 0)
  readonly property real innerX: root.deskX + root.gapOut
  readonly property real innerY: root.deskY + root.gapOut
  readonly property real innerW: Math.max(0, root.deskW - 2 * root.gapOut)
  readonly property real innerH: Math.max(0, root.deskH - 2 * root.gapOut)

  readonly property rect termRect: Qt.rect(root.innerX, root.innerY,
    Math.round((root.innerW - root.gapIn) * 0.54), root.innerH)
  readonly property rect editorRect: Qt.rect(root.termRect.x + root.termRect.width + root.gapIn, root.innerY,
    root.innerW - root.termRect.width - root.gapIn, Math.round((root.innerH - root.gapIn) * 0.56))
  readonly property rect browserRect: Qt.rect(root.editorRect.x, root.editorRect.y + root.editorRect.height + root.gapIn,
    root.editorRect.width, root.innerH - root.editorRect.height - root.gapIn)

  clip: true

  // ---- Wallpaper ----------------------------------------------------
  Rectangle {
    anchors.fill: parent
    color: root.bg
    radius: root.u * 1.5
  }

  Image {
    id: wall
    anchors.fill: parent
    source: root.wallpaper ? "file://" + root.wallpaper : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    visible: status === Image.Ready
  }

  // Fade the wallpaper slightly so mock windows stay legible on busy images.
  Rectangle {
    anchors.fill: parent
    color: root.bg
    opacity: wall.status === Image.Ready ? 0.25 : 0
    radius: root.u * 1.5
  }

  // Blur: the wallpaper as seen through the windows. One blurred copy of the
  // wallpaper, masked to the three window shapes, drawn under the windows;
  // the windows themselves go translucent over it.
  Item {
    id: windowMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Rectangle { x: root.termRect.x; y: root.termRect.y; width: root.termRect.width; height: root.termRect.height; radius: root.radius; color: "white" }
    Rectangle { x: root.editorRect.x; y: root.editorRect.y; width: root.editorRect.width; height: root.editorRect.height; radius: root.radius; color: "white" }
    Rectangle { x: root.browserRect.x; y: root.browserRect.y; width: root.browserRect.width; height: root.browserRect.height; radius: root.radius; color: "white" }
  }
  MultiEffect {
    anchors.fill: wall
    source: wall
    visible: root.blurOn && wall.status === Image.Ready
    blurEnabled: true
    blur: 0.9
    blurMax: 40
    blurMultiplier: 1.0
    maskEnabled: true
    maskSource: windowMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 0.0
  }

  // ---- Bar -----------------------------------------------------------
  // Anchored to whichever edge is staged. A transparent bar drops its fill
  // and lets the wallpaper through, exactly as `omarchy bar transparent` does.
  // Placed by explicit geometry, not by anchors switched on the position. An
  // anchor bound to undefined does not reliably give up the edge it already
  // held, so a bar that has been along the top keeps its left and right
  // anchors when it moves to a side, spans the full width instead of a thin
  // strip, and takes the rail's tokens out to the middle of the mock with it.
  Rectangle {
    id: bar
    x: root.barPosition === "right" ? root.width - width : 0
    y: root.barPosition === "bottom" ? root.height - height : 0
    width: root.barHorizontal ? root.width : root.barThickness
    height: root.barHorizontal ? root.barThickness : root.height
    color: root.barTransparent
      ? "transparent"
      : Qt.rgba(root.darkBg.r, root.darkBg.g, root.darkBg.b, 0.92)

    BarRail {
      anchors.fill: parent
      layout: root.layoutOrDefault
      glyphs: root.glyphs
      horizontal: root.barHorizontal
      u: root.u
      t: root.t
      fontFamily: root.fontFamily
      fg: root.fg
      dimFg: root.dimFg
      accent: root.accent
      green: root.green
      yellow: root.yellow
      blue: root.blue
    }
  }

  // ---- Windows ---------------------------------------------------------
  // One window: Hyprland's border and rounding, the fitting's shadow and
  // blur, and whatever content the caller puts inside.
  component Win: Item {
    id: win
    property bool focused: false
    property color fill: root.bg
    property rect place: Qt.rect(0, 0, 0, 0)
    default property alias content: inner.data

    x: place.x; y: place.y; width: place.width; height: place.height

    Rectangle {
      id: body
      anchors.fill: parent
      radius: root.radius
      color: Qt.rgba(win.fill.r, win.fill.g, win.fill.b, root.blurOn ? 0.80 : 0.95)
      border.width: root.border
      border.color: win.focused ? root.accent : root.inactiveBorder
      antialiasing: true

      layer.enabled: root.shadowOn
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "black"
        shadowOpacity: 0.55
        shadowBlur: 1.0
        shadowVerticalOffset: root.px * 4
        shadowHorizontalOffset: 0
        shadowScale: 1.0
      }

      Item {
        id: inner
        anchors { fill: parent; margins: root.border }
        clip: true
      }
    }
  }

  // The terminal, with focus: the theme's own stat line.
  Win {
    id: term
    focused: true
    fill: root.bg
    place: root.termRect

    Column {
      anchors { fill: parent; margins: root.u * 2.4 }
      spacing: root.t * 1.35

      Item {
        width: parent.width
        height: cwd.height
        Text {
          id: cwd
          text: "~/dev/omarchy"
          color: root.green
          font.family: root.fontFamily
          font.pixelSize: root.t * 3.1
          font.bold: true
        }
        Text {
          id: termName
          anchors.right: parent.right
          text: root.terminalName
          color: root.dimFg
          font.family: root.fontFamily
          font.pixelSize: root.t * 2.5
        }
      }
      Text {
        id: cmdLine
        text: "$ omarchy theme set " + (root.themeName || "…").toLowerCase()
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.t * 3.1
      }
      Text { text: "→ palette applied";      color: root.cyan;   font.family: root.fontFamily; font.pixelSize: root.t * 3.1 }
      Text { text: "warning: looking good";  color: root.yellow; font.family: root.fontFamily; font.pixelSize: root.t * 3.1 }
      Text { text: "error: none";            color: root.red;    font.family: root.fontFamily; font.pixelSize: root.t * 3.1 }

      // Palette strip — the theme's own "stat line".
      Row {
        id: paletteRow
        spacing: root.u * 0.8
        Repeater {
          model: [root.red, root.yellow, root.green, root.cyan, root.blue, root.magenta, root.fg, root.dimFg]
          Rectangle {
            required property color modelData
            width: root.u * 3
            height: root.u * 2.2
            radius: root.u * 0.4
            color: modelData
          }
        }
      }

      Item { width: 1; height: root.t * 0.6 }

      // The prompt, with the fitted coding agent about to be called and a
      // cursor waiting on it.
      Row {
        id: promptRow
        spacing: root.t * 0.8
        Text {
          text: "$ " + (root.agentName || "")
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: root.t * 3.1
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: root.t * 1.7
          height: root.t * 3.3
          color: root.accent
          opacity: 0.85
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  // The editor: a tab strip and a few lines of code, so a font reads as
  // code and the text size shows against a second window.
  Win {
    id: editor
    fill: root.darkBg
    place: root.editorRect

    Column {
      id: editorColumn
      anchors { fill: parent; margins: root.u * 2.0 }
      spacing: root.t * 1.15

      Item {
        width: parent.width
        height: tabText.height + root.u * 1.2
        Row {
          spacing: root.t * 1.2
          Text {
            id: tabText
            text: "equip.rs"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: root.t * 2.6
          }
          Text {
            text: "×"
            color: root.dimFg
            font.family: root.fontFamily
            font.pixelSize: root.t * 2.6
          }
        }
        Text {
          anchors.right: parent.right
          text: root.editorName
          color: root.dimFg
          font.family: root.fontFamily
          font.pixelSize: root.t * 2.4
        }
        Rectangle {
          anchors { left: parent.left; bottom: parent.bottom }
          width: tabText.width
          height: Math.max(1, root.u * 0.35)
          color: root.accent
        }
      }

      Repeater {
        model: [
          [[root.dimFg, "// fit the desktop, then deploy"]],
          [[root.blue, "fn "], [root.yellow, "equip"], [root.fg, "(slot: "], [root.cyan, "Slot"], [root.fg, ") -> "], [root.cyan, "Fit"], [root.fg, " {"]],
          [[root.fg, "    let theme = "], [root.cyan, "Theme"], [root.fg, "::load("], [root.green, "\"" + (root.themeName || "…").toLowerCase() + "\""], [root.fg, ");"]],
          [[root.fg, "    "], [root.blue, "match"], [root.fg, " slot {"]],
          [[root.fg, "        "], [root.magenta, "Slot"], [root.fg, "::Font => theme."], [root.yellow, "font"], [root.fg, "(),"]],
          [[root.fg, "        _ => theme."], [root.yellow, "wear"], [root.fg, "(slot),"]],
          [[root.fg, "    }"]],
          [[root.fg, "}"]]
        ]
        delegate: Row {
          id: codeLine
          required property var modelData
          Repeater {
            model: codeLine.modelData
            delegate: Text {
              required property var modelData
              text: modelData[1]
              color: modelData[0]
              font.family: root.fontFamily
              font.pixelSize: root.t * 2.8
            }
          }
        }
      }
    }
  }

  // The browser: chrome dots, an address, and a page in the accent.
  Win {
    id: browser
    fill: root.lighterBg
    place: root.browserRect

    Column {
      id: page
      anchors { fill: parent; margins: root.u * 2.0 }
      spacing: root.u * 1.5

      Row {
        width: parent.width
        spacing: root.u * 1.2
        Repeater {
          model: [root.red, root.yellow, root.green]
          Rectangle {
            required property color modelData
            width: root.u * 1.7; height: width
            radius: width / 2
            color: modelData
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Rectangle {
          id: urlPill
          width: page.width - 3 * (root.u * 1.7 + root.u * 1.2) - root.u * 1.2
          height: root.t * 3.4
          radius: height / 2
          color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.55)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            anchors { left: parent.left; leftMargin: root.t * 1.6; verticalCenter: parent.verticalCenter }
            text: "omarchy.org" + (root.browserName ? "   ·   " + root.browserName : "")
            color: root.dimFg
            font.family: root.fontFamily
            font.pixelSize: root.t * 2.3
          }
        }
      }

      Rectangle { width: page.width * 0.52; height: root.t * 2.0; radius: height / 2; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.85) }
      Repeater {
        model: [0.92, 0.78, 0.64]
        Rectangle {
          required property real modelData
          width: page.width * modelData
          height: root.t * 1.3
          radius: height / 2
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.28)
        }
      }
      Rectangle {
        width: page.width
        height: Math.max(0, page.height - y)
        radius: root.u * 0.8
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
        Rectangle {
          anchors { left: parent.left; bottom: parent.bottom; margins: root.u * 1.4 }
          width: parent.width * 0.35
          height: root.t * 1.6
          radius: height / 2
          color: root.accent
        }
      }
    }
  }
}
