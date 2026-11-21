import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One saved session: when it was last saved, how many windows, and Restore (not for this login's own session).
RowLayout {
  id: row

  property var panel: null
  property var session: ({})

  spacing: Style.spacing.sm

  Text {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    elide: Text.ElideRight
    text: (row.session.savedAt > 0 ? Qt.formatDateTime(new Date(row.session.savedAt * 1000), "d MMM, hh:mm") : "unknown time")
      + (row.session.current ? " (this login)" : "")
    color: row.panel.foreground
    font.family: row.panel.fontFamily
    font.pixelSize: Style.font.body
  }
  Text {
    textFormat: Text.PlainText
    text: row.session.windows < 0 ? "unreadable" : row.session.windows === 1 ? "1 window" : row.session.windows + " windows"
    color: Qt.darker(row.panel.foreground, 1.6)
    font.family: row.panel.fontFamily
    font.pixelSize: Style.font.caption
  }
  Button {
    text: "Restore"
    enabled: !row.session.current && row.session.windows > 0
    opacity: enabled ? 1 : 0.5
    foreground: row.panel.foreground
    accent: row.panel.accent
    fontFamily: row.panel.fontFamily
    onClicked: row.panel.restore(row.session.instance)
  }
}
