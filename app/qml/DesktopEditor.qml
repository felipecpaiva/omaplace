import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Desktops.js" as Desktops
import "../js/Zones.js" as Zones
import "../js/LayoutOps.js" as LayoutOps

// The selected desktop: its layout picker (in the order that fits the desktop now, D34, D35), custom zones (typed or
// drawn), a preview, one row per place with an app picker, Open all, Open at login and Remove plan. Every change is one
// editPlan request; the card comes back rebuilt from the files.
ColumnLayout {
    id: editor
    property var app
    property var card: ({})
    property var apps: []
    property var omagnet: ({ loaded: false, layouts: [] })
    // Which desktop has the custom zones field open and which one is being drawn: by card key, so another desktop
    // picked meanwhile never gets them (and a Save always writes the desktop it was drawn for).
    property string customKey: ""
    property string drawKey: ""
    property string drawText: ""
    readonly property bool drawing: drawKey !== "" && drawKey === card.key
    property var openRows: ({})
    readonly property bool writable: app.panel.scenesWritable === true && card.editable !== false
    readonly property bool custom: customKey === card.key || card.choice === "custom"
    readonly property var options: card.options || [{ value: "", label: qsTr("No plan") }].concat(Desktops.LAYOUT_CHOICES, [{ value: "custom", label: qsTr("Custom zones") }])
    readonly property bool zoned: !!Zones.ofLayout(card.layout || "").zones

    function edit(op, arg) { app.act("editPlan", [card.identity, card.slot, card.focused === true, op, arg, card.mode || ""]) }
    function removePlan() {
        if (card.plan) app.ask(qsTr("Remove the plan of desktop %1? The file before the change is kept as scenes.toml.bak.").arg(card.slot), "removeScene", [card.name], qsTr("Plan removed"))
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.bold: true
            font.pixelSize: 16
            text: qsTr("Desktop %1 on %2").arg(editor.card.slot).arg(editor.card.monitorName || "")
        }
        Label { color: ui.secondary; text: editor.card.badge || ""; elide: Text.ElideRight; Layout.maximumWidth: editor.width / 2 }
    }

    // The apps open on this desktop now (D41), and one button to make them its plan, as they are placed now.
    Pane {
        objectName: "openNow"
        visible: (editor.card.live || []).length > 0
        Layout.fillWidth: true
        padding: 10
        background: Rectangle { color: ui.off; radius: Math.min(6, ui.radius) }
        contentItem: ColumnLayout {
            spacing: 6
            Label { text: qsTr("Open on this desktop now"); font.bold: true }
            ZoneThumb {
                objectName: "livePreview"
                visible: !editor.card.plan && (editor.card.liveRows || []).length > 0
                Layout.preferredWidth: Math.min(editor.width - 20, 320)
                rows: editor.card.liveRows || []
            }
            Flow {
                Layout.fillWidth: true
                spacing: 10
                Repeater {
                    model: editor.card.live || []
                    Row {
                        required property var modelData
                        spacing: 4
                        Image { source: modelData.icon ? backend.iconSource(modelData.icon) : ""; visible: source != ""; width: 18; height: 18; sourceSize: Qt.size(36, 36); anchors.verticalCenter: parent.verticalCenter }
                        Label { text: modelData.label; textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                ActionButton {
                    objectName: "planFromDesktop"
                    primary: !editor.card.plan
                    text: editor.card.plan ? qsTr("Replace the plan with these") : qsTr("Make these the plan")
                    enabled: editor.writable && (editor.card.workspace || 0) > 0
                    onClicked: {
                        const args = [editor.card.identity, editor.card.slot, editor.card.focused === true, editor.card.mode || "", editor.card.workspace]
                        const n = (editor.card.live || []).length
                        const done = qsTr("Desktop %1 has a plan with the apps open on it").arg(editor.card.slot)
                        if (editor.card.plan) editor.app.ask(qsTr("Replace the plan of desktop %1 with the %2 apps open on it now? The file before the change is kept as scenes.toml.bak.").arg(editor.card.slot).arg(n), "planFromDesktop", args, done)
                        else editor.app.act("planFromDesktop", args, done)
                    }
                }
                Hint { text: editor.card.mode === "floating" ? qsTr("Each window keeps its size and spot.") : qsTr("The apps keep their order, left to right.") }
            }
        }
    }

    Hint { warn: true; visible: (editor.card.error || "") !== ""; text: qsTr("This plan has a problem: %1. Fix it in ~/.config/omaplace/scenes.toml first; nothing is saved until then.").arg(editor.card.error) }
    Hint { warn: true; visible: editor.card.editable === false; text: qsTr("Reading the monitors failed. Press F5 to try again. Nothing can be changed until then.") }

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
                // show the saved layout until the reply (and after a Cancel or a refusal)
                currentIndex = Qt.binding(function () { return Math.max(0, editor.options.findIndex(function (o) { return o.value === (editor.custom ? "custom" : (editor.card.choice || "")) })) })
            }
        }
        ActionButton {
            objectName: "drawZones"
            visible: editor.writable && !editor.drawing && (editor.custom || editor.zoned) && !editor.omagnet.loaded
            text: qsTr("Draw zones")
            onClicked: {
                const z = Zones.ofLayout(editor.card.layout || "")
                editor.drawText = z.zones ? LayoutOps.toText(z.zones) : "0 0 0.5 1; 0.5 0 0.5 1"
                editor.drawKey = editor.card.key
            }
        }
        ActionButton {
            visible: editor.omagnet.loaded
            text: qsTr("Edit in omagnet")
            onClicked: editor.app.act("openOmagnet", [], qsTr("Opened omagnet's settings"))
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
        text: qsTr("A zone layout or Free floating switches this desktop to floating when you press Open all. Custom zones are x y w h fractions, separated by ;.")
            + (editor.omagnet.loaded ? " " + qsTr("Layouts made in omagnet show in the list after you press F5.") : "")
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

    ZoneThumb {
        visible: editor.card.plan === true && !editor.card.error
        Layout.preferredWidth: Math.min(editor.width, 360)
        rows: editor.card.rows || []
    }

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

    RowLayout {
        visible: editor.card.plan === true
        Layout.fillWidth: true
        spacing: 8
        ActionButton {
            objectName: "openAll"
            text: qsTr("Open all")
            primary: true
            enabled: !editor.card.error && (editor.card.rows || []).some(function (r) { return !r.empty })
            onClicked: editor.app.act("open", [editor.card.name], qsTr("Opened desktop %1").arg(editor.card.slot))
        }
        Item { Layout.fillWidth: true }
        Switch {
            objectName: "openAtLogin"
            text: qsTr("Open at login")
            checked: editor.card.openAtLogin === true
            enabled: editor.writable && !editor.card.error
            onToggled: { editor.edit("login", checked); checked = Qt.binding(function () { return editor.card.openAtLogin === true }) }
        }
        ActionButton { text: qsTr("Remove plan"); enabled: editor.writable; onClicked: editor.removePlan() }
    }
    Hint {
        text: editor.card.plan ? qsTr("Open all starts the planned apps that are missing and moves open ones into place. A planned app you open by hand goes to its place too, unless a note above says otherwise.")
            : qsTr("Pick a layout to make a plan for this desktop, then pick an app for each place.")
    }
}
