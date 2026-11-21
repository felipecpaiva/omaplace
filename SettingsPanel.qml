import QtQuick
import Quickshell

// Stub. WP6 fills this in (the settings window), then WP8 adds the menu button.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
}
