import QtQuick
import QtQuick.Layouts
import qs.Commons

// Desktops (design 14.1): every desktop of every monitor as a small card with its layout badge and preview; the selected
// one opens below its monitor's grid for editing (DesktopCard). The model is Service.desktopCards(), read again after each
// change (panel.info) and when the live desktops arrive (service.revision).
Flickable {
  id: page

  property var panel: null
  property string selected: ""     // the selected card's key: monitor identity and slot
  readonly property var desks: page.visible && page.panel.service ? page.build(page.panel.info, page.panel.service.revision) : ({ groups: [], reason: "", loading: false })
  readonly property var apps: page.visible && page.panel.service ? page.panel.service.appChoices() : []
  readonly property string current: page.selected !== "" ? page.selected
    : page.desks.groups.length > 0 ? page.desks.groups[0].cards[0].key : ""

  // info and revision are only there so the binding runs again when they change.
  function build(info, revision) { return page.panel.service.desktopCards() }

  clip: true
  contentWidth: width
  contentHeight: column.implicitHeight
  boundsBehavior: Flickable.StopAtBounds

  ColumnLayout {
    id: column
    width: page.width
    spacing: Style.spacing.md

    Note {
      panel: page.panel
      visible: page.panel.info.ok && !page.panel.info.scenesWritable
      color: Color.urgent
      text: "scenes.toml has a newer schema or a scene with a problem: plans are shown but not changed. Fix the file first."
    }
    Note { panel: page.panel; visible: page.desks.reason !== ""; color: Color.urgent; text: page.desks.reason }
    Note { panel: page.panel; visible: page.desks.loading; text: "Reading the desktops..." }
    Note {
      panel: page.panel
      visible: !page.desks.loading && page.desks.groups.length === 0
      text: "No monitors found yet."
    }

    ListView {
      id: monitors
      Layout.fillWidth: true
      Layout.preferredHeight: contentHeight
      interactive: false
      spacing: Style.spacing.md
      model: page.desks.groups
      delegate: MonitorDesks {
        required property var modelData
        width: monitors.width
        panel: page.panel
        group: modelData
        apps: page.apps
        selected: page.current
        onPicked: function (key) { page.selected = key }
      }
    }
  }
}
