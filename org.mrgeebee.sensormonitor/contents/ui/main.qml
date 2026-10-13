import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "sensors.js" as Sensors

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    readonly property string cmd: "sh '" + Qt.resolvedUrl("../scripts/read-sensors.sh").toString().replace("file://", "") + "'"
    // 0 = standard theme background, 1 = translucent, 2 = fully transparent (desktop only)
    readonly property bool customBg: cfg.bgMode > 0 && Plasmoid.formFactor === PlasmaCore.Types.Planar
    Plasmoid.backgroundHints: cfg.bgMode === 0 ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground
    property real hottest: NaN
    property string layoutKey: ""

    // 0 = cold (blue) ... 1 = hot (red)
    function fraction(t) {
        var lo = cfg.tempMin, hi = Math.max(cfg.tempMax, lo + 1)
        return Math.max(0, Math.min(1, (t - lo) / (hi - lo)))
    }
    function tempColor(t) {
        return Qt.hsla((1 - fraction(t)) * 240 / 360, 0.85, 0.55, 1)
    }

    function parse(text) {
        var hidden = cfg.hiddenSensors ? cfg.hiddenSensors.split(",") : []
        var shown = cfg.shownSensors ? cfg.shownSensors.split(",") : []
        var names = {}
        try { names = JSON.parse(cfg.sensorNames) } catch (e) {}
        var all = [], temps = [], seen = {}
        Sensors.describeAll(Sensors.parseOutput(text)).forEach(d => {
            if (hidden.indexOf(d.sid) >= 0) return
            if (d.defaultHidden && shown.indexOf(d.sid) < 0) return
            if (cfg.hideStopped && d.stopped) return
            all.push({ sid: d.sid, kind: d.kind, label: names[d.sid] || d.label, group: d.group,
                       value: d.value, order: d.order, key: d.key, idx: d.idx })
        })
        all.sort(Sensors.compare)
        all.forEach(s => {
            seen[s.label] = (seen[s.label] || 0) + 1
            if (seen[s.label] > 1) s.label += " #" + seen[s.label]
            if (s.kind === "temp") temps.push(s)
            delete s.order; delete s.key; delete s.idx
        })
        var key = all.map(s => s.sid + s.label + s.group).join("|")
        if (key !== layoutKey) {
            layoutKey = key
            sensorModel.clear()
            all.forEach(s => sensorModel.append(s))
        } else {
            all.forEach((s, n) => sensorModel.setProperty(n, "value", s.value))
        }
        hottest = temps.length ? Math.max.apply(null, temps.map(s => s.value)) : NaN
    }

    ListModel { id: sensorModel }

    Plasma5Support.DataSource {
        engine: "executable"
        connectedSources: [root.cmd]
        interval: Math.max(1, cfg.interval) * 1000
        onNewData: (source, data) => root.parse(data["stdout"])
    }

    Plasmoid.icon: "temperature-normal"
    toolTipMainText: i18n("Sensor Monitor")
    toolTipSubText: isNaN(hottest) ? "" : i18n("Hottest: %1 °C", hottest.toFixed(0))

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded
        implicitWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        PlasmaComponents3.Label {
            id: label
            anchors.centerIn: parent
            font.bold: true
            text: isNaN(root.hottest) ? "–" : root.hottest.toFixed(0) + "°"
            color: isNaN(root.hottest) ? Kirigami.Theme.textColor : root.tempColor(root.hottest)
        }
    }

    fullRepresentation: Item {
      id: panel
      readonly property real pad: root.customBg ? Kirigami.Units.largeSpacing : 0
      readonly property real ui: Math.max(50, root.cfg.uiScale) / 100
      implicitWidth: Kirigami.Units.gridUnit * 20 * ui
      implicitHeight: Math.min(list.contentHeight + pad * 2, Kirigami.Units.gridUnit * 30) * ui
      Layout.minimumWidth: Kirigami.Units.gridUnit * 14 * ui
      Layout.minimumHeight: Kirigami.Units.gridUnit * 6 * ui

      // Everything lives in `content`, laid out at 100% and scaled as one piece
      Item {
      id: content
      width: panel.width / panel.ui
      height: panel.height / panel.ui
      scale: panel.ui
      transformOrigin: Item.TopLeft

      Rectangle {
        anchors.fill: parent
        visible: root.customBg && root.cfg.bgMode === 1
        radius: Kirigami.Units.largeSpacing
        color: Qt.alpha(Kirigami.Theme.backgroundColor, root.cfg.bgOpacity / 100)
      }

      ListView {
        id: list
        anchors.fill: parent
        anchors.margins: panel.pad
        clip: true

        // Soft drop shadow so text stays readable on a bare wallpaper (Transparent mode only)
        layer.enabled: root.customBg && root.cfg.bgMode === 2
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.85
            shadowBlur: 0.6
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 1
        }
        spacing: Kirigami.Units.smallSpacing
        model: sensorModel

        section.property: "group"
        section.delegate: Item {
            id: head
            required property string section
            readonly property bool first: sensorModel.count > 0 && sensorModel.get(0).group === section
            width: list.width
            height: title.implicitHeight + (first ? 0 : Kirigami.Units.largeSpacing * 2)

            Rectangle {
                visible: !head.first
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Kirigami.Units.smallSpacing }
                height: 1
                color: Qt.alpha(Kirigami.Theme.textColor, 0.35)
            }
            Kirigami.Heading {
                id: title
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                level: 3
                font.weight: Font.Bold
                text: head.section
                color: Kirigami.Theme.textColor
            }
        }

        delegate: RowLayout {
            id: row
            required property string kind
            required property string label
            required property real value
            readonly property bool isTemp: kind === "temp"
            readonly property color tint: isTemp ? root.tempColor(value) : Kirigami.Theme.highlightColor

            width: list.width
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
            }
            Rectangle {
                visible: row.isTemp
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
                radius: height / 2
                color: Kirigami.Theme.alternateBackgroundColor
                Rectangle {
                    width: parent.width * root.fraction(row.value)
                    height: parent.height
                    radius: parent.radius
                    color: row.tint
                }
            }
            PlasmaComponents3.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                horizontalAlignment: Text.AlignRight
                font.bold: true
                font.features: { "tnum": 1 }
                color: row.tint
                text: row.isTemp ? row.value.toFixed(1) + " °C" : row.value.toFixed(0) + " RPM"
            }
        }
      }
      }
    }
}
