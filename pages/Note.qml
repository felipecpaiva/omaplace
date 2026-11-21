import QtQuick
import QtQuick.Layouts
import qs.Commons

// One caption line under a heading or a control.
Text {
  property var panel: null
  Layout.fillWidth: true
  textFormat: Text.PlainText
  wrapMode: Text.WordWrap
  color: panel ? Qt.darker(panel.foreground, 1.6) : Color.menu.text
  font.family: panel ? panel.fontFamily : Style.font.menuFamily
  font.pixelSize: Style.font.caption
}
