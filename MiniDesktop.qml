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
  // proportional at any panel size.
  readonly property real u: height / 100

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

  // ---- Top bar -------------------------------------------------------
  Rectangle {
    id: bar
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: root.u * 7
    color: Qt.rgba(root.darkBg.r, root.darkBg.g, root.darkBg.b, 0.92)

    Row {
      anchors { left: parent.left; leftMargin: root.u * 2.5; verticalCenter: parent.verticalCenter }
      spacing: root.u * 1.6

      // Workspace pips — first one active in the accent color.
      Repeater {
        model: 5
        Rectangle {
          required property int index
          width: index === 0 ? root.u * 4 : root.u * 2
          height: root.u * 2
          radius: height / 2
          color: index === 0 ? root.accent : root.dimFg
          opacity: index === 0 ? 1 : 0.45
        }
      }
    }

    Text {
      anchors.centerIn: parent
      text: Qt.formatDateTime(new Date(), "ddd d MMM  hh:mm")
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: root.u * 3.4
    }

    Row {
      anchors { right: parent.right; rightMargin: root.u * 2.5; verticalCenter: parent.verticalCenter }
      spacing: root.u * 1.8

      Repeater {
        model: [root.green, root.yellow, root.blue]
        Rectangle {
          required property color modelData
          width: root.u * 2.2
          height: root.u * 2.2
          radius: width / 2
          color: modelData
        }
      }
    }
  }

  // ---- Mock terminal window -----------------------------------------
  Rectangle {
    id: term
    anchors {
      top: bar.bottom; topMargin: root.u * 4
      left: parent.left; leftMargin: root.u * 4
    }
    width: parent.width * 0.58
    height: parent.height * 0.62
    radius: root.u * 1.2
    color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.94)
    border.width: Math.max(1, root.u * 0.25)
    border.color: root.accent

    Column {
      anchors { fill: parent; margins: root.u * 2.5 }
      spacing: root.u * 1.4

      Text {
        text: "~/dev/omarchy"
        color: root.green
        font.family: root.fontFamily
        font.pixelSize: root.u * 3.2
        font.bold: true
      }
      Text {
        text: "$ omarchy theme set " + (root.themeName || "…").toLowerCase()
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.u * 3.2
      }
      Text {
        text: "→ palette applied"
        color: root.cyan
        font.family: root.fontFamily
        font.pixelSize: root.u * 3.2
      }
      Text {
        text: "warning: looking good"
        color: root.yellow
        font.family: root.fontFamily
        font.pixelSize: root.u * 3.2
      }
      Text {
        text: "error: none"
        color: root.red
        font.family: root.fontFamily
        font.pixelSize: root.u * 3.2
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
        height: root.u * 2
        radius: height / 2
        color: root.accent
      }
      Repeater {
        model: 4
        Rectangle {
          required property int index
          width: sideColumn.width * (0.9 - index * 0.15)
          height: root.u * 1.5
          radius: height / 2
          color: root.fg
          opacity: 0.3 - index * 0.05
        }
      }
    }
  }
}
