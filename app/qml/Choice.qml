import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A setting with a few fixed choices: a label, a row of radio buttons, a help line. options: [{ value, label }].
ColumnLayout {
    id: row
    property string title
    property string help
    property string current
    property var options: []
    property bool enabledAll: true
    signal picked(string value)
    Layout.fillWidth: true
    spacing: 2
    Label { text: row.title; color: ui.text; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    Flow {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: row.options
            RadioButton {
                required property var modelData
                text: modelData.label
                checked: modelData.value === row.current
                autoExclusive: false // the saved value decides which one is on, never a click alone
                enabled: row.enabledAll
                Accessible.name: row.title + ": " + modelData.label
                onClicked: {
                    if (modelData.value !== row.current) row.picked(modelData.value)
                    checked = Qt.binding(function () { return modelData.value === row.current })
                }
            }
        }
    }
    Hint { text: row.help; visible: text.length > 0 }
}
