pragma ComponentBehavior: Bound

import QtQuick

// The contents of a bar: three groups of widget tokens at its start, middle
// and end, drawn from a layout map. Workspaces draw as the pip row, the clock
// as the time, the tray as a dot cluster, and everything else as its glyph.
//
// Shared by the mini desktop's bar and the workbench's rail, so there is one
// definition of what a bar looks like. Everything scales off `u` (furniture)
// and `t` (type), which the host derives from its own size: the same tokens
// read at thumbnail size on the mock desktop and at rail size in the
// workbench.
Item {
  id: root

  // { left: [ids], center: [ids], right: [ids] }
  property var layout: ({ left: [], center: [], right: [] })
  // Glyph per widget id, handed in by the host so tiles and bar agree.
  property var glyphs: ({})
  property bool horizontal: true

  property real u: 1
  property real t: 1
  property real margin: u * 2.5

  // The workbench lights the token it has the cursor on, so a tile and its
  // real place on the bar read as the same thing. The mini desktop leaves
  // these alone and the rail draws as a plain bar.
  property string highlightId: ""
  property bool interactive: false
  signal tokenHovered(string id)

  property string fontFamily: "monospace"
  property color fg: "#cacccc"
  property color dimFg: "#707880"
  property color accent: "#7aa2f7"
  property color green: "#a6e3a1"
  property color yellow: "#f9e2af"
  property color blue: "#89b4fa"

  function glyphFor(id) {
    var g = root.glyphs ? root.glyphs[id] : ""
    return g || "▪"
  }

  // Placed by explicit geometry rather than anchors switched on `horizontal`:
  // an anchor bound to undefined does not reliably release the edge it already
  // held, so a rail that has been horizontal keeps those anchors when it turns
  // vertical and the groups land in the wrong place. Along the bar the groups
  // sit at its start, middle and end whichever way it runs.
  BarGroup {
    ids: root.layout.left || []
    x: root.horizontal ? root.margin : (root.width - width) / 2
    y: root.horizontal ? (root.height - height) / 2 : root.margin
  }
  BarGroup {
    ids: root.layout.center || []
    x: (root.width - width) / 2
    y: (root.height - height) / 2
  }
  BarGroup {
    ids: root.layout.right || []
    x: root.horizontal ? root.width - width - root.margin : (root.width - width) / 2
    y: root.horizontal ? (root.height - height) / 2 : root.height - height - root.margin
  }

  component BarGroup: Grid {
    id: group
    property var ids: []
    columns: root.horizontal ? Math.max(1, ids.length) : 1
    spacing: root.u * 2
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: Grid.AlignHCenter

    Repeater {
      model: group.ids
      delegate: BarToken {}
    }
  }

  component BarToken: Item {
    id: tok
    required property string modelData
    readonly property bool lit: root.highlightId !== "" && root.highlightId === tok.modelData
    readonly property string kind: modelData === "omarchy.workspaces" ? "pips"
      : modelData === "omarchy.clock" ? "clock"
      : modelData === "omarchy.tray" ? "tray"
      : modelData === "omarchy.spacer" ? "gap"
      : "glyph"

    width: kind === "pips" ? pips.width : kind === "clock" ? clock.width
      : kind === "tray" ? tray.width : kind === "gap" ? root.u * 4 : glyph.width
    height: kind === "pips" ? pips.height : kind === "clock" ? clock.height
      : kind === "tray" ? tray.height : kind === "gap" ? root.u * 2 : glyph.height

    // The cursor's token, lit from behind so pips and tray dots mark up
    // as clearly as a glyph does.
    Rectangle {
      visible: tok.lit
      anchors.centerIn: parent
      width: parent.width + root.u * 2.6
      height: parent.height + root.u * 2.2
      radius: root.u * 0.8
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
      border.width: Math.max(1, root.u * 0.22)
      border.color: root.accent
    }

    // Workspace pips — first one active in the accent color.
    Grid {
      id: pips
      visible: tok.kind === "pips"
      columns: root.horizontal ? 5 : 1
      spacing: root.u * 1.6
      Repeater {
        model: 5
        Rectangle {
          required property int index
          width: root.horizontal ? (index === 0 ? root.u * 4 : root.u * 2) : root.u * 2
          height: root.horizontal ? root.u * 2 : (index === 0 ? root.u * 4 : root.u * 2)
          radius: Math.min(width, height) / 2
          color: index === 0 ? root.accent : root.dimFg
          opacity: index === 0 ? 1 : 0.45
        }
      }
    }

    Text {
      id: clock
      visible: tok.kind === "clock"
      text: root.horizontal
        ? Qt.formatDateTime(new Date(), "ddd d MMM  hh:mm")
        : Qt.formatDateTime(new Date(), "hh\n—\nmm")
      horizontalAlignment: Text.AlignHCenter
      color: tok.lit ? root.accent : root.fg
      font.family: root.fontFamily
      font.pixelSize: root.t * 3.4
    }

    Grid {
      id: tray
      visible: tok.kind === "tray"
      columns: root.horizontal ? 3 : 1
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

    MouseArea {
      anchors.fill: parent
      enabled: root.interactive
      hoverEnabled: root.interactive
      onEntered: root.tokenHovered(tok.modelData)
    }

    Text {
      id: glyph
      visible: tok.kind === "glyph"
      text: root.glyphFor(tok.modelData)
      color: tok.lit ? root.accent : root.fg
      opacity: tok.lit ? 1 : 0.85
      font.family: root.fontFamily
      font.pixelSize: root.t * 3.2
    }
  }
}
