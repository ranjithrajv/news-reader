import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Config.js" as Config

BarWidget {
  id: root
  moduleName: "ranjithraj.news-reader"

  function openOverlay() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.moduleName, "{}"])
  }

  property int unread: 0

  // --- State paths (1) — shared via Config.js ---
  readonly property string stateDir: Config.stateDir(Quickshell.env("HOME"))
  readonly property string unreadPath: stateDir + "news-reader-unread.json"

  // --- Timing config (3) ---
  readonly property int badgePollIntervalMs: 4000

  implicitWidth: button.implicitWidth + (badge.visible ? 6 : 0)
  implicitHeight: button.implicitHeight

  function applyUnread(t) {
    // clamp to a sane non-negative integer — state file is user-writable
    var n = parseInt(String(t || "").trim(), 10)
    if (!isFinite(n) || n < 0) n = 0
    if (n > 99999) n = 99999
    root.unread = n
  }

  // bounded regular-file/no-follow read of the unread bridge (security baseline)
  Process {
    id: unreadReader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyUnread(String(text || ""))
    }
  }
  function reloadUnread() {
    unreadReader.command = ["bash", "-c", Config.stateReadCmd(root.unreadPath, Config.stateMaxBytes)]
    unreadReader.running = true
  }
  Timer {
    interval: root.badgePollIntervalMs; running: true; repeat: true
    onTriggered: root.reloadUnread()
  }
  Component.onCompleted: root.reloadUnread()

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // newspaper icon (Nerd Font: nf-fa-newspaper_o  \uf1ea) fallback to text
    text: "\uF1EA"
    tooltipText: root.unread > 0 ? "News Reader — " + root.unread + " unread" : "News Reader — summon overlay"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openOverlay()
    }
  }

  // unread badge — dot + count
  Rectangle {
    id: badge
    visible: root.unread > 0
    width: Math.max(10, badgeText.implicitWidth + 6)
    height: 12
    radius: 6
    color: Color.urgent
    border.width: 1
    border.color: root.bar ? root.bar.background : Color.background
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: -4
    anchors.topMargin: 2
    Text {
      id: badgeText
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      color: Color.background
      font.pixelSize: 8
      font.bold: true
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
    }
  }
}
