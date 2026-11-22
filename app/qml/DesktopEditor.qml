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
    property bool customOpen: false
    property bool drawing: false
    property string drawText: ""
    property var openRows: ({})
    readonly property bool writable: app.panel.scenesWritable === true && card.editable !== false
    readonly property bool custom: customOpen || card.choice === "custom"
    readonly property var options: card.options || [{ value: "", label: qsTr("No plan") }].concat(Desktops.LAYOUT_CHOICES, [{ value: "custom", label: qsTr("Custom zones") }])
    readonly property bool zoned: !!Zones.ofLayout(card.layout || "").zones

    function edit(op, arg) { app.act("editPlan", [card.identity, card.slot, card.focused === true, op, arg, card.mode || ""]) }
    function removePlan() {
        if (card.plan) app.ask(qsTr("Remove the plan of desktop %1? The file before the change is kept as scenes.toml.bak.").arg(card.slot), "removeScene", [card.name], qsTr("Plan removed"))
    }
    onCardChanged: if (card.choice !== "custom" && card.key !== undefined) customOpen = customOpen && card.layout === ""

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

    Hint { warn: true; visible: (editor.card.error || "") !== ""; text: qsTr("This plan has a problem: %1. Fix it in ~/.config/omaplace/scenes.toml first; nothing is saved until then.").arg(editor.card.error) }
    Hint { warn: true; visible: editor.card.editable === false; text: qsTr("Reading the monitors failed. Press F5 to try again. Nothing can be changed until then.") }

    Flow { // wraps the buttons under the picker on a narrow window
        Layout.fillWidth: true
        spacing: 8
        Label { text: qsTr("Layout"); height: layoutPicker.height; verticalAlignment: Text.AlignVCenter }
        ComboBox {
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
                editor.customOpen = v === "custom"
                if (v === "") editor.removePlan()
                else if (v !== "custom" && v !== editor.card.layout) editor.edit("layout", v)
            }
        }
        Button {
            visible: editor.writable && !editor.drawing && (editor.custom || editor.zoned) && !editor.omagnet.loaded
            text: qsTr("Draw zones")
            onClicked: {
                const z = Zones.ofLayout(editor.card.layout || "")
                editor.drawText = z.zones ? LayoutOps.toText(z.zones) : "0 0 0.5 1; 0.5 0 0.5 1"
                editor.drawing = true
            }
        }
        Button {
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
        onEditingFinished: if (text.trim() !== "" && text.trim() !== editor.card.layout) editor.edit("layout", text.trim())
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
            onCanceled: editor.drawing = false
            onSaved: function (text) { editor.drawing = false; editor.customOpen = true; editor.edit("layout", text) }
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
                Button {
                    visible: !place.modelData.empty
                    text: place.more ? qsTr("Less") : qsTr("More")
                    onClicked: { const o = Object.assign({}, editor.openRows); o[place.rowKey] = !place.more; editor.openRows = o }
                }
                Button {
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
        Button {
            objectName: "openAll"
            text: qsTr("Open all")
            highlighted: true
            enabled: !editor.card.error && (editor.card.rows || []).some(function (r) { return !r.empty })
            onClicked: editor.app.act("open", [editor.card.name], qsTr("Opened desktop %1").arg(editor.card.slot))
        }
        Item { Layout.fillWidth: true }
        Switch {
            text: qsTr("Open at login")
            checked: editor.card.openAtLogin === true
            enabled: editor.writable && !editor.card.error
            onToggled: editor.edit("login", checked)
        }
        Button { text: qsTr("Remove plan"); enabled: editor.writable; onClicked: editor.removePlan() }
    }
    Hint {
        text: editor.card.plan ? qsTr("Open all starts the planned apps that are missing and moves open ones into place. A planned app you open by hand goes to its place too, unless a note above says otherwise.")
            : qsTr("Pick a layout to make a plan for this desktop, then pick an app for each place.")
    }
}
