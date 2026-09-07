pragma ComponentBehavior: Bound

import QtQuick

// One equipment slot: a label, a count, and the inventory row for that slot.
// Mirrors the reference layout where each slot lists what you own and marks
// what is worn.
Item {
  id: root

  property var slotDef: ({})
  property var host: null
  property bool alignRight: false

  readonly property var items: host ? host.itemsFor(slotDef.id) : []
  readonly property int selected: host ? host.selectedIndexFor(slotDef.id) : 0
  readonly property bool focused: host && host.currentSlot && host.currentSlot.id === slotDef.id
  readonly property bool staged: host && host.staged[slotDef.id] ? true : false

  readonly property color fg: host ? host.previewFg : "#cacccc"
  readonly property color muted: host ? host.previewMuted : "#707880"
  readonly property color accent: host ? host.previewAccent : "#7aa2f7"
  readonly property string uiFont: host ? host.uiFont : "monospace"

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: 8

    // ---- Label row ----------------------------------------------------
    Item {
      width: parent.width
      height: 34

      Column {
        anchors.left: root.alignRight ? undefined : parent.left
        anchors.right: root.alignRight ? parent.right : undefined
        spacing: 2

        Text {
          anchors.right: root.alignRight ? parent.right : undefined
          text: root.slotDef.label || ""
          color: root.focused ? root.accent : root.fg
          font.family: root.uiFont
          font.pixelSize: 15
          font.bold: true
          font.letterSpacing: 3
        }

        Text {
          anchors.right: root.alignRight ? parent.right : undefined
          text: root.items.length === 0
            ? "NONE AVAILABLE"
            : root.items.length + (root.staged ? " AVAILABLE · STAGED" : " AVAILABLE")
          color: root.staged ? root.host.pc("yellow", "#f9e2af") : root.muted
          font.family: root.uiFont
          font.pixelSize: 10
          font.letterSpacing: 1
        }
      }
    }

    // ---- Inventory row --------------------------------------------------
    Rectangle {
      width: parent.width
      height: 62
      color: root.host ? (root.focused ? root.host.paneBgFocused : root.host.paneBg) : "transparent"
      radius: 4
      border.width: root.focused ? 2 : 1
      border.color: root.focused
        ? root.accent
        : (root.host ? root.host.paneBorder : root.fg)

      ListView {
        id: list
        anchors { fill: parent; margins: 6 }
        orientation: ListView.Horizontal
        spacing: 6
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

          width: 46
          height: list.height

          readonly property bool isSelected: cell.index === root.selected
          readonly property bool isEquipped: cell.modelData.equipped === true

          Rectangle {
            anchors.fill: parent
            radius: 3
            color: cell.isSelected
              ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
              : (root.host ? root.host.paneBgFocused : "transparent")
            border.width: cell.isSelected ? 2 : (cell.isEquipped ? 1 : 0)
            border.color: cell.isSelected ? root.accent : root.fg
          }

          // Theme items own a preview image, backgrounds are their own
          // thumbnail; everything else falls back to initials.
          readonly property string thumbnail: {
            if (cell.modelData.preview) return "file://" + cell.modelData.preview
            if (cell.modelData.path && root.slotDef.id === "background")
              return "file://" + cell.modelData.path
            return ""
          }

          Image {
            anchors { fill: parent; margins: 4 }
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

          Text {
            anchors.centerIn: parent
            visible: cell.thumbnail.length === 0
            text: cell.isFont ? "Aa" : (cell.modelData.name || "?").substring(0, 2).toUpperCase()
            color: root.fg
            font.family: cell.isFont ? cell.modelData.id : root.uiFont
            font.pixelSize: cell.isFont ? 17 : 13
            font.bold: !cell.isFont
          }

          // Equipped marker — the "EQUIPPED" tag from the reference, shrunk
          // to a corner pip so it survives at inventory-cell size.
          Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 3 }
            width: 6; height: 6; radius: 3
            color: root.host ? root.host.pc("green", "#a6e3a1") : "#a6e3a1"
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
        font.pixelSize: 14
      }
    }

    // ---- Selected item name ---------------------------------------------
    Text {
      width: parent.width
      horizontalAlignment: root.alignRight ? Text.AlignRight : Text.AlignLeft
      text: root.items.length > 0 && root.selected < root.items.length
        ? root.items[root.selected].name
        : ""
      color: root.fg
      font.family: root.uiFont
      font.pixelSize: 12
      elide: Text.ElideRight
    }
  }
}
