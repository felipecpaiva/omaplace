import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../js/Settings.js" as Settings

// One window of a scene: app, where it goes, and its folder, program and context, each editable (Enter saves). An edit
// is marked in the window's `edited` list, so a later save of the scene keeps it. A window whose profile or folder is
// unknown (context "?") asks for it: the browser's profiles, or a folder for an IDE.
ColumnLayout {
  id: row

  property var panel: null
  property string sceneName: ""
  property var win: ({})
  property int winIndex: 0
  readonly property bool writable: row.panel.info.scenesWritable
  readonly property var need: row.win.need || { kind: "none", profiles: [] }
  readonly property bool unknown: row.win.context === "?"

  function save(field, value) { row.panel.setWindow(row.sceneName, row.winIndex, row.win.class, field, value) }

  spacing: Style.spacing.xxs

  Text {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: row.win.app + ", " + Settings.positionText(row.win) + ", order " + row.win.order
    color: row.panel.foreground
    font.family: row.panel.fontFamily
    font.pixelSize: Style.font.body
  }

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.spacing.sm
    rowSpacing: Style.spacing.xxs

    Note { panel: row.panel; Layout.fillWidth: false; Layout.preferredWidth: Style.space(110); text: Settings.isEdited(row.win, "folder") ? "Folder (edited)" : "Folder" }
    TextField {
      id: folderField
      Layout.fillWidth: true
      enabled: row.writable
      placeholderText: "none"
      foreground: row.panel.foreground
      accent: row.panel.accent
      onEditingFinished: if (text !== row.win.folder) row.save("folder", text)
    }
    Binding { target: folderField; property: "text"; value: row.win.folder; restoreMode: Binding.RestoreNone }

    Note { panel: row.panel; Layout.fillWidth: false; Layout.preferredWidth: Style.space(110); text: Settings.isEdited(row.win, "launch") ? "Program (edited)" : "Program" }
    TextField {
      id: launchField
      Layout.fillWidth: true
      enabled: row.writable
      placeholderText: "none"
      foreground: row.panel.foreground
      accent: row.panel.accent
      onEditingFinished: if (text !== row.win.launch) row.save("launch", text)
    }
    Binding { target: launchField; property: "text"; value: row.win.launch; restoreMode: Binding.RestoreNone }

    Note { panel: row.panel; Layout.fillWidth: false; Layout.preferredWidth: Style.space(110); text: "Profile or project" }
    TextField {
      id: contextField
      visible: !row.unknown
      Layout.fillWidth: true
      enabled: row.writable
      placeholderText: "none"
      foreground: row.panel.foreground
      accent: row.panel.accent
      onEditingFinished: if (text !== row.win.context) row.save("context", text)
    }
    Binding { target: contextField; property: "text"; value: row.win.context; restoreMode: Binding.RestoreNone }

    // Unknown context: the browser's profiles when they were found, a folder chooser for an IDE, else a typed name.
    RowLayout {
      visible: row.unknown
      Layout.fillWidth: true
      spacing: Style.spacing.sm
      Dropdown {
        visible: row.need.kind === "profile" && row.need.profiles.length > 0
        showLabel: false
        value: ""
        options: Settings.profileOptions(row.need.profiles)
        enabled: row.writable
        foreground: row.panel.foreground
        accent: row.panel.accent
        fontFamily: row.panel.fontFamily
        onChanged: function (value) { if (value !== "") row.save("context", value) }
      }
      Button {
        visible: row.need.kind === "folder"
        text: "Choose folder..."
        bordered: true
        enabled: row.writable
        foreground: row.panel.foreground
        accent: row.panel.accent
        fontFamily: row.panel.fontFamily
        onClicked: row.panel.pickFolder(row.sceneName, row.winIndex, row.win.class)
      }
      TextField {
        id: typedField
        visible: row.need.kind === "folder" || row.need.profiles.length === 0
        Layout.fillWidth: true
        enabled: row.writable
        placeholderText: row.need.kind === "folder" ? "or type a folder" : "type the profile name"
        foreground: row.panel.foreground
        accent: row.panel.accent
        onEditingFinished: if (text.trim() !== "") row.save("context", text)
      }
    }
  }

  Note {
    panel: row.panel
    visible: row.unknown
    color: row.panel.accent
    text: "omaplace does not know which profile or project this window had. Pick it once and the scene opens it."
  }
}
