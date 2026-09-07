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
  ipcTarget: "io.github.simonab.forge"
  manageIpc: false

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  property var snapshot: ({})
  property var boardProjects: []
  property string errorText: ""
  property bool loading: false
  property int pendingReads: 0
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color foreground: bar ? bar.foreground : Color.foreground

  function refresh() {
    if (reader.running || boardReader.running) return
    loading = true
    errorText = ""
    pendingReads = 2
    reader.running = true
    boardReader.running = true
  }

  function openBoard() { if (bar) bar.run("forge-board") }
  function openSuperProductivity() { if (bar) bar.run("super-productivity") }
  function openProject(path) {
    if (!path) return
    launcher.command = ["xdg-open", path]
    launcher.running = true
  }
  function readFinished() {
    pendingReads = Math.max(0, pendingReads - 1)
    if (pendingReads === 0) loading = false
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Process {
    id: reader
    command: ["forge", "dashboard", "--json"]
    stdout: StdioCollector { id: output }
    stderr: StdioCollector { id: diagnostics }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        errorText = diagnostics.text || "Forge dashboard failed"
      } else {
        try { snapshot = JSON.parse(output.text) }
        catch (error) { errorText = "Forge returned invalid dashboard JSON" }
      }
      root.readFinished()
    }
  }

  Process {
    id: boardReader
    command: ["forge", "board", "--json"]
    stdout: StdioCollector { id: boardOutput }
    stderr: StdioCollector { id: boardDiagnostics }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        errorText = boardDiagnostics.text || "Forge board failed"
      } else {
        try {
          var payload = JSON.parse(boardOutput.text)
          boardProjects = payload.projects || []
        } catch (error) { errorText = "Forge returned invalid board JSON" }
      }
      root.readFinished()
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
    text: "F"
    tooltipText: "Forge"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(350))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(430))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.openBoard()
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "r") root.refresh()
        else if (key === "o") root.openBoard()
        else if (key === "s") root.openSuperProductivity()
      }
    }

    Column {
      id: column
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "Forge"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
      Text {
        text: root.loading ? "Refreshing…" : root.errorText
        visible: text !== ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Text {
        text: {
          var columns = root.snapshot.columns || {}
          var names = Object.keys(columns)
          return names.length
            ? names.map(function(name) { return name + "  " + columns[name] }).join("\n")
            : "No board data"
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        text: {
          var world = root.snapshot.world || {}
          var calendar = root.snapshot.calendar_error ? " · Calendar unavailable" : ""
          return "SP: " + (world.open_tasks || 0) + " open · " + (world.inbox || 0) + " inbox" + calendar
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        text: "Projects"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }
      Column {
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: root.boardProjects
          delegate: Button {
            required property var modelData
            width: parent.width
            text: (modelData.column || "(none)") + " · "
              + (modelData.metaTags && modelData.metaTags.some(function(tag) { return String(tag).toUpperCase().indexOf("URGENT") === 0 }) ? "⚠️ " : "")
              + (modelData.name || "")
            leftAlign: true
            foreground: root.foreground
            onClicked: root.openProject(modelData.path || "")
          }
        }
      }
      RowLayout {
        width: parent.width
        Button { text: "Open board"; onClicked: root.openBoard(); Layout.fillWidth: true }
        Button { text: "Open SP"; onClicked: root.openSuperProductivity(); Layout.fillWidth: true }
      }
    }
  }
}
