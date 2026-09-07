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
  // The dock's NEW cell is an action, not stock.
  readonly property int stockCount: items.filter(function(i) { return !i.isNew }).length
  readonly property int selected: host ? host.selectedIndexFor(slotDef.id) : 0
  readonly property bool focused: host && host.currentSlot && host.currentSlot.id === slotDef.id
  // Fitted: the slot holds a change that has not been deployed.
  readonly property bool staged: host && host.staged[slotDef.id] && host.staged[slotDef.id] !== "__new" ? true : false
  readonly property string fittedId: host && host.staged[slotDef.id] ? String(host.staged[slotDef.id]) : ""

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property int cellSize: host ? host.cellSize : Style.space(64)
  // The row never grows past the host's cell cap, even in a wider column:
  // past that the cursor cycles rather than the row stretching.
  readonly property real rowWidth: host ? Math.min(width, host.slotRowWidth) : width
  // A multi-select slot: cells are on/off, the cursor stages nothing.
  readonly property bool multi: slotDef.multi === true
  readonly property int onCount: items.filter(function(i) { return i.on === true }).length

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: root.rowWidth
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
        text: root.stockCount === 0 ? "NONE"
          : (root.staged ? "FITTED · " : "")
            + (root.multi ? String(root.onCount).padStart(2, "0") + " / " : "")
            + String(root.stockCount).padStart(2, "0")
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

        // Keep the equipped/staged cell in view. Now that a row shows six
        // cells at most, a slot the cursor has never visited can still open
        // scrolled away from its equipped cell, so re-reveal whenever the
        // row's geometry or its stock changes and not only as the cursor
        // moves. callLater so the view has laid the cells out first.
        function reveal() { positionViewAtIndex(currentIndex, ListView.Contain) }
        onCurrentIndexChanged: Qt.callLater(reveal)
        onWidthChanged: Qt.callLater(reveal)
        onCountChanged: Qt.callLater(reveal)
        Component.onCompleted: Qt.callLater(reveal)

        delegate: Item {
          id: cell
          required property int index
          required property var modelData

          // Dock cards are wide: thumbnail plus a name and a line of meta.
          readonly property bool wide: root.slotDef.wide === true
          readonly property bool isNew: cell.modelData.isNew === true
          // Multi cells: off ones are dim and dashed, and the first cell of
          // each bar section (and of the bench) carries a divider.
          readonly property bool off: root.multi && cell.modelData.on !== true
          readonly property bool changed: root.multi && cell.modelData.changed === true
          readonly property real lead: root.multi && cell.modelData.sectionStart === true ? Style.space(18) : 0

          width: (cell.wide ? Style.space(200) : root.cellSize) + cell.lead
          height: list.height

          readonly property bool isSelected: cell.index === root.selected
          readonly property bool isEquipped: cell.modelData.equipped === true
          readonly property bool isFitted: !root.multi && root.fittedId !== "" && String(cell.modelData.id) === root.fittedId

          Item {
            visible: cell.lead > 0
            width: cell.lead
            height: parent.height

            Rectangle {
              anchors { left: parent.left; leftMargin: Style.space(4); top: parent.top; bottom: parent.bottom }
              width: 1
              color: root.line
            }
            Text {
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: Style.space(2)
              rotation: -90
              text: cell.modelData.section === "left" ? "LEFT"
                : cell.modelData.section === "center" ? "CENTER"
                : cell.modelData.section === "right" ? "RIGHT" : "BENCH"
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption - 2
              font.letterSpacing: 1.5
            }
          }

          TechFrame {
            anchors.fill: parent
            anchors.leftMargin: cell.lead
            chamfer: Style.space(6)
            cuts: ["tr", "bl"]
            fill: cell.isSelected
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.selectedFillAlpha)
              : (root.host ? root.host.paneBgFocused : "transparent")
            stroke: cell.isSelected ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
            strokeWidth: 1
            dashed: cell.isNew || cell.off
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
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: Style.space(5) }
            anchors.leftMargin: Style.space(5) + cell.lead
            width: cell.wide ? height : parent.width - Style.space(10)
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

          // Wide card text: name and meta beside the thumbnail.
          Column {
            visible: cell.wide && !cell.isNew
            anchors {
              left: parent.left; leftMargin: (cell.thumbnail.length > 0 ? parent.height : Style.space(5)) + Style.space(6)
              right: parent.right; rightMargin: Style.space(10)
              verticalCenter: parent.verticalCenter
            }
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: cell.modelData.name || ""
              color: cell.isSelected ? root.accent : root.fg
              font.family: root.uiFont
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: cell.modelData.meta || ""
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Row {
            visible: cell.isNew
            anchors.centerIn: parent
            spacing: Style.space(8)
            Text {
              text: "󰐕"
              color: cell.isSelected ? root.accent : root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.iconLarge
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: "NEW LOADOUT"
              color: cell.isSelected ? root.accent : root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 2
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: cell.lead / 2
            opacity: cell.off ? 0.45 : 1
            visible: cell.thumbnail.length === 0 && !cell.wide
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
            anchors.leftMargin: Style.space(6) + cell.lead
            anchors.rightMargin: Style.space(3)
            height: Style.space(3)
            color: cell.changed || cell.isFitted ? root.warn : root.good
            visible: root.multi ? (cell.modelData.on === true || cell.changed) : (cell.isEquipped || cell.isFitted)
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (!root.host) return
              root.host.slotIndex = root.host.slotDefs.findIndex(function(d) {
                return d.id === root.slotDef.id
              })
              if (root.multi) root.host.modsCursor = cell.index
              else root.host.previewItem(cell.modelData.id)
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
