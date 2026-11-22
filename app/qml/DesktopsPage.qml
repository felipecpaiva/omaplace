import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Desktops: the map of every desktop of every monitor on the left, the editor of the selected one on the right. Each
// side scrolls on its own, so the editor stays in view while the map scrolls to another monitor.
Item {
    id: page
    property var app
    property string selected: ""
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
                        Label { text: mon.modelData.name; font.bold: true; textFormat: Text.PlainText; Layout.fillWidth: true; elide: Text.ElideRight }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: mapScroll.availableWidth >= 300 ? 5 : 3
                            uniformCellWidths: true
                            columnSpacing: 4
                            rowSpacing: 4
                            Repeater {
                                model: mon.modelData.cards
                                DeskTile {
                                    required property var modelData
                                    objectName: "tile-" + modelData.slot
                                    Layout.fillWidth: true
                                    card: modelData
                                    selected: modelData.key === page.current
                                    onClicked: page.selected = modelData.key
                                }
                            }
                        }
                    }
                }
                Hint { text: qsTr("Pick a desktop to plan it. The word under each one is its layout, or what Omarchy has now.") }
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
                }
            }
        }
    }
}
