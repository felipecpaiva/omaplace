import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../js/Desktops.js" as Desktops

// Desktops (design 14.1): every desktop of every monitor as a small card with its layout badge and preview; the selected
// one opens below its monitor's grid for editing (DesktopCard). The model is Service.desktopCards(), read again after each
// change (panel.info) and when the live desktops arrive (service.revision).
Flickable {
  id: page

  property var panel: null
  property string selected: ""     // the selected card's key: monitor identity and slot
  // Set by refresh(), never computed in a binding: desktopCards() reads files. The editor state lives here because the
  // card delegates are rebuilt with every new model: which desktop has the custom zones field open, its typed text
  // (kept when a save is refused), and which rows show More ("<card key>\n<pos>": true).
  property var desks: ({ groups: [], reason: "", loading: false })
  property var apps: []
  property string customKey: ""
  property var drafts: ({})
  property var openRows: ({})
  readonly property string current: page.selected !== "" ? page.selected
    : page.desks.groups.length > 0 ? page.desks.groups[0].cards[0].key : ""

  function refresh() {
    if (!page.visible || !page.panel.service) return
    page.desks = page.panel.service.desktopCards()
    let kept = Desktops.pruneDrafts(page.drafts, page.desks.groups)
    if (kept) page.drafts = kept
  }
  function setDraft(key, text) { let d = Object.assign({}, page.drafts); d[key] = text; page.drafts = d }
  function toggleRow(key) { let o = Object.assign({}, page.openRows); o[key] = !o[key]; page.openRows = o }

  onVisibleChanged: {
    if (visible && page.panel.service) page.apps = page.panel.service.appChoices()
    page.refresh()
  }
  Connections { target: page.panel; function onInfoChanged() { page.refresh() } }
  Connections { target: page.panel.service; ignoreUnknownSignals: true; function onRevisionChanged() { page.refresh() } }

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
        view: page
        group: modelData
        apps: page.apps
        selected: page.current
        onPicked: function (key) { page.selected = key }
      }
    }
  }
}
