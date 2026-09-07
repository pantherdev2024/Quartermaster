pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// The saved loadouts, worn across the top of the screen: one small card per
// fitting, thumbnail and name, the equipped one ringed. Hovering a card
// previews it on the character, clicking selects it, ENTER equips it. The
// keyboard reaches the same row as the last stop of ↑ ↓.
Item {
  id: root

  property var host: null

  readonly property var items: host ? host.itemsFor("loadouts") : []
  readonly property int selected: host ? host.selectedIndexFor("loadouts") : 0
  readonly property bool focused: host ? host.onLoadouts : false
  readonly property string stagedId: host && host.staged ? String(host.staged["loadouts"] || "") : ""

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color warn: host ? host.warn : Color.urgent
  readonly property color good: host ? host.good : Color.accent
  readonly property color line: host ? host.line : Color.muted
  readonly property string uiFont: host ? host.uiFont : Style.font.menuFamily

  readonly property real cardHeight: Style.space(44)
  readonly property real cardWidth: Style.space(160)
  readonly property real newWidth: Style.space(96)

  implicitHeight: cardHeight

  ListView {
    id: list
    // Centred while the row fits, scrolling once it does not.
    width: Math.min(parent.width, contentWidth)
    anchors.horizontalCenter: parent.horizontalCenter
    height: parent.height
    orientation: ListView.Horizontal
    spacing: Style.space(10)
    clip: true
    model: root.items
    currentIndex: root.selected
    highlightMoveDuration: 180
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

    delegate: Item {
      id: card
      required property int index
      required property var modelData

      readonly property bool isNew: modelData.isNew === true
      readonly property bool isEquipped: modelData.equipped === true
      readonly property bool isCursor: root.focused && card.index === root.selected
      readonly property bool isStaged: !card.isNew && root.stagedId === String(modelData.id)

      width: isNew ? root.newWidth : root.cardWidth
      height: root.cardHeight

      // The ring: the fitting the desktop is actually wearing.
      TechFrame {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        chamfer: Style.space(9)
        cuts: ["tr", "bl"]
        fill: "transparent"
        stroke: root.good
        strokeWidth: 1.5
        visible: card.isEquipped
      }

      TechFrame {
        anchors.fill: parent
        chamfer: Style.space(6)
        cuts: ["tr", "bl"]
        fill: card.isCursor
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, Style.selectedFillAlpha)
          : (root.host ? root.host.paneBgFocused : "transparent")
        stroke: card.isCursor || card.isStaged ? root.accent
          : mouse.containsMouse ? root.fg
          : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
        strokeWidth: 1
        dashed: card.isNew
        brackets: card.isCursor
        bracketColor: root.accent
        bracketLength: Style.space(9)
        bracketWidth: 2
        bracketInset: 2

        // Thumbnail: the loadout's theme preview.
        Item {
          id: thumb
          visible: !card.isNew
          anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: Style.space(5) }
          width: height

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
          }
          Image {
            anchors.fill: parent
            source: card.modelData.preview ? "file://" + card.modelData.preview : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
            sourceSize.width: 96
          }
        }

        Column {
          visible: !card.isNew
          anchors {
            left: thumb.right; leftMargin: Style.space(8)
            right: parent.right; rightMargin: Style.space(8)
            verticalCenter: parent.verticalCenter
          }
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: card.modelData.name || ""
            color: card.isCursor || card.isStaged ? root.accent : root.fg
            font.family: root.uiFont
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: card.isStaged ? "FITTED" : card.isEquipped ? "EQUIPPED" : (card.modelData.meta || "")
            color: card.isStaged ? root.warn : card.isEquipped ? root.good : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.letterSpacing: card.isStaged || card.isEquipped ? 1.5 : 0
            elide: Text.ElideRight
          }
        }

        Row {
          visible: card.isNew
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text {
            text: "󰐕"
            color: card.isCursor ? root.accent : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "NEW"
            color: card.isCursor ? root.accent : root.muted
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 2
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: if (!card.isNew && root.host) root.host.hoverLoadout(card.modelData.id)
          onExited: if (!card.isNew && root.host) root.host.unhoverLoadout()
          onClicked: if (root.host) root.host.pickLoadout(card.modelData.id)
        }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.items.length === 0
    text: "NO LOADOUTS"
    color: root.muted
    font.family: root.uiFont
    font.pixelSize: Style.font.caption
    font.letterSpacing: 2
  }
}
