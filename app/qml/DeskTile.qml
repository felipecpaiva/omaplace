import QtQuick
import QtQuick.Controls

// One desktop on the map: its number and window count, a small preview, and one word for its layout (the plan's,
// else what Omarchy has now). The full badge is in the editor and in the accessible name.
AbstractButton {
    id: tile
    property var card: ({})
    property bool selected: false
    // one word only where there is something to know (D45): remembered, or changed since; nothing under the others
    readonly property string word: card.error ? qsTr("Problem") : card.state === "changed" ? qsTr("Changed") : card.plan ? qsTr("Saved") : ""
    activeFocusOnTab: true
    padding: 3
    Accessible.name: qsTr("Desktop %1, %2").arg(tile.card.number || tile.card.slot).arg(tile.card.badge)
    Keys.onReturnPressed: tile.clicked()
    Keys.onEnterPressed: tile.clicked()

    background: Rectangle {
        color: tile.selected ? Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, 0.12) : tile.hovered ? ui.off : "transparent"
        radius: Math.min(4, ui.radius)
        border.width: tile.activeFocus ? 2 : 0
        border.color: ui.accent
    }
    contentItem: Column {
        spacing: 2
        Label {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: String(tile.card.number || tile.card.slot) + (tile.card.windows > 0 ? "  · " + tile.card.windows : "")
            font.pixelSize: 12
            font.bold: true
            color: tile.selected ? ui.accent : ui.text
        }
        ZoneThumb {
            width: parent.width
            rows: tile.card.plan ? (tile.card.rows || []) : (tile.card.liveRows || []) // no plan: the apps open now (D42)
            showNames: false
            selected: tile.selected
        }
        Label {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: tile.word
            font.pixelSize: 11
            font.bold: tile.card.plan === true
            color: tile.card.error || tile.card.state === "changed" ? ui.warn : ui.accent
        }
    }
}
