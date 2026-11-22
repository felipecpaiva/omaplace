import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Restore (today's Session page): restore the last session now, restore at login, the snapshot switch, older sessions.
ScrollView {
    id: page
    property var app
    readonly property var settings: app.panel.settings || ({})
    readonly property var sessions: app.panel.sessions || []
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: page.availableWidth
        spacing: 14

        Card {
            title: qsTr("Bring your windows back")
            help: qsTr("Opens the apps of your last session again, each on its own monitor and desktop. Windows that are open already are moved.")
            ActionButton {
                objectName: "restoreLast"
                text: qsTr("Restore last session")
                primary: true
                onClicked: page.app.act("restore", [""], qsTr("Restoring the last session"))
            }
            Choice {
                objectName: "restoreAtLogin"
                title: qsTr("Restore at login")
                current: page.settings.restore_at_login || "off"
                options: [{ value: "off", label: qsTr("Off") }, { value: "ask", label: qsTr("Ask with a notification") }, { value: "auto", label: qsTr("Automatic") }]
                help: qsTr("Only right after a login or reboot, never after a shell restart.")
                onPicked: function (v) { page.app.act("setSetting", ["restore_at_login", v]) }
            }
            Switch {
                objectName: "sessionSwitch"
                text: qsTr("Keep a session snapshot")
                checked: page.settings.session === "on"
                onToggled: { page.app.act("setSetting", ["session", checked ? "on" : "off"]); checked = Qt.binding(function () { return page.settings.session === "on" }) }
            }
            Hint { text: qsTr("After your windows change, omaplace notes each window's app, monitor and desktop (never window titles), so a reboot can bring them back.") }
        }

        Card {
            objectName: "olderSessions"
            title: qsTr("Older sessions")
            Hint { visible: page.sessions.length === 0; text: qsTr("Nothing saved yet. omaplace saves after your windows change.") }
            Repeater {
                model: page.sessions
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: (modelData.savedAt > 0 ? new Date(modelData.savedAt * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : qsTr("unknown time"))
                            + (modelData.current ? qsTr(" (this login)") : "")
                    }
                    Label {
                        color: ui.secondary
                        text: modelData.windows < 0 ? qsTr("unreadable") : (modelData.windows === 1 ? qsTr("1 window") : qsTr("%1 windows").arg(modelData.windows))
                    }
                    ActionButton {
                        text: qsTr("Restore")
                        enabled: !modelData.current && modelData.windows > 0
                        Accessible.name: qsTr("Restore the session of %1").arg(modelData.savedAt)
                        onClicked: page.app.act("restore", [String(modelData.instance)], qsTr("Restoring"))
                    }
                }
            }
        }
    }
}
