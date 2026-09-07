pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

// The character sheet: one horizontal band of live system metrics along the
// bottom of the screen. Sections run left to right — identity, headline
// tiles, CPU/memory history, per-core heat, network throughput, capacity —
// each with a caption heading and its live summary on the right, the way the
// shell's panels do it. Charts flex; everything else has a fixed width, and
// the core strip drops out first when the screen is narrow.
//
// Everything is drawn in the accent family (accent, a darker second hue, a
// warning tint mixed toward urgent) so charted values never read as text and
// nothing depends on palette keys a theme may not define.
BorderSurface {
  id: root

  property var host: null

  readonly property var stats: (host && host.stats) ? host.stats : ({})
  readonly property var cpu: stats.cpu || ({})
  readonly property var memory: stats.memory || ({})
  readonly property var swap: stats.swap || ({})
  readonly property var disk: stats.disk || ({})
  readonly property var network: stats.network || ({})
  readonly property var gpu: stats.gpu || ({})
  readonly property var perCore: cpu.perCore || []
  readonly property bool hasGpu: gpu.percent !== undefined && gpu.percent >= 0

  readonly property color fg: host ? host.fg : Color.foreground
  readonly property color muted: host ? host.muted : Color.muted
  readonly property color accent: host ? host.accent : Color.accent
  readonly property color urgent: host ? host.warn : Color.urgent
  readonly property string fontFamily: host ? host.uiFont : Style.font.family
  readonly property color trackColor: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color chartGrid: Qt.rgba(fg.r, fg.g, fg.b, 0.18)
  readonly property color secondary: Qt.darker(accent, 1.5)
  readonly property color warningColor: Qt.tint(accent, Qt.rgba(urgent.r, urgent.g, urgent.b, 0.6))
  readonly property real warnAt: 80
  readonly property real critAt: 95

  color: host ? host.paneBg : "transparent"
  radius: Style.cornerRadius
  borderSpec: Border.controlSpec("normal", fg, accent)
  padding: Style.space(14)
  clip: true

  // ---- Geometry ----------------------------------------------------------
  // Below `compact` the strip sheds what it can spare: the core heat strip
  // goes, temperature folds into the CPU tile, the hero and gutters tighten.
  // The two charts split whatever is left and never drop below a floor
  // where their labels would collide.
  readonly property real innerWidth: width - contentLeftInset - contentRightInset
  readonly property bool compact: innerWidth < Style.space(1380)
  readonly property real gap: Style.space(compact ? 18 : 28)
  readonly property real heroWidth: Style.space(compact ? 160 : 190)
  readonly property bool showTemp: !compact
  readonly property int tileCount: (showTemp ? 3 : 2) + (hasGpu ? 1 : 0)
  readonly property real tileWidth: Style.space(112)
  readonly property real tilesWidth: tileCount * tileWidth + (tileCount - 1) * Style.space(8)
  readonly property real coresWidth: compact ? 0 : Style.space(196)
  readonly property real capacityWidth: Style.space(compact ? 220 : 236)
  readonly property int sectionCount: compact ? 5 : 6
  readonly property real flexWidth: Math.max(Style.space(320),
    innerWidth - heroWidth - tilesWidth - coresWidth - capacityWidth - gap * (sectionCount - 1))
  readonly property real netWidth: Math.max(Style.space(150), flexWidth * 0.45)
  readonly property real historyWidth: flexWidth - netWidth

  // ---- Formatting --------------------------------------------------------
  function percent(value) {
    return isFinite(value) && value >= 0 ? Math.round(value) + "%" : "—"
  }

  function formatBytes(value) {
    var amount = Number(value)
    if (!isFinite(amount) || amount < 0) return "—"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var index = 0
    while (amount >= 1024 && index < units.length - 1) {
      amount /= 1024
      index++
    }
    var digits = index >= 3 ? 1 : (amount >= 100 ? 0 : 1)
    return amount.toFixed(digits) + " " + units[index]
  }

  // "8.3 / 14.8 GiB": both numbers in the total's unit, named once, so the
  // pair fits a tile. Falls back to two full readouts when the units differ.
  function formatPairKb(usedKb, totalKb) {
    if (!(totalKb > 0)) return "—"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var total = totalKb * 1024
    var index = 0
    while (total >= 1024 && index < units.length - 1) { total /= 1024; index++ }
    var used = usedKb * 1024 / Math.pow(1024, index)
    var digits = index >= 3 ? 1 : (total >= 100 ? 0 : 1)
    return used.toFixed(digits) + " / " + total.toFixed(digits) + " " + units[index]
  }

  function formatRate(value) {
    return isFinite(value) && value >= 0 ? formatBytes(value) + "/s" : "—"
  }

  function formatUptime(seconds) {
    var totalMinutes = Math.floor(Number(seconds) / 60)
    if (!isFinite(totalMinutes) || totalMinutes < 0) return "—"
    var days = Math.floor(totalMinutes / 1440)
    var hours = Math.floor((totalMinutes % 1440) / 60)
    var minutes = totalMinutes % 60
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    return minutes + "m"
  }

  function loadText() {
    function one(v) { return isFinite(v) && v >= 0 ? Number(v).toFixed(2) : "—" }
    return one(cpu.load) + " / " + one(cpu.load5) + " / " + one(cpu.load15)
  }

  function levelColor(value, warn, crit) {
    if (!isFinite(value) || value < 0) return root.muted
    if (value >= crit) return root.urgent
    if (value >= warn) return root.warningColor
    return root.accent
  }

  function peakOf(list) {
    var peak = 0
    for (var i = 0; i < list.length; i++) if (list[i].value > peak) peak = list[i].value
    return peak
  }

  readonly property real coreMaximum: {
    var m = 0
    for (var i = 0; i < perCore.length; i++) if (perCore[i] > m) m = perCore[i]
    return m
  }
  readonly property real networkPeak: host
    ? Math.max(peakOf(host.rxHistory), peakOf(host.txHistory)) : 0

  // Package temperature only spans a useful band; drawing 57°C as 57% of a
  // meter makes a cold chip look half-loaded. Anchor the scale at 30°C.
  function temperatureMeter(t) {
    if (!(t >= 0)) return -1
    return Math.max(0, Math.min(100, (t - 30) * 100 / 70))
  }

  // ---- Layout ------------------------------------------------------------
  Row {
    id: sections
    anchors.fill: parent
    anchors.topMargin: root.contentTopInset
    anchors.bottomMargin: root.contentBottomInset
    anchors.leftMargin: root.contentLeftInset
    anchors.rightMargin: root.contentRightInset
    spacing: 0

    // -- Identity: host, uptime, load ------------------------------------
    Item {
      width: root.heroWidth
      height: parent.height

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Row {
          spacing: Style.space(8)
          Text {
            text: "󰻠"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.stats.hostname || "SYSTEM"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          text: "UP " + root.formatUptime(root.stats.uptimeSeconds).toUpperCase()
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        Text {
          text: "LOAD " + root.loadText()
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }
      }
    }

    Separator {}

    // -- Headline tiles ----------------------------------------------------
    Row {
      width: root.tilesWidth
      height: parent.height
      spacing: Style.space(8)

      StatTile {
        width: root.tileWidth; height: parent.height
        title: "CPU"
        value: root.percent(root.cpu.percent)
        // Compact folds the temperature in here, so the thread count shortens
        // to make room: "16 thr · 39°C" instead of eliding.
        detail: !root.showTemp && root.cpu.temp >= 0
          ? (root.cpu.cores || "—") + " thr · " + Math.round(root.cpu.temp) + "°C"
          : (root.cpu.cores ? root.cpu.cores + " threads" : "—")
        meter: root.cpu.percent !== undefined ? root.cpu.percent : -1
        meterColor: root.levelColor(root.cpu.percent, root.warnAt, root.critAt)
        alarming: root.cpu.percent >= root.critAt
      }

      StatTile {
        width: root.tileWidth; height: parent.height
        title: "MEMORY"
        value: root.percent(root.memory.percent)
        detail: root.formatPairKb(root.memory.usedKb, root.memory.totalKb)
        meter: root.memory.percent !== undefined ? root.memory.percent : -1
        meterColor: root.levelColor(root.memory.percent, root.warnAt, root.critAt)
        alarming: root.memory.percent >= root.critAt
      }

      StatTile {
        visible: root.showTemp
        width: root.tileWidth; height: parent.height
        title: "TEMP"
        value: root.cpu.temp >= 0 ? Math.round(root.cpu.temp) + "°C" : "—"
        detail: root.cpu.temp >= 95 ? "Critical" : (root.cpu.temp >= 85 ? "Hot" : (root.cpu.temp >= 0 ? "Normal" : "No sensor"))
        meter: root.temperatureMeter(root.cpu.temp)
        meterColor: root.levelColor(root.cpu.temp, 85, 95)
        alarming: root.cpu.temp >= 95
      }

      StatTile {
        visible: root.hasGpu
        width: root.tileWidth; height: parent.height
        title: "GPU"
        value: root.percent(root.gpu.percent)
        detail: root.gpu.temp >= 0 ? Math.round(root.gpu.temp) + "°C" : (root.gpu.name || "—")
        meter: root.gpu.percent !== undefined ? root.gpu.percent : -1
        meterColor: root.levelColor(root.gpu.percent, root.warnAt, root.critAt)
        alarming: root.gpu.percent >= root.critAt
      }
    }

    Separator {}

    // -- CPU & memory history ---------------------------------------------
    Section {
      width: root.historyWidth
      height: parent.height
      title: "CPU & MEMORY"
      value: "2 MIN"

      Item {
        anchors.fill: parent

        Sparkline {
          anchors.fill: parent
          points: root.host ? root.host.cpuHistory : []
          lineColor: root.accent
          fillColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
          gridColor: root.chartGrid
          gridLevels: [0.25, 0.5, 0.75]
          fixedMaximum: 100
        }

        Sparkline {
          anchors.fill: parent
          points: root.host ? root.host.memHistory : []
          lineColor: root.secondary
          fillColor: "transparent"
          dashed: true
          lineWidth: 1.2
          fixedMaximum: 100
        }

        // The scale is pinned at 100%, so say so — otherwise an idle
        // machine just looks like an empty box.
        Text {
          anchors.left: parent.left
          anchors.top: parent.top
          text: "100%"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.top: parent.top
          anchors.right: parent.right
          spacing: Style.space(8)
          LegendDot { colorValue: root.accent; label: "CPU" }
          LegendDot { colorValue: root.secondary; label: "RAM" }
        }
      }
    }

    Separator { visible: !root.compact }

    // -- Per-thread heat ---------------------------------------------------
    Section {
      visible: !root.compact
      width: root.coresWidth
      height: parent.height
      title: "CORES"
      value: root.perCore.length > 0 ? "PEAK " + root.percent(root.coreMaximum) : ""

      Grid {
        id: coreGrid
        anchors.fill: parent
        readonly property int count: root.perCore.length
        rows: count <= 8 ? 2 : 4
        columns: count > 0 ? Math.ceil(count / rows) : 1
        spacing: Style.space(3)
        readonly property real cellWidth: (width - spacing * (columns - 1)) / Math.max(1, columns)
        readonly property real cellHeight: (height - spacing * (rows - 1)) / Math.max(1, rows)
        // Numbers only survive down to about four characters; past that the
        // tint carries the reading on its own.
        readonly property bool showValues: cellWidth >= Style.space(30)

        Repeater {
          model: root.perCore

          Rectangle {
            id: coreCell
            required property var modelData
            required property int index
            readonly property real load: Math.max(0, Math.min(100, Number(modelData))) / 100

            width: coreGrid.cellWidth
            height: coreGrid.cellHeight
            radius: Style.cornerRadius
            color: root.trackColor

            // Heat, not a bar: a 5%-loaded core drawn as a bar is a 1px
            // sliver that reads as an artifact, while a tint stays legible.
            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: root.levelColor(Number(coreCell.modelData), root.warnAt, root.critAt)
              opacity: 0.12 + 0.68 * coreCell.load
            }

            Text {
              anchors.centerIn: parent
              visible: coreGrid.showValues
              text: root.percent(Number(coreCell.modelData))
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    Separator {}

    // -- Network: up above the axis, down below it -----------------------
    Section {
      width: root.netWidth
      height: parent.height
      title: root.network.name && !root.compact ? "NET · " + root.network.name : "NET"
      value: root.networkPeak > 0 ? "±" + root.formatRate(root.networkPeak) : ""

      Column {
        anchors.fill: parent
        spacing: Style.space(4)

        Item {
          width: parent.width
          height: Math.max(upRate.implicitHeight, downRate.implicitHeight)

          RateLabel {
            id: upRate
            anchors.left: parent.left
            glyph: "↑"
            glyphColor: root.accent
            value: root.network.txBytesPerSec
          }
          RateLabel {
            id: downRate
            anchors.right: parent.right
            glyph: "↓"
            glyphColor: root.secondary
            value: root.network.rxBytesPerSec
          }
        }

        Sparkline {
          width: parent.width
          height: parent.height - parent.spacing - upRate.implicitHeight
          points: root.host ? root.host.txHistory : []
          mirrorPoints: root.host ? root.host.rxHistory : []
          lineColor: root.accent
          mirrorLineColor: root.secondary
          gridColor: root.chartGrid
          fixedMaximum: root.networkPeak
        }
      }
    }

    Separator {}

    // -- Capacity and disk throughput -------------------------------------
    Section {
      width: root.capacityWidth
      height: parent.height
      title: "CAPACITY"
      value: root.disk.name ? String(root.disk.name).toUpperCase() : ""

      Column {
        anchors.fill: parent
        spacing: Style.space(6)

        CapacityRow {
          label: "Root filesystem"
          value: root.formatPairKb(root.disk.usedKb, root.disk.totalKb)
          percentValue: root.disk.percent !== undefined ? root.disk.percent : -1
        }

        CapacityRow {
          visible: root.swap.totalKb > 0
          label: "Swap"
          value: root.formatPairKb(root.swap.usedKb, root.swap.totalKb)
          percentValue: root.swap.percent !== undefined ? root.swap.percent : -1
        }

        Item {
          width: parent.width
          height: diskRates.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "DISK I/O"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Row {
            id: diskRates
            spacing: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            RateLabel { glyph: "W"; glyphColor: root.accent; value: root.disk.writeBytesPerSec }
            RateLabel { glyph: "R"; glyphColor: root.secondary; value: root.disk.readBytesPerSec }
          }
        }
      }
    }
  }

  // ---- Building blocks -----------------------------------------------------

  // Vertical hairline between sections, with the gutter on either side.
  component Separator: Item {
    width: root.gap
    height: parent ? parent.height : 0
    Rectangle {
      anchors.centerIn: parent
      width: 1
      height: parent.height
      color: root.trackColor
    }
  }

  // Caption heading on the left, its live summary on the right, content
  // filling whatever is left below.
  component Section: Item {
    id: section
    property string title: ""
    property string value: ""
    default property alias content: body.data

    Item {
      id: heading
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: Math.max(headingText.implicitHeight, valueText.implicitHeight)

      PanelSectionHeader {
        id: headingText
        text: section.title
        foreground: root.fg
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: valueText.visible ? valueText.left : parent.right
        anchors.rightMargin: valueText.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: valueText
        text: section.value
        visible: text !== ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.62)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
      }
    }

    Item {
      id: body
      anchors { left: parent.left; right: parent.right; top: heading.bottom; bottom: parent.bottom }
      anchors.topMargin: Style.space(8)
    }
  }

  component Meter: Rectangle {
    id: meter
    property real value: -1
    property real maximum: 100
    property color fillColor: root.accent

    height: Style.space(3)
    radius: height / 2
    color: root.trackColor

    Rectangle {
      width: meter.width * Math.max(0, Math.min(1, meter.value / meter.maximum))
      height: meter.height
      radius: meter.radius
      color: meter.fillColor
      Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
  }

  component StatTile: BorderSurface {
    id: tile
    property string title: ""
    property string value: "—"
    property string detail: ""
    property real meter: -1
    property color meterColor: root.accent
    property bool alarming: false

    radius: Style.cornerRadius
    color: Style.normalFillFor(root.fg, root.accent)
    borderSpec: Border.controlSpec("normal", root.fg, root.accent)

    Column {
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(9) }
      spacing: Style.space(2)

      Text {
        text: tile.title
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }
      Text {
        text: tile.value
        color: tile.alarming ? root.urgent : root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }
      Text {
        width: parent.width
        text: tile.detail
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Meter {
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.space(9) }
      value: tile.meter
      fillColor: tile.meterColor
    }
  }

  component LegendDot: Row {
    property color colorValue: "white"
    property string label: ""
    spacing: Style.space(4)
    Rectangle {
      width: Style.space(6); height: width; radius: width / 2
      color: parent.colorValue
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      text: parent.label
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // The arrow carries its series' colour so a value maps to a half of the
  // mirrored chart without a second legend.
  component RateLabel: Row {
    id: rate
    property string glyph: ""
    property color glyphColor: root.accent
    property real value: -1
    spacing: Style.space(4)
    Text {
      text: rate.glyph
      color: rate.glyphColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    Text {
      text: root.formatRate(rate.value)
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component CapacityRow: Column {
    id: capacity
    property string label: ""
    property string value: "—"
    property real percentValue: -1
    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Item {
      width: parent.width
      height: Math.max(capacityLabel.implicitHeight, capacityValue.implicitHeight)
      Text {
        id: capacityLabel
        text: capacity.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: capacityValue
        text: capacity.value
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: capacity.percentValue
      fillColor: root.levelColor(capacity.percentValue, root.warnAt, root.critAt)
    }
  }
}
