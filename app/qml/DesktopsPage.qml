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
        : (allCards.find(function (c) { return c.focused === true }) || allCards[0] || { key: "" }).key   // the monitor in use first
    readonly property var chosen: allCards.find(function (c) { return c.key === page.current }) || null

    RowLayout {
        anchors.fill: parent
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
