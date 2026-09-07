import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.simonab.forge"
  ipcTarget: "io.github.simonab.forge"
  manageIpc: false

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openBoard() {
    if (bar) bar.run("forge-board")
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openBoard() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "F"
    tooltipText: "Forge"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openBoard()
    }
  }
}
