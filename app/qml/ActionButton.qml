import QtQuick
import QtQuick.Controls

// A button that looks like one in every theme: filled with the accent for the main action of a card (`primary`),
// outlined for the others. Material's own button fill can vanish on the app's dark surfaces.
Button {
    id: b
    property bool primary: false
    leftPadding: 14
    rightPadding: 14
    contentItem: Label {
        text: b.text
        textFormat: Text.PlainText
        color: b.primary && b.enabled ? ui.ink : ui.text
        opacity: b.enabled ? 1 : 0.5
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        implicitHeight: 36
        implicitWidth: 64
        radius: Math.min(6, ui.radius)
        color: b.primary ? (b.enabled ? (b.down ? Qt.darker(ui.accent, 1.15) : ui.accent) : ui.off) : (b.down ? ui.edge : b.hovered ? ui.off : "transparent")
        border.width: b.primary ? 0 : 1
        border.color: b.activeFocus ? ui.accent : ui.edge
    }
}
