import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Appearance: theme picker + wallpaper mode + donate, as one bar widget.
//
// The bar icon opens a panel built from the same kit the built-in panels use,
// so every surface re-themes itself the moment a theme is applied: colors come
// from the injected bar facade (bar.foreground / bar.fontFamily) and the
// Commons singletons (Color.accent, Style.*), never from literals.
//
// Preferences are shared with the service half of this plugin (Service.qml,
// which owns the cycle timer and the per-workspace switching) through one JSON
// state file. This side writes; the service watches and acts. `donated` lives
// in the same file so the donate button can hide itself forever.
Panel {
  id: root
  moduleName: "mendestein.appearance"
  ipcTarget: "mendestein.appearance"
  manageIpc: false

  // ------------------------------------------------------------- shared state
  property string mode: "single"
  property int intervalMinutes: 5
  property bool donated: false
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/mendestein.appearance.json"

  // ------------------------------------------------------------------- themes
  property var themes: []
  property bool themesLoading: false
  property string currentTheme: ""
  readonly property string themeNamePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
  property int backgroundCount: 0

  // PayPal donations for this plugin. Opening the page and setting the flag is
  // one atomic click: the button never comes back once donated.
  readonly property string donateUrl:
    "https://www.paypal.com/cgi-bin/webscr?cmd=_donations"
    + "&business=mendestein%40outlook.com"
    + "&item_name=mendestein.appearance%20omarchy%20plugin"
    + "&currency_code=EUR&no_shipping=1"

  // Theme-following presentation. All colors route through the bar facade or
  // the Commons singletons, so the panel re-renders on every theme change.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  readonly property string modeDescription: Model.modeDescription(mode, intervalMinutes, backgroundCount)
  readonly property var intervalPresets: [5, 10, 15, 30, 60]

  function clampCursor(value, lo, hi) { return Math.max(lo, Math.min(hi, value)) }

  // -------------------------------------------------------------- state file
  function loadState(raw) {
    var data
    try {
      data = JSON.parse(String(raw || "{}"))
    } catch (e) {
      return
    }
    if (!data || typeof data !== "object") return
    if (Model.isMode(data.mode)) root.mode = data.mode
    if (data.intervalMinutes !== undefined)
      root.intervalMinutes = Model.clampInterval(data.intervalMinutes)
    root.donated = data.donated === true
  }

  function persist() {
    stateFile.setText(JSON.stringify({
      mode: root.mode,
      intervalMinutes: root.intervalMinutes,
      donated: root.donated
    }, null, 2) + "\n")
  }

  function setMode(next) {
    if (!Model.isMode(next) || next === root.mode) return
    root.mode = next
    root.persist()
  }

  function setIntervalMinutes(next) {
    var value = Model.clampInterval(next)
    if (value === root.intervalMinutes) return
    root.intervalMinutes = value
    root.persist()
  }

  function donate() {
    if (root.donated) return
    donateProc.command = ["xdg-open", root.donateUrl]
    donateProc.running = true
    // Persisted immediately: the thank-you message survives restarts and the
    // button never comes back.
    root.donated = true
    root.persist()
  }

  function refresh() {
    if (!themeListProc.running) {
      themesLoading = true
      themeListProc.running = true
    }
    if (!backgroundCountProc.running) backgroundCountProc.running = true
  }

  function setTheme(name) {
    if (!name || name === root.currentTheme) return
    setThemeProc.command = ["omarchy", "theme", "set", name]
    setThemeProc.running = true
  }

  Component.onCompleted: {
    refresh()
    if (!stateFile.loaded) stateFile.reload()
  }
  onOpenedChanged: if (opened) refresh()

  // ------------------------------------------------------------------ processes
  Process {
    id: themeListProc
    command: ["omarchy", "theme", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.themes = Model.parseLines(text)
        root.themesLoading = false
      }
    }
  }

  Process {
    id: backgroundCountProc
    command: ["bash", "-c", Model.backgroundsCommand() + " | grep -c ."]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.backgroundCount = Math.max(0, parseInt(String(text).trim(), 10) || 0)
    }
  }

  Process {
    id: setThemeProc
    command: []
    onExited: {
      // omarchy rewrites theme.name; the FileView below picks the new value up.
      if (!themeListProc.running) themeListProc.running = true
    }
  }

  Process {
    id: donateProc
    command: []
  }

  // Theme changes: omarchy rewrites this file on every `omarchy theme set`.
  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.currentTheme = Model.themeNameFromState(String(text() || ""))
    onLoadFailed: root.currentTheme = ""
    onFileChanged: reload()
  }

  // Shared preferences. This side writes; Service.qml watches the same file.
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

  // The bar sizes this slot from the root's implicit size; without these the
  // widget mounts with zero width and the icon never appears.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // --------------------------------------------------------------- shell IPC
  IpcHandler {
    target: "mendestein.appearance"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function setMode(mode: string): string { root.setMode(String(mode || "")); return "ok" }
    function setInterval(minutes: int): string { root.setIntervalMinutes(Number(minutes)); return "ok" }
  }

  // -------------------------------------------------------------- bar + panel
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    tooltipText: "Appearance"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.refresh()
        if (!root.opened) root.open()
      }
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        panelScroll.contentY = root.clampCursor(
          panelScroll.contentY + dy * Style.space(48),
          0, Math.max(0, panelScroll.contentHeight - panelScroll.height))
      }
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: panelScroll.width
          spacing: Style.space(12)

          // ---------- Hero: palette icon · title · current theme ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰏘"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Appearance"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.currentTheme !== "" ? root.currentTheme.toUpperCase() : "…"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // ---------- Theme picker ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "THEME"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.themesLoading
              width: parent.width
              text: "Loading themes…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            ListView {
              id: themeList
              visible: root.themes.length > 0
              width: parent.width
              height: Math.min(contentHeight, Style.space(220))
              spacing: Style.space(4)
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height
              model: root.themes

              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: ThemeRow {
                required property var modelData
                required property int index
                width: themeList.width
                themeName: String(modelData)
              }
            }

            Text {
              visible: !root.themesLoading && root.themes.length === 0
              width: parent.width
              text: "No themes found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Wallpaper mode ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "WALLPAPER MODE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              id: modeRow
              width: parent.width
              spacing: Style.space(6)

              readonly property var modes: ["single", "workspace", "cycle"]
              readonly property real cellWidth: (width - spacing * (modes.length - 1)) / modes.length

              Repeater {
                model: modeRow.modes

                Button {
                  required property string modelData
                  required property int index

                  width: modeRow.cellWidth
                  text: Model.modeLabel(modelData)
                  fontSize: Style.font.caption
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                  bordered: true
                  active: root.mode === modelData
                  onClicked: root.setMode(modelData)
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.modeDescription
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Cycle interval (only when cycling) ----------
          Column {
            visible: root.mode === "cycle"
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: intervalHeader.implicitHeight

              PanelSectionHeader {
                id: intervalHeader
                text: "CYCLE INTERVAL"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                textFormat: Text.PlainText
                text: Model.clampInterval(root.intervalMinutes) + " min"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              id: intervalRow
              width: parent.width
              spacing: Style.space(6)

              // "Custom" is a button like the presets; clicking it reveals the
              // number input on its own row instead of keeping a spinner on
              // screen always.
              readonly property int cellCount: root.intervalPresets.length + 1
              readonly property real cellWidth: (width - spacing * (cellCount - 1)) / cellCount
              readonly property bool customActive: root.intervalPresets.indexOf(root.intervalMinutes) === -1

              Repeater {
                model: root.intervalPresets

                Button {
                  required property int modelData
                  required property int index

                  width: intervalRow.cellWidth
                  text: modelData + " min"
                  fontSize: Style.font.caption
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                  bordered: true
                  active: root.intervalMinutes === modelData
                  onClicked: {
                    customField.visible = false
                    root.setIntervalMinutes(modelData)
                  }
                }
              }

              Button {
                width: intervalRow.cellWidth
                text: "Custom"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: intervalRow.customActive
                onClicked: {
                  customField.visible = true
                  customField.field.forceActiveFocus()
                }
              }
            }

            NumberField {
              id: customField
              visible: false
              width: parent.width
              fieldWidth: parent.width
              value: root.intervalMinutes
              from: 1
              to: 1440
              stepSize: 5
              label: "Custom interval (minutes) — Enter applies"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onModified: function(v) { root.setIntervalMinutes(v) }
              onVisibleChanged: {
                if (visible) field.forceActiveFocus()
                else keyCatcher.forceActiveFocus()
              }
            }
          }

          // ---------- Support ----------
          PanelSeparator { visible: true; foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Button {
              visible: !root.donated
              width: parent.width
              iconText: "♥"
              text: "Support this plugin"
              fontSize: Style.font.body
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: false
              tooltipText: "Opens PayPal · mendestein@outlook.com"
              onClicked: root.donate()
            }

            Text {
              visible: !root.donated
              width: parent.width
              text: "Donations go to mendestein@outlook.com via PayPal."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // The donated state is permanent: the flag lives in the shared
            // state file, so the thank-you message replaces the button
            // forever — across restarts and theme switches.
            BorderSurface {
              visible: root.donated
              width: parent.width
              implicitHeight: thanksRow.implicitHeight + Style.space(20)
              color: root.alpha(root.foreground, 0.05)
              borderSpec: Border.flat(root.alpha(root.foreground, 0.25), 1)
              radius: Style.cornerRadius

              Row {
                id: thanksRow
                anchors.centerIn: parent
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: "♥"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: "Thank you for your support!"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }

  // One theme row in the picker. The active theme is picked out with the kit's
  // active fill and a check mark, exactly like the built-in pill rows.
  component ThemeRow: Button {
    id: themeRow
    required property string themeName

    text: themeRow.themeName
    fontSize: Style.font.bodySmall
    leftAlign: true
    foreground: root.foreground
    fontFamily: root.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    active: root.currentTheme.toLowerCase() === themeRow.themeName.toLowerCase()
    tooltipText: active ? "Current theme" : "Apply " + themeRow.themeName
    onClicked: root.setTheme(themeRow.themeName)
  }
}
