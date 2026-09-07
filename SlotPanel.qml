pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// One equipment slot: a header with the slot's glyph, label and count, then
// the inventory row for that slot. Left-aligned only: every slot now lives in
// the left column, mirroring the reference where the slot list stacks down
// one side and the character stands on the other.
Item {
  id: root

  property var slotDef: ({})
  property var host: null

  readonly property var items: host ? host.itemsFor(slotDef.id) : []
  readonly property int selected: host ? host.selectedIndexFor(slotDef.id) : 0
  readonly property bool focused: host && host.currentSlot && host.currentSlot.id === slotDef.id
  readonly property bool staged: host && host.staged[slotDef.id] ? true : false

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property int cellSize: Style.space(46)

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing.sm

    // ---- Header row ----------------------------------------------------
    Item {
      width: parent.width
      height: Math.max(Style.space(30), labelCol.implicitHeight)

      Text {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.iconLarge + Style.space(4)
        text: root.slotDef.icon || ""
        color: root.focused ? root.accent : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.iconLarge
      }

      Column {
        id: labelCol
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          text: root.slotDef.label || ""
          color: root.focused ? root.accent : root.fg
          font.family: root.uiFont
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 2
        }

        Text {
          text: root.items.length === 0
            ? "NONE AVAILABLE"
            : root.items.length + (root.staged ? " AVAILABLE · STAGED" : " AVAILABLE")
          color: root.staged ? root.warn : root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }

      // Name of whatever is selected, pinned to the right of the header so
      // the row below can be pure thumbnails.
      Text {
        anchors.right: parent.right
        anchors.left: labelCol.right
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: root.items.length > 0 && root.selected < root.items.length
          ? root.items[root.selected].name
          : ""
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: Style.font.body
        elide: Text.ElideLeft
      }
    }

    // ---- Inventory row --------------------------------------------------
    BorderSurface {
      width: parent.width
      height: root.cellSize + Style.space(12)
      color: root.host ? (root.focused ? root.host.paneBgFocused : root.host.paneBg) : "transparent"
      radius: Style.cornerRadius
      borderSpec: root.focused
        ? Border.flat(root.accent, 2)
        : Border.controlSpec("normal", root.fg, root.accent)

      ListView {
        id: list
        anchors { fill: parent; margins: Style.space(6) }
        orientation: ListView.Horizontal
        spacing: Style.space(6)
        clip: true
        model: root.items
        currentIndex: root.selected
        highlightMoveDuration: 180
        // Keep the equipped/staged cell in view as the cursor moves.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
          id: cell
          required property int index
          required property var modelData

          width: root.cellSize
          height: list.height

          readonly property bool isSelected: cell.index === root.selected
          readonly property bool isEquipped: cell.modelData.equipped === true

          Rectangle {
            anchors.fill: parent
            radius: Math.max(0, Style.cornerRadius - 1)
            color: cell.isSelected
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.selectedFillAlpha)
              : (root.host ? root.host.paneBgFocused : "transparent")
            border.width: cell.isSelected ? 2 : (cell.isEquipped ? 1 : 0)
            border.color: cell.isSelected ? root.accent : root.fg
          }

          // Theme items own a preview image, backgrounds are their own
          // thumbnail; everything else falls back to a glyph, a short tag,
          // or the name's initials.
          readonly property string thumbnail: {
            if (cell.modelData.preview) return "file://" + cell.modelData.preview
            if (cell.modelData.path && root.slotDef.id === "background")
              return "file://" + cell.modelData.path
            return ""
          }

          Image {
            anchors { fill: parent; margins: Style.space(4) }
            source: cell.thumbnail
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: 92
          }

          // A font item is its own best thumbnail — render the specimen in
          // the face itself rather than in the UI font.
          readonly property bool isFont: root.slotDef.id === "font"
          readonly property string glyph: cell.modelData.icon || ""
          readonly property string tag: cell.modelData.short || ""

          Text {
            anchors.centerIn: parent
            visible: cell.thumbnail.length === 0
            text: cell.isFont ? "Aa"
              : cell.glyph ? cell.glyph
              : cell.tag ? cell.tag
              : (cell.modelData.name || "?").substring(0, 2).toUpperCase()
            color: root.fg
            font.family: cell.isFont ? cell.modelData.id : root.uiFont
            font.pixelSize: cell.isFont ? Style.font.iconLarge
              : cell.glyph ? Style.font.display
              : cell.tag.length > 3 ? Style.font.caption
              : Style.font.subtitle
            font.bold: !cell.isFont && !cell.glyph
          }

          // Equipped marker — the "EQUIPPED" tag from the reference, shrunk
          // to a corner pip so it survives at inventory-cell size.
          Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 3 }
            width: 6; height: 6; radius: 3
            color: root.host ? root.host.good : root.accent
            visible: cell.isEquipped
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (!root.host) return
              root.host.slotIndex = root.host.slotDefs.findIndex(function(d) {
                return d.id === root.slotDef.id
              })
              root.host.stageCurrent(cell.modelData.id)
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.items.length === 0
        text: "—"
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.title
      }
    }
  }
}
