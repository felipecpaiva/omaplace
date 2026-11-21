import QtQuick
import qs.Commons

// The layout a desktop has, as a small framed label: accent when the desktop has a plan, dim when not, urgent for a bad plan.
Rectangle {
  id: badge

  property var panel: null
  property string text: ""
  property bool plan: false
  property bool bad: false
  readonly property color tone: badge.bad ? Color.urgent : badge.plan ? badge.panel.accent : Qt.darker(badge.panel.foreground, 1.6)

  implicitWidth: label.implicitWidth + Style.space(12)
  implicitHeight: label.implicitHeight + Style.space(4)
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  color: Qt.rgba(badge.tone.r, badge.tone.g, badge.tone.b, 0.15)
  border.width: 1
  border.color: badge.tone

  Text {
    id: label
    anchors.centerIn: parent
    width: Math.min(implicitWidth, badge.width - Style.space(8))
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: badge.text
    color: badge.panel.foreground
    font.family: badge.panel.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: badge.plan
  }
}
