import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A setting with a few fixed choices: a heading, a row of buttons (the current one bordered), and a note.
// options: [{ value, label, later }]; a `later` choice is shown but cannot be picked yet.
ColumnLayout {
  id: row

  property var panel: null
  property string title: ""
  property string note: ""
  property string current: ""
  property var options: []
  signal picked(string value)

  Layout.fillWidth: true
  spacing: Style.spacing.xs

  PanelSectionHeader { text: row.title; foreground: row.panel.foreground; fontFamily: row.panel.fontFamily }

  ListView {
    id: choices
    Layout.fillWidth: true
    Layout.preferredHeight: contentItem.childrenRect.height
    orientation: ListView.Horizontal
    interactive: false
    spacing: Style.spacing.xs
    model: row.options
    delegate: Button {
      required property var modelData
      text: modelData.later ? modelData.label + " (later)" : modelData.label
      bordered: modelData.value === row.current
      enabled: !modelData.later
      opacity: enabled ? 1 : 0.5
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: if (modelData.value !== row.current) row.picked(modelData.value)
    }
  }

  Note { panel: row.panel; visible: row.note !== ""; text: row.note }
}
