import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// Wallpaper engine for the Appearance plugin. Mounted once (service kind);
// the per-monitor panel instances only write preferences through the shared
// state file and this side acts on them. Owns:
//   - cycle mode: the "omarchy theme bg next" timer
//   - workspace mode: Hyprland workspace-event wallpaper switching
//   - theme follow-up: re-derives the background list when the theme changes
Item {
  id: root

  property var shell: null

  // ---- Shared state (source of truth: the JSON file) ----
  property string mode: "single"
  property int intervalMinutes: 5
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/pmendes.appearance.json"

  // ---- Theme tracking ----
  property string currentTheme: ""
  property var backgrounds: []
  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"

  onModeChanged: applyMode()
  onIntervalMinutesChanged: {
    if (root.mode === "cycle") cycleTimer.restart()
  }
  onCurrentThemeChanged: refreshBackgrounds()
  onBackgroundsChanged: {
    if (root.mode === "workspace") applyForFocusedWorkspace()
  }

  Component.onCompleted: {
    refreshBackgrounds()
    applyMode()
  }

  function refreshBackgrounds() {
    if (backgroundsProc.running) return
    backgroundsProc.command = ["bash", "-c", Model.backgroundsCommand()]
    backgroundsProc.running = true
  }

  function applyMode() {
    cycleTimer.running = root.mode === "cycle"
    if (root.mode === "cycle") cycleTimer.restart()
    else if (root.mode === "workspace") applyForFocusedWorkspace()
  }

  function applyForFocusedWorkspace() {
    var workspace = Hyprland.focusedWorkspace
    if (workspace) applyForWorkspace(workspace.id)
  }

  function applyForWorkspace(workspaceId) {
    var path = Model.backgroundForWorkspace(root.backgrounds, workspaceId)
    if (path !== "") runApply(["omarchy", "theme", "bg", "set", path])
  }

  function runApply(argv) {
    if (applyProc.running) return
    applyProc.command = argv
    applyProc.running = true
  }

  function loadState(raw) {
    var data
    try {
      data = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return
    if (Model.isMode(data.mode)) root.mode = data.mode
    root.intervalMinutes = Model.clampInterval(data.intervalMinutes !== undefined ? data.intervalMinutes : 5)
  }

  // Only the workspace events matter here; data is the workspace name, which
  // is numeric for the regular 1..9 workspaces this mapping addresses. The
  // state file is re-read on each event: atomic writes (rename) can evade the
  // file watcher, and a missed write would leave this side acting on a stale
  // mode forever.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      if (name !== "workspace" && name !== "workspacev2") return
      if (stateFile.loaded) root.loadState(stateFile.text())
      else stateFile.reload()
      if (root.mode !== "workspace") return
      var raw = String(event && event.data ? event.data : "").trim()
      var id = parseInt(raw.split(",")[0], 10)
      if (!isNaN(id)) root.applyForWorkspace(id)
    }
  }

  Timer {
    id: cycleTimer
    interval: root.intervalMinutes * 60 * 1000
    repeat: true
    running: false
    onTriggered: root.runApply(["omarchy", "theme", "bg", "next"])
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: backgroundsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.backgrounds = Model.parseNullList(text)
    }
  }

  // The panel writes; this side reloads and acts.
  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("{}")
    onFileChanged: reload()
  }

  // Following the theme: omarchy rewrites this file on every theme change.
  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.currentTheme = String(text() || "").trim()
    onLoadFailed: root.currentTheme = ""
    onFileChanged: reload()
  }
}
