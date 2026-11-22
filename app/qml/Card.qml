import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A titled group of settings on a page (the omadials-settings card).
Pane {
    id: card
    property string title
    property string help
    default property alias rows: body.data
    Layout.fillWidth: true
    padding: 16
    background: Rectangle { color: ui.surface; radius: ui.radius }
    contentItem: ColumnLayout {
        id: body
        spacing: 10
        Label { text: card.title; font.bold: true; font.pixelSize: 16; color: ui.text; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        Hint { text: card.help; visible: text.length > 0 }
    }
}
