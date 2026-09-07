import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Text { text: "♜"; color: bar ? bar.foreground : Color.foreground; font.pixelSize: Style.font.pixelSize(15) }
    }
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(300)
    contentHeight: Style.space(230)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      RowLayout {
        width: parent.width
        Text { text: "Forge"; color: bar ? bar.foreground : Color.foreground; font.bold: true; Layout.fillWidth: true }
        Button { text: "↻"; onClicked: root.refresh() }
      }
      Label { text: root.loading ? "Refreshing…" : root.errorText; visible: text !== ""; wrapMode: Text.WordWrap }
      Label {
        text: {
          var columns = root.snapshot.columns || {}
          var names = Object.keys(columns)
          return names.length ? names.map(function (name) { return name + "  " + columns[name] }).join("\n") : "No board data"
        }
        color: bar ? bar.foreground : Color.foreground
      }
      Label {
        text: {
          var world = root.snapshot.world || {}
          return "SP: " + (world.open_tasks || 0) + " open · " + (world.inbox || 0) + " inbox"
        }
        color: bar ? bar.foreground : Color.foreground
      }
      RowLayout {
        width: parent.width
        Button { text: "Open board"; onClicked: root.openBoard(); Layout.fillWidth: true }
        Button { text: "Open SP"; onClicked: root.openSuperProductivity(); Layout.fillWidth: true }
      }
    }
  }
}
