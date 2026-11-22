import QtQuick
import QtQuick.Controls

// A desktop drawn as a monitor-shaped frame with one box per plan row (zone, column or full screen), each with the
// app's icon and name. Rows come from Desktops.js (rect in fractions; an empty "add" row has no rect and is not drawn).
Item {
    id: thumb
    property var rows: []
    property real aspect: 16 / 9
    property bool selected: false
    property bool showNames: true
    property string emptyText: ""

    implicitWidth: 120
    implicitHeight: frame.height

    Rectangle {
        id: frame
        width: thumb.width
        height: thumb.width / thumb.aspect
        color: ui.off
        radius: Math.min(4, ui.radius)
        border.width: thumb.selected ? 3 : 1
        border.color: thumb.selected ? ui.accent : ui.edge

        Label {
            visible: thumb.emptyText !== ""
            anchors.centerIn: parent
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: thumb.emptyText
            color: ui.secondary
            font.pixelSize: 12
        }

        Repeater { // a handful of zones (64 at the very most), never a long list
            model: thumb.rows.filter(function (r) { return r.rect })
            Rectangle {
                id: box
                required property var modelData
                x: modelData.rect[0] * frame.width + 2
                y: modelData.rect[1] * frame.height + 2
                width: Math.max(1, modelData.rect[2] * frame.width - 4)
                height: Math.max(1, modelData.rect[3] * frame.height - 4)
                // a plan's zone in the accent; an app open now (no plan yet, D42) in the text colour, quieter
                readonly property color tone: modelData.live ? ui.text : ui.accent
                color: Qt.rgba(tone.r, tone.g, tone.b, modelData.empty ? 0.08 : modelData.live ? 0.10 : 0.22)
                border.width: 1
                border.color: modelData.live ? ui.edge : ui.accent
                radius: Math.min(3, ui.radius)
                clip: true
                // an open window or a stack of them (D42, D44): icon and names in the top-left corner, like a title bar,
                // and what is true about it in the bottom-right ("full screen", "2 windows")
                Column {
                    visible: box.modelData.live === true
                    x: 4; y: 3
                    width: parent.width - 8
                    spacing: 1
                    Repeater {
                        model: box.modelData.live === true && thumb.showNames ? (box.modelData.names || []).slice(0, 3) : []
                        Row {
                            required property var modelData
                            required property int index
                            spacing: 4
                            Image {
                                visible: index === 0 && box.modelData.icon !== ""
                                width: 14; height: 14
                                sourceSize: Qt.size(28, 28)
                                source: visible ? backend.iconSource(box.modelData.icon) : ""
                            }
                            Label { text: modelData; textFormat: Text.PlainText; color: ui.text; font.pixelSize: 11; elide: Text.ElideRight; width: box.width - 30 }
                        }
                    }
                    Image {
                        visible: !thumb.showNames && box.modelData.live === true && box.modelData.icon !== ""
                        width: 10; height: 10
                        sourceSize: Qt.size(20, 20)
                        source: visible ? backend.iconSource(box.modelData.icon) : ""
                    }
                }
                Label {
                    visible: box.modelData.live === true && (box.modelData.full || box.modelData.count > 1)
                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 3
                    textFormat: Text.PlainText
                    font.pixelSize: thumb.showNames ? 11 : 8
                    color: ui.secondary
                    text: thumb.showNames ? (box.modelData.count > 1 ? qsTr("%1 windows").arg(box.modelData.count) + (box.modelData.full ? qsTr(", full screen") : "") : qsTr("full screen"))
                        : (box.modelData.count > 1 ? String(box.modelData.count) : "")
                }
                Column {
                    visible: box.modelData.live !== true
                    anchors.centerIn: parent
                    width: parent.width - 4
                    spacing: 2
                    Image {
                        visible: !box.modelData.empty && box.modelData.icon !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property int side: Math.max(8, Math.min(28, box.height * 0.45, box.width * 0.6))
                        width: side; height: side
                        sourceSize: Qt.size(side * 2, side * 2)
                        source: visible ? backend.iconSource(box.modelData.icon) : ""
                    }
                    Label {
                        visible: thumb.showNames
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: box.modelData.empty ? qsTr("empty") : box.modelData.label
                        color: box.modelData.empty ? ui.secondary : ui.text
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
