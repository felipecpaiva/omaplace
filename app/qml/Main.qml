import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../js/Settings.js" as Settings

// The omaplace settings app (design 17): five pages in a sidebar. Every action is one request to the omaplace service,
// which saves it and sends the next model back (backend.model). Nothing is written here.
ApplicationWindow {
    id: win
    objectName: "main"
    width: 1040; height: 720; minimumWidth: 720; minimumHeight: 520
    visible: true
    title: qsTr("omaplace settings")
    color: ui.background
    Material.theme: ui.light ? Material.Light : Material.Dark
    Material.accent: ui.accent
    Material.foreground: ui.text
    Material.roundedScale: desktopTheme.radius

    AppTheme { id: ui }

    readonly property var model: backend.model
    readonly property var panel: model.panel || Settings.emptyData()
    readonly property bool ready: backend.connected
    readonly property var pages: [qsTr("Desktops"), qsTr("Apps"), qsTr("Scenes"), qsTr("Restore"), qsTr("General")]
    property int page: 0
    property string toast: ""
    property bool toastBad: false
    property var confirm: null           // { text, op, args, ok }
    property var okTexts: ({})           // request id -> the text shown when it works

    // One action through the service; the reply's text goes to the toast.
    // The control that made an edit gets the keyboard focus back after the page is rebuilt from the reply (by its
    // objectName, since a rebuilt list makes new controls).
    property string focusName: ""
    function findNamed(item, name) {
        if (!item || name === "") return null
        if (item.objectName === name && item.visible) return item
        for (let i = 0; i < item.children.length; i++) { const f = win.findNamed(item.children[i], name); if (f) return f }
        return null
    }
    function act(op, args, okText) {
        win.focusName = win.activeFocusItem ? win.activeFocusItem.objectName : ""
        const id = backend.request(op, args || [])
        const t = Object.assign({}, win.okTexts); t[id] = okText || qsTr("Saved"); win.okTexts = t
        return id
    }
    function ask(text, op, args, okText) { win.confirm = { text: text, op: op, args: args, ok: okText }; confirmDialog.open() }
    function show(text, bad) { win.toast = text; win.toastBad = bad; toastTimer.restart() }

    Connections {
        target: backend
        function onModelChanged() {
            if (win.focusName === "") return
            Qt.callLater(function () {
                const f = win.findNamed(win.contentItem, win.focusName)
                if (f && !f.activeFocus) f.forceActiveFocus()
            })
        }
        function onReplied(id, op, answer) {
            const key = id.indexOf("done-") === 0 ? "" : id
            const okText = win.okTexts[key] || (op === "open" ? qsTr("Opened") : op === "restore" ? qsTr("Restored") : qsTr("Saved"))
            const a = Settings.answerText(JSON.stringify(answer), okText)
            if (op === "refresh" && a.ok) return
            win.show(answer.text && a.ok ? answer.text : a.text, !a.ok)
        }
    }
    Timer { id: toastTimer; interval: win.toastBad ? 8000 : 3500; onTriggered: win.toast = "" }

    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W"]; context: Qt.ApplicationShortcut; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+1"; context: Qt.ApplicationShortcut; onActivated: win.page = 0 }
    Shortcut { sequence: "Ctrl+2"; context: Qt.ApplicationShortcut; onActivated: win.page = 1 }
    Shortcut { sequence: "Ctrl+3"; context: Qt.ApplicationShortcut; onActivated: win.page = 2 }
    Shortcut { sequence: "Ctrl+4"; context: Qt.ApplicationShortcut; onActivated: win.page = 3 }
    Shortcut { sequence: "Ctrl+5"; context: Qt.ApplicationShortcut; onActivated: win.page = 4 }
    Shortcut { sequence: "F5"; context: Qt.ApplicationShortcut; onActivated: win.act("refresh", []) }
    Shortcut { sequences: ["?", "Shift+?", "F1"]; context: Qt.ApplicationShortcut; onActivated: help.open() }

    Dialog {
        id: help
        objectName: "help"
        title: qsTr("Keyboard shortcuts")
        background: Rectangle { color: ui.surface; radius: Math.min(8, ui.radius); border.width: 1; border.color: ui.edge }
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok
        Label {
            textFormat: Text.PlainText
            text: qsTr("Ctrl+1 to Ctrl+5: the pages\nTab, Shift+Tab: move between controls\nEnter or Space: press the control\n? or F1: this list\nF5: read the desktops again\nCtrl+W or Ctrl+Q: close")
        }
    }

    Dialog {
        id: confirmDialog
        objectName: "confirm"
        anchors.centerIn: parent
        modal: true
        title: qsTr("Are you sure?")
        background: Rectangle { color: ui.surface; radius: Math.min(8, ui.radius); border.width: 1; border.color: ui.edge }
        standardButtons: Dialog.Yes | Dialog.Cancel
        width: Math.min(480, win.width - 40)
        Label { textFormat: Text.PlainText; wrapMode: Text.WordWrap; width: confirmDialog.availableWidth; text: win.confirm ? win.confirm.text : "" }
        onAccepted: { const c = win.confirm; win.confirm = null; if (c) win.act(c.op, c.args, c.ok) }
        onRejected: win.confirm = null
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            Layout.preferredWidth: 160
            Layout.maximumWidth: 160
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 6
            Label { text: "omaplace"; font.pixelSize: 22; font.bold: true; Layout.bottomMargin: 16 }
            Repeater {
                model: win.pages
                Button {
                    required property int index
                    required property string modelData
                    objectName: "nav" + index
                    Layout.fillWidth: true
                    text: modelData
                    highlighted: win.page === index
                    Accessible.name: modelData
                    contentItem: Label { text: parent.text; color: parent.highlighted ? ui.ink : ui.text; horizontalAlignment: Text.AlignLeft; verticalAlignment: Text.AlignVCenter; leftPadding: 12 }
                    background: Rectangle { color: parent.highlighted ? ui.accent : parent.activeFocus ? ui.off : "transparent"; radius: ui.radius }
                    onClicked: win.page = index
                }
            }
            Item { Layout.fillHeight: true }
            Label { text: qsTr("Saved as you go"); color: ui.secondary; font.pixelSize: 12 }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Label { text: win.pages[win.page]; font.pixelSize: 26; font.bold: true }

            // The service is not there, too old, or another version: say so, never an empty page (D38).
            Pane {
                objectName: "problem"
                visible: backend.problem !== "" || !win.ready
                Layout.fillWidth: true
                padding: 14
                background: Rectangle { color: ui.surface; radius: ui.radius; border.color: ui.warn; border.width: backend.problem !== "" ? 1 : 0 }
                contentItem: RowLayout {
                    spacing: 10
                    Hint { warn: backend.problem !== ""; text: backend.problem !== "" ? backend.problem : qsTr("Connecting to omaplace...") }
                    ActionButton { visible: backend.problem !== ""; text: qsTr("Try again"); onClicked: backend.start() }
                }
            }
            Hint {
                visible: win.ready && win.panel.warnings && win.panel.warnings.length > 0
                warn: true
                text: (win.panel.warnings || []).join("\n")
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page
                visible: win.ready
                DesktopsPage { app: win }
                AppsPage { app: win }
                ScenesPage { app: win }
                RestorePage { app: win }
                GeneralPage { app: win }
            }

            Pane {
                objectName: "toast"
                visible: win.toast !== ""
                Layout.fillWidth: true
                padding: 10
                background: Rectangle { color: win.toastBad ? ui.warn : ui.surface; radius: ui.radius; opacity: win.toastBad ? 0.25 : 1 }
                contentItem: Label { text: win.toast; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: ui.text }
            }
        }
    }
}
