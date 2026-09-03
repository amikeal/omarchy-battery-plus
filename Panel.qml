import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "mikeal.battery-plus"
  ipcTarget: moduleName
  manageIpc: false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var b: service.battery
  readonly property var cpu: service.cpu
  readonly property var tlp: service.tlp
  readonly property var tweaks: service.tweaks

  readonly property bool showPercentage: setting("showPercentage", true) === true
  readonly property bool charging: b.status === "Charging"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (bar && bar.shell && bar.shell.updateEntryInline) bar.shell.updateEntryInline(moduleName, root.settings)
  }

  onOpenedChanged: {
    service.live = opened
    if (opened) {
      service.refresh()
      flick.contentY = 0
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  PowerService {
    id: service
    binDir: String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, "")
    pollInterval: Math.max(2000, Math.min(60000, (Number(root.setting("pollIntervalSec", 5)) || 5) * 1000))
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? (Model.batteryIcon(root.b.percent, root.b.status) + "  " + root.b.percent + "%")
      : Model.batteryIcon(root.b.percent, root.b.status)
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2.3 : 1)
    tooltipText: root.b.present
      ? ("Battery " + root.b.percent + "%  ·  " + Model.fmtWatts(root.b.watts)
         + (root.b.status === "Discharging" ? "  ·  " + Model.fmtDuration(root.b.minutes) + " left" : ""))
      : "Running on AC"
    onPressed: function(btn) {
      if (btn === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400), Style.space(440))
    contentHeight: Math.max(Style.space(160), Math.round(Math.min(
      availableCardHeight,
      Style.space(720),
      contentColumn.implicitHeight + verticalContentInset)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy) flick.contentY = Math.max(0, Math.min(
          Math.max(0, flick.contentHeight - flick.height),
          flick.contentY + dy * Style.space(48)))
      }
      onTextKey: function(t) { if (t === "r" || t === "R") service.refresh() }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: flick.width
          spacing: Style.space(14)

          // ---------- Hero ----------
          PanelHero {
            width: parent.width
            title: "Battery"
            meta: Model.modeLabel(root.b)
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: Model.batteryIcon(root.b.percent, root.b.status)
                color: root.charging ? root.fg : (root.b.percent <= 10 ? root.urgent : root.fg)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                Behavior on color { ColorAnimation { duration: 200 } }
              }
            }
            trailingControl: Component {
              Text {
                text: (root.b.percent || 0) + "%"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
            }
          }

          // ---------- Charge bar ----------
          Item {
            width: parent.width
            implicitHeight: Style.space(8)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: root.faint
            }
            Rectangle {
              id: chargeFill
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              radius: height / 2
              color: root.b.percent <= 10 && !root.charging ? root.urgent : root.fg
              width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.b.fraction)))

              Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 220 } }

              SequentialAnimation on opacity {
                running: root.charging && root.opened
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { from: 1.0; to: 0.5; duration: 950; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.5; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
              }
            }
          }

          // ---------- Stats grid ----------
          Grid {
            id: statsGrid
            width: parent.width
            columns: 2
            columnSpacing: Style.space(16)
            rowSpacing: Style.spacing.sm

            StatPair {
              label: root.b.status === "Charging" ? "To full" : "Time left"
              value: root.b.status === "Discharging" || root.b.status === "Charging"
                ? Model.fmtDuration(root.b.minutes) : "—"
            }
            StatPair { label: "Draw"; value: Model.fmtWatts(root.b.watts) }
            StatPair { label: "Health"; value: (root.b.health || 0) + "%" }
            StatPair { label: "Cycles"; value: String(root.b.cycles || "—") }
            StatPair {
              label: "Capacity"
              value: Number(root.b.whFull).toFixed(1) + "/" + Number(root.b.whDesign).toFixed(1) + " Wh"
            }
            StatPair {
              label: "Temp"
              value: (root.b.tempC ? root.b.tempC + "°" : "—")
                + (root.cpu.pkgTempC ? " · cpu " + root.cpu.pkgTempC + "°" : "")
            }
          }

          // ---------- Power-draw sparkline ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: sparkTitle.implicitHeight
              PanelSectionHeader {
                id: sparkTitle
                text: "POWER DRAW"
                foreground: root.fg
                fontFamily: root.fontFamily
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: sparkTitle.verticalCenter
                text: service.rapl.available ? Model.raplLabel(service.rapl)
                                             : Model.fmtWatts(root.b.watts)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            BorderSurface {
              width: parent.width
              height: Style.space(52)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.03)
              borderSpec: Border.flat(root.faint, Style.normalBorderWidth)
              radius: Style.cornerRadius

              Canvas {
                id: spark
                anchors.fill: parent
                anchors.margins: Style.space(4)
                property var pts: service.history
                property color line: root.fg
                onPtsChanged: requestPaint()
                onLineChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var n = pts.length
                  if (n < 2) return
                  var mx = 1
                  for (var i = 0; i < n; i++) mx = Math.max(mx, Number(pts[i]) || 0)
                  mx = Math.ceil(mx / 5) * 5
                  var w = width, h = height
                  ctx.beginPath()
                  for (i = 0; i < n; i++) {
                    var x = w * i / (n - 1)
                    var y = h - (h - 2) * ((Number(pts[i]) || 0) / mx) - 1
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                  }
                  ctx.strokeStyle = line
                  ctx.lineWidth = 1.5
                  ctx.stroke()
                  ctx.lineTo(w, h)
                  ctx.lineTo(0, h)
                  ctx.closePath()
                  ctx.fillStyle = Qt.rgba(line.r, line.g, line.b, 0.14)
                  ctx.fill()
                }
              }
            }
          }

          // ---------- Tuning (needs TLP) ----------
          BorderSurface {
            visible: !root.tlp.installed
            width: parent.width
            implicitHeight: installCol.implicitHeight + Style.space(24)
            color: Style.normalFillFor(root.fg, Color.accent)
            borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
            radius: Style.cornerRadius

            Column {
              id: installCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Power tuning isn’t set up yet"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                width: parent.width
                text: "Install TLP + the MacBook tunables to control power modes, CPU turbo, Wi-Fi and PCIe power saving from here."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
              Button {
                text: "Install power tuning"
                bordered: true
                focusable: true
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: { service.openTerminal("install"); root.close() }
              }
            }
          }

          Column {
            visible: root.tlp.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.fg }
            PanelSectionHeader { text: "POWER MODE"; foreground: root.fg; fontFamily: root.fontFamily }

            Segmented {
              width: parent.width
              options: [
                { value: "auto",  label: "Auto" },
                { value: "saver", label: "Saver" },
                { value: "full",  label: "Full power" }
              ]
              value: Model.activeMode(root.tlp)
              onPicked: function(v) { service.act("mode", v) }
            }
            Text {
              width: parent.width
              text: root.tlp.active
                ? "Auto follows the AC adapter · currently on " + (root.tlp.mode === "battery" ? "battery profile" : "AC profile")
                : "tlp.service is not running"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- CPU ----------
          Column {
            visible: root.tlp.installed
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { foreground: root.fg }
            PanelSectionHeader { text: "CPU"; foreground: root.fg; fontFamily: root.fontFamily }

            Toggle {
              width: parent.width
              label: "Turbo boost"
              description: "Higher peaks, but a big hit to battery"
              checked: root.cpu.turbo
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: service.act("turbo", root.cpu.turbo ? "off" : "on")
            }

            Segmented {
              width: parent.width
              options: Model.EPP_OPTIONS
              value: Model.eppValue(root.cpu.epp)
              onPicked: function(v) { service.act("epp", v) }
            }
            Text {
              width: parent.width
              text: "Energy bias · governor " + root.cpu.governor
                + (root.cpu.freqMHz ? " · " + root.cpu.freqMHz + " MHz" : "")
                + " · load " + Number(root.cpu.load1).toFixed(2)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Device power saving ----------
          Column {
            visible: root.tlp.installed
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.fg }
            PanelSectionHeader { text: "DEVICE POWER SAVING"; foreground: root.fg; fontFamily: root.fontFamily }

            Toggle {
              width: parent.width
              label: "Wi-Fi power saving"
              checked: root.tweaks.wifi
              foreground: root.fg; fontFamily: root.fontFamily
              onClicked: service.act("wifi", root.tweaks.wifi ? "off" : "on")
            }
            Toggle {
              width: parent.width
              label: "PCIe runtime power"
              checked: root.tweaks.pcie
              foreground: root.fg; fontFamily: root.fontFamily
              onClicked: service.act("pcie", root.tweaks.pcie ? "off" : "on")
            }
            Toggle {
              width: parent.width
              label: "USB autosuspend"
              description: "Keyboards & mice are always excluded"
              checked: root.tweaks.usb
              foreground: root.fg; fontFamily: root.fontFamily
              onClicked: service.act("usb", root.tweaks.usb ? "off" : "on")
            }
            Toggle {
              width: parent.width
              label: "Audio codec power save"
              checked: root.tweaks.audio
              foreground: root.fg; fontFamily: root.fontFamily
              onClicked: service.act("audio", root.tweaks.audio ? "off" : "on")
            }
            Text {
              width: parent.width
              topPadding: Style.space(6)
              text: "Applied for this session. Edit the TLP config to make them permanent."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Top consumers ----------
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator { foreground: root.fg }
            Item {
              width: parent.width
              implicitHeight: consumersTitle.implicitHeight
              PanelSectionHeader {
                id: consumersTitle
                text: "TOP CONSUMERS"
                foreground: root.fg
                fontFamily: root.fontFamily
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: consumersTitle.verticalCenter
                text: "CPU SHARE"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Repeater {
              model: Model.consumers(service.procs)

              Item {
                required property var modelData
                width: parent.width
                implicitHeight: Style.space(24)

                Text {
                  id: procName
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width * 0.34
                  text: modelData.name
                  elide: Text.ElideRight
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  id: procTrack
                  anchors.left: procName.right
                  anchors.right: procPct.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: height / 2
                  color: root.faint

                  Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    radius: height / 2
                    width: Math.max(height, parent.width * Math.max(0, Math.min(1, modelData.frac)))
                    color: root.fg
                    Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                  }
                }

                Text {
                  id: procPct
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(42)
                  horizontalAlignment: Text.AlignRight
                  text: Math.round(modelData.pct) + "%"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Text {
              visible: (service.procs || []).length === 0
              width: parent.width
              text: "Gathering process data…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // ---------- Footer ----------
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              Layout.fillWidth: true
              text: "PowerTOP scan"
              bordered: true
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: { service.openTerminal("scan"); root.close() }
            }
            Button {
              Layout.fillWidth: true
              text: "Full dashboard"
              bordered: true
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: { service.openTerminal("dashboard"); root.close() }
            }
          }

          Text {
            width: parent.width
            text: "R refresh · J/K scroll · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  // ---- inline helpers -------------------------------------------------

  component StatPair: Item {
    id: sp
    property string label: ""
    property string value: ""
    width: (statsGrid.width - statsGrid.columnSpacing) / 2
    implicitHeight: Math.max(spLabel.implicitHeight, spValue.implicitHeight)

    Text {
      id: spLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: sp.label
      color: root.fg
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: spValue
      anchors.right: parent.right
      anchors.left: spLabel.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: sp.value
      color: root.fg
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      horizontalAlignment: Text.AlignRight
    }
  }

  component Segmented: Row {
    id: seg
    property var options: []
    property string value: ""
    signal picked(string value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(6)
    readonly property real cell: options.length > 0
      ? (width - spacing * (options.length - 1)) / options.length : 0

    Repeater {
      model: seg.options
      Button {
        required property var modelData
        width: seg.cell
        text: modelData.label
        fontSize: Style.font.bodySmall
        foreground: root.fg
        fontFamily: root.fontFamily
        horizontalPadding: Style.spacing.sm
        bordered: true
        active: seg.value === String(modelData.value)
        onClicked: seg.picked(String(modelData.value))
      }
    }
  }
}
