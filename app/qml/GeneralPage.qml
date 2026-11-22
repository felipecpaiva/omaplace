import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Settings.js" as Settings
import "../js/ConfigIO.js" as ConfigIO

// General: the Omarchy menu, the timings (Advanced) and About.
ScrollView {
    id: page
    property var app
    property bool advanced: false
    readonly property var settings: app.panel.settings || ({})
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: page.availableWidth
        spacing: 14

        Card {
            title: qsTr("Omarchy menu")
            help: qsTr("Adds a Scenes menu: save this desktop, open a scene, restore, always open here, settings. The menu file is backed up first, as omarchy-menu.jsonc.omaplace.bak.")
            ActionButton {
                objectName: "menuButton"
                text: page.app.panel.menu ? qsTr("Remove from the Omarchy menu") : qsTr("Add omaplace to the Omarchy menu")
                enabled: page.app.panel.ok === true
                onClicked: page.app.panel.menu ? page.app.act("menuRemove", [], qsTr("Removed from the Omarchy menu"))
                    : page.app.act("menuAdd", [], qsTr("Added to the Omarchy menu"))
            }
        }

        Card {
            title: qsTr("Advanced")
            ActionButton {
                objectName: "advancedButton"
                text: page.advanced ? qsTr("Hide the timings") : qsTr("Show the timings")
                onClicked: page.advanced = !page.advanced
            }
            Repeater {
                model: page.advanced && page.app.panel.ok ? Settings.timingRows(ConfigIO.SETTING_SPECS, page.settings) : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; text: qsTr("%1, %2 to %3").arg(modelData.label).arg(modelData.min).arg(modelData.max) }
                    SpinBox {
                        from: modelData.min
                        to: modelData.max
                        value: modelData.value
                        editable: true
                        Accessible.name: modelData.label
                        onValueModified: { if (value !== modelData.value) page.app.act("setSetting", [modelData.key, value]); value = Qt.binding(function () { return modelData.value }) }
                    }
                }
            }
        }

        Card {
            title: qsTr("About")
            Hint { text: qsTr("omaplace settings %1. Your settings are in ~/.config/omaplace (config.toml and scenes.toml); more options are in config.toml.").arg(Qt.application.version) }
            ActionButton { text: qsTr("Open the settings folder"); onClicked: backend.openConfigFolder() }
        }
    }
}
