import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A button that opens a searchable list of installed apps (each with its icon and its hint when two share a name,
// feedback 1). apps: Desktops.appChoices() rows { value, label, icon }. picked(id) on Enter or a click.
Button {
    id: picker
    property var apps: []
    property string value: ""
    property string placeholder: qsTr("Pick an app")
    signal picked(string id)

    readonly property var current: apps.find(function (a) { return a.value === picker.value }) || null
    text: current ? current.label : placeholder
    icon.source: current && current.icon ? backend.iconSource(current.icon) : ""
    icon.color: "transparent"
    leftPadding: 10
    rightPadding: 10
    background: Rectangle {
        implicitHeight: 36
        radius: Math.min(6, ui.radius)
        color: picker.hovered ? ui.off : "transparent"
        border.width: 1
        border.color: picker.activeFocus ? ui.accent : ui.edge
    }
    Accessible.name: qsTr("App: %1").arg(text)
    onClicked: { filter.text = ""; popup.open(); filter.forceActiveFocus() }

    Popup {
        id: popup
        y: picker.height
        width: Math.max(picker.width, 320)
        height: 360
        padding: 8
        focus: true
        background: Rectangle { color: ui.surface; radius: ui.radius; border.color: ui.edge }
        readonly property var shown: {
            const q = filter.text.trim().toLowerCase()
            return q === "" ? picker.apps : picker.apps.filter(function (a) { return a.label.toLowerCase().indexOf(q) !== -1 || a.value.toLowerCase().indexOf(q) !== -1 })
        }
        contentItem: ColumnLayout {
            spacing: 6
            TextField {
                id: filter
                Layout.fillWidth: true
                placeholderText: qsTr("Search apps")
                Keys.onDownPressed: list.forceActiveFocus()
                Keys.onReturnPressed: if (popup.shown.length > 0) { picker.picked(popup.shown[0].value); popup.close() }
                Keys.onEscapePressed: popup.close()
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: popup.shown
                keyNavigationWraps: true
                Keys.onReturnPressed: if (currentIndex >= 0) { picker.picked(popup.shown[currentIndex].value); popup.close() }
                Keys.onEscapePressed: popup.close()
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: list.width
                    text: modelData.label
                    highlighted: ListView.isCurrentItem
                    icon.source: modelData.icon ? backend.iconSource(modelData.icon) : ""
                    icon.color: "transparent"
                    icon.width: 22
                    icon.height: 22
                    onClicked: { picker.picked(modelData.value); popup.close() }
                }
            }
            Hint { visible: popup.shown.length === 0; text: qsTr("No app matches.") }
        }
    }
}
