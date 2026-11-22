import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Settings.js" as Settings

// Scenes: open, rename and delete saved desktops, and each window's folder, program and profile; what a scene does
// with apps already open and with a missing monitor.
ScrollView {
    id: page
    property var app
    property var expanded: ({})
    property string filter: ""
    readonly property var settings: app.panel.settings || ({})
    readonly property bool writable: app.panel.scenesWritable === true
    // saved desktops with a home show on Desktops; here are the ones you open anywhere (D48)
    readonly property var homeless: (app.panel.scenes || []).filter(function (s) { return s.plan !== true })
    // the desktops a saved one can move to: not remembered yet
    readonly property var freeDesks: {
        const out = []
        for (const g of ((page.app.model.desks || {}).groups || [])) for (const c of g.cards)
            if (!c.plan && g.connected !== false) out.push({ value: out.length, label: qsTr("Desktop %1, %2").arg(c.slot).arg(g.label || g.name), card: c })
        return out
    }
    readonly property var scenes: page.homeless.filter(function (s) { return s.name.toLowerCase().indexOf(page.filter.toLowerCase()) !== -1 })
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: page.availableWidth
        spacing: 14

        Hint { text: qsTr("Saved desktops you can open on any desktop. Save one with Save this desktop in the Omarchy menu, or: omaplace save <name>. Remembered desktops are on the Desktops page.") }
        Hint { warn: true; visible: page.app.panel.ok === true && !page.writable; text: qsTr("scenes.toml has a newer schema or a scene with a bad name: it is shown but not changed. Fix the file first.") }

        Card {
            title: qsTr("Saved desktops")
            TextField {
                objectName: "sceneFilter"
                visible: (page.app.panel.scenes || []).length > 3
                Layout.fillWidth: true
                placeholderText: qsTr("Filter scenes")
                onTextChanged: page.filter = text
            }
            Hint { visible: page.homeless.length === 0; text: qsTr("Nothing saved here yet.") }
            Repeater {
                model: page.scenes
                ColumnLayout {
                    id: sceneRow
                    required property var modelData
                    readonly property bool open: !!page.expanded[modelData.name]
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextField {
                            objectName: "sceneName-" + sceneRow.modelData.name
                            Layout.fillWidth: true
                            maximumLength: 40
                            enabled: page.writable
                            text: sceneRow.modelData.name
                            Accessible.name: qsTr("Scene name")
                            onEditingFinished: {
                                if (text.trim() !== "" && text.trim() !== sceneRow.modelData.name) page.app.act("rename", [sceneRow.modelData.name, text.trim()], qsTr("Renamed"))
                                text = Qt.binding(function () { return sceneRow.modelData.name })
                            }
                        }
                        Label { color: ui.secondary; text: (sceneRow.modelData.windows.length === 1 ? qsTr("1 window") : qsTr("%1 windows").arg(sceneRow.modelData.windows.length)) }
                        ActionButton { text: qsTr("Open"); primary: true; onClicked: page.app.act("open", [sceneRow.modelData.name], qsTr("Opened %1").arg(sceneRow.modelData.name)) }
                        ActionButton {
                            objectName: "sceneHome-" + sceneRow.modelData.name
                            text: qsTr("Give it a home...")
                            enabled: page.writable && page.freeDesks.length > 0
                            onClicked: homeMenu.popup()
                            Menu {
                                id: homeMenu
                                background: Rectangle { implicitWidth: 260; color: ui.surface; border.color: ui.edge; radius: Math.min(6, ui.radius) }
                                Repeater {
                                    model: page.freeDesks
                                    MenuItem {
                                        required property var modelData
                                        text: modelData.label
                                        onTriggered: page.app.act("sceneHome", [sceneRow.modelData.name, modelData.card.identity, modelData.card.slot, modelData.card.focused === true, modelData.card.mode || ""],
                                            qsTr("%1 now lives on %2").arg(sceneRow.modelData.name).arg(modelData.label))
                                    }
                                }
                            }
                        }
                        ActionButton {
                            objectName: "sceneWindows-" + sceneRow.modelData.name
                            text: sceneRow.open ? qsTr("Hide windows") : qsTr("Windows")
                            onClicked: { const o = Object.assign({}, page.expanded); o[sceneRow.modelData.name] = !sceneRow.open; page.expanded = o }
                        }
                        ActionButton {
                            text: qsTr("Delete")
                            enabled: page.writable
                            onClicked: page.app.ask(qsTr("Delete %1? The file before the change is kept as scenes.toml.bak.").arg(sceneRow.modelData.name),
                                "removeScene", [sceneRow.modelData.name], qsTr("Deleted %1").arg(sceneRow.modelData.name))
                        }
                    }
                    Repeater {
                        model: sceneRow.open ? sceneRow.modelData.windows : []
                        ColumnLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            Label { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; text: modelData.app + ", " + Settings.positionText(modelData) + ", " + qsTr("order %1").arg(modelData.order) }
                            WindowFields { Layout.fillWidth: true; app: page.app; sceneName: sceneRow.modelData.name; win: modelData; winIndex: index; writable: page.writable }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: ui.off }
                }
            }
        }

        Card {
            title: qsTr("When a scene opens")
            Choice {
                title: qsTr("Apps that are open already")
                current: page.settings.existing_default || "move"
                options: [{ value: "move", label: qsTr("Move them") }, { value: "new", label: qsTr("Open new ones") }]
                onPicked: function (v) { page.app.act("setSetting", ["existing_default", v]) }
            }
            Choice {
                title: qsTr("If its monitor is not connected")
                current: page.settings.missing_monitor_scene || "focused"
                options: [{ value: "focused", label: qsTr("Use the focused monitor") }, { value: "skip", label: qsTr("Skip it") }]
                onPicked: function (v) { page.app.act("setSetting", ["missing_monitor_scene", v]) }
            }
        }
    }
}
