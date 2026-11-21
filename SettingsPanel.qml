import QtQuick
import Quickshell

// Stub. WP9 fills this in (the settings window).
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
}
