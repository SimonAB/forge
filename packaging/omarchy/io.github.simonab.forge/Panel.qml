import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.simonab.forge"
  ipcTarget: "forge"
  manageIpc: false

  property var snapshot: ({})
  property string errorText: ""
  property bool loading: false

  function refresh() {
    if (reader.running) return
    loading = true
    errorText = ""
    reader.running = true
  }

  function openBoard() { launcher.command = ["forge-board"]; launcher.running = true }
  function openSuperProductivity() { launcher.command = ["super-productivity"]; launcher.running = true }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Process {
    id: reader
    command: ["forge", "dashboard", "--json"]
    stdout: StdioCollector { id: output }
    stderr: StdioCollector { id: diagnostics }
    onExited: function (exitCode) {
      loading = false
      if (exitCode !== 0) {
        errorText = diagnostics.text || "Forge dashboard failed"
        return
      }
      try { snapshot = JSON.parse(output.text) }
      catch (error) { errorText = "Forge returned invalid dashboard JSON" }
    }
  }

  Process { id: launcher; command: []; running: false }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
  }

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: 27
    implicitHeight: 26
    Rectangle {
      anchors.centerIn: parent
      width: 10
      height: 10
      radius: width / 2
      color: "white"
    }
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.refresh()
        else root.openBoard()
      }
    }
  }
}
