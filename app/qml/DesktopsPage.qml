import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../js/Desktops.js" as Desktops

// Desktops: the map of every desktop of every monitor on the left, the editor of the selected one on the right. Each
// side scrolls on its own, so the editor stays in view while the map scrolls to another monitor.
Item {
    id: page
    property var app
    property string selected: ""
    property var unfolded: ({})          // monitors whose empty desktops are shown (D45)
    readonly property var desks: app.model.desks || ({ groups: [], reason: "", loading: true })
    readonly property var groups: desks.groups || []
    readonly property var omagnet: desks.omagnet || ({ loaded: false, layouts: [] })
    readonly property var allCards: [].concat.apply([], groups.map(function (g) { return g.cards }))
    readonly property string current: page.selected !== "" && allCards.some(function (c) { return c.key === page.selected }) ? page.selected
        // first a desktop with something to show (remembered or apps open), on the monitor in use when it has one
        : (allCards.find(function (c) { return c.focused === true && (c.plan || (c.live || []).length > 0) })
           || allCards.find(function (c) { return c.plan || (c.live || []).length > 0 })
           || allCards.find(function (c) { return c.focused === true }) || allCards[0] || { key: "" }).key
    readonly property var chosen: allCards.find(function (c) { return c.key === page.current }) || null
    // first use (D46): nothing remembered yet, apps open on some desktops
    readonly property bool firstRun: allCards.length > 0 && !allCards.some(function (c) { return c.plan }) && allCards.some(function (c) { return (c.live || []).length > 0 })
    readonly property bool askRestart: !page.app.restartAsked && allCards.some(function (c) { return c.plan }) && (page.app.panel.settings || {}).restore_at_login === "off"

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

    Pane {
        objectName: "firstRun"
        visible: page.firstRun
        Layout.fillWidth: true
        padding: 14
        background: Rectangle { color: ui.surface; radius: ui.radius; border.width: 1; border.color: ui.accent }
        contentItem: RowLayout {
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: qsTr("omaplace can put your desktops back the way they are now."); font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Hint { text: qsTr("Each desktop keeps its apps and where they are. An app you open by hand then goes to its desktop too.") }
            }
            ActionButton {
                objectName: "rememberAll"
                primary: true
                text: qsTr("Remember all my desktops")
                onClicked: page.app.act("rememberAll", [], "")
            }
        }
    }
    Pane {
        objectName: "askRestart"
        visible: page.askRestart
        Layout.fillWidth: true
        padding: 14
        background: Rectangle { color: ui.surface; radius: ui.radius; border.width: 1; border.color: ui.accent }
        contentItem: RowLayout {
            spacing: 10
            Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; font.bold: true; text: qsTr("After a restart, should your desktops come back?") }
            ActionButton { objectName: "restartAsk"; primary: true; text: qsTr("Ask me"); onClicked: { page.app.act("setSetting", ["restore_at_login", "ask"], qsTr("After a restart, omaplace asks first")); page.app.restartAsked = true } }
            ActionButton { objectName: "restartAuto"; text: qsTr("Bring them back"); onClicked: { page.app.act("setSetting", ["restore_at_login", "auto"], qsTr("After a restart, your desktops come back")); page.app.restartAsked = true } }
            ActionButton { objectName: "restartNo"; text: qsTr("Not now"); onClicked: page.app.restartAsked = true }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 16

        ScrollView {
            id: mapScroll
            Layout.fillHeight: true
            Layout.preferredWidth: Math.max(240, Math.min(440, page.width * 0.4))
            Layout.fillWidth: false
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: mapScroll.availableWidth
                spacing: 10
                Hint { warn: true; visible: page.app.panel.ok === true && page.app.panel.scenesWritable !== true; text: qsTr("scenes.toml has a newer schema or a scene with a problem: plans are shown but not changed. Fix the file first.") }
                Hint { warn: true; visible: (page.desks.reason || "") !== ""; text: page.desks.reason || "" }
                Hint { visible: page.groups.length === 0; text: page.desks.loading ? qsTr("Reading the desktops...") : qsTr("No monitors found yet. Press F5 to try again.") }
                Repeater {
                    model: page.groups
                    ColumnLayout {
                        id: mon
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        readonly property var fold: Desktops.shownCards(mon.modelData.cards)
                        readonly property bool open: !!page.unfolded[mon.modelData.identity]
                        Label {
                            text: mon.modelData.label || mon.modelData.name
                            font.bold: true; textFormat: Text.PlainText; Layout.fillWidth: true; elide: Text.ElideRight
                            ToolTip.visible: tip.hovered; ToolTip.text: mon.modelData.name
                            HoverHandler { id: tip }
                        }
                        Hint {
                            visible: mon.modelData.noDesktops === true
                            text: mon.modelData.cards.length > 0 ? qsTr("Your workspace rules (hyprmoncfg) give this monitor no desktops of its own. These are the workspaces on it now.")
                                : qsTr("Your workspace rules (hyprmoncfg) give this monitor no desktops of its own.")
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: mapScroll.availableWidth >= 300 ? 5 : 3
                            columnSpacing: 4
                            rowSpacing: 4
                            Repeater {
                                model: mon.open ? mon.modelData.cards : mon.fold.shown
                                DeskTile {
                                    required property var modelData
                                    objectName: "tile-" + modelData.slot
                                    // a fixed share of the row, so two tiles are as big as ten
                                    Layout.preferredWidth: (mapScroll.availableWidth - 16) / (mapScroll.availableWidth >= 300 ? 5 : 3)
                                    Layout.fillWidth: false
                                    card: modelData
                                    selected: modelData.key === page.current
                                    onClicked: page.selected = modelData.key
                                }
                            }
                        }
                        ActionButton {
                            objectName: "unfold"
                            visible: mon.fold.folded > 0
                            text: mon.open ? qsTr("Hide empty desktops") : (mon.fold.folded === 1 ? qsTr("1 empty desktop") : qsTr("%1 empty desktops").arg(mon.fold.folded))
                            onClicked: { const u = Object.assign({}, page.unfolded); u[mon.modelData.identity] = !mon.open; page.unfolded = u }
                        }
                    }
                }

            }
        }

        ScrollView {
            id: editScroll
            Layout.fillWidth: true
            Layout.preferredWidth: 1   // take what the map leaves, never the editor's own wide implicit size
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            Pane {
                visible: page.chosen !== null
                width: editScroll.availableWidth
                padding: 14
                background: Rectangle { color: ui.surface; radius: ui.radius }
                contentItem: DesktopEditor {
                    objectName: "desktopEditor"
                    app: page.app
                    card: page.chosen || ({})
                    apps: page.app.model.apps || []
                    omagnet: page.omagnet
                    monitorLabel: (page.groups.find(function (g) { return g.cards.some(function (c) { return c.key === page.current }) }) || {}).label || ""
                }
            }
        }
    }
    }
}
