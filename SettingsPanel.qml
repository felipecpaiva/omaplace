import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "js/Settings.js" as Settings
import "pages"

// omaplace settings window (WP6): a side list of four pages (Scenes, Rules, Session, General), like omahop's (D24).
// It reads and writes nothing itself: every read and every change is a function of Service.qml, which the shell hands
// in as `service`. Opened with `omarchy-shell shell toggle io.github.felipecpaiva.omaplace` or the launcher entry.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string page: "scenes"
  property var info: Settings.emptyData()
  property string status: ""
  property bool failed: false
  property string waitReq: ""      // a slow request this window started; its result is shown when it ends
  property var confirm: null       // { kind: "scene" | "rule", name } while the delete question is open

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color scrim: Color.menu.scrim
  property string fontFamily: Style.font.menuFamily

  readonly property var pages: [
    { id: "scenes", title: "Scenes" }, { id: "rules", title: "Rules" },
    { id: "session", title: "Session" }, { id: "general", title: "General" }
  ]

  function open(payloadJson) {
    root.opened = true
    if (root.service) {
      root.service.ensureDirs()
      root.service.refreshMonitors()
    }
    root.reload()
    Qt.callLater(function () { content.forceActiveFocus() })
  }

  function close() { root.opened = false; root.confirm = null }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.felipecpaiva.omaplace")
    else root.close()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function reload() { root.info = root.service ? root.service.panelData() : Settings.emptyData() }

  // Shows one answer from the service and reads the files again.
  function act(answer, okText) {
    let a = Settings.answerText(answer, okText)
    root.status = a.text
    root.failed = !a.ok
    root.waitReq = a.req
    root.reload()
  }

  // Each action is one Service.qml function; without a service there is nothing to call (the page says so).
  function openScene(name) { if (root.service) root.act(root.service.startOpen(name), "Opening " + name) }
  function renameScene(from, to) { if (root.service) root.act(root.service.renameScene(from, to), "Renamed") }
  function setWindow(scene, index, cls, field, value) { if (root.service) root.act(root.service.setSceneWindow(scene, index, cls, field, value), "Saved") }
  function pickFolder(scene, index, cls) { if (root.service) root.act(root.service.pickFolder(scene, index, cls), "Pick a folder") }
  function addRule() { if (root.service) root.act(root.service.startRuleAdd(), "Adding a rule") }
  function setRule(name, field, value) { if (root.service) root.act(root.service.setRuleField(name, field, value), "Saved") }
  function setSetting(key, value) { if (root.service) root.act(root.service.setSetting(key, value), "Saved") }
  function addMenu() { if (root.service) root.act(root.service.menuAdd(), "Added to the Omarchy menu, the old file is kept as omarchy-menu.jsonc.omaplace.bak") }
  function removeMenu() { if (root.service) root.act(root.service.menuRemove(), "Removed from the Omarchy menu") }
  function restore(instance) { if (root.service) root.act(root.service.startRestore(instance), "Restoring") }
  function askDelete(kind, name) { root.confirm = { kind: kind, name: name } }
  function confirmDelete() {
    let c = root.confirm
    root.confirm = null
    if (c && root.service) root.act(c.kind === "rule" ? root.service.removeRule(c.name) : root.service.removeScene(c.name), "Deleted, the old file is kept as a .bak")
    content.forceActiveFocus()
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    // A slow request ended (finish() writes the result right after it clears req, hence callLater).
    function onReqChanged() {
      if (root.service.req !== null || !root.opened) return
      Qt.callLater(function () {
        if (root.waitReq !== "") root.act(root.service.resultOf(root.waitReq) || '{"ok":true}', "Done")
        else root.reload()
      })
    }
    // A late answer (folder chooser) or new live monitors.
    function onRevisionChanged() {
      if (!root.opened) return
      if (root.service.lastAnswer !== "") { root.act(root.service.lastAnswer, "Saved"); root.service.lastAnswer = "" }
    }
  }

  PanelWindow {
    id: window
    // Hidden while Omarchy's file chooser runs: it is a normal window and would open under this overlay.
    visible: root.opened && !(root.service && root.service.picking)
    onVisibleChanged: if (visible) Qt.callLater(function () { content.forceActiveFocus() })
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omaplace-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(820), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(660), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Ancestor of every field, so Escape from inside a text field still closes the window.
      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.borderTop + Style.spacing.panelPadding
        anchors.bottomMargin: card.borderBottom + Style.spacing.panelPadding
        anchors.leftMargin: card.borderLeft + Style.spacing.panelPadding
        anchors.rightMargin: card.borderRight + Style.spacing.panelPadding
        focus: true
        Keys.onPressed: function (event) {
          if (confirmDialog.handleKey(event)) { event.accepted = true; return }
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.spacing.sm

          RowLayout {
            Layout.fillWidth: true
            Column {
              Layout.fillWidth: true
              spacing: Style.spacing.xxs
              Text {
                textFormat: Text.PlainText
                text: "omaplace"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                text: "~/.config/omaplace"
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Button {
              text: "Close"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.dismiss()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.md

            ListView {
              id: sideList
              Layout.alignment: Qt.AlignTop
              Layout.preferredWidth: Style.space(140)
              Layout.fillHeight: true
              interactive: false
              spacing: Style.spacing.xs
              model: root.pages
              delegate: Button {
                required property var modelData
                width: sideList.width
                text: modelData.title
                bordered: root.page === modelData.id
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.page = modelData.id
              }
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Text {
                visible: !root.service
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: "The omaplace service is not running. Turn the plugin on, then run: omarchy restart shell"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              ScenesPage {
                anchors.fill: parent
                visible: !!root.service && root.page === "scenes"
                panel: root
              }
              RulesPage {
                anchors.fill: parent
                visible: !!root.service && root.page === "rules"
                panel: root
              }
              SessionPage {
                anchors.fill: parent
                visible: !!root.service && root.page === "session"
                panel: root
              }
              GeneralPage {
                anchors.fill: parent
                visible: !!root.service && root.page === "general"
                panel: root
              }
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.status !== "" ? root.status : root.info.warnings.length > 0
              ? root.info.warnings.length + " problem(s) in the config files, the first: " + root.info.warnings[0]
              : "Changes are saved at once."
            color: root.failed ? Color.urgent : Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          z: 10
          opened: root.confirm !== null
          message: root.confirm ? "Delete the " + root.confirm.kind + " " + root.confirm.name + "?" : ""
          confirmText: "Delete"
          cancelText: "Cancel"
          background: root.background
          foreground: root.foreground
          fontFamily: root.fontFamily
          onCanceled: { root.confirm = null; content.forceActiveFocus() }
          onConfirmed: root.confirmDelete()
        }
      }
    }
  }
}
