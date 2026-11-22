import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Desktops.js" as Desktops
import "../js/Zones.js" as Zones
import "../js/LayoutOps.js" as LayoutOps

// One desktop, picture first (D44). The big picture shows the plan when the desktop has one, else what is open on it now
// (stacked windows as one stack). One main action: "Remember this desktop" (its apps, as they are placed now), or, with a
// plan, "Put windows back" and "Update from now". Layouts, zones, drawing and the app of each place wait under
// "Change layout". Every change is one request; the card comes back rebuilt from the files.
ColumnLayout {
    id: editor
    property var app
    property var card: ({})
    property var apps: []
    property var omagnet: ({ loaded: false, layouts: [] })
    // By card key, so another desktop picked meanwhile never gets them (and a Save writes the desktop it was drawn for).
    property string customKey: ""
    property string drawKey: ""
    property string drawText: ""
    property string moreKey: ""
    readonly property bool drawing: drawKey !== "" && drawKey === card.key
    property var openRows: ({})
    readonly property bool writable: app.panel.scenesWritable === true && card.editable !== false
    readonly property bool custom: customKey === card.key || card.choice === "custom"
    readonly property var options: card.options || [{ value: "", label: qsTr("No plan") }].concat(Desktops.LAYOUT_CHOICES, [{ value: "custom", label: qsTr("Custom zones") }])
    readonly property bool zoned: !!Zones.ofLayout(card.layout || "").zones
    readonly property var live: card.live || []
    readonly property bool hasLive: live.length > 0
    // the layout tools: open when asked, or by themselves on an empty desktop with no plan (nothing to remember there)
    readonly property bool tools: moreKey === card.key || drawing || (!card.plan && !hasLive)

    function edit(op, arg) { app.act("editPlan", [card.identity, card.slot, card.focused === true, op, arg, card.mode || ""]) }
    function removePlan() {
        if (card.plan) app.ask(qsTr("Forget the plan of desktop %1? The file before the change is kept as scenes.toml.bak.").arg(card.slot), "removeScene", [card.name], qsTr("Desktop %1 is forgotten").arg(card.slot))
    }
    function remember() {
        const args = [card.identity, card.slot, card.focused === true, card.mode || "", card.workspace]
        const done = qsTr("Desktop %1 is remembered").arg(card.slot)
        if (card.plan) app.ask(qsTr("Remember desktop %1 as it is now? This replaces its plan. The file before the change is kept as scenes.toml.bak.").arg(card.slot), "planFromDesktop", args, done)
        else app.act("planFromDesktop", args, done)
    }

    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.bold: true
            font.pixelSize: 18
            text: qsTr("Desktop %1").arg(editor.card.slot) + "  " + (editor.card.monitorName || "")
        }
        Label {
            color: editor.card.plan ? ui.accent : ui.secondary
            font.bold: editor.card.plan === true
            text: editor.card.plan ? qsTr("Remembered") : editor.card.mode === "floating" ? qsTr("Floating") : editor.card.mode === "scrolling" ? qsTr("Scrolling") : editor.card.mode === "tiled" ? qsTr("Tiled") : ""
        }
    }

    Hint { warn: true; visible: (editor.card.error || "") !== ""; text: qsTr("This plan has a problem: %1. Fix it in ~/.config/omaplace/scenes.toml first; nothing is saved until then.").arg(editor.card.error) }
    Hint { warn: true; visible: editor.card.editable === false; text: qsTr("Reading the monitors failed. Press F5 to try again. Nothing can be changed until then.") }

    // The picture: the plan, else the desktop as it is now.
    ZoneThumb {
        objectName: "desktopPicture"
        Layout.fillWidth: true
        Layout.maximumWidth: 460
        rows: editor.card.plan ? (editor.card.rows || []) : (editor.card.liveRows || [])
        emptyText: editor.card.plan || editor.hasLive ? "" : qsTr("Nothing is open here")
    }
    Label {
        objectName: "nowLine"
        visible: text !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: ui.secondary
        text: editor.card.plan ? (editor.hasLive ? qsTr("Open now: %1").arg(editor.card.liveSummary) : qsTr("Nothing of it is open now."))
            : editor.hasLive ? qsTr("Open now: %1").arg(editor.card.liveSummary) : qsTr("Open the apps you want here, or choose a layout below.")
    }

    // The main actions.
    Flow {
        Layout.fillWidth: true
        spacing: 8
        ActionButton {
            objectName: "planFromDesktop"
            visible: !editor.card.plan && editor.hasLive
            primary: true
            text: qsTr("Remember this desktop")
            enabled: editor.writable && (editor.card.workspace || 0) > 0
            onClicked: editor.remember()
        }
        ActionButton {
            objectName: "openAll"
            visible: editor.card.plan === true
            primary: true
            text: qsTr("Put windows back")
            enabled: !editor.card.error && (editor.card.rows || []).some(function (r) { return !r.empty })
            onClicked: editor.app.act("open", [editor.card.name], qsTr("Desktop %1 is back as remembered").arg(editor.card.slot))
        }
        ActionButton {
            objectName: "updateFromNow"
            visible: editor.card.plan === true && editor.hasLive
            text: qsTr("Update from now")
            enabled: editor.writable && (editor.card.workspace || 0) > 0
            onClicked: editor.remember()
        }
    }
    Hint {
        visible: !editor.card.plan && editor.hasLive
        text: editor.card.mode === "floating" ? qsTr("Keeps every window where it is, and its size. After a reboot, or with Put windows back, they come back like this.")
            : qsTr("Keeps the apps in their order, left to right. After a reboot, or with Put windows back, they come back like this.")
    }
    RowLayout {
        visible: editor.card.plan === true
        Layout.fillWidth: true
        Switch {
            objectName: "openAtLogin"
            text: qsTr("Open at login")
            checked: editor.card.openAtLogin === true
            enabled: editor.writable && !editor.card.error
            onToggled: { editor.edit("login", checked); checked = Qt.binding(function () { return editor.card.openAtLogin === true }) }
        }
        Item { Layout.fillWidth: true }
        ActionButton { objectName: "removePlan"; text: qsTr("Forget"); enabled: editor.writable; onClicked: editor.removePlan() }
    }

    // Change layout: everything else, out of the way until asked.
    ActionButton {
        objectName: "changeLayout"
        visible: editor.card.plan === true || editor.hasLive
        text: editor.tools ? qsTr("Hide layout options") : qsTr("Change layout...")
        onClicked: editor.moreKey = editor.tools ? "" : editor.card.key
    }
    ColumnLayout {
        visible: editor.tools
        Layout.fillWidth: true
        spacing: 10

        Flow { // wraps the buttons under the picker on a narrow window
            Layout.fillWidth: true
            spacing: 8
            Label { text: qsTr("Layout"); height: layoutPicker.height; verticalAlignment: Text.AlignVCenter }
            Combo {
                id: layoutPicker
                objectName: "layoutPicker"
                width: Math.min(280, editor.width - 60)
                model: editor.options
                textRole: "label"
                valueRole: "value"
                enabled: editor.writable
                currentIndex: Math.max(0, editor.options.findIndex(function (o) { return o.value === (editor.custom ? "custom" : (editor.card.choice || "")) }))
                Accessible.name: qsTr("Layout of desktop %1").arg(editor.card.slot)
                onActivated: {
                    const v = currentValue
                    editor.customKey = v === "custom" ? editor.card.key : ""
                    if (v === "") editor.removePlan()
                    else if (v !== "custom" && v !== editor.card.layout) editor.edit("layout", v)
                    currentIndex = Qt.binding(function () { return Math.max(0, editor.options.findIndex(function (o) { return o.value === (editor.custom ? "custom" : (editor.card.choice || "")) })) })
                }
            }
            ActionButton {
                objectName: "drawZones"
                visible: editor.writable && !editor.drawing && (editor.custom || editor.zoned)
                text: qsTr("Draw zones")
                onClicked: {
                    const z = Zones.ofLayout(editor.card.layout || "")
                    editor.drawText = z.zones ? LayoutOps.toText(z.zones) : "0 0 0.5 1; 0.5 0 0.5 1"
                    editor.drawKey = editor.card.key
                }
            }
        }
        TextField {
            objectName: "zonesField"
            visible: editor.custom
            Layout.fillWidth: true
            enabled: editor.writable
            text: editor.card.choice === "custom" ? editor.card.layout : ""
            placeholderText: "0 0 0.5 1; 0.5 0 0.5 1"
            Accessible.name: qsTr("Custom zones")
            onEditingFinished: if (text.trim() !== "" && text.trim() !== editor.card.layout) editor.edit("layout", text.trim()) // kept as typed when refused, to fix it
        }
        Hint {
            text: qsTr("A zone layout or Free floating makes this desktop floating when the windows are put back. Custom zones are x y w h fractions, separated by ;.")
                + (editor.omagnet.loaded ? " " + qsTr("omagnet snaps windows on this desktop to the same zones.") : "")
        }
        Loader {
            id: drawLoader
            active: editor.drawing
            visible: active
            Layout.fillWidth: true
            Layout.preferredHeight: item ? item.implicitHeight : 0
            sourceComponent: ZoneEditor {
                width: drawLoader.width
                zonesText: editor.drawText
                onEdited: function (text) { editor.drawText = text }
                onCanceled: editor.drawKey = ""
                onSaved: function (text) { editor.drawKey = ""; editor.customKey = editor.card.key; editor.edit("layout", text) }
            }
        }
        Hint { visible: (editor.card.modeNote || "") !== ""; text: editor.card.modeNote || "" }

        Repeater {
            model: editor.card.rows || []
            ColumnLayout {
                id: place
                required property var modelData
                readonly property string rowKey: editor.card.key + "\n" + modelData.pos
                readonly property bool more: !!editor.openRows[rowKey]
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label { Layout.preferredWidth: 90; elide: Text.ElideRight; textFormat: Text.PlainText; text: Desktops.rowTitle(editor.card.layout, place.modelData.pos) }
                    AppPicker {
                        objectName: "zoneApp-" + place.modelData.pos
                        Layout.fillWidth: true
                        apps: editor.apps
                        value: place.modelData.app
                        enabled: editor.writable
                        // the same app again is sent too when its stored class is a guess the page can now confirm
                        onPicked: function (id) {
                            if (id === "" || (id === place.modelData.app && place.modelData.cls === place.modelData.want)) return
                            editor.edit("app", { pos: place.modelData.pos, id: id })
                        }
                    }
                    ActionButton {
                        visible: !place.modelData.empty
                        text: place.more ? qsTr("Less") : qsTr("More")
                        onClicked: { const o = Object.assign({}, editor.openRows); o[place.rowKey] = !place.more; editor.openRows = o }
                    }
                    ActionButton {
                        visible: !place.modelData.empty
                        text: qsTr("Clear")
                        enabled: editor.writable
                        onClicked: editor.edit("clear", place.modelData.pos)
                    }
                }
                Repeater {
                    model: place.modelData.notes || []
                    Hint { required property var modelData; Layout.leftMargin: 98; text: modelData }
                }
                WindowFields {
                    visible: place.more && !place.modelData.empty
                    Layout.fillWidth: true
                    Layout.leftMargin: 98
                    app: editor.app
                    sceneName: editor.card.name || ""
                    win: place.modelData.win || ({})
                    winIndex: place.modelData.index || 0
                    writable: editor.writable
                }
            }
        }
    }
}
