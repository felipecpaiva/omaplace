import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../js/Desktops.js" as Desktops

// The selected desktop, editable: its layout badge and picker (custom zones as text), a preview of where each app goes,
// one row per zone with an app picker, Open all, Open at login, and Remove plan. Every change is one Desktops.edit
// through the service (panel.editPlan); the card is rebuilt from the files after it.
ColumnLayout {
  id: editor

  property var panel: null
  property var model: ({})
  property var apps: []
  property string customKey: ""    // the desktop whose custom zones field the user opened
  readonly property bool writable: editor.panel.info.scenesWritable
  readonly property bool custom: editor.model.choice === "custom" || editor.customKey === editor.model.key
  readonly property var layoutOptions: [{ value: "", label: "No plan" }].concat(Desktops.LAYOUT_CHOICES, [{ value: "custom", label: "Custom zones" }])

  spacing: Style.spacing.sm

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.sm
    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: "Desktop " + editor.model.slot + " on " + editor.model.monitorName + (editor.model.plan ? ", plan " + editor.model.name : "")
      color: editor.panel.foreground
      font.family: editor.panel.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    LayoutBadge { panel: editor.panel; text: editor.model.badge; plan: editor.model.plan; bad: editor.model.error !== "" }
  }

  Note {
    panel: editor.panel
    visible: editor.model.error !== ""
    color: Color.urgent
    text: "This plan has a problem: " + editor.model.error + ". Fix it in ~/.config/omaplace/scenes.toml first; nothing is saved until then."
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.md
    Dropdown {
      Layout.preferredWidth: Style.space(200)
      label: "Layout"
      value: editor.custom ? "custom" : editor.model.choice
      options: editor.layoutOptions
      enabled: editor.writable
      foreground: editor.panel.foreground
      accent: editor.panel.accent
      fontFamily: editor.panel.fontFamily
      onChanged: function (value) {
        editor.customKey = value === "custom" ? editor.model.key : ""
        if (value === "") { if (editor.model.plan) editor.panel.askDelete("plan", editor.model.name) }
        else if (value !== "custom" && value !== editor.model.layout) editor.panel.editPlan(editor.model, "layout", value)
      }
    }
    TextField {
      id: zonesField
      visible: editor.custom
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignBottom
      enabled: editor.writable
      placeholderText: "0 0 0.5 1; 0.5 0 0.5 1"
      foreground: editor.panel.foreground
      accent: editor.panel.accent
      onEditingFinished: if (text.trim() !== "" && text.trim() !== editor.model.layout) editor.panel.editPlan(editor.model, "layout", text)
    }
    Binding { target: zonesField; property: "text"; value: editor.model.choice === "custom" ? editor.model.layout : ""; restoreMode: Binding.RestoreNone }
  }
  Note {
    panel: editor.panel
    text: "A zone layout or Free floating switches this desktop to floating when you press Open all. Custom zones are typed as x y w h fractions, separated by ; (there is no drawing editor yet)."
  }
  Note { panel: editor.panel; visible: editor.model.modeNote !== ""; color: editor.panel.accent; text: editor.model.modeNote }

  ZoneThumb {
    visible: editor.model.plan && editor.model.error === ""
    Layout.preferredWidth: Math.min(editor.width, Style.space(360))
    Layout.preferredHeight: implicitHeight
    rows: editor.model.rows
    emptyText: editor.model.rows.length === 0 ? "No apps yet" : ""
    foreground: editor.panel.foreground
    accent: editor.panel.accent
    fontFamily: editor.panel.fontFamily
  }

  ListView {
    id: places
    Layout.fillWidth: true
    Layout.preferredHeight: contentHeight
    interactive: false
    spacing: Style.spacing.xs
    model: editor.model.rows
    delegate: ZoneRow {
      required property var modelData
      width: places.width
      panel: editor.panel
      card: editor.model
      place: modelData
      apps: editor.apps
    }
  }

  RowLayout {
    visible: editor.model.plan
    Layout.fillWidth: true
    spacing: Style.spacing.sm
    Button {
      text: "Open all"
      bordered: true
      enabled: editor.model.error === "" && editor.model.rows.some(function (r) { return !r.empty })
      opacity: enabled ? 1 : 0.5
      foreground: editor.panel.foreground
      accent: editor.panel.accent
      fontFamily: editor.panel.fontFamily
      onClicked: editor.panel.openScene(editor.model.name)
    }
    Item { Layout.fillWidth: true }
    Text {
      textFormat: Text.PlainText
      text: "Open at login"
      color: editor.panel.foreground
      font.family: editor.panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    ToggleSwitch {
      checked: editor.model.openAtLogin
      interactive: editor.writable && editor.model.error === ""
      onToggled: editor.panel.editPlan(editor.model, "login", !editor.model.openAtLogin)
    }
    Button {
      text: "Remove plan"
      enabled: editor.writable
      foreground: editor.panel.foreground
      accent: editor.panel.accent
      fontFamily: editor.panel.fontFamily
      onClicked: editor.panel.askDelete("plan", editor.model.name)
    }
  }
  Note {
    panel: editor.panel
    visible: editor.model.plan
    text: "Open all starts the planned apps that are missing and moves open ones into place. A planned app you open by hand goes to its place too, unless a note above says otherwise."
  }
  Note {
    panel: editor.panel
    visible: !editor.model.plan
    text: "Pick a layout to make a plan for this desktop, then pick an app for each place."
  }
}
