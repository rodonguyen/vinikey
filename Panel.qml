import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Strings.js" as Strings

// Settings popup for fcitx5 Bamboo: a language switch on top, then the typing
// method and the Bamboo options people most often change.
//
// Options are read from, and written to, the running fcitx5 over D-Bus
// (Controller1.GetConfig / SetConfig), so a change applies at once and fcitx5
// saves it to ~/.config/fcitx5/conf/bamboo.conf itself.
//
// BarWidget.qml owns the bar label and hands this panel the button to anchor to.
//
// Keyboard focus: fcitx5 keeps the input method per input context, and a panel that
// holds the keyboard becomes the focused context itself. The bar would then show the
// panel's state and the typing switch would toggle the panel, not the app. So when the
// panel is opened with the mouse it never takes the keyboard (the app keeps it). When
// it is summoned from the keyboard it takes focus as usual for Esc/Tab/arrows, and
// gives it back to the app the first time the typing switch is used.
Panel {
  id: root
  moduleName: "rodonguyen.vinikey"
  ipcTarget: "rodonguyen.vinikey"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot, not this nested panel.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Bamboo's current values; the defaults match what Bamboo ships with.
  property var opts: ({
    InputMethod: "Telex",
    ModernStyle: "False",
    FreeMarking: "True",
    AutoNonVnRestore: "True",
    SpellCheck: "True"
  })
  property bool fcitxUp: true
  // True while this opening of the panel leaves the keyboard with the app.
  property bool keyboardReleased: false
  // The last six switches are tucked away until asked for.
  property bool expanded: false
  // fcitx5 or Bamboo is missing and this folder has install.sh to fix it.
  property bool setupNeeded: false

  readonly property string installScript: decodeURIComponent(String(Qt.resolvedUrl("install.sh")).replace(/^file:\/\//, ""))
  readonly property string fcitxProfile: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/fcitx5/profile"

  // fcitx5's "Toggle Input Method" keys, in order; null until read.
  property var triggerKeys: null
  // Ctrl+Shift as fcitx5 spells it: either key first, either Shift. fcitx5 fires a
  // modifier-only hotkey on release with nothing pressed in between, so shortcuts
  // like Ctrl+Shift+T keep working.
  readonly property var ctrlShiftKeys: ["Control+Shift_L", "Control+Shift_R", "Shift+Control_L", "Shift+Control_R"]
  readonly property bool ctrlShift: triggerKeys !== null && triggerKeys.indexOf("Control+Shift_L") >= 0

  readonly property bool vietnamese: hostWidget ? hostWidget.vietnamese : false
  readonly property string shortcut: hostWidget ? hostWidget.shortcut : "Ctrl+Space"
  readonly property string lang: hostWidget ? hostWidget.lang : "vi"

  function tr(key) { return Strings.tr(root.lang, key) }

  // Bamboo stores the method by name. The French-keyboard VNI, the triple
  // combos and "Custom" are left to the full settings window.
  readonly property var methods: [
    "Telex", "VNI", "VIQR", "Telex 2", "Telex W", "Telex + VNI", "Microsoft layout"
  ]

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground

  function flag(key) { return root.opts[key] === "True" }

  function setOption(key, value) {
    if (!root.bar) return
    // Applied locally first so the control answers the click itself; Bamboo's
    // own value is read back when the panel next opens.
    var next = {}
    for (var k in root.opts) next[k] = root.opts[k]
    next[key] = value
    root.opts = next
    // Guarded like every other call: a write to a dead fcitx5 would D-Bus-start a stray one.
    root.bar.run("pgrep -x fcitx5 >/dev/null && exec busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetConfig sv fcitx://config/addon/bamboo 'a{sv}' 1 "
      + Util.shellQuote(key) + " s " + Util.shellQuote(value))
  }

  function setFlag(key, on) { setOption(key, on ? "True" : "False") }

  function parseOptions(text) {
    var next = {}
    for (var k in root.opts) next[k] = root.opts[k]
    // The value block lists `"Key" s "Value"`; the description block that
    // follows spells `"Key" "Type"`, so this only matches values.
    for (var key in next) {
      var m = new RegExp('"' + key + '" s "([^"]*)"').exec(text)
      if (m) next[key] = m[1]
    }
    root.opts = next
  }

  // GetConfig lists the keys as `"TriggerKeys" a{sv} N "0" s "Control+space" "1" s ...`.
  function parseTriggerKeys(text) {
    var m = /"TriggerKeys" a\{sv\} (\d+)((?: "\d+" s "[^"]*")*)/.exec(text)
    if (!m) return
    var keys = []
    var re = /"\d+" s "([^"]*)"/g, k
    while ((k = re.exec(m[2])) !== null) keys.push(k[1])
    root.triggerKeys = keys
  }

  // Off: Ctrl+Space switches. On: Ctrl+Shift switches instead. Other keys in the
  // list (e.g. Zenkaku_Hankaku) stay; the chosen shortcut goes first, since the bar
  // shows the first key.
  function setCtrlShift(on) {
    if (!root.bar || root.triggerKeys === null) return
    var keys = root.triggerKeys.filter(function(k) {
      return root.ctrlShiftKeys.indexOf(k) < 0 && k !== "Control+space"
    })
    keys = (on ? root.ctrlShiftKeys : ["Control+space"]).concat(keys)
    root.triggerKeys = keys
    if (root.hostWidget) root.hostWidget.shortcut = on ? "Ctrl+Shift" : "Ctrl+Space"
    var args = ""
    for (var i = 0; i < keys.length; i++) args += " " + Util.shellQuote(String(i)) + " s " + Util.shellQuote(keys[i])
    root.bar.run("pgrep -x fcitx5 >/dev/null && exec busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetConfig sv fcitx://config/global "
      + "'a{sv}' 1 Hotkey 'a{sv}' 1 TriggerKeys 'a{sv}' " + keys.length + args)
  }

  function refresh() {
    if (!setupProbe.running) setupProbe.running = true
    if (!globalProc.running) globalProc.running = true
    if (readProc.running) return
    readProc.running = true
  }

  // Runs install.sh in Omarchy's floating terminal, where pacman can ask for the
  // password. The launcher hands its arguments to bash again, hence the double quoting.
  function runSetup() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation "
      + Util.shellQuote(Util.shellQuote(root.installScript)))
    root.close()
  }

  function reloadFcitx() {
    if (root.bar) root.bar.run("systemctl --user restart omarchy-fcitx5.service")
    root.close()
  }

  // fcitx5-configtool is a separate package; say how to get it rather than fail silently.
  function openFullSettings() {
    if (root.bar) root.bar.run("if command -v fcitx5-configtool >/dev/null; then exec setsid -f fcitx5-configtool; "
      + "else exec notify-send " + Util.shellQuote(root.tr("configtoolMissing")) + " 'sudo pacman -S fcitx5-configtool'; fi")
    root.close()
  }

  function open(pointer) {
    root.keyboardReleased = pointer === true
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  Process {
    id: readProc
    // Only ask when fcitx5 is up, so a dead fcitx5 isn't D-Bus-started by this.
    command: ["sh", "-c", "pgrep -x fcitx5 >/dev/null && exec busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 GetConfig s fcitx://config/addon/bamboo"]
    onExited: function(code) { root.fcitxUp = (code === 0) }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseOptions(String(text || ""))
    }
  }

  Process {
    id: globalProc
    command: ["sh", "-c", "pgrep -x fcitx5 >/dev/null && exec busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 GetConfig s fcitx://config/global"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseTriggerKeys(String(text || ""))
    }
  }

  // Exit 1: fcitx5 or Bamboo is not set up. Exit 2: no install.sh here (e.g. a
  // copy without the scripts), so there is nothing to offer.
  Process {
    id: setupProbe
    command: ["sh", "-c", "[ -x \"$1\" ] || exit 2; "
      + "pacman -Q fcitx5 fcitx5-bamboo >/dev/null 2>&1 && grep -qx 'Name=bamboo' \"$2\" 2>/dev/null || exit 1",
      "sh", root.installScript, root.fcitxProfile]
    onExited: function(code) { root.setupNeeded = (code === 1) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Overrides KeyboardPanel's own binding (Exclusive prime, then OnDemand) only to
    // add the released case; see the note at the top of this file.
    WlrLayershell.keyboardFocus: !root.opened || root.keyboardReleased
      ? WlrKeyboardFocus.None
      : (panel.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "Vinikey"
          color: root.contentForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        // ---- Typing language switch. This is the same action as Ctrl+Space
        //      (the fcitx5 hotkey).
        Toggle {
          width: parent.width
          label: root.tr("typing")
          description: root.fcitxUp
            ? root.tr("shortcut") + ": " + root.shortcut
            : root.tr("notRunning")
          checked: root.vietnamese
          enabled: root.fcitxUp
          onClicked: if (root.hostWidget) root.hostWidget.toggleImFromPanel()
        }

        Button {
          visible: root.setupNeeded
          width: parent.width
          text: root.tr("setup")
          tooltipText: root.tr("setupTip")
          onClicked: root.runSetup()
        }

        PanelSeparator { foreground: root.contentForeground }

        Dropdown {
          width: parent.width
          label: root.tr("inputMethod")
          // A method set elsewhere that isn't listed shows a prompt instead of a value
          // the list doesn't contain.
          value: root.methods.indexOf(root.opts.InputMethod) >= 0 ? root.opts.InputMethod : root.tr("chooseMethod")
          options: root.methods
          enabled: root.fcitxUp
          onChanged: function(v) { root.setOption("InputMethod", v) }
        }

        // Shows the last six switches (including the language switch) and the tools.
        Button {
          width: parent.width
          text: root.expanded ? root.tr("fewerOptions") + "  ▴" : root.tr("moreOptions") + "  ▾"
          onClicked: root.expanded = !root.expanded
        }

        Column {
          id: extraOptions
          visible: root.expanded
          width: parent.width
          spacing: content.spacing

          Toggle {
            width: parent.width
            label: root.tr("ctrlShift")
            description: root.tr("ctrlShiftDesc")
            checked: root.ctrlShift
            enabled: root.fcitxUp && root.triggerKeys !== null
            onClicked: root.setCtrlShift(!root.ctrlShift)
          }

          Toggle {
            width: parent.width
            label: root.tr("modern")
            description: root.tr("modernDesc")
            checked: root.flag("ModernStyle")
            enabled: root.fcitxUp
            onClicked: root.setFlag("ModernStyle", !root.flag("ModernStyle"))
          }

          Toggle {
            width: parent.width
            label: root.tr("free")
            description: root.tr("freeDesc")
            checked: root.flag("FreeMarking")
            enabled: root.fcitxUp
            onClicked: root.setFlag("FreeMarking", !root.flag("FreeMarking"))
          }

          Toggle {
            width: parent.width
            label: root.tr("restore")
            description: root.tr("restoreDesc")
            checked: root.flag("AutoNonVnRestore")
            enabled: root.fcitxUp
            onClicked: root.setFlag("AutoNonVnRestore", !root.flag("AutoNonVnRestore"))
          }

          Toggle {
            width: parent.width
            label: root.tr("spell")
            description: root.tr("spellDesc")
            checked: root.flag("SpellCheck")
            enabled: root.fcitxUp
            onClicked: root.setFlag("SpellCheck", !root.flag("SpellCheck"))
          }

          // ---- Language of this panel. Bilingual label so it can be found
          //      from either language. On means Vietnamese.
          Toggle {
            width: parent.width
            label: "Language/Ngôn ngữ"
            description: root.tr("languageDesc")
            checked: root.lang === "vi"
            onClicked: if (root.hostWidget) root.hostWidget.setLanguage(root.lang === "vi" ? "en" : "vi")
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: root.tr("secTools")
            foreground: root.contentForeground
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.tr("reload")
              tooltipText: root.tr("reloadTip")
              onClicked: root.reloadFcitx()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.tr("fullSettings")
              tooltipText: root.tr("fullSettingsTip")
              onClicked: root.openFullSettings()
            }
          }
        }
      }
    }
  }
}
