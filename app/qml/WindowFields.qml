import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Settings.js" as Settings

// One window of a scene: its folder, program and profile or project, each saved on Enter. A window whose profile or
// folder omaplace could not tell (context "?") asks for it: the browser's profiles, or a folder for an editor.
GridLayout {
    id: row
    property var app
    property string sceneName
    property var win: ({})
    property int winIndex: 0
    property bool writable: true
    readonly property var need: win.need || { kind: "none", profiles: [] }
    readonly property bool unknown: win.context === "?"
    function save(field, value) { app.act("setWindow", [sceneName, winIndex, String(win.class || ""), field, value]) }

    columns: 2
    columnSpacing: 10
    rowSpacing: 4

    Label { text: Settings.isEdited(row.win, "folder") ? qsTr("Folder (edited)") : qsTr("Folder"); color: ui.secondary }
    TextField {
        objectName: "folderField"
        Layout.fillWidth: true
        enabled: row.writable
        text: row.win.folder || ""
        placeholderText: qsTr("none")
        Accessible.name: qsTr("Folder")
        onEditingFinished: { if (text !== (row.win.folder || "")) row.save("folder", text); text = Qt.binding(function () { return row.win.folder || "" }) }
    }
    Label { text: Settings.isEdited(row.win, "launch") ? qsTr("Program (edited)") : qsTr("Program"); color: ui.secondary }
    TextField {
        Layout.fillWidth: true
        enabled: row.writable
        text: row.win.launch || ""
        placeholderText: qsTr("none")
        Accessible.name: qsTr("Program")
        onEditingFinished: { if (text !== (row.win.launch || "")) row.save("launch", text); text = Qt.binding(function () { return row.win.launch || "" }) }
    }
    Label { text: qsTr("Profile or project"); color: ui.secondary }
    TextField {
        visible: !row.unknown
        Layout.fillWidth: true
        enabled: row.writable
        text: row.win.context || ""
        placeholderText: qsTr("none")
        Accessible.name: qsTr("Profile or project")
        onEditingFinished: { if (text !== (row.win.context || "")) row.save("context", text); text = Qt.binding(function () { return row.win.context || "" }) }
    }
    RowLayout {
        visible: row.unknown
        Layout.fillWidth: true
        Combo {
            visible: row.need.kind === "profile" && row.need.profiles.length > 0
            model: Settings.profileOptions(row.need.profiles)
            textRole: "label"
            valueRole: "value"
            enabled: row.writable
            Accessible.name: qsTr("Browser profile")
            onActivated: if (currentValue !== "") row.save("context", currentValue)
        }
        ActionButton {
            objectName: "chooseFolder"
            visible: row.need.kind === "folder"
            text: qsTr("Choose folder...")
            enabled: row.writable
            onClicked: row.app.act("pickFolder", [row.sceneName, row.winIndex, String(row.win.class || "")], qsTr("Pick a folder"))
        }
        TextField {
            visible: row.need.kind === "folder" || row.need.profiles.length === 0
            Layout.fillWidth: true
            enabled: row.writable
            placeholderText: row.need.kind === "folder" ? qsTr("or type a folder") : qsTr("type the profile name")
            onEditingFinished: if (text.trim() !== "") row.save("context", text)
        }
    }
    Hint {
        Layout.columnSpan: 2
        visible: row.unknown
        text: qsTr("omaplace does not know which profile or project this window had. Pick it once and the scene opens it.")
    }
}
