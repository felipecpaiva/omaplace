import QtQuick
import QtQuick.Layouts
import qs.Commons

// Scenes: one row per scene (open, rename, delete, its windows). Which scenes are unfolded lives here, so a reload of
// the list keeps them unfolded.
ColumnLayout {
  id: page

  property var panel: null
  property var expanded: ({})

  function setExpanded(name, on) {
    let o = Object.assign({}, page.expanded)
    o[name] = on
    page.expanded = o
  }

  spacing: Style.spacing.sm

  Note {
    panel: page.panel
    text: "Captured folders and programs are saved in plain text in ~/.config/omaplace/scenes.toml, which may end up in a dotfiles repo."
  }
  Note {
    panel: page.panel
    visible: page.panel.info.ok && !page.panel.info.scenesWritable
    color: Color.urgent
    text: "scenes.toml has a newer schema or a scene with a bad name: it is shown but not changed. Fix the file first."
  }
  Note {
    panel: page.panel
    visible: page.panel.info.scenes.length === 0
    text: "No scenes yet. Save the desktop you are on with: omaplace save <name>"
  }

  ListView {
    id: list
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    spacing: Style.spacing.sm
    boundsBehavior: Flickable.StopAtBounds
    model: page.panel.info.scenes
    delegate: SceneRow {
      required property var modelData
      width: list.width
      panel: page.panel
      scene: modelData
      expanded: !!page.expanded[modelData.name]
      onExpandToggled: page.setExpanded(modelData.name, !expanded)
    }
  }
}
