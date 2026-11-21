import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons

// A desktop drawn as a monitor-shaped frame with one box per plan row (zone, column or the full screen), each with the
// app's icon and name. The frame and box style is copied from omagnet's LayoutThumb.qml; rows come from Desktops.js
// (rect in fractions, null for an empty "add" row, which is not drawn).
Item {
  id: thumb

  property var rows: []
  property real aspect: 16 / 9
  property bool selected: false
  property bool showNames: true
  property string emptyText: ""
  property color foreground: "white"
  property color accent: "steelblue"
  property string fontFamily: ""

  implicitWidth: Style.space(120)
  implicitHeight: frame.height

  Rectangle {
    id: frame
    width: thumb.width
    height: thumb.width / thumb.aspect
    color: Qt.rgba(thumb.foreground.r, thumb.foreground.g, thumb.foreground.b, 0.06)
    border.width: thumb.selected ? 3 : 1
    border.color: thumb.selected ? thumb.accent : Qt.rgba(thumb.foreground.r, thumb.foreground.g, thumb.foreground.b, 0.4)

    Text {
      visible: thumb.emptyText !== ""
      anchors.centerIn: parent
      width: parent.width - 8
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: thumb.emptyText
      color: Qt.darker(thumb.foreground, 1.6)
      font.family: thumb.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater { // a handful of zones at most (a layout has 64 at the very most), never a long list
      model: thumb.rows.filter(function (r) { return r.rect })
      Rectangle {
        id: box
        required property var modelData
        x: modelData.rect[0] * frame.width + 2
        y: modelData.rect[1] * frame.height + 2
        width: Math.max(1, modelData.rect[2] * frame.width - 4)
        height: Math.max(1, modelData.rect[3] * frame.height - 4)
        color: Qt.rgba(thumb.accent.r, thumb.accent.g, thumb.accent.b, modelData.empty ? 0.08 : 0.22)
        border.width: 1
        border.color: thumb.accent
        clip: true

        Column {
          anchors.centerIn: parent
          width: parent.width - 4
          spacing: 2
          IconImage {
            visible: !box.modelData.empty && box.modelData.icon !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: Math.max(8, Math.min(Style.space(28), box.height * 0.45, box.width * 0.6))
            source: visible ? Quickshell.iconPath(box.modelData.icon, "application-x-executable") : ""
          }
          Text {
            visible: thumb.showNames
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: box.modelData.empty ? "empty" : box.modelData.label
            color: box.modelData.empty ? Qt.darker(thumb.foreground, 1.6) : thumb.foreground
            font.family: thumb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
