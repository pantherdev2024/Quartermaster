pragma ComponentBehavior: Bound

import QtQuick

// A miniature mock of the Omarchy desktop, painted entirely from a candidate
// theme's palette. Deliberately NOT a screen capture: the real screen can only
// show what is already applied, and this overlay covers it anyway. Mocking it
// is what makes "try before you equip" possible.
Item {
  id: root

  property var colors: ({})
  property string wallpaper: ""
  property string fontFamily: "monospace"
  property string themeName: ""
  property string terminalName: ""

  // Chassis: where the bar sits, whether it's see-through, and how big text
  // is relative to the 12px shell default.
  property string barPosition: "top"
  property bool barTransparent: false
  property real fontScale: 1.0
  // Which widgets sit where: { left: [ids], center: [ids], right: [ids] }.
  property var barLayout: ({ left: [], center: [], right: [] })

  // Before the inventory lands the layout is empty; show a plausible bar
  // rather than a bare strip.
  readonly property var layoutOrDefault: {
    var l = root.barLayout || {}
    var n = (l.left || []).length + (l.center || []).length + (l.right || []).length
    return n > 0 ? l : { left: ["omarchy.workspaces"], center: ["omarchy.clock"], right: ["omarchy.tray"] }
  }

  // Glyph per widget id, handed in by the host so tiles and bar agree.
  property var glyphs: ({})

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
  // staged text-size scale, so TEXT SIZE previews as bigger type only.
  readonly property real u: height / 100
  readonly property real t: u * fontScale

  readonly property bool barHorizontal: barPosition === "top" || barPosition === "bottom"
  readonly property real barThickness: (barHorizontal ? u * 7 : u * 7.5) * Math.max(1, fontScale)

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
    layer.enabled: true
    layer.effect: null
  }

  // Fade the wallpaper slightly so mock windows stay legible on busy images.
  Rectangle {
    anchors.fill: parent
    color: root.bg
    opacity: wall.status === Image.Ready ? 0.25 : 0
    radius: root.u * 1.5
  }

  // ---- Bar -----------------------------------------------------------
  // Anchored to whichever edge is staged. A transparent bar drops its fill
  // and lets the wallpaper through, exactly as `omarchy bar transparent` does.
  Rectangle {
    id: bar
    anchors {
      top: root.barPosition === "bottom" ? undefined : parent.top
      bottom: root.barPosition === "top" ? undefined : parent.bottom
      left: root.barPosition === "right" ? undefined : parent.left
      right: root.barPosition === "left" ? undefined : parent.right
    }
    width: root.barHorizontal ? parent.width : root.barThickness
    height: root.barHorizontal ? root.barThickness : parent.height
    color: root.barTransparent
      ? "transparent"
      : Qt.rgba(root.darkBg.r, root.darkBg.g, root.darkBg.b, 0.92)

    // The widgets, mirrored from the fitting's bar layout, drawn by the
    // shared BarRail so the mock bar and the workbench's rail agree.
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

  // The tiling area is whatever the bar leaves over.
  Item {
    id: desk
    anchors {
      fill: parent
      topMargin: root.barPosition === "top" ? root.barThickness : 0
      bottomMargin: root.barPosition === "bottom" ? root.barThickness : 0
      leftMargin: root.barPosition === "left" ? root.barThickness : 0
      rightMargin: root.barPosition === "right" ? root.barThickness : 0
    }

    // ---- Mock terminal window -----------------------------------------
    Rectangle {
      id: term
      anchors {
        top: parent.top; topMargin: root.u * 4
        left: parent.left; leftMargin: root.u * 4
      }
      width: parent.width * 0.58
      height: parent.height * 0.64
      radius: root.u * 1.2
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.94)
      border.width: Math.max(1, root.u * 0.25)
      border.color: root.accent

      Column {
        anchors { fill: parent; margins: root.u * 2.5 }
        spacing: root.t * 1.4
        clip: true

        Item {
          width: parent.width
          height: cwd.height

          Text {
            id: cwd
            text: "~/dev/omarchy"
            color: root.green
            font.family: root.fontFamily
            font.pixelSize: root.t * 3.2
            font.bold: true
          }
          Text {
            anchors.right: parent.right
            text: root.terminalName
            color: root.dimFg
            font.family: root.fontFamily
            font.pixelSize: root.t * 2.6
          }
        }
        Text {
          text: "$ omarchy theme set " + (root.themeName || "…").toLowerCase()
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: root.t * 3.2
        }
        Text {
          text: "→ palette applied"
          color: root.cyan
          font.family: root.fontFamily
          font.pixelSize: root.t * 3.2
        }
        Text {
          text: "warning: looking good"
          color: root.yellow
          font.family: root.fontFamily
          font.pixelSize: root.t * 3.2
        }
        Text {
          text: "error: none"
          color: root.red
          font.family: root.fontFamily
          font.pixelSize: root.t * 3.2
        }

        // Palette strip — the theme's own "stat line".
        Row {
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
      }
    }

    // ---- Secondary window (shows layering + accent) --------------------
    Rectangle {
      anchors {
        right: parent.right; rightMargin: root.u * 4
        bottom: parent.bottom; bottomMargin: root.u * 5
      }
      width: parent.width * 0.34
      height: parent.height * 0.44
      radius: root.u * 1.2
      color: Qt.rgba(root.lighterBg.r, root.lighterBg.g, root.lighterBg.b, 0.95)
      border.width: Math.max(1, root.u * 0.2)
      border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)

      Column {
        id: sideColumn
        anchors { fill: parent; margins: root.u * 2.2 }
        spacing: root.u * 1.6

        Rectangle {
          width: sideColumn.width * 0.5
          height: root.t * 2
          radius: height / 2
          color: root.accent
        }
        Repeater {
          model: 4
          Rectangle {
            required property int index
            width: sideColumn.width * (0.9 - index * 0.15)
            height: root.t * 1.5
            radius: height / 2
            color: root.fg
            opacity: 0.3 - index * 0.05
          }
        }
      }
    }
  }
}
