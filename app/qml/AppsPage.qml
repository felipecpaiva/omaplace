import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Settings.js" as Settings

// Apps: where an app always opens (rules), what apps you open yourself do (app memory), and apps to leave alone.
ScrollView {
    id: page
    property var app
    property string newApp: ""
    readonly property var settings: app.panel.settings || ({})
    readonly property var rules: app.panel.rules || []
    readonly property var apps: app.model.apps || []
    readonly property var monitors: app.model.monitors || []
    contentWidth: availableWidth
    clip: true

    // The rule's app is a window class; show the installed app's name when one matches it.
    function appLabel(cls) {
        const c = String(cls || "").toLowerCase()
        const a = page.apps.find(function (x) { return x.startupWMClass.toLowerCase() === c || x.value.toLowerCase() === c })
        return a ? a.label : cls
    }
    function appIcon(cls) {
        const c = String(cls || "").toLowerCase()
        const a = page.apps.find(function (x) { return x.startupWMClass.toLowerCase() === c || x.value.toLowerCase() === c })
        return a && a.icon ? backend.iconSource(a.icon) : ""
    }

    ColumnLayout {
        width: page.availableWidth
        spacing: 14

        Card {
            title: qsTr("Always open here")
            help: qsTr("This app always opens on this desktop of this monitor. A browser or editor with many profiles or projects is placed only when omaplace opened it.")

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                AppPicker {
                    objectName: "newRuleApp"
                    Layout.fillWidth: true
                    apps: page.apps
                    value: page.newApp
                    placeholder: qsTr("Add an app...")
                    onPicked: function (id) { page.newApp = id }
                }
                ComboBox {
                    id: newMonitor
                    objectName: "newRuleMonitor"
                    Layout.preferredWidth: 220
                    model: Settings.monitorChoices(page.monitors, "")
                    textRole: "label"
                    valueRole: "value"
                    Accessible.name: qsTr("Monitor")
                }
                SpinBox { id: newSlot; objectName: "newRuleSlot"; from: 1; to: 10; value: 1; editable: true; Accessible.name: qsTr("Desktop") }
                Button {
                    objectName: "newRuleAdd"
                    text: qsTr("Add")
                    highlighted: true
                    enabled: page.newApp !== ""
                    onClicked: { page.app.act("ruleNew", [page.newApp, String(newMonitor.currentValue || ""), newSlot.value]); page.newApp = "" }
                }
            }

            Hint { visible: page.rules.length === 0; text: qsTr("No app has a fixed place yet.") }
            Repeater {
                model: page.rules
                ColumnLayout {
                    id: ruleRow
                    required property var modelData
                    readonly property var rule: modelData
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Image { source: page.appIcon(ruleRow.rule.app); sourceSize: Qt.size(24, 24); visible: source != ""; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font.bold: true
                            text: ruleRow.rule.app !== "" ? page.appLabel(ruleRow.rule.app) : qsTr("%1 (no app)").arg(ruleRow.rule.name)
                        }
                        Switch {
                            text: qsTr("On")
                            checked: ruleRow.rule.enabled !== false
                            Accessible.name: qsTr("Rule %1 on").arg(ruleRow.rule.name)
                            onToggled: page.app.act("setRule", [ruleRow.rule.name, "enabled", checked])
                        }
                        Button {
                            text: qsTr("Remove")
                            onClicked: page.app.ask(qsTr("Remove the rule for %1? The file before the change is kept as config.toml.bak.").arg(page.appLabel(ruleRow.rule.app)),
                                "removeRule", [ruleRow.rule.name], qsTr("Removed"))
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        ComboBox {
                            width: 240
                            model: Settings.monitorChoices(page.monitors, ruleRow.rule.monitor)
                            textRole: "label"
                            valueRole: "value"
                            currentIndex: Math.max(0, model.findIndex(function (o) { return o.value === (ruleRow.rule.monitor || "") }))
                            Accessible.name: qsTr("Monitor")
                            onActivated: if (currentValue !== ruleRow.rule.monitor) page.app.act("setRule", [ruleRow.rule.name, "monitor", currentValue])
                        }
                        RowLayout {
                            Label { text: qsTr("Desktop") }
                            SpinBox {
                                from: 1; to: 10; value: ruleRow.rule.slot || 1; editable: true
                                Accessible.name: qsTr("Desktop")
                                onValueModified: if (value !== ruleRow.rule.slot) page.app.act("setRule", [ruleRow.rule.name, "slot", value])
                            }
                        }
                        Switch {
                            text: qsTr("Switch to that desktop when it opens")
                            checked: ruleRow.rule.follow === true
                            onToggled: page.app.act("setRule", [ruleRow.rule.name, "follow", checked])
                        }
                        Switch {
                            visible: (ruleRow.rule.rect || "") !== ""
                            text: qsTr("Open in the same spot")
                            checked: ruleRow.rule.keep_rect === true
                            onToggled: page.app.act("setRule", [ruleRow.rule.name, "keep_rect", checked])
                        }
                    }
                    Hint { visible: (ruleRow.rule.rect || "") !== ""; text: qsTr("Same spot works on a floating desktop.") }
                    Rectangle { Layout.fillWidth: true; height: 1; color: ui.off }
                }
            }
            Choice {
                title: qsTr("If the monitor is not connected")
                current: page.settings.missing_monitor_rule || "skip"
                options: [{ value: "skip", label: qsTr("Open as usual") }, { value: "focused", label: qsTr("Use the focused monitor") }]
                onPicked: function (v) { page.app.act("setSetting", ["missing_monitor_rule", v]) }
            }
        }

        Card {
            title: qsTr("Apps you open yourself")
            Choice {
                objectName: "appMemory"
                title: qsTr("Go back to")
                current: page.settings.app_memory || "scene"
                options: [{ value: "scene", label: qsTr("Where a scene put it") }, { value: "last_place", label: qsTr("Where you left it") },
                    { value: "auto", label: qsTr("Automatic") }, { value: "off", label: qsTr("Nowhere special") }]
                help: qsTr("Automatic: like Where you left it, and moving an app between two desktops that show a scene moves it from one scene to the other. Nowhere special: apps open where Hyprland puts them.")
                onPicked: function (v) { page.app.act("setSetting", ["app_memory", v]) }
            }
        }

        Card {
            title: qsTr("Leave these apps alone")
            help: qsTr("Window classes omaplace never places or saves, separated by commas.")
            TextField {
                objectName: "ignoreField"
                Layout.fillWidth: true
                placeholderText: "steam, mpv"
                text: page.settings.ignore || ""
                Accessible.name: qsTr("Apps to leave alone")
                onEditingFinished: if (text.trim() !== (page.settings.ignore || "")) page.app.act("setSetting", ["ignore", text])
            }
        }
    }
}
