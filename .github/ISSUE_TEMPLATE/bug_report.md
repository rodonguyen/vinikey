---
name: Bug report
about: Something doesn't work as described
labels: bug
---

**What happened**

<!-- What did you do, what did you expect, what happened instead? -->

**Versions**

<!-- Paste the output of: -->

```bash
omarchy version
pacman -Q fcitx5 fcitx5-bamboo hyprland
jq -r .version ~/.config/omarchy/plugins/rodonguyen.vinikey/manifest.json
ls -l ~/.local/bin/fcitx5-im-watch   # the optional helper
```

**Logs**

<!-- Output of the following, right after the problem happens: -->

```bash
journalctl --user --since "-10 min" | grep -iE "vinikey|qml"
systemctl --user status omarchy-fcitx5.service --no-pager
```
