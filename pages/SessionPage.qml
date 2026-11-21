import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Session: the snapshot switch, restore the last session or a saved one, and restore at login (only off for now).
ColumnLayout {
  id: page

  property var panel: null
  readonly property var settings: page.panel.info.settings

  spacing: Style.spacing.sm

  Toggle {
    Layout.fillWidth: true
    label: "Keep a session snapshot"
    description: "After window changes, omaplace notes every window's app, monitor and desktop, so a reboot can bring them back."
    checked: page.settings.session === "on"
    foreground: page.panel.foreground
    accent: page.panel.accent
    fontFamily: page.panel.fontFamily
    onClicked: page.panel.setSetting("session", page.settings.session === "on" ? "off" : "on")
  }

  RowLayout {
    Layout.fillWidth: true
    Button {
      text: "Restore last session"
      bordered: true
      foreground: page.panel.foreground
      accent: page.panel.accent
      fontFamily: page.panel.fontFamily
      onClicked: page.panel.restore("")
    }
  }

  ChoiceRow {
    panel: page.panel
    title: "Restore at login"
    current: page.settings.restore_at_login || "off"
    options: [{ value: "off", label: "Off" }, { value: "ask", label: "Ask", later: true }, { value: "auto", label: "Automatic", later: true }]
    note: "Coming later. For now, restore by hand with the button above or: omaplace restore"
    onPicked: function (value) { page.panel.setSetting("restore_at_login", value) }
  }

  PanelSectionHeader { text: "Saved sessions"; foreground: page.panel.foreground; fontFamily: page.panel.fontFamily }
  Note {
    panel: page.panel
    visible: page.panel.info.sessions.length === 0
    text: "No session saved yet."
  }

  ListView {
    id: list
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds
    model: page.panel.info.sessions
    delegate: SessionRow {
      required property var modelData
      width: list.width
      panel: page.panel
      session: modelData
    }
  }
}
