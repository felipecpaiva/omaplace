import QtQuick
import QtQuick.Controls

// A small picture of a screen with boxes (an arrangement or a spot), named on hover and for screen readers (D53).
// rects: fractions of the screen; the last one is filled when `last` is set (the window being moved).
AbstractButton {
    id: b
    property var rects: []
    property bool last: false
    property string tip: ""
    implicitWidth: 52
    implicitHeight: 36
    padding: 4
    activeFocusOnTab: true
    Accessible.name: tip
    ToolTip.visible: hovered || activeFocus
    ToolTip.delay: 300
    ToolTip.text: tip
    Keys.onReturnPressed: b.clicked()
    Keys.onSpacePressed: b.clicked()
    background: Rectangle {
        radius: Math.min(4, ui.radius)
        color: b.down ? ui.edge : b.hovered ? ui.off : "transparent"
        border.width: 1
        border.color: b.activeFocus ? ui.accent : ui.edge
    }
    contentItem: Item {
        Rectangle { // the screen
            id: screen
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: ui.secondary
            radius: 2
            Repeater {
                model: b.rects
                Rectangle {
                    required property var modelData
                    required property int index
                    x: modelData[0] * screen.width + 1.5
                    y: modelData[1] * screen.height + 1.5
                    width: Math.max(1, modelData[2] * screen.width - 3)
                    height: Math.max(1, modelData[3] * screen.height - 3)
                    radius: 1
                    color: Qt.rgba(ui.accent.r, ui.accent.g, ui.accent.b, b.last && index !== b.rects.length - 1 ? 0.15 : 0.55)
                }
            }
        }
    }
}
