pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The screen Quartermaster opens on: one group, centred, that does not try
// to fill the output. On the left a mission card -- flat, in the chrome's
// own colours, an index at its head and the word EQUIP at its foot -- which
// is the way into the equip screen. A hairline divider. On the right the
// saved loadouts as a compact grid, three to a row. One cursor covers both:
// ← → walk from the card into the grid and along it, ↑ ↓ move by row, ENTER
// takes whatever is under it. A loadout card fits every slot it recorded
// and continues to the equip screen wearing it, so the character shows the
// fitting and D deploys it. Nothing is saved from here; that is the equip
// screen's S.
Item {
  id: root

  property var host: null

  readonly property bool onCard: host ? host.bootIndex < 0 : true

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  // The card sets the group's height; a short output shrinks it and the
  // grid's visible rows with it rather than pushing the hints away.
  readonly property real cardHeight: Math.min(Style.space(380), Math.max(Style.space(240), height - Style.space(60)))
  readonly property real cardWidth: Math.round(cardHeight * 0.74)
  readonly property real kickerGap: Style.space(12)
  readonly property real dividerGap: Style.space(44)

  Item {
    id: group
    anchors.centerIn: parent
    width: card.width + root.dividerGap * 2 + 1 + grid.implicitWidth
    height: leftKicker.implicitHeight + root.kickerGap + root.cardHeight

    // -- The mission card ------------------------------------------------
    Text {
      id: leftKicker
      anchors { top: parent.top; left: parent.left }
      text: "CHARACTER"
      color: root.onCard ? root.accent : root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.bold: root.onCard
      font.letterSpacing: 2.5
    }

    TechFrame {
      id: card
      anchors { top: leftKicker.bottom; topMargin: root.kickerGap; left: parent.left }
      width: root.cardWidth
      height: root.cardHeight
      readonly property real inset: Style.space(20)
      cuts: []
      fill: root.onCard || cardMouse.containsMouse
        ? (root.host ? root.host.paneBgFocused : "transparent")
        : (root.host ? root.host.paneBg : "transparent")
      stroke: root.onCard ? root.accent : cardMouse.containsMouse ? root.fg : root.line
      strokeWidth: 1
      brackets: root.onCard
      bracketColor: root.accent
      bracketLength: Style.space(18)
      bracketInset: 5
      edge: "left"
      edgeColor: root.accent
      edgeWidth: root.onCard ? Style.space(4) : 0

      // Texture: a band of fine diagonal hatching across the upper half,
      // the way the reference screens rule their empty panels.
      Canvas {
        id: hatch
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
        height: Math.round(parent.height * 0.5)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: root; function onFgChanged() { hatch.requestPaint() } }
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.clearRect(0, 0, width, height)
          // The lines fade out toward the caption, so the band has no edge.
          var g = ctx.createLinearGradient(0, 0, 0, height)
          g.addColorStop(0, Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07))
          g.addColorStop(1, Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0))
          ctx.strokeStyle = g
          ctx.lineWidth = 1
          ctx.beginPath()
          for (var x = -height; x < width; x += 7) {
            ctx.moveTo(x, height)
            ctx.lineTo(x + height, 0)
          }
          ctx.stroke()
        }
      }

      // Index and state, along the top edge.
      Item {
        id: topRow
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: card.inset }
        anchors.leftMargin: card.inset + Style.space(4)
        height: Style.space(22)

        Rectangle {
          id: indexBar
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          width: Style.space(3)
          height: parent.height
          color: root.onCard ? root.accent : root.line
        }
        Text {
          anchors { left: indexBar.right; leftMargin: Style.space(10); verticalCenter: parent.verticalCenter }
          text: "01"
          color: root.onCard ? root.accent : root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 2
        }
        Row {
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          spacing: Style.space(8)
          Rectangle {
            width: Style.space(6); height: width
            rotation: 45
            color: root.host && root.host.dirty ? root.warn : (root.host ? root.host.good : root.accent)
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.host && root.host.dirty ? "UNDEPLOYED" : "READY"
            color: root.host && root.host.dirty ? root.warn : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: 2.5
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // The watermark: the character's glyph, large and nearly gone.
      Text {
        anchors { horizontalCenter: parent.horizontalCenter; top: topRow.bottom; bottom: caption.top }
        verticalAlignment: Text.AlignVCenter
        text: "󰍹"
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.onCard ? 0.10 : 0.06)
        font.family: root.uiFont
        font.pixelSize: Math.round(card.height * 0.30)
      }

      Column {
        id: caption
        anchors { left: parent.left; right: parent.right; bottom: footer.top }
        anchors.leftMargin: card.inset + Style.space(4)
        anchors.rightMargin: card.inset
        anchors.bottomMargin: Style.space(16)
        spacing: Style.space(6)

        Rectangle {
          width: parent.width
          height: 1
          color: root.onCard ? root.accent : root.line
        }
        Item { width: 1; height: Style.space(6) }
        // The kicker names the loadout the fitting represents, when it
        // does, so the status line below has room to say what state it is in.
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: {
            var name = root.host ? root.host.activeLoadoutName : ""
            return name ? "LOADOUT  ·  " + name.toUpperCase() : "EQUIP SYSTEM"
          }
          color: root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 3
        }
        Row {
          spacing: Style.space(10)
          Text {
            text: "EQUIP"
            color: root.onCard ? root.accent : root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.display
            font.bold: true
            font.letterSpacing: 6
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "󰅂"
            color: root.onCard ? root.accent : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.iconLarge
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        // What the character is wearing, in the nameplate's words.
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: {
            if (!root.host) return ""
            var n = root.host.stagedCount
            if (n > 0) return n + (n === 1 ? " SLOT FITTED" : " SLOTS FITTED") + "  ·  D DEPLOYS"
            return root.host.activeLoadoutName ? "EQUIPPED" : "CURRENT CONFIGURATION"
          }
          color: root.host && root.host.dirty ? root.warn : root.fg
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
        }
      }

      // The prompt, along the bottom edge.
      Row {
        id: footer
        anchors { left: parent.left; bottom: parent.bottom }
        anchors.leftMargin: card.inset + Style.space(4)
        anchors.bottomMargin: card.inset
        spacing: Style.space(8)
        Text {
          text: "ENTER"
          color: root.onCard ? root.accent : root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.5
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "CONTINUE"
          color: root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.host) root.host.bootPick("")
      }
    }

    // -- The divider -----------------------------------------------------
    Rectangle {
      id: divider
      anchors { left: card.right; leftMargin: root.dividerGap; top: card.top; bottom: card.bottom }
      width: 1
      color: root.line
      Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
        width: Style.space(5); height: width
        rotation: 45
        color: root.muted
      }
      Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        width: Style.space(5); height: width
        rotation: 45
        color: root.muted
      }
    }

    // -- The saved loadouts ----------------------------------------------
    Text {
      id: rightKicker
      anchors { top: parent.top; left: grid.left }
      text: "SAVED LOADOUTS  " + String(grid.savedCount).padStart(2, "0")
      color: root.onCard ? root.muted : root.accent
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.bold: !root.onCard
      font.letterSpacing: 2.5
    }

    LoadoutGrid {
      id: grid
      anchors { left: divider.right; leftMargin: root.dividerGap; top: card.top; bottom: card.bottom }
      width: implicitWidth
      host: root.host
    }
  }
}
