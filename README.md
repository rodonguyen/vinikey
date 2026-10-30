# vn-keyboard

A bar widget for [Omarchy](https://omarchy.org) that shows whether you are typing
Vietnamese or English, and puts the [fcitx5](https://github.com/fcitx/fcitx5)
Bamboo options one click away.

- **`VI` / `EN` indicator** in the bar, following `Ctrl+Space` within about 100 ms.
- **Settings panel** (click the indicator):
  - the typing switch and your shortcut,
  - input method: Telex, VNI, VIQR, Telex 2, Telex W, Telex + VNI, Microsoft layout,
  - modern tone placement (`hoà` instead of `hòa`), free tone marking,
    restore English words (`window` stays `window`), spell check,
  - **Reload fcitx5** and **Full settings** buttons,
  - a **Language/Ngôn ngữ** switch: the panel is Vietnamese by default, English on request.
- Changes apply to the running fcitx5 immediately; no restart.
- Light on resources: the optional helper uses about 0.06% of a core and under 1 MB.

> Tested on Omarchy with Hyprland 0.56.2, fcitx5 5.1.23 and fcitx5-bamboo 1.0.11.
> Other versions may need small changes; see [docs/DESIGN.md](docs/DESIGN.md).

## Requirements

- Omarchy with its shell plugin support (`omarchy plugin ...`).
- `fcitx5`, `fcitx5-bamboo` (and `fcitx5-configtool` for the Full settings button).
  All are in Arch's official `extra` repo.
- fcitx5 running as Omarchy's `omarchy-fcitx5.service` (the default on Omarchy).
- Optional, for instant updates: a C compiler (`base-devel`).

## Install

**1. Install fcitx5 and Bamboo** (skip what you already have):

```bash
sudo pacman -S --needed fcitx5 fcitx5-bamboo fcitx5-configtool
```

**2. Add Bamboo as an input method.** The easy way: run `fcitx5-configtool`, open
*Input Method*, untick *Only show current language*, and add **Bamboo**. Keep your
normal keyboard first in the list.

> If you edit `~/.config/fcitx5/profile` by hand, stop fcitx5 first
> (`systemctl --user stop omarchy-fcitx5.service`), edit, then start it again.
> fcitx5 rewrites that file from memory when it exits, so edits made while it runs
> are lost.

**3. Install the plugin:**

```bash
omarchy plugin add https://github.com/rodonguyen/vn-keyboard --enable
omarchy restart shell
```

The indicator appears on the right side of the bar. Move it with
`omarchy bar move vn-keyboard --section center` (or `left`/`right`).

**4. Optional: the fast helper.** Without it the widget checks fcitx5 every 1.5 s, so
the label can lag after `Ctrl+Space`. With it the label updates in about 50 ms:

```bash
~/.config/omarchy/plugins/vn-keyboard/scripts/build-helper.sh   # or run it from a clone of this repo
omarchy restart shell
```

This compiles `helper/fcitx5-im-watch.c` into `~/.local/bin/fcitx5-im-watch`. If there
is no compiler it tells you and the widget keeps working with the slower check.

## Use

| Action | What happens |
|---|---|
| `Ctrl+Space` (or your fcitx5 hotkey) | switch between English and Vietnamese; the label follows |
| Click the indicator | open the settings panel (click outside to close) |
| Panel: typing switch | switch language for the window you are typing in |
| Panel: dropdown and option switches | change Bamboo live |
| Panel: Language/Ngôn ngữ | switch the panel between Vietnamese and English |

The label reads `--` when fcitx5 is not running, and also when no window has keyboard
focus, because fcitx5 keeps one input state per window.

## Troubleshooting

- **`--` in the bar:** fcitx5 isn't running. Check
  `systemctl --user status omarchy-fcitx5.service`. Don't start `fcitx5` by hand
  while that service is enabled; the two fight over the D-Bus name.
- **`Ctrl+Space` seems to do nothing:** your profile's `DefaultIM` should be
  `bamboo` (the method `Ctrl+Space` switches to), not your plain keyboard. If you
  ever restored state with `fcitx5-remote -s <keyboard>`, reset it with
  `fcitx5-remote -s bamboo; fcitx5-remote -c`.
- **Label lags by a second:** the helper isn't installed or loaded. Run step 4, then
  `omarchy restart shell`. Widget code changes always need a shell restart.
- **Typing doesn't convert in one app:** check that the app has an input-method
  environment (`QT_IM_MODULE=fcitx`, and no `GTK_IM_MODULE` on Wayland).
- **Settings panel text is English/Vietnamese the wrong way round:** use the
  **Language/Ngôn ngữ** switch.

## Safety

Omarchy plugins are **not sandboxed**: they run inside the shell with your
permissions. This widget runs only: `fcitx5-remote`, `busctl` (to read and write
Bamboo's settings on the session bus), `pgrep`, `hyprctl` (to return focus to your
window), `systemctl --user restart omarchy-fcitx5.service`, `fcitx5-configtool`,
and the optional `~/.local/bin/fcitx5-im-watch`. It only reads from fcitx5 on every
poll and never auto-starts it. Read the code before installing; it is short.

## Uninstall

```bash
omarchy plugin remove vn-keyboard
rm -f ~/.local/bin/fcitx5-im-watch      # if you built the helper
omarchy restart shell
```

## Development

See [docs/DESIGN.md](docs/DESIGN.md) for the requirements, how the widget talks to
fcitx5, a list of gotchas that cost real debugging time, and how it was tested.

```bash
omarchy plugin validate .
```

## Tiếng Việt

Widget cho thanh bar của Omarchy, hiển thị bạn đang gõ **tiếng Việt (`VI`)** hay
**tiếng Anh (`EN`)** với fcitx5 + Bamboo. Bấm vào biểu tượng để mở bảng cài đặt:
đổi kiểu gõ (Telex, VNI, VIQR...), đặt dấu kiểu mới (`hoà`), bỏ dấu tự do, khôi phục
từ tiếng Anh, kiểm tra chính tả. Bảng mặc định bằng tiếng Việt; công tắc
**Language/Ngôn ngữ** đổi sang English.

Cài đặt: làm theo các bước ở phần *Install* phía trên (cài `fcitx5-bamboo`, thêm
Bamboo trong `fcitx5-configtool`, rồi `omarchy plugin add ... --enable`). Phím tắt
chuyển ngôn ngữ mặc định là `Ctrl+Space`.

## License

[MIT](LICENSE)
