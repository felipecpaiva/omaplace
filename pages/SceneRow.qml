import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One scene: an editable name (Enter renames), its window count, Open, Delete, and when unfolded its windows.
ColumnLayout {
  id: row

  property var panel: null
  property var scene: ({ name: "", windows: [] })
  property bool expanded: false
  signal expandToggled()

  spacing: Style.spacing.xs

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.sm

    TextField {
      id: nameField
      Layout.fillWidth: true
      maximumLength: 40
      enabled: row.panel.info.scenesWritable
      foreground: row.panel.foreground
      accent: row.panel.accent
      onEditingFinished: if (text.trim() !== "" && text.trim() !== row.scene.name) row.panel.renameScene(row.scene.name, text.trim())
    }
    // A plain `text:` binding breaks once the user types; Binding puts the saved name back after a reload.
    Binding { target: nameField; property: "text"; value: row.scene.name; restoreMode: Binding.RestoreNone }

    Text {
      textFormat: Text.PlainText
      text: row.scene.windows.length === 1 ? "1 window" : row.scene.windows.length + " windows"
      color: Qt.darker(row.panel.foreground, 1.6)
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    Button {
      text: "Open"
      bordered: true
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: row.panel.openScene(row.scene.name)
    }
    Button {
      text: row.expanded ? "Hide windows" : "Windows"
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: row.expandToggled()
    }
    Button {
      text: "Delete"
      enabled: row.panel.info.scenesWritable
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: row.panel.askDelete("scene", row.scene.name)
    }
  }

  ListView {
    id: windows
    visible: row.expanded
    Layout.fillWidth: true
    Layout.leftMargin: Style.space(16)
    Layout.preferredHeight: row.expanded ? contentHeight : 0
    interactive: false
    spacing: Style.spacing.sm
    model: row.expanded ? row.scene.windows : []
    delegate: WindowRow {
      required property var modelData
      required property int index
      width: windows.width
      panel: row.panel
      sceneName: row.scene.name
      win: modelData
      winIndex: index
    }
  }

  PanelSeparator { Layout.fillWidth: true; foreground: row.panel.foreground }
}
