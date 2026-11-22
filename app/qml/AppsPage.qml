import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Settings.js" as Settings

// Apps (D47): one list of the apps that have their own place, one choice each: always on a desktop, or left alone. A new
// one comes from an open window (its desktop, monitor and spot filled in) or an installed app. Above it, the one default
// for every other app. The details of a place open under its row.
ScrollView {
    id: page
    property var app
    property string openRow: ""
    property bool adding: false
    readonly property var settings: app.panel.settings || ({})
    readonly property var rules: app.panel.rules || []
    readonly property var apps: app.model.apps || []
    readonly property var monitors: app.model.monitors || []
    readonly property var groups: (app.model.desks || {}).groups || []
    readonly property var ignored: String(settings.ignore || "").split(/[\s,]+/).filter(function (x) { return x !== "" })
    // every open window with where it is: { class, label, icon, rect, identity, monitor, slot, floating }
    readonly property var openWindows: {
        const out = []
        for (const g of page.groups) for (const c of g.cards) for (const a of (c.live || []))
            out.push({ class: a.class, label: a.label, icon: a.icon, rect: a.rect, identity: c.identity, monitor: g.label || g.name, slot: c.slot, number: c.number || c.slot, floating: c.mode === "floating" })
        return out
    }
    contentWidth: availableWidth
    clip: true

    function appOf(cls) {
        const c = String(cls || "").toLowerCase()
        return page.apps.find(function (x) { return x.startupWMClass.toLowerCase() === c || x.value.toLowerCase() === c }) || null
    }
    function labelOf(cls) { const a = page.appOf(cls); return a ? a.label : cls }
    function iconOf(cls) { const a = page.appOf(cls); return a && a.icon ? backend.iconSource(a.icon) : "" }
    function placeText(rule) {
        const g = page.groups.find(function (x) { return x.identity === rule.monitor }) || null
        const mon = rule.monitor === "laptop" ? qsTr("any laptop screen") : rule.monitor === "" ? qsTr("the monitor in use") : g ? (g.label || g.name) : rule.monitor
        const card = g ? g.cards.find(function (c) { return c.slot === (rule.slot || 1) }) : null
        return qsTr("Desktop %1, %2").arg(card ? card.number : (rule.slot || 1)).arg(mon)  // the number the user's keys use (D50)
    }
    function setIgnored(list) { page.app.act("setSetting", ["ignore", list.join(", ")]) }

    ColumnLayout {
        width: page.availableWidth
        spacing: 14

        Card {
            title: qsTr("Apps you open yourself go")
            Choice {
                objectName: "appMemory"
                current: page.settings.app_memory || "scene"
                options: [{ value: "scene", label: qsTr("To their remembered desktop") }, { value: "last_place", label: qsTr("Where you left them") },
                    { value: "auto", label: qsTr("Where you left them, remembered desktops follow") }, { value: "off", label: qsTr("Where Hyprland puts them") }]
                onPicked: function (v) { page.app.act("setSetting", ["app_memory", v]) }
            }
        }

        Card {
            title: qsTr("Apps with their own place")

            Hint { visible: page.rules.length === 0 && page.ignored.length === 0; text: qsTr("No app has its own place yet. Add one: it then always opens there.") }

            Repeater {
                model: page.rules
                ColumnLayout {
                    id: ruleRow
                    required property var modelData
                    readonly property var rule: modelData
                    readonly property bool open: page.openRow === rule.name
                    Layout.fillWidth: true
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Image { source: page.iconOf(ruleRow.rule.app); sourceSize: Qt.size(24, 24); visible: source != ""; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; font.bold: true; text: page.labelOf(ruleRow.rule.app) }
                            Label {
                                Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; color: ui.secondary
                                text: (ruleRow.rule.enabled === false ? qsTr("Paused. ") : "") + qsTr("Always on %1").arg(page.placeText(ruleRow.rule))
                                    + (ruleRow.rule.keep_rect === true ? qsTr(", same size and spot") : "")
                            }
                        }
                        ActionButton {
                            objectName: "ruleOpen-" + ruleRow.rule.name
                            text: ruleRow.open ? qsTr("Done") : qsTr("Change")
                            onClicked: page.openRow = ruleRow.open ? "" : ruleRow.rule.name
                        }
                    }
                    Flow {
                        visible: ruleRow.open
                        Layout.fillWidth: true
                        Layout.leftMargin: 32
                        spacing: 10
                        Combo {
                            objectName: "ruleMonitor-" + ruleRow.rule.name
                            width: 240
                            model: Settings.monitorChoices(page.monitors, ruleRow.rule.monitor)
                            textRole: "label"
                            valueRole: "value"
                            currentIndex: Math.max(0, model.findIndex(function (o) { return o.value === (ruleRow.rule.monitor || "") }))
                            Accessible.name: qsTr("Monitor")
                            onActivated: {
                                if (currentValue !== ruleRow.rule.monitor) page.app.act("setRule", [ruleRow.rule.name, "monitor", currentValue])
                                currentIndex = Qt.binding(function () { return Math.max(0, model.findIndex(function (o) { return o.value === (ruleRow.rule.monitor || "") })) })
                            }
                        }
                        RowLayout {
                            Label { text: qsTr("Desktop") }
                            SpinBox {
                                objectName: "ruleSlot-" + ruleRow.rule.name
                                from: 1; to: 10; value: ruleRow.rule.slot || 1; editable: true
                                Accessible.name: qsTr("Desktop")
                                onValueModified: { if (value !== ruleRow.rule.slot) page.app.act("setRule", [ruleRow.rule.name, "slot", value]); value = Qt.binding(function () { return ruleRow.rule.slot || 1 }) }
                            }
                        }
                        Switch {
                            objectName: "ruleFollow-" + ruleRow.rule.name
                            text: qsTr("Go there with it")
                            checked: ruleRow.rule.follow === true
                            onToggled: { page.app.act("setRule", [ruleRow.rule.name, "follow", checked]); checked = Qt.binding(function () { return ruleRow.rule.follow === true }) }
                        }
                        Switch {
                            objectName: "ruleSpot-" + ruleRow.rule.name
                            visible: (ruleRow.rule.rect || "") !== ""
                            text: qsTr("Same size and spot")
                            checked: ruleRow.rule.keep_rect === true
                            onToggled: { page.app.act("setRule", [ruleRow.rule.name, "keep_rect", checked]); checked = Qt.binding(function () { return ruleRow.rule.keep_rect === true }) }
                        }
                        Switch {
                            objectName: "ruleOn-" + ruleRow.rule.name
                            text: qsTr("On")
                            checked: ruleRow.rule.enabled !== false
                            onToggled: { page.app.act("setRule", [ruleRow.rule.name, "enabled", checked]); checked = Qt.binding(function () { return ruleRow.rule.enabled !== false }) }
                        }
                        ActionButton {
                            text: qsTr("Remove")
                            onClicked: page.app.ask(qsTr("%1 then opens like any other app. The file before the change is kept as config.toml.bak.").arg(page.labelOf(ruleRow.rule.app)),
                                "removeRule", [ruleRow.rule.name], qsTr("Removed"))
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: ui.off }
                }
            }

            Repeater {
                model: page.ignored
                RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 8
                    Image { source: page.iconOf(modelData); sourceSize: Qt.size(24, 24); visible: source != ""; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; font.bold: true; text: page.labelOf(modelData) }
                        Label { color: ui.secondary; text: qsTr("Left alone: omaplace never moves or saves it") }
                    }
                    ActionButton {
                        objectName: "unignore-" + modelData
                        text: qsTr("Remove")
                        onClicked: { const l = page.ignored.slice(); l.splice(index, 1); page.setIgnored(l) }
                    }
                }
            }

            ActionButton {
                objectName: "addApp"
                primary: page.rules.length === 0
                text: page.adding ? qsTr("Cancel") : qsTr("Add an app...")
                onClicked: page.adding = !page.adding
            }
            ColumnLayout {
                visible: page.adding
                Layout.fillWidth: true
                spacing: 6
                Label { visible: page.openWindows.length > 0; text: qsTr("From an open window: it always opens where it is now"); font.bold: true }
                Repeater {
                    model: page.openWindows
                    RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 8
                        Image { source: modelData.icon ? backend.iconSource(modelData.icon) : ""; sourceSize: Qt.size(20, 20); visible: source != ""; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                        Label { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; text: qsTr("%1, desktop %2, %3").arg(modelData.label).arg(modelData.number).arg(modelData.monitor) }
                        ActionButton {
                            objectName: "always-" + index
                            text: qsTr("Always here")
                            onClicked: {
                                const r = modelData.floating && modelData.rect ? modelData.rect.map(function (v) { return Math.round(v * 1000) / 1000 }).join(" ") : ""
                                page.app.act("ruleNewAt", [modelData.class, modelData.identity, modelData.slot, r], qsTr("%1 always opens on desktop %2, %3").arg(modelData.label).arg(modelData.number).arg(modelData.monitor))
                                page.adding = false
                            }
                        }
                        ActionButton {
                            objectName: "leave-" + index
                            text: qsTr("Leave it alone")
                            onClicked: { const l = page.ignored.slice(); if (l.indexOf(modelData.class) === -1) l.push(modelData.class); page.setIgnored(l); page.adding = false }
                        }
                    }
                }
                Label { text: qsTr("Or an installed app"); font.bold: true }
                AppPicker {
                    objectName: "newRuleApp"
                    Layout.fillWidth: true
                    apps: page.apps
                    placeholder: qsTr("Pick an app; then choose its desktop")
                    onPicked: function (id) { page.app.act("ruleNew", [id, "", 1], qsTr("Added: choose its desktop with Change")); page.adding = false }
                }
            }
        }

        Card {
            title: qsTr("If a monitor is not connected")
            Choice {
                current: page.settings.missing_monitor_rule || "skip"
                options: [{ value: "skip", label: qsTr("The app opens as usual") }, { value: "focused", label: qsTr("It goes to the monitor in use") }]
                onPicked: function (v) { page.app.act("setSetting", ["missing_monitor_rule", v]) }
            }
        }
    }
}
