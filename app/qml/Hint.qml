import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One line of help or a note under a control. `warn` paints it in the theme's warning colour.
Label {
    property bool warn: false
    Layout.fillWidth: true
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: warn ? ui.warn : ui.secondary
    font.pixelSize: 13
}
