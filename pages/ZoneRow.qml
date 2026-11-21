import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../js/Desktops.js" as Desktops

// One place of a plan (zone, column, full screen or free window): an app picker of the installed apps, Clear, the notes
// on why it may not snap, and under "More" the window's profile, folder and program (WindowRow, as on the Scenes page).
ColumnLayout {
  id: row

  property var panel: null
  property var card: ({})
  property var place: ({})
  property var apps: []
  property var view: null          // the DesktopsPage: which rows show More survives a rebuild there
  readonly property string rowKey: row.card.key + "\n" + row.place.pos
  readonly property bool more: !!row.view && !!row.view.openRows[row.rowKey]
  readonly property bool writable: row.panel.info.scenesWritable

  spacing: Style.spacing.xxs

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.sm

    Text {
      Layout.preferredWidth: Style.space(90)
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: Desktops.rowTitle(row.card.layout, row.place.pos)
      color: row.panel.foreground
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.body
    }
    SearchableDropdown {
      Layout.fillWidth: true
      showLabel: false
      value: row.place.app
      triggerLabel: row.place.empty ? "Pick an app" : row.place.label
      options: row.apps
      enabled: row.writable
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onChanged: function (value) { if (value !== "" && value !== row.place.app) row.panel.editPlan(row.card, "app", { pos: row.place.pos, id: value }) }
    }
    Button {
      visible: !row.place.empty
      text: row.more ? "Less" : "More"
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: row.view.toggleRow(row.rowKey)
    }
    Button {
      visible: !row.place.empty
      text: "Clear"
      enabled: row.writable
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: row.panel.editPlan(row.card, "clear", row.place.pos)
    }
  }

  ListView {
    id: notes
    Layout.fillWidth: true
    Layout.leftMargin: Style.space(90) + Style.spacing.sm
    Layout.preferredHeight: contentHeight
    interactive: false
    model: row.place.notes
    delegate: Note {
      required property var modelData
      width: notes.width
      panel: row.panel
      color: row.panel.accent
      text: modelData
    }
  }

  Loader {
    id: windowLoader
    active: row.more && !row.place.empty
    visible: active
    Layout.fillWidth: true
    Layout.leftMargin: Style.space(90) + Style.spacing.sm
    Layout.preferredHeight: item ? item.implicitHeight : 0
    sourceComponent: WindowRow {
      width: windowLoader.width
      panel: row.panel
      sceneName: row.card.name
      win: row.place.win
      winIndex: row.place.index
    }
  }
}
