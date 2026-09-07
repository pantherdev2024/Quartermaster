pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The character: the mock desktop in a bracketed viewport with every slot's
// current fitting called out around it — outfit down the left, cyberware down
// the right, chassis along the foot — each tethered to the viewport by a
// leader line. Callouts read from the same staged/equipped state as the slot
// list, so browsing on the left re-labels the character on the right at once.
Item {
  id: root

  property var host: null

  readonly property var defs: host ? host.slotDefs : []
  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  function slotsIn(cat) {
    return root.defs.filter(function(d) { return d.cat === cat })
  }
  readonly property var leftSlots: slotsIn("outfit")
  readonly property var rightSlots: slotsIn("cyberware")
  readonly property var bottomSlots: slotsIn("chassis")

  readonly property real gutter: Style.space(30)
  readonly property real calloutHeight: Style.space(58)
  readonly property real sideWidth: Math.max(Style.space(140), (width - viewport.width) / 2 - gutter)

  function repaintLeaders() { leaders.requestPaint() }
  onWidthChanged: repaintLeaders()
  onHeightChanged: repaintLeaders()
  Component.onCompleted: Qt.callLater(repaintLeaders)

  Connections {
    target: root.host
    function onSlotIndexChanged() { root.repaintLeaders() }
    function onStagedChanged() { root.repaintLeaders() }
  }

  // ---- Viewport ------------------------------------------------------
  TechFrame {
    id: viewport
    anchors.horizontalCenter: parent.horizontalCenter
    // The group (viewport, nameplate, chassis row) sits centred in the pane.
    readonly property real groupHeight: height + Style.space(12 + 30 + 34) + root.calloutHeight
    y: Math.max(Style.space(16), (parent.height - groupHeight) / 2)
    width: Math.min(parent.width * 0.58, (parent.height * 0.50) * (16 / 9))
    height: width * (9 / 16)
    chamfer: Style.space(14)
    cuts: ["tl", "tr", "bl", "br"]
    fill: "transparent"
    stroke: root.line
    strokeWidth: 1
    brackets: true
    bracketColor: root.accent
    bracketLength: Style.space(22)
    bracketWidth: 2
    bracketInset: 6

    onXChanged: root.repaintLeaders()
    onYChanged: root.repaintLeaders()
    onWidthChanged: root.repaintLeaders()

    MiniDesktop {
      id: preview
      anchors { fill: parent; margins: Style.space(6) }
      colors: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.colors : ({})
      wallpaper: root.host ? root.host.previewWallpaper : ""
      fontFamily: root.host ? root.host.previewFont : "monospace"
      themeName: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.name : ""
      terminalName: root.host ? root.host.previewTerminal : ""
      barPosition: root.host ? root.host.previewBarPosition : "top"
      barTransparent: root.host ? root.host.previewBarTransparent : false
      fontScale: root.host ? root.host.previewFontScale : 1
    }
  }

  // Nameplate under the viewport: the staged theme and whether the
  // character matches what is actually worn.
  Item {
    id: nameplate
    anchors { top: viewport.bottom; topMargin: Style.space(12); horizontalCenter: viewport.horizontalCenter }
    width: viewport.width
    height: Style.space(30)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.host && root.host.stagedThemeObject ? root.host.stagedThemeObject.name.toUpperCase() : ""
      color: root.fg
      font.family: root.uiFont
      font.pixelSize: Style.font.title
      font.bold: true
      font.letterSpacing: 4
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.host && root.host.dirty ? "STAGED CONFIGURATION" : "CURRENT CONFIGURATION"
      color: root.host && root.host.dirty ? root.warn : root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.letterSpacing: 2
    }
  }

  // ---- Leader lines ----------------------------------------------------
  // One line per callout, from its inner edge to the nearest viewport edge,
  // ending in a small square on the viewport. The focused slot's line is
  // accent; a staged slot's line is the warning colour.
  Canvas {
    id: leaders
    anchors.fill: parent
    z: -1
    antialiasing: true

    function lineColorFor(def) {
      if (!root.host) return root.line
      if (root.host.currentSlot && root.host.currentSlot.id === def.id) return root.accent
      if (root.host.staged[def.id]) return root.warn
      return root.line
    }

    function drawLeader(ctx, from, to, color) {
      ctx.strokeStyle = color
      ctx.fillStyle = color
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(from.x, from.y)
      ctx.lineTo(to.x, to.y)
      ctx.stroke()
      ctx.fillRect(to.x - 2.5, to.y - 2.5, 5, 5)
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)

      function each(column, side) {
        for (var i = 0; i < column.children.length; i++) {
          var card = column.children[i]
          if (!card.def) continue
          var p = card.mapToItem(root, 0, 0)
          var color = lineColorFor(card.def)
          if (side === "left") {
            var y = p.y + card.height / 2
            drawLeader(ctx, { x: p.x + card.width, y: y }, { x: viewport.x, y: Math.max(viewport.y + 8, Math.min(viewport.y + viewport.height - 8, y)) }, color)
          } else if (side === "right") {
            var y2 = p.y + card.height / 2
            drawLeader(ctx, { x: p.x, y: y2 }, { x: viewport.x + viewport.width, y: Math.max(viewport.y + 8, Math.min(viewport.y + viewport.height - 8, y2)) }, color)
          } else {
            var x = p.x + card.width / 2
            drawLeader(ctx, { x: x, y: p.y }, { x: x, y: nameplate.y + nameplate.height }, color)
          }
        }
      }
      each(leftColumn, "left")
      each(rightColumn, "right")
      each(bottomRow, "bottom")
    }
  }

  // ---- Callout columns -------------------------------------------------
  Column {
    id: leftColumn
    anchors { left: parent.left; verticalCenter: viewport.verticalCenter }
    width: root.sideWidth
    spacing: Style.space(16)
    onHeightChanged: root.repaintLeaders()

    Repeater {
      model: root.leftSlots
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "left"
        width: leftColumn.width
      }
    }
  }

  Column {
    id: rightColumn
    anchors { right: parent.right; verticalCenter: viewport.verticalCenter }
    width: root.sideWidth
    spacing: Style.space(16)
    onHeightChanged: root.repaintLeaders()

    Repeater {
      model: root.rightSlots
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "right"
        width: rightColumn.width
      }
    }
  }

  Row {
    id: bottomRow
    anchors { top: nameplate.bottom; topMargin: Style.space(34); horizontalCenter: viewport.horizontalCenter }
    spacing: Style.space(16)
    onWidthChanged: root.repaintLeaders()

    Repeater {
      model: root.bottomSlots
      delegate: Callout {
        required property var modelData
        def: modelData
        side: "bottom"
        width: (viewport.width - bottomRow.spacing * (root.bottomSlots.length - 1)) / Math.max(1, root.bottomSlots.length)
      }
    }
  }

  // ---- One callout card ------------------------------------------------
  component Callout: Item {
    id: card
    property var def: ({})
    property string side: "left"

    readonly property var item: root.host ? root.host.selectedItem(def.id) : null
    readonly property bool focused: root.host && root.host.currentSlot && root.host.currentSlot.id === def.id
    readonly property bool staged: root.host && root.host.staged[def.id] ? true : false
    readonly property string tag: staged ? "STAGED" : (item && item.equipped ? "EQUIPPED" : (item ? "" : "EMPTY"))
    readonly property color tagColor: staged ? root.warn : (item && item.equipped ? root.good : root.muted)

    height: root.calloutHeight

    TechFrame {
      anchors.fill: parent
      chamfer: Style.space(9)
      cuts: card.side === "left" ? ["tl", "bl"] : card.side === "right" ? ["tr", "br"] : ["bl", "br"]
      fill: root.host ? (card.focused ? root.host.paneBgFocused : root.host.paneBg) : "transparent"
      stroke: card.focused ? root.accent : root.line
      strokeWidth: 1
      brackets: card.focused
      bracketColor: root.accent
      bracketLength: Style.space(10)
      bracketWidth: 2
      bracketInset: 3
      edge: card.staged ? (card.side === "left" ? "right" : card.side === "right" ? "left" : "top") : ""
      edgeColor: root.warn
      edgeWidth: Style.space(3)

      Text {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: card.def.icon || ""
        color: card.focused ? root.accent : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.iconLarge
      }

      Column {
        anchors.left: icon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Item {
          width: parent.width
          height: labelText.implicitHeight

          Text {
            id: labelText
            anchors.left: parent.left
            anchors.right: tagText.visible ? tagText.left : parent.right
            anchors.rightMargin: tagText.visible ? Style.space(6) : 0
            elide: Text.ElideRight
            text: card.def.label || ""
            color: card.focused ? root.accent : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }

          Text {
            id: tagText
            anchors.right: parent.right
            text: card.tag
            color: card.tagColor
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            visible: text !== ""
          }
        }

        Text {
          width: parent.width
          text: card.item ? card.item.name : "—"
          color: root.fg
          font.family: root.uiFont
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        if (!root.host) return
        root.host.slotIndex = root.host.slotDefs.findIndex(function(d) { return d.id === card.def.id })
      }
    }
  }
}
