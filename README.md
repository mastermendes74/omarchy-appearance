# omarchy-appearance

An Omarchy shell bar widget (plugin id: `mendestein.appearance`) that puts theme
switching and wallpaper control behind one bar icon, styled entirely with the
active theme's colors.

## Features

- Theme picker: lists every installed theme (`omarchy theme list`), highlights
  the current one, applies on click.
- Wallpaper modes:
  - SINGLE — one wallpaper everywhere
  - PER WORKSPACE — workspace N uses background N (wraps)
  - CYCLING — next background every N minutes; presets 5/10/15/30/60 plus a
    custom number field (1–1440)
- The wallpaper engine watches theme changes and re-derives the background
  list (user backgrounds win over stock theme backgrounds, matching
  `omarchy theme bg next`).
- Donate button (PayPal, mendestein@outlook.com). After donating, the button
  is replaced by a persistent thank-you message — the flag lives in the
  plugin state file and never resets.

## Install

```bash
omarchy plugin add https://github.com/mendestein/omarchy-appearance.git --enable --yes
```

The bar widget lands in the right section; move it with
`omarchy bar move mendestein.appearance --section <left|center|right>`.

State file: `~/.local/state/omarchy/mendestein.appearance.json`
(`mode`, `intervalMinutes`, `donated`).

IPC: `omarchy-shell ipc call mendestein.appearance toggle|open|close|setMode <single|workspace|cycle>|setInterval <minutes>`

## License

MIT
