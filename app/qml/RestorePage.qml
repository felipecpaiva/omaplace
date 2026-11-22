import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// After a restart (D46): one question, one button to bring the last session back now, and the rest under Earlier and
// Advanced. The question is restore_at_login only; what each remembered desktop does at login stays its own switch.
ScrollView {
    id: page
    property var app
    property bool earlier: false
    readonly property var settings: app.panel.settings || ({})
    readonly property var sessions: app.panel.sessions || []
    readonly property var older: sessions.filter(function (s) { return !s.current })
    contentWidth: availableWidth
    clip: true

    ColumnLayout {
        width: page.availableWidth
        spacing: 14

        Card {
            title: qsTr("After a restart, should your desktops come back?")
            Choice {
                objectName: "restoreAtLogin"
                current: page.settings.restore_at_login || "off"
                options: [{ value: "ask", label: qsTr("Ask me") }, { value: "auto", label: qsTr("Bring them back") }, { value: "off", label: qsTr("Do nothing") }]
                onPicked: function (v) { page.app.act("setSetting", ["restore_at_login", v], v === "ask" ? qsTr("After a restart, omaplace asks first") : v === "auto" ? qsTr("After a restart, your desktops come back") : qsTr("After a restart, nothing happens")) }
            }
            Hint { visible: page.settings.session !== "on"; warn: true; text: qsTr("omaplace is not keeping track of your windows now, so there is nothing to bring back. Turn it on under Advanced.") }
        }

        Card {
            title: qsTr("Bring back the last session now")
            help: page.older.length > 0 ? qsTr("Opens the apps you had before the last restart, each on its own monitor and desktop.") : qsTr("Nothing saved yet. omaplace saves after your windows change.")
            ActionButton {
                objectName: "restoreLast"
                primary: true
                text: qsTr("Bring it back")
                enabled: page.older.length > 0
                onClicked: page.app.act("restore", [""], qsTr("Bringing back the last session"))
            }
        }

        ActionButton {
            objectName: "earlier"
            text: page.earlier ? qsTr("Hide earlier sessions and advanced") : qsTr("Earlier sessions and advanced...")
            onClicked: page.earlier = !page.earlier
        }
        Card {
            visible: page.earlier
            title: page.older.length > 1 ? qsTr("Earlier sessions") : qsTr("Advanced")
            Repeater {
                model: page.older.length > 1 ? page.older : []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10
                    Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: modelData.savedAt > 0 ? new Date(modelData.savedAt * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : qsTr("unknown time")
                    }
                    Label { color: ui.secondary; text: modelData.windows < 0 ? qsTr("unreadable") : (modelData.windows === 1 ? qsTr("1 window") : qsTr("%1 windows").arg(modelData.windows)) }
                    ActionButton {
                        text: qsTr("Bring back")
                        enabled: modelData.windows > 0
                        onClicked: page.app.act("restore", [String(modelData.instance)], qsTr("Bringing it back"))
                    }
                }
            }
            Switch {
                objectName: "sessionSwitch"
                text: qsTr("Keep track of my windows (needed to bring them back)")
                checked: page.settings.session === "on"
                onToggled: { page.app.act("setSetting", ["session", checked ? "on" : "off"]); checked = Qt.binding(function () { return page.settings.session === "on" }) }
            }
            Hint { text: qsTr("omaplace notes each window's app, monitor and desktop, never window titles.") }
        }
    }
}
