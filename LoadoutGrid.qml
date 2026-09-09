pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The saved loadouts as a compact grid on the boot screen: three to a row,
// each tile the loadout's theme as a thumbnail over the name you gave it,
// the equipped one ringed. The cursor is the host's boot cursor, so the
// keyboard and the pointer land on the same tiles: clicking one does what
// ENTER does there (fits it), EDIT on a tile does what E does (fits it and
// continues to the equip screen), and the cross deletes it (after asking).
// Nothing is saved from here; that is the equip screen's S. The grid scrolls
// once the rows outgrow the pane.
Item {
  id: root

  property var host: null

  readonly property var items: host ? host.bootItems : []
  readonly property int savedCount: items.length
  readonly property int columns: host ? host.bootColumns : 3
  readonly property int selected: host ? host.bootIndex : -1
  readonly property string stagedId: host && host.staged ? String(host.staged["loadouts"] || "") : ""

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  // Tiles are a fixed, small size: the grid is meant to sit beside the
  // mission card, not fill a pane. Each cell carries a pad on every side so
  // the cursor brackets and the equipped ring, which paint just outside a
  // tile, are not clipped at the grid's edges; the grid itself is pulled up
  // and left by that pad so the first tile still sits flush with the kicker.
  readonly property real pad: Style.space(6)
  readonly property real cardWidth: Style.space(150)
  readonly property real cardHeight: Style.space(112)
  readonly property real captionHeight: Style.space(38)
  implicitWidth: columns * cardWidth + (columns - 1) * 2 * pad

  GridView {
    id: grid
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    anchors.leftMargin: -root.pad
    anchors.topMargin: -root.pad
    width: root.columns * cellWidth
    cellWidth: root.cardWidth + 2 * root.pad
    cellHeight: root.cardHeight + 2 * root.pad
    clip: true
    model: root.items
    currentIndex: root.selected
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)

    delegate: Item {
      id: cell
      required property int index
      required property var modelData
      width: grid.cellWidth
      height: grid.cellHeight

      readonly property bool isEquipped: modelData.equipped === true
      readonly property bool isCursor: cell.index === root.selected
      readonly property bool isStaged: root.stagedId === String(modelData.id)

      // The ring: the fitting the desktop is actually wearing.
      TechFrame {
        anchors.fill: card
        anchors.margins: -Style.space(4)
        chamfer: Style.space(9)
        cuts: ["tr", "bl"]
        fill: "transparent"
        stroke: root.good
        strokeWidth: 1.5
        visible: cell.isEquipped
      }

      TechFrame {
        id: card
        anchors { fill: parent; margins: root.pad }
        chamfer: Style.space(6)
        cuts: ["tr", "bl"]
        fill: cell.isCursor
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.selectedFillAlpha)
          : (root.host ? root.host.paneBgFocused : "transparent")
        stroke: cell.isCursor || cell.isStaged ? root.accent
          : mouse.containsMouse ? root.fg
          : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
        strokeWidth: 1
        brackets: cell.isCursor
        bracketColor: root.accent
        bracketLength: Style.space(9)
        bracketWidth: 2
        bracketInset: 2

        // Thumbnail: the loadout's theme preview, filling the card above
        // the caption.
        Item {
          id: thumb
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(4) }
          anchors.bottomMargin: 0
          height: parent.height - root.captionHeight - Style.space(4)
          clip: true

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          }
          Image {
            anchors.fill: parent
            source: cell.modelData.preview ? "file://" + cell.modelData.preview : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: 320
          }
        }

        Column {
          anchors {
            left: parent.left; leftMargin: Style.space(8)
            right: parent.right; rightMargin: Style.space(8)
            bottom: parent.bottom; bottomMargin: Style.space(6)
          }
          spacing: Style.space(1)
          Text {
            width: parent.width
            text: cell.modelData.name || ""
            color: cell.isCursor || cell.isStaged ? root.accent : root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: cell.isStaged ? "FITTED" : cell.isEquipped ? "EQUIPPED" : (cell.modelData.meta || "")
            color: cell.isStaged ? root.warn : cell.isEquipped ? root.good : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: cell.isStaged || cell.isEquipped ? 1.5 : 0
            elide: Text.ElideRight
          }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.host) root.host.bootPick(cell.modelData.id)
        }

        // Edit: over the thumbnail's other corner, shown with the cross.
        Rectangle {
          visible: deleteButton.visible
          anchors { left: parent.left; top: parent.top; leftMargin: Style.space(7); topMargin: Style.space(7) }
          width: editText.implicitWidth + Style.space(12)
          height: Style.space(20)
          radius: Style.space(3)
          color: root.host ? Qt.rgba(root.host.backdrop.r, root.host.backdrop.g, root.host.backdrop.b, 0.78) : "transparent"
          Text {
            id: editText
            anchors.centerIn: parent
            text: "EDIT"
            color: editMouse.containsMouse ? root.accent : root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }
          MouseArea {
            id: editMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.host) root.host.bootEdit(cell.modelData.id)
          }
        }

        // Delete: a small cross over the thumbnail's corner, shown while the
        // pointer or the cursor is on the card. Asks before it does anything.
        Rectangle {
          id: deleteButton
          visible: mouse.containsMouse || cell.isCursor || deleteMouse.containsMouse || editMouse.containsMouse
          anchors { right: parent.right; top: parent.top; rightMargin: Style.space(7); topMargin: Style.space(7) }
          width: Style.space(20)
          height: width
          radius: Style.space(3)
          color: root.host ? Qt.rgba(root.host.backdrop.r, root.host.backdrop.g, root.host.backdrop.b, 0.78) : "transparent"
          Text {
            anchors.centerIn: parent
            text: "󰅖"
            color: deleteMouse.containsMouse ? root.warn : root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.caption + 2
          }
          MouseArea {
            id: deleteMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.host) root.host.requestDeleteLoadout(cell.modelData.id)
          }
        }
      }
    }
  }

  // Nothing saved yet: say so where the first tile would be, and say how to fix it.
  Text {
    visible: root.savedCount === 0
    anchors { left: parent.left; right: parent.right; top: parent.top }
    text: "No saved loadouts yet. Equip, fit a few slots, and press S to record the fitting here."
    color: root.muted
    font.family: root.uiFont
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
