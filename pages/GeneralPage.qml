import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../js/Settings.js" as Settings
import "../js/ConfigIO.js" as ConfigIO

// General: app memory, what a scene does with open apps, missing monitors, ignored apps, and an Advanced fold with the
// timing settings and their limits.
Flickable {
  id: page

  property var panel: null
  property bool advanced: false
  readonly property var settings: page.panel.info.settings

  clip: true
  contentWidth: width
  contentHeight: column.implicitHeight
  boundsBehavior: Flickable.StopAtBounds

  ColumnLayout {
    id: column
    width: page.width
    spacing: Style.spacing.md

    ChoiceRow {
      panel: page.panel
      title: "App memory"
      current: page.settings.app_memory || "scene"
      options: [{ value: "scene", label: "Scene place" }, { value: "last_place", label: "Last place" }, { value: "auto", label: "Automatic" }, { value: "off", label: "Off" }]
      note: "Where an app you open by hand goes. Scene place: where the last scene put it. Last place: where you last closed it. Automatic: like Last place, and moving an app between two desktops that show a scene moves it from one scene to the other. Off: apps open where Hyprland puts them."
      onPicked: function (value) { page.panel.setSetting("app_memory", value) }
    }
    ChoiceRow {
      panel: page.panel
      title: "Apps already open when a scene opens"
      current: page.settings.existing_default || "move"
      options: [{ value: "move", label: "Move them" }, { value: "new", label: "Open new ones" }]
      onPicked: function (value) { page.panel.setSetting("existing_default", value) }
    }
    ChoiceRow {
      panel: page.panel
      title: "Scene monitor not connected"
      current: page.settings.missing_monitor_scene || "focused"
      options: [{ value: "focused", label: "Use the focused monitor" }, { value: "skip", label: "Skip" }]
      onPicked: function (value) { page.panel.setSetting("missing_monitor_scene", value) }
    }
    ChoiceRow {
      panel: page.panel
      title: "Rule monitor not connected"
      current: page.settings.missing_monitor_rule || "skip"
      options: [{ value: "focused", label: "Use the focused monitor" }, { value: "skip", label: "Skip" }]
      onPicked: function (value) { page.panel.setSetting("missing_monitor_rule", value) }
    }

    PanelSectionHeader { text: "Ignored apps"; foreground: page.panel.foreground; fontFamily: page.panel.fontFamily }
    TextField {
      id: ignoreField
      Layout.fillWidth: true
      placeholderText: "steam, mpv"
      foreground: page.panel.foreground
      accent: page.panel.accent
      onEditingFinished: if (text.trim() !== (page.settings.ignore || "")) page.panel.setSetting("ignore", text)
    }
    Binding { target: ignoreField; property: "text"; value: page.settings.ignore || ""; restoreMode: Binding.RestoreNone }
    Note { panel: page.panel; text: "Window classes omaplace leaves alone, separated by commas." }

    PanelSectionHeader { text: "Omarchy menu"; foreground: page.panel.foreground; fontFamily: page.panel.fontFamily }
    Button {
      text: page.panel.info.menu ? "Remove from the menu" : "Add omaplace to the Omarchy menu"
      enabled: page.panel.info.ok
      foreground: page.panel.foreground
      accent: page.panel.accent
      fontFamily: page.panel.fontFamily
      onClicked: if (page.panel.info.menu) page.panel.removeMenu(); else page.panel.addMenu()
    }
    Note {
      panel: page.panel
      text: "Adds a Scenes menu (save, open, restore, always open here, settings). The menu file is backed up first, as omarchy-menu.jsonc.omaplace.bak."
    }

    Button {
      text: page.advanced ? "Hide advanced settings" : "Show advanced settings (7)"
      foreground: page.panel.foreground
      accent: page.panel.accent
      fontFamily: page.panel.fontFamily
      onClicked: page.advanced = !page.advanced
    }

    ListView {
      id: timing
      visible: page.advanced
      Layout.fillWidth: true
      Layout.preferredHeight: page.advanced ? contentHeight : 0
      interactive: false
      spacing: Style.spacing.xs
      model: page.advanced && page.panel.info.ok ? Settings.timingRows(ConfigIO.SETTING_SPECS, page.settings) : []
      delegate: RowLayout {
        required property var modelData
        width: timing.width
        spacing: Style.spacing.md
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: modelData.label + ", " + modelData.min + " to " + modelData.max
          color: page.panel.foreground
          font.family: page.panel.fontFamily
          font.pixelSize: Style.font.body
        }
        NumberField {
          value: modelData.value
          from: modelData.min
          to: modelData.max
          foreground: page.panel.foreground
          accent: page.panel.accent
          fontFamily: page.panel.fontFamily
          onModified: function (value) { if (value !== modelData.value) page.panel.setSetting(modelData.key, value) }
        }
      }
    }
  }
}
