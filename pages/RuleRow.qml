import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../js/Settings.js" as Settings

// One rule: the app, a monitor picker of the live monitors, desktop 1 to 10, follow, on or off, and Remove.
ColumnLayout {
  id: row

  property var panel: null
  property var rule: ({})

  spacing: Style.spacing.xs

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.sm
    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: row.rule.app !== "" ? row.rule.app : row.rule.name + " (no app)"
      color: row.panel.foreground
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      textFormat: Text.PlainText
      text: "On"
      color: row.panel.foreground
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    ToggleSwitch {
      checked: row.rule.enabled
      onToggled: row.panel.setRule(row.rule.name, "enabled", !row.rule.enabled)
    }
    Button {
      text: "Remove"
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onClicked: row.panel.askDelete("rule", row.rule.name)
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.md
    Dropdown {
      Layout.fillWidth: true
      label: "Monitor"
      value: row.rule.monitor
      options: Settings.monitorChoices(row.panel.service ? row.panel.service.liveMonitors : [], row.rule.monitor)
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onChanged: function (value) { if (value !== row.rule.monitor) row.panel.setRule(row.rule.name, "monitor", value) }
    }
    NumberField {
      label: "Desktop"
      value: row.rule.slot
      from: 1
      to: 10
      foreground: row.panel.foreground
      accent: row.panel.accent
      fontFamily: row.panel.fontFamily
      onModified: function (value) { if (value !== row.rule.slot) row.panel.setRule(row.rule.name, "slot", value) }
    }
    Text {
      textFormat: Text.PlainText
      text: "Follow"
      color: row.panel.foreground
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    ToggleSwitch {
      checked: row.rule.follow
      onToggled: row.panel.setRule(row.rule.name, "follow", !row.rule.follow)
    }
    Text {
      visible: (row.rule.rect || "") !== ""
      textFormat: Text.PlainText
      text: "Same spot"
      color: row.panel.foreground
      font.family: row.panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    ToggleSwitch {
      visible: (row.rule.rect || "") !== ""
      checked: row.rule.keep_rect === true
      onToggled: row.panel.setRule(row.rule.name, "keep_rect", !row.rule.keep_rect)
    }
  }

  PanelSeparator { Layout.fillWidth: true; foreground: row.panel.foreground }
}
