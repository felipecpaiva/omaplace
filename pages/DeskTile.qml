import QtQuick
import qs.Commons

// One desktop in the grid: its number, the window count, a small preview and the layout badge. Click to edit it below.
Item {
  id: tile

  property var panel: null
  property var card: ({})
  property bool selected: false
  signal picked()

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(4)
    spacing: Style.space(3)

    Text {
      width: parent.width
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: "Desktop " + tile.card.slot + (tile.card.windows > 0 ? ", " + tile.card.windows + (tile.card.windows === 1 ? " window" : " windows") : "")
      color: tile.panel.foreground
      font.family: tile.panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: tile.selected
    }
    ZoneThumb {
      width: parent.width
      rows: tile.card.rows
      showNames: false
      selected: tile.selected
      emptyText: tile.card.plan ? "" : "No plan"
      foreground: tile.panel.foreground
      accent: tile.panel.accent
      fontFamily: tile.panel.fontFamily
    }
    LayoutBadge {
      width: Math.min(implicitWidth, parent.width)
      panel: tile.panel
      text: tile.card.badge
      plan: tile.card.plan
      bad: tile.card.error !== ""
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.picked()
  }
}
