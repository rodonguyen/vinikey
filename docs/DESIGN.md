# Vinikey: design notes

Requirements, design and hard-won gotchas for later developers. Written
2026-10-31 against Omarchy with Hyprland 0.56.2 (Lua config), fcitx5 5.1.23,
fcitx5-bamboo 1.0.11. Re-check the version-specific parts if those move.

## 1. Purpose

Show, in the Omarchy bar, whether fcitx5 is typing Vietnamese (Bamboo) or plain
English, and put the Bamboo options one click away in a panel.

What is in this repo:

| Part | Where | What it is |
|---|---|---|
| Bar widget (Omarchy shell plugin) | `manifest.json`, `BarWidget.qml`, `Panel.qml`, `Strings.js` | `EN` / `VI` indicator + settings panel |
| Optional helper | `helper/fcitx5-im-watch.c`, `scripts/build-helper.sh` | Makes the label follow a switch within about 100 ms |

Setting up fcitx5 itself (packages, adding Bamboo to the profile) is described in
the README; this repo does not change your fcitx5 configuration except through the
panel's switches.

## 2. Requirements

### 2.1 Bar widget

| ID | Requirement |
|---|---|
| W-1 | Show `VI` when the active fcitx5 input method is `bamboo`, `EN` otherwise, `--` (dimmed, with an explanatory tooltip) when fcitx5 is not running. |
| W-2 | Clicking the icon (any button) opens the settings panel, consistent with the other Omarchy panel widgets. There is no click-to-toggle on the icon: the typing language is switched with the panel's switch or the fcitx5 hotkey (`Ctrl+Space`). |
| W-3 | Show the current toggle shortcut (read live from fcitx5's `Hotkey/TriggerKeys`, shown as e.g. `Ctrl+Space`) in the panel and tooltip. |
| W-4 | Panel contains, top to bottom: a centered `Vinikey` title; a Vietnamese-typing switch (toggles the focused app's input method; the panel stays open); input method dropdown (Telex, VNI, VIQR, Telex 2, Telex W, Telex + VNI, Microsoft layout; an unlisted method shows `Chọn kiểu gõ…` / `Choose method…`); an expander (`Tùy chọn khác` / `More options`, in the panel's current language) that is **collapsed by default** and reveals five switches: Modern tone placement, Free tone marking, Restore English words, Spell check and the bilingual `Language/Ngôn ngữ` switch, followed by the Tools section (Reload fcitx5, Full settings), which is collapsed with them. |
| W-5 | Option changes apply immediately to the running fcitx5 (no restart) and are persisted by fcitx5 itself. |
| W-6 | Panel text is Vietnamese by default and can be switched to English with the `Language/Ngôn ngữ` toggle. The label is intentionally bilingual and identical in both languages so it can be found from either. The choice persists in the widget's `shell.json` entry (`"language": "vi"|"en"`). |
| W-7 | The widget must never cause fcitx5 to be started (see gotcha G-1). |
| W-8 | The label follows a switch (hotkey, panel or `fcitx5-remote`) within about 100 ms at negligible cost, with one poller for all bars. |

Out of scope (deliberately): macros (`Macro`/`CapitalizeMacro`), output charset,
custom keymap, per-application defaults, the French-keyboard VNI and the
triple-method combos. They stay reachable through **Full settings**
(`fcitx5-configtool`).

## 3. Design

### 3.1 How the widget talks to fcitx5

* **Reading state**: `Controller1.CurrentInputMethod`, polled every 100 ms by the
  `fcitx5-im-watch` helper (section 3.4). Fallback: `fcitx5-remote -n` spawned
  every 1.5 s.
* **Switching**: `fcitx5-remote -t` (from the panel's switch; see G-9 for focus).
* **Bamboo options**: D-Bus `org.fcitx.Fcitx.Controller1` at `/controller`:
  * `GetConfig s "fcitx://config/addon/bamboo"` to read values. The reply is a
    flat dump; values appear as `"Key" s "Value"` before the description block,
    which spells `"Key" "Type"`, so a regex on `"Key" s "..."` only matches values.
  * `SetConfig sv "fcitx://config/addon/bamboo" a{sv} 1 "Key" s "Value"` to write.
    It merges (only the named key changes) and applies live.
* Booleans are the strings `"True"` / `"False"`. Input methods are stored by
  name (`"Telex"`, `"VNI"`, `"Telex + VNI"`, ...). Keys used: `InputMethod`,
  `ModernStyle` (True = `hoà`), `FreeMarking`, `AutoNonVnRestore`, `SpellCheck`.
* Shortcut: `GetConfig s "fcitx://config/global"`, first `TriggerKeys` entry.

### 3.2 Widget files

| File | Role |
|---|---|
| `manifest.json` | Plugin manifest (id, kind `bar-widget`, entry point). |
| `BarWidget.qml` | Bar button, runs/reads the helper (or the fallback poll), language setting, loads the panel, IPC handler. |
| `Panel.qml` | The popup (modelled on Omarchy's clock panel). |
| `Strings.js` | Vietnamese/English string table; unknown keys fall back to English, then the key. |

IPC (`omarchy-shell vinikey <fn>`): `open` (like a keyboard summon: the
panel takes the keyboard), `openLikeClick` (like a click: it does not), `close`,
`toggle`, `switchLanguage` (toggles EN/VI typing), `toggleFromPanel` (exactly what
the panel's switch does), `setLanguage <vi|en>` (panel language). These exist
mainly for scripting and testing.

### 3.3 The `fcitx5-im-watch` helper

fcitx5 sends nothing when the input method changes (G-4), so something has to
ask. Spawning `pgrep` + `fcitx5-remote` costs about 40 ms CPU per check, so a
fast spawn poll is out. Instead a ~200-line C program
(`helper/fcitx5-im-watch.c`, libc only, speaks the D-Bus wire protocol itself)
keeps one session-bus connection and calls `CurrentInputMethod` every 100 ms.

* **Never starts fcitx5**: every call carries the D-Bus `NO_AUTO_START` flag;
  while fcitx5 is down the call just fails and the helper reports `-` (label
  `--`). Also `-` when no input context has focus (same as `fcitx5-remote -n`
  printing nothing).
* **One poller for all bars**: each bar runs
  `fcitx5-im-watch 100 $XDG_RUNTIME_DIR/fcitx5-im-watch`. The first instance
  takes `flock` on `...fcitx5-im-watch.lock` and rewrites the state file in place
  (one 32-byte write) on every change; the others block in `flock` at zero CPU
  and take over within milliseconds if it dies. Every bar watches the file with
  `FileView` (inotify).
* **No orphans**: the helper sets `PR_SET_PDEATHSIG`, so it dies with the shell.
* **Fallback**: the widget runs it through `sh -c '[ -x "$1" ] || exit 127; exec ...'`.
  A missing binary (exit 127) or three exits within 5 s each switch the widget to
  the old 1.5 s spawn poll; it tries the helper again every 60 s. Helper exits
  otherwise restart it after 2 s (the 1.5 s poll covers the gap).
* **Built by `scripts/build-helper.sh`** with `cc -O2 -s -static`, falling back
  to a dynamic build, into `~/.local/bin/fcitx5-im-watch`. Optional: without it the
  widget uses the slower poll.

Measured on the dev machine (2 monitors, 40 s windows):

| | Before (1.5 s spawn poll, 2 bars) | After (helper) |
|---|---|---|
| Label delay after a switch | up to 1.5 s | `Ctrl+Space` 17-107 ms (mean 62, n=12); `fcitx5-remote -t` 6-98 ms (mean 50, n=12) |
| CPU, widget's own processes | about 5.4% of a core (spawns: ~1.7 s CPU per 30 s) | active helper 0.06%, standby 0% |
| CPU added in fcitx5 + dbus-broker | negligible | about 0.1% + 0.1% |
| Memory | short-lived spawns | 770 kB RSS per helper (static), ~410 kB PSS |

## 4. Gotchas (each one cost us real debugging time)

| ID | Gotcha | What to do |
|---|---|---|
| G-1 | `org.fcitx.Fcitx5` is D-Bus-activatable. Any client call while fcitx5 is down (`fcitx5-remote`, `busctl call`, even `fcitx5-remote -e`) auto-starts a stray plain `fcitx5`, which then fights the systemd service for the bus name and sends it into a restart loop (we saw 2,800+ restarts). | Guard every call with `pgrep -x fcitx5 >/dev/null && ...`. Stop fcitx5 with `systemctl --user stop` + `pkill -x fcitx5`, never `fcitx5-remote -e`. Never start fcitx5 by hand while the service is enabled. |
| G-2 | fcitx5 **rewrites `~/.config/fcitx5/profile` from memory when it exits.** Editing the file while it runs, then restarting it, loses the edit. | Stop fcitx5, then write config, then start. |
| G-3 | `fcitx5-remote -r` does not reload the profile. | Restart the service instead. |
| G-4 | fcitx5 does **not** emit a D-Bus signal when the input method changes (verified with `busctl monitor`: only method calls; `Controller1`'s declared signals never fire; an unfocused input context gets no `CurrentIM`; Hyprland's socket2 and the fcitx5 config files show nothing). The kimpanel addon *does* push `UpdateProperty` on every switch, but only to whoever owns `org.kde.impanel`, and owning that name makes fcitx5 hand its whole UI (candidate window, switch popup) to the owner. | Poll cheaply: the `fcitx5-im-watch` helper (section 3.4). Do not claim `org.kde.impanel`. |
| G-5 | The Omarchy shell caches bar-widget code. Saving files reloads the plugin list but the running widget instance stays old. | `omarchy restart shell` to load widget changes (brief bar blink). Panel changes need it too. |
| G-6 | Plugin folders must not contain symlinks (validator rejects them). | Copy, don't link. |
| G-7 | Hyprland 0.56 uses **Lua** dispatch syntax. `hyprctl dispatch focuswindow title:X` silently does nothing. | `hyprctl dispatch 'hl.dsp.focus({ window = "title:^X$" })'`. |
| G-8 | Third-party plugin IDs cannot use the `omarchy.*` prefix. | Current id is `vinikey`. |
| G-9 | A panel that holds keyboard focus is itself the focused fcitx5 input context. Then `fcitx5-remote -t` flips the **panel's** context (status changes, nothing visible), and `CurrentInputMethod` reports the panel's method, so the bar would show `EN` while the app is in `VI`. Setting the panel's `keyboardFocus` to `None` after it had focus does **not** give the keyboard back to the app in Hyprland 0.56; re-focusing the active window (`hl.dsp.focus({ window = "address:0x..." })`) does, and the panel stays open. | Opened by a click, the panel overrides `WlrLayershell.keyboardFocus` to `None` and never takes the keyboard. Summoned from the keyboard it takes focus (Esc/Tab/arrows work); the first use of the typing switch drops it, re-focuses the active window, then toggles. The panel stays open either way. Close the panel before sending keys in automated tests. |
| G-10 | `wtype` types into whatever has focus. | In tests, verify the target window has focus (`hyprctl activewindow -j`) before every batch. |
| G-12 | fcitx5 has two independent things: the *selected* method (`fcitx5-remote -s`) and active/inactive (`-t`, `Ctrl+Space`, `-c`, `-o`). Inactive is always the first method (plain keyboard); `Ctrl+Space` flips to the selected/default method. Restoring with `-s keyboard-us` selects the keyboard as the active method, after which `Ctrl+Space` toggles two identical keyboards and looks dead. | Restore with `fcitx5-remote -c` (inactive). Keep `DefaultIM=bamboo` in the profile so the toggle has somewhere to go. |
| G-11 | `qmllint` on these files reports "Failed to import qs.Ui/qs.Commons" and "WidgetButton not found". That is noise: the `qs.*` modules only resolve inside the running shell. | Look for syntax errors only; load it in the shell and read `qs -p /usr/share/omarchy/shell log`. |

## 5. Testing

### 5.1 Static
```bash
omarchy plugin validate .
bash -n scripts/build-helper.sh
BIN_DIR=$(mktemp -d) ./scripts/build-helper.sh   # builds into a temp dir
```

### 5.2 End to end (what was actually run)
* Widget loaded in a real Omarchy shell; fcitx5 service stable (0 restarts).
* Real typing through Bamboo into a throwaway `foot` window with `wtype`:
  * VNI `Vie65t Nam` gives **Việt Nam**; `Xin cha2o cac1 ba5n` gives **Xin chào các bạn**.
  * Modern tone ON, `hoa2` gives **hoà**; OFF gives **hòa**; changed live via the same D-Bus call the panel uses.
  * Telex `Tooi yeeu Vieetj Nam` gives **Tôi yêu Việt Nam**.
  * "Restore English words" ON keeps `window` as `window`.
  * Real `Ctrl+Space` switched to the plain keyboard.
* Panel verified by screenshot (`grim`), including values read back after
  changing `InputMethod`/`ModernStyle` over D-Bus, the Vietnamese and English
  text, and the Language toggle persisting to `shell.json`.
* **Not verified end to end**: Telex typing in isolation and the
  "Restore English words OFF" case were inconclusive in the last run; the
  final `Ctrl+Space` back-toggle also was. Re-test these after any change.
* Clicks were exercised through IPC and the equivalent commands, not with a
  physical pointer.
* Helper (2026-10-31): latency numbers in 3.4 from real `Ctrl+Space` (`wtype`
  into a throwaway `foot`) and `fcitx5-remote -t`. Killing the active helper:
  the standby took over within 0.3 s and the killed one came back as standby.
  `systemctl --user restart omarchy-fcitx5.service`: state went `-` then back
  within 100 ms, NRestarts stayed 0. `omarchy restart shell`: no helper
  survived. Binary renamed away: the label kept updating through the 1.5 s poll,
  and the helper came back by itself after the binary returned.
* Panel switch (both `openLikeClick` and `open`): the test window's method
  flipped on each `toggleFromPanel`, the panel layer stayed mapped, and a second
  toggle went back.

## 6. Known limitations and open items

* **Update latency.** With the helper the label follows within about 100 ms.
  Without it (no compiler at install time) the fallback poll can lag up to
  1.5 s, and a toggle from the panel re-reads after 150 ms. Rejected
  alternatives: a faster spawn poll (200 ms would cost about 19% of a core), a
  persistent Python poller (about 30 MB RSS per instance), kimpanel (G-4).
* **One widget instance per monitor** (the bar is built per monitor). Each
  starts a helper, but only one polls; the rest wait on the lock.
* **Panel keyboard focus.** A clicked-open panel does not take the keyboard,
  so Esc/Tab/arrow keys do not reach it (click outside to close). A
  keyboard-summoned panel keeps them until its typing switch is used.
* **Plugin ID.** `vinikey` (earlier names: `rodo.vietnamese-input`, `vn-keyboard`) has no namespace prefix. The validator accepts
  it, but ids are global, so a clash with another plugin of the same name is
  possible. Third-party ids cannot start with `omarchy.` (G-8).
* **Plugins run unsandboxed** in the shell with the user's permissions. The
  widget only runs `fcitx5-remote`, `busctl`, `pgrep`, `hyprctl` (re-focus, G-9),
  `~/.local/bin/fcitx5-im-watch`, `systemctl --user restart
  omarchy-fcitx5.service` and `fcitx5-configtool`.
* On a fresh login the profile's `DefaultIM` decides the starting method. The
  shipped template uses `keyboard-us` (English); a live profile may differ
  because fcitx5 rewrites it.
