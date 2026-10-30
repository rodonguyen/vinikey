# Contributing to Vinikey

Thanks for helping. Bug reports, fixes, translations and small features are all
welcome. For anything bigger than a bug fix, open an issue first so we can agree
on the approach before you spend time on it.

## Set up

You need an Omarchy machine with fcitx5 and Bamboo working (`./install.sh` sets that up).

`omarchy plugin add` installs the plugin as a git clone, so you can work in place:

```bash
# Fresh: clone your fork straight into the plugins folder
git clone https://github.com/<you>/vinikey ~/.config/omarchy/plugins/rodonguyen.vinikey
omarchy plugin enable rodonguyen.vinikey

# Or, if you already installed it with `omarchy plugin add`:
cd ~/.config/omarchy/plugins/rodonguyen.vinikey
git remote add fork https://github.com/<you>/vinikey
```

The plugin folder must not contain symlinks (the validator rejects them), so
don't link it to a checkout somewhere else.

**The shell caches widget code.** After editing a `.qml` or `.js` file, run
`omarchy restart shell` to see the change.

Useful while testing (no mouse needed):

```bash
omarchy-shell rodonguyen.vinikey openLikeClick   # open the panel as a click does
omarchy-shell rodonguyen.vinikey setOptionsExpanded true
omarchy-shell rodonguyen.vinikey setLanguage en  # or vi
omarchy-shell rodonguyen.vinikey close
journalctl --user --since "-5 min" | grep -i qml # QML errors and warnings
```

## Run the tests

```bash
sudo pacman -S --needed nodejs dbus python-gobject base-devel   # once
bash tests/run.sh
omarchy plugin validate .
```

What they cover:

| Test | Checks |
|---|---|
| `tests/strings.test.mjs` | both languages have the same keys, fallbacks, every key the QML uses exists |
| `tests/manifest.test.mjs` | manifest fields, id rules, QML and README use the manifest id, no symlinks |
| `tests/helper.test.sh` | the C helper on a private D-Bus: never auto-starts fcitx5, reports changes, state-file handover |
| `tests/install.test.sh` | `install.sh` in a throwaway HOME (fcitx5, systemd and omarchy stubbed): fcitx5 profile merge and rollback, keeping the user's method, plugin placement and id migration, helper build |

The helper test runs its own D-Bus daemon and a mock fcitx5, so it never touches
your real session. CI runs the same suite on every pull request.

The QML itself has no automated tests (it needs the Omarchy shell), so describe
in your pull request what you tried by hand.

## Rules that keep it safe

These come from real bugs; [docs/DESIGN.md](docs/DESIGN.md) explains each one.

- **Never let a call start fcitx5.** fcitx5 is D-Bus-activatable, and a stray copy
  fights `omarchy-fcitx5.service`. Guard every `fcitx5-remote`/`busctl` call with
  `pgrep -x fcitx5 >/dev/null && ...`, and keep `NO_AUTO_START` in the helper.
- **Don't edit `~/.config/fcitx5/profile` while fcitx5 runs**; it rewrites the file
  on exit.
- **Put every user-visible string in `Strings.js`, in both `vi` and `en`.** The
  tests fail if a key is missing. Natural Vietnamese is better than a literal
  translation; ask in the PR if unsure.
- **Keep the plugin id `rodonguyen.vinikey`** in the manifest, both `moduleName`s
  and the IPC target. Changing it breaks existing installs.
- **Keep it light.** The bar widget runs all day; no new polling loops or
  long-lived processes without a good reason.

## Pull requests

- One change per pull request, with a clear title (`Panel: …`, `Helper: …`, `Docs: …`).
- Fill in the template: what changed, how you tested it, and a screenshot for
  anything visible.
- Don't bump `version` in `manifest.json`; the maintainer does that when releasing.
- By contributing you agree your work is released under the [MIT license](LICENSE).
