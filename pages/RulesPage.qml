import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Rules: an app always opens on a monitor and desktop. One row per rule; a new rule comes from the focused window.
ColumnLayout {
  id: page

  property var panel: null

  spacing: Style.spacing.sm

  RowLayout {
    Layout.fillWidth: true
    Button {
      text: "Add a rule for the focused window"
      bordered: true
      foreground: page.panel.foreground
      accent: page.panel.accent
      fontFamily: page.panel.fontFamily
      onClicked: page.panel.addRule()
    }
  }
  Note {
    panel: page.panel
    text: "The focused window is the one you used before this window opened. Its app gets a rule for the monitor and desktop it is on now. A browser or editor with many profiles or projects is placed only when omaplace opened it."
  }
  Note {
    panel: page.panel
    visible: page.panel.info.rules.length === 0
    text: "No rules yet."
  }

  ListView {
    id: list
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    spacing: Style.spacing.sm
    boundsBehavior: Flickable.StopAtBounds
    model: page.panel.info.rules
    delegate: RuleRow {
      required property var modelData
      width: list.width
      panel: page.panel
      rule: modelData
    }
  }
}
