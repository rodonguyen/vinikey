import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Strings.js" as Strings

// EN/VI indicator for fcitx5 Bamboo.
//
// Any click opens the settings panel, like the other panel widgets. The typing
// language is switched from the panel's switch or with fcitx5's own hotkey.
//
// Reading the state: fcitx5 sends no signal when the input method changes, so it has
// to be asked. Normally ~/.local/bin/fcitx5-im-watch (built by setup-vietnamese.sh)
// does that every 100 ms and keeps the answer in one state file; every bar (one per
// monitor) watches that file, and a flock makes sure only one helper polls while the
// others wait as standbys. Without the helper (no compiler at install time, or it
// keeps dying) the widget falls back to spawning fcitx5-remote every 1.5 s.
BarWidget {
  id: root
  moduleName: "vn-keyboard"

  // Name of the active fcitx5 input method, or "" when fcitx5 can't be reached.
  property string imName: ""
  // First key of fcitx5's "Toggle Input Method" hotkey, as shown to people.
  property string shortcut: "Ctrl+Space"

  // Language of the panel and tooltip text ("vi" or "en"), kept in this widget's
  // shell.json entry. Vietnamese until someone chooses otherwise.
  readonly property string lang: setting("language", "vi") === "en" ? "en" : "vi"

  function tr(key) { return Strings.tr(root.lang, key) }

  readonly property bool vietnamese: imName === "bamboo"
  readonly property string label: imName === "" ? "--" : (vietnamese ? "VI" : "EN")
  readonly property string tip: imName === ""
    ? tr("tipDown")
    : tr(vietnamese ? "tipVi" : "tipEn") + "  -  " + shortcut + " " + tr("toSwitch")

  function setLanguage(language) {
    var next = language === "en" ? "en" : "vi"
    if (next === root.lang) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.language = next

    // Applied locally first so the text changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Fast path: the shared fcitx5-im-watch helper.
  readonly property string helperBin: Quickshell.env("HOME") + "/.local/bin/fcitx5-im-watch"
  readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fcitx5-im-watch"
  // True while this bar's helper process is alive (polling, or waiting as a standby).
  property bool helperUp: false
  property int helperQuickExits: 0
  property real helperStartedAt: 0

  function startHelper() {
    if (!helperProc.running) helperProc.running = true
  }

  // The helper writes "-" when fcitx5 is down or nothing has input focus.
  function applyState(raw) {
    var v = String(raw || "").trim()
    root.imName = v === "-" ? "" : v
  }

  // ---- Fallback path: one spawn per check.
  function refresh() {
    if (root.helperUp || queryProc.running) return
    queryProc.running = true
  }

  function toggleIm() {
    if (!root.bar || root.imName === "") return
    root.bar.run("fcitx5-remote -t")
    // The helper reports the change within about 100 ms by itself.
    if (!root.helperUp) refreshTimer.restart()
  }

  // The panel's typing switch; the panel stays open. Opened by a click, the panel
  // never held the keyboard, so this is a plain toggle of the app's input method.
  // Summoned from the keyboard, the panel holds it and fcitx5 would toggle the panel's
  // own input context instead. Dropping the panel's keyboard focus is not enough
  // (Hyprland does not hand it back by itself), so also re-focus the active window,
  // then toggle. Both dispatch syntaxes are sent: Lua (Hyprland 0.56+) and hyprlang;
  // each Hyprland ignores the other one.
  function toggleImFromPanel() {
    var p = panelLoader.item
    if (!root.opened || !p || p.keyboardReleased) {
      root.toggleIm()
      return
    }
    p.keyboardReleased = true
    if (!root.bar) return
    root.bar.run("a=$(hyprctl activewindow | sed -n '1s/^Window \\([0-9a-f]*\\) .*/0x\\1/p'); "
      + "if [ -n \"$a\" ]; then "
      + "hyprctl dispatch \"hl.dsp.focus({ window = \\\"address:$a\\\" })\" >/dev/null 2>&1; "
      + "hyprctl dispatch focuswindow \"address:$a\" >/dev/null 2>&1; fi; "
      + "sleep 0.05; pgrep -x fcitx5 >/dev/null && exec fcitx5-remote -t")
    if (!root.helperUp) refreshTimer.restart()
  }

  // fcitx5 spells keys like "Control+space"; show them the way keycaps read.
  function prettyKey(key) {
    return String(key).split("+").map(function(part) {
      if (part === "Control") return "Ctrl"
      if (part === "space") return "Space"
      return part.length > 0 ? part.charAt(0).toUpperCase() + part.slice(1) : part
    }).join("+")
  }

  Component.onCompleted: {
    refresh()
    shortcutProc.running = true
    startHelper()
  }

  // ---- Settings panel. Shape contract for shell.summon/hide/toggle routing:
  //      open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // pointer: opened by a click, so the panel leaves the keyboard with the app.
  function open(pointer) {
    shortcutProc.running = true
    if (panelLoader.item) panelLoader.item.open(pointer === true)
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel(pointer) {
    if (root.opened) root.close()
    else root.open(pointer === true)
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout identity.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "vn-keyboard"

    function open(): void { root.open() }
    // Opens the panel the way a click does (keyboard stays with the app).
    function openLikeClick(): void { root.open(true) }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function switchLanguage(): void { root.toggleIm() }
    function toggleFromPanel(): void { root.toggleImFromPanel() }
    function setLanguage(language: string): void { root.setLanguage(language) }
  }

  Process {
    id: helperProc
    // sh only checks for the binary and then becomes the helper (exec): no extra process.
    command: ["sh", "-c", "[ -x \"$1\" ] || exit 127; exec \"$1\" 100 \"$2\"", "sh", root.helperBin, root.stateFile]
    onStarted: {
      root.helperStartedAt = Date.now()
      helperSettleTimer.restart()
    }
    // The active helper prints "active" once its first value is in the file.
    stdout: SplitParser { onRead: function() { stateView.reload() } }
    onExited: function(code) {
      helperSettleTimer.stop()
      root.helperUp = false
      root.refresh()
      var quick = Date.now() - root.helperStartedAt < 5000
      root.helperQuickExits = quick ? root.helperQuickExits + 1 : 0
      if (code === 127 || root.helperQuickExits >= 3) {
        // Missing or crashing: stay on the 1.5 s poll, look again in a minute.
        root.helperQuickExits = 0
        helperRetryTimer.restart()
      } else {
        helperRestartTimer.restart()
      }
    }
  }

  // A missing binary makes sh exit within milliseconds; still running after this
  // means the helper is up (active or standby) and the state file can be trusted.
  Timer {
    id: helperSettleTimer
    interval: 300
    onTriggered: if (helperProc.running) root.helperUp = true
  }

  Timer {
    id: helperRestartTimer
    interval: 2000
    onTriggered: root.startHelper()
  }

  Timer {
    id: helperRetryTimer
    interval: 60000
    onTriggered: root.startHelper()
  }

  FileView {
    id: stateView
    path: root.helperUp ? root.stateFile : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: if (root.helperUp) root.applyState(text())
    // A standby can come up before the active helper has created the file.
    onLoadFailed: if (root.helperUp) stateRetryTimer.restart()
  }

  Timer {
    id: stateRetryTimer
    interval: 1000
    onTriggered: if (root.helperUp) stateView.reload()
  }

  Process {
    id: queryProc
    // Only ask when fcitx5 is up: fcitx5-remote on a dead fcitx5 D-Bus-starts a stray one
    // that fights the omarchy-fcitx5 service.
    command: ["sh", "-c", "pgrep -x fcitx5 >/dev/null && exec fcitx5-remote -n"]
    onRunningChanged: {
      if (running) stallTimer.restart()
      else stallTimer.stop()
    }
    // A missing binary or dead daemon yields no output; show "--" rather than guessing.
    onExited: function(code) { if (code !== 0) root.imName = "" }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.imName = String(text || "").trim()
    }
  }

  // The hotkey lives in fcitx5's global config; ask the running daemon so a
  // customised ~/.config/fcitx5/config is respected.
  Process {
    id: shortcutProc
    command: ["sh", "-c", "pgrep -x fcitx5 >/dev/null && exec busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 GetConfig s fcitx://config/global"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = /"TriggerKeys" a\{sv\} \d+ "0" s "([^"]*)"/.exec(String(text || ""))
        if (m && m[1] !== "") root.shortcut = root.prettyKey(m[1])
      }
    }
  }

  // Fallback only: short delay so fcitx5 has applied the toggle before we read it back.
  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: root.refresh()
  }

  // Fallback poll, only while no helper is up. fcitx5 sends no signal when the input
  // method changes (checked on the bus), so Ctrl+Space can only be noticed by asking.
  Timer {
    interval: 1500
    running: !root.helperUp
    repeat: true
    onTriggered: root.refresh()
  }

  // Give up on a query that hangs so the next poll can run.
  Timer {
    id: stallTimer
    interval: 3000
    onTriggered: queryProc.running = false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: 6
    opacity: root.imName === "" ? 0.5 : 1.0
    tooltipText: root.tip
    onPressed: function() { root.togglePanel(true) }
  }
}
