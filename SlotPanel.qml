pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// One equipment slot: a header rule with the slot's glyph, label and count,
// then the inventory row — an angled frame with a heavy accent edge when the
// cursor is on it. The selected cell wears corner brackets; an equipped cell
// carries a green tag bar along its foot.
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
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property int cellSize: Style.space(64)

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(6)

    // ---- Header rule ---------------------------------------------------
    Item {
      width: parent.width
      height: Style.space(22)

      Text {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.font.icon + Style.space(6)
        text: root.slotDef.icon || ""
        color: root.focused ? root.accent : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.icon
      }

      Text {
        id: label
        anchors.left: glyph.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.slotDef.label || ""
        color: root.focused ? root.accent : root.fg
        font.family: root.uiFont
        font.pixelSize: Style.font.body
        font.bold: true
        font.letterSpacing: 2.5
      }

      // The rule runs from the label to the count, thicker under the cursor.
      Rectangle {
        anchors.left: label.right
        anchors.leftMargin: Style.space(10)
        anchors.right: count.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: root.focused ? root.accent : root.line
        opacity: root.focused ? 0.8 : 1
      }

      Text {
        id: count
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.items.length === 0 ? "NONE"
          : (root.staged ? "STAGED · " : "") + String(root.items.length).padStart(2, "0")
        color: root.staged ? root.warn : root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.bold: root.staged
        font.letterSpacing: 1.5
      }
    }

    // ---- Inventory row --------------------------------------------------
    TechFrame {
      width: parent.width
      height: root.cellSize + Style.space(14)
      chamfer: Style.space(10)
      fill: root.host ? (root.focused ? root.host.paneBgFocused : root.host.paneBg) : "transparent"
      stroke: root.focused ? root.accent : root.line
      strokeWidth: 1
      edge: "left"
      edgeColor: root.focused ? root.accent : root.line
      edgeWidth: root.focused ? Style.space(4) : Style.space(2)

      ListView {
        id: list
        anchors { fill: parent; margins: Style.space(7) }
        anchors.leftMargin: Style.space(12)
        orientation: ListView.Horizontal
        spacing: Style.space(8)
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

          TechFrame {
            anchors.fill: parent
            chamfer: Style.space(6)
            cuts: ["tr", "bl"]
            fill: cell.isSelected
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.selectedFillAlpha)
              : (root.host ? root.host.paneBgFocused : "transparent")
            stroke: cell.isSelected ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
            strokeWidth: 1
            brackets: cell.isSelected
            bracketColor: root.accent
            bracketLength: Style.space(9)
            bracketWidth: 2
            bracketInset: 2
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
            anchors { fill: parent; margins: Style.space(5) }
            source: cell.thumbnail
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: 128
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
            color: cell.isSelected ? root.accent : root.fg
            font.family: cell.isFont ? cell.modelData.id : root.uiFont
            font.pixelSize: cell.isFont ? Style.font.iconLarge
              : cell.glyph ? Style.font.display
              : cell.tag.length > 3 ? Style.font.caption
              : Style.font.subtitle
            font.bold: !cell.isFont && !cell.glyph
          }

          // Equipped tag bar — the "EQUIPPED" strip from the reference,
          // shrunk to a coloured foot so it survives at cell size.
          Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(3)
            height: Style.space(3)
            color: root.good
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
        text: "NO COMPATIBLE ITEMS"
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2
      }
    }
  }
}
