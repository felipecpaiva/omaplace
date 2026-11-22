import QtQuick
import QtQuick.Controls

// A ComboBox whose list has a solid background in every theme (Material's own list background can render see-through).
ComboBox {
    id: combo
    popup.background: Rectangle {
        color: ui.surface
        radius: Math.min(6, ui.radius)
        border.width: 1
        border.color: ui.edge
    }
}
