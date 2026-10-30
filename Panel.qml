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
  moduleName: "vn-keyboard"
  ipcTarget: "vn-keyboard"
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
    root.bar.run("busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 SetConfig sv fcitx://config/addon/bamboo 'a{sv}' 1 "
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

  function refresh() {
    if (readProc.running) return
    readProc.running = true
  }

  function reloadFcitx() {
    if (root.bar) root.bar.run("systemctl --user restart omarchy-fcitx5.service")
    root.close()
  }

  function openFullSettings() {
    if (root.bar) root.bar.run("setsid -f fcitx5-configtool")
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

        PanelSeparator { foreground: root.contentForeground }

        PanelSectionHeader {
          text: root.tr("secTyping")
          foreground: root.contentForeground
        }

        Dropdown {
          width: parent.width
          label: root.tr("inputMethod")
          value: root.opts.InputMethod
          options: root.methods
          onChanged: function(v) { root.setOption("InputMethod", v) }
        }

        Toggle {
          width: parent.width
          label: root.tr("modern")
          description: root.tr("modernDesc")
          checked: root.flag("ModernStyle")
          onClicked: root.setFlag("ModernStyle", !root.flag("ModernStyle"))
        }

        Toggle {
          width: parent.width
          label: root.tr("free")
          description: root.tr("freeDesc")
          checked: root.flag("FreeMarking")
          onClicked: root.setFlag("FreeMarking", !root.flag("FreeMarking"))
        }

        Toggle {
          width: parent.width
          label: root.tr("restore")
          description: root.tr("restoreDesc")
          checked: root.flag("AutoNonVnRestore")
          onClicked: root.setFlag("AutoNonVnRestore", !root.flag("AutoNonVnRestore"))
        }

        Toggle {
          width: parent.width
          label: root.tr("spell")
          description: root.tr("spellDesc")
          checked: root.flag("SpellCheck")
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
