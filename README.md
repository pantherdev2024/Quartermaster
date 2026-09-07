# Loadout

An RPG equip screen for Omarchy. Slot in themes, backgrounds, fonts and
defaults, preview them on a miniature desktop, then apply for real — with
system stats reading out along the bottom like a character sheet.

## Usage

- `SUPER + SHIFT + L`, or the Omarchy menu → **Style → Loadout**
- `↑ ↓` move between slots, `← →` browse that slot's inventory
- `ENTER` applies everything staged, `ESC` discards and closes

Browsing only *stages* a selection: the mini desktop repaints instantly and
nothing on the real system changes until you press ENTER.

## Slots

| Slot | Inventory source | Applied with |
|------|------------------|--------------|
| Theme | `~/.config/omarchy/themes` + `/usr/share/omarchy/themes` | `omarchy-theme-set` |
| Background | the staged theme's `backgrounds/` | `omarchy-theme-bg-set` |
| Font | `omarchy font list` | `omarchy-font-set` |
| Terminal | whichever of alacritty/foot/ghostty/kitty are installed | `omarchy-default-terminal` |

Adding a slot means adding one entry to `slotDefs` in `Loadout.qml` and a
matching branch in `itemsFor()`.

## How it works

`scan.sh` emits the whole inventory as one JSON document (themes with their
parsed `colors.toml` palettes, preview images and wallpapers); `stats.sh`
emits one metrics snapshot, keeping the previous sample in a state file so CPU
and network rates are deltas rather than requiring a blocking sleep. The QML
polls stats only while the screen is open, since the plugin shares the
long-running Omarchy shell process.

The centre preview is a *mock* desktop, not a screen capture. A capture can
only show what is already applied, and this overlay covers the screen anyway —
mocking it is what makes previewing an unapplied theme possible.

## Notes

The backdrop is deliberately opaque. Besides suiting the genre, a partially
transparent child on this layer surface has its alpha dropped and paints
nothing, while an opaque one composites correctly. Panel colours are the
theme's background with a little of its foreground mixed in, so contrast holds
under light themes (Lupine, Catppuccin Latte) as well as dark ones.

## Files

```
manifest.json    overlay plugin declaration
Loadout.qml      overlay entry: slots, staging, apply queue, layout
MiniDesktop.qml  the miniature mock desktop
SlotPanel.qml    one equipment slot + its inventory row
Gauge.qml        radial dial (CPU, GPU)
Meter.qml        horizontal bar (memory, disk, swap)
scan.sh          inventory as JSON
stats.sh         system metrics as JSON
```
