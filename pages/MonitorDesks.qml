import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One monitor on the Desktops page: its name, a grid of its desktops (DeskTile), and the editor of the selected one.
ColumnLayout {
  id: mon

  property var panel: null
  property var view: null          // the DesktopsPage, which keeps the editor state
  property var group: ({ name: "", cards: [] })
  property var apps: []
  property string selected: ""
  readonly property var chosen: mon.group.cards.find(function (c) { return c.key === mon.selected }) || null
  signal picked(string key)

  spacing: Style.spacing.sm

  PanelSectionHeader { text: mon.group.name; foreground: mon.panel.foreground; fontFamily: mon.panel.fontFamily }

  GridView {
    id: grid
    readonly property int perRow: Math.max(1, Math.min(5, Math.floor(width / Style.space(110))))
    Layout.fillWidth: true
    Layout.preferredHeight: Math.ceil(count / perRow) * cellHeight
    interactive: false
    cellWidth: Math.floor(width / perRow)
    cellHeight: Math.round((cellWidth - Style.space(8)) * 9 / 16) + Style.space(56)
    model: mon.group.cards
    delegate: DeskTile {
      required property var modelData
      width: grid.cellWidth
      height: grid.cellHeight
      panel: mon.panel
      card: modelData
      selected: modelData.key === mon.selected
      onPicked: mon.picked(modelData.key)
    }
  }

  DesktopCard {
    visible: mon.chosen !== null
    Layout.fillWidth: true
    panel: mon.panel
    view: mon.view
    model: mon.chosen || ({ key: "", slot: 0, monitorName: "", plan: false, name: "", badge: "", error: "", choice: "", layout: "", modeNote: "", rows: [], openAtLogin: false, mode: "" })
    apps: mon.apps
  }

  PanelSeparator { Layout.fillWidth: true; foreground: mon.panel.foreground }
}
