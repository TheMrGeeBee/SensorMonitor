import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "sensors.js" as Sensors

KCM.SimpleKCM {
    id: page

    property alias cfg_interval: intervalSpin.value
    property alias cfg_tempMin: minSpin.value
    property alias cfg_tempMax: maxSpin.value
    property alias cfg_hideStopped: stoppedCheck.checked
    property alias cfg_uiScale: scaleSlider.value
    property int cfg_uiScaleDefault
    property alias cfg_bgMode: bgCombo.currentIndex
    property alias cfg_bgOpacity: bgSlider.value
    property int cfg_bgModeDefault
    property int cfg_bgOpacityDefault
    property string cfg_hiddenSensors
    property string cfg_shownSensors
    property string cfg_sensorNames
    property int cfg_intervalDefault
    property int cfg_tempMinDefault
    property int cfg_tempMaxDefault
    property bool cfg_hideStoppedDefault
    property string cfg_hiddenSensorsDefault
    property string cfg_shownSensorsDefault
    property string userPath: ""
    property string userError: ""
    property string cfg_sensorNamesDefault

    readonly property string cmd: "sh '" + Qt.resolvedUrl("../scripts/read-sensors.sh").toString().replace("file://", "") + "'"

    // A sensor is shown unless the user hid it, or it is hidden by default and not explicitly shown.
    function isVisible(id, defaultHidden) {
        if (cfg_hiddenSensors.split(",").indexOf(id) >= 0) return false
        return !defaultHidden || cfg_shownSensors.split(",").indexOf(id) >= 0
    }
    function setVisible(id, show, defaultHidden) {
        var h = cfg_hiddenSensors ? cfg_hiddenSensors.split(",").filter(x => x !== id) : []
        var s = cfg_shownSensors ? cfg_shownSensors.split(",").filter(x => x !== id) : []
        if (show && defaultHidden) s.push(id)
        if (!show) h.push(id)
        cfg_hiddenSensors = h.join(",")
        cfg_shownSensors = s.join(",")
    }

    function nameOf(id) {
        try { return JSON.parse(cfg_sensorNames)[id] || "" } catch (e) { return "" }
    }
    function setName(id, name) {
        var m = {}
        try { m = JSON.parse(cfg_sensorNames) } catch (e) {}
        name = name.trim()
        if (name) m[id] = name; else delete m[id]
        cfg_sensorNames = JSON.stringify(m)
    }

    ListModel { id: found }

    Plasma5Support.DataSource {
        engine: "executable"
        connectedSources: [page.cmd]
        onNewData: (source, data) => {
            disconnectSource(source)
            found.clear()
            var parsed = Sensors.parseOutput(data["stdout"])
            page.userPath = parsed.userPath
            page.userError = parsed.error
            var list = Sensors.describeAll(parsed)
            list.sort(Sensors.compare)
            list.forEach(d => found.append({
                sid: d.sid, label: d.label, group: d.group, defaultHidden: d.defaultHidden,
                valueText: d.kind === "temp" ? d.value.toFixed(0) + " °C" : d.value.toFixed(0) + " RPM"
            }))
        }
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: intervalSpin
            Kirigami.FormData.label: i18n("Refresh every (s):")
            from: 1; to: 60
        }
        QQC2.SpinBox {
            id: minSpin
            Kirigami.FormData.label: i18n("Blue at or below (°C):")
            from: 0; to: 150
        }
        QQC2.SpinBox {
            id: maxSpin
            Kirigami.FormData.label: i18n("Red at or above (°C):")
            from: 1; to: 200
        }
        QQC2.CheckBox {
            id: stoppedCheck
            Kirigami.FormData.label: i18n("Invalid readings:")
            text: i18n("Hide 0 RPM fans and temperatures of 5 °C or less")
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Widget size:")
            QQC2.Slider {
                id: scaleSlider
                from: 50; to: 200; stepSize: 10
                snapMode: QQC2.Slider.SnapAlways
            }
            QQC2.Label {
                text: Math.round(scaleSlider.value) + " %"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            }
        }
        QQC2.ComboBox {
            id: bgCombo
            Kirigami.FormData.label: i18n("Desktop background:")
            model: [i18n("Standard"), i18n("Translucent"), i18n("Transparent")]
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Translucency (opacity):")
            enabled: bgCombo.currentIndex === 1
            QQC2.Slider {
                id: bgSlider
                from: 0; to: 100; stepSize: 10
                snapMode: QQC2.Slider.SnapAlways
            }
            QQC2.Label {
                text: Math.round(bgSlider.value) + " %"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
            }
        }
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Sensors to show") }
        QQC2.Label {
            Kirigami.FormData.label: i18n("Custom rules file:")
            text: page.userPath
            opacity: 0.7
        }
        QQC2.Label {
            visible: page.userError !== ""
            Kirigami.FormData.label: i18n("Rules file error:")
            text: page.userError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 25
        }
        Repeater {
            model: found
            RowLayout {
                id: entry
                required property string sid
                required property string label
                required property string valueText
                required property string group
                required property bool defaultHidden
                Kirigami.FormData.label: ""
                QQC2.CheckBox {
                    checked: page.isVisible(entry.sid, entry.defaultHidden)
                    onToggled: page.setVisible(entry.sid, checked, entry.defaultHidden)
                    text: entry.group + " · " + entry.label + " [" + entry.sid.split("/").pop() + "] — " + entry.valueText
                }
                QQC2.TextField {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    placeholderText: i18n("Custom name")
                    text: page.nameOf(entry.sid)
                    onEditingFinished: page.setName(entry.sid, text)
                }
            }
        }
    }
}
