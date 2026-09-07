# Loadout

An RPG equip screen for Omarchy. Slot in themes, backgrounds, fonts and
defaults, preview them on a miniature desktop, then apply for real — with
system stats reading out along the bottom like a character sheet.

## Usage

- `SUPER + SHIFT + L`, or the Omarchy menu → **Style → Loadout**
- `TAB` / `SHIFT+TAB` (or `1` `2` `3`) switch equipment category
- `↑ ↓` move between slots, `← →` browse that slot's inventory
- `ENTER` applies everything staged, `ESC` discards and closes

Browsing only *stages* a selection: the mini desktop repaints instantly and
nothing on the real system changes until you press ENTER.

## Categories and slots

Slots are grouped into three categories, picked from the glyph pills across
the top of the left column. The active pill spells out its name.

| Category | Slot | Inventory source | Applied with |
|----------|------|------------------|--------------|
| **Outfit** | Theme | `~/.config/omarchy/themes` + `/usr/share/omarchy/themes` | `omarchy-theme-set` |
| | Background | the staged theme's `backgrounds/` | `omarchy-theme-bg-set` |
| | Font | `omarchy font list` | `omarchy-font-set` |
| **Chassis** | Bar position | top / bottom / left / right | `omarchy-bar position` |
| | Bar surface | solid / transparent | `omarchy-bar transparent` |
| | Text size | 9–20 px | `omarchy-display-text-size` |
| **Cyberware** | Terminal | installed alacritty / foot / ghostty / kitty | `omarchy-default-terminal` |
| | Editor | installed editors `omarchy default editor` knows | `omarchy-default-editor` |
| | Browser | installed browsers `omarchy default browser` knows | `omarchy-default-browser` |
| | Agent | coding agents on `PATH` | `agent-set.sh` |

Outfit is what the desktop wears, Chassis is the frame it hangs on, and
Cyberware is the tooling wired into it. Chassis choices preview live: the
mini desktop moves its bar, drops the bar fill, and scales its type.

The agent slot writes `~/.config/omarchy/defaults/agent` directly rather than
calling `omarchy-default-agent`, because that command also launches the agent
in a terminal, which is not what "apply" should do from an equip screen.

Adding a slot means adding one entry to `slotDefs` in `Loadout.qml` (with its
category, glyph and apply-command prefix) and a matching branch in
`itemsFor()`. The staged item id is appended to the prefix as the final
argument.

## How it works

`scan.sh` emits the whole inventory as one JSON document (themes with their
parsed `colors.toml` palettes, preview images and wallpapers); `stats.sh`
emits one metrics snapshot, keeping the previous sample in a state file so
CPU, network and disk rates are deltas rather than requiring a blocking sleep.
The QML polls stats only while the screen is open, since the plugin shares the
long-running Omarchy shell process, and keeps two-minute rolling histories for
the charts.

The character sheet along the bottom runs left to right: host, uptime and
load; CPU / memory / temperature (and GPU when a card reports utilisation)
tiles; a two-minute CPU and memory history; per-core heat; network throughput
with upload above the axis and download below; root and swap capacity with
disk I/O. Its look follows [omarchy-system-monitor][sysmon] by Harshith
Chennupati, laid out horizontally, and `Sparkline.qml` is adapted from it
under MIT. Everything is drawn in the accent family so it survives any theme.

[sysmon]: https://github.com/Harshith292002/omarchy-system-monitor

The centre preview is a *mock* desktop, not a screen capture. A capture can
only show what is already applied, and this overlay covers the screen anyway —
mocking it is what makes previewing an unapplied theme possible.

## Notes

The screen's own chrome follows the live Omarchy theme through the shared
`Color` and `Style` singletons, the same way the stock menu and clipboard
overlays do: menu surface colours, the theme's font and type scale, its corner
radius and control-border tokens. Only the mini desktop repaints in the
*staged* theme, because that is the preview.

The backdrop is deliberately opaque. Besides suiting the genre, a partially
transparent child on this layer surface has its alpha dropped and paints
nothing, while an opaque one composites correctly. Panel colours are the
background with a little foreground mixed in (at the theme's own control fill
alphas), so contrast holds under light themes (Lupine, Catppuccin Latte) as
well as dark ones.

## Files

```
manifest.json    overlay plugin declaration
Loadout.qml      overlay entry: categories, slots, staging, apply queue, layout
MiniDesktop.qml  the miniature mock desktop
SlotPanel.qml    one equipment slot + its inventory row
StatsStrip.qml   the character sheet: metrics band along the bottom
Sparkline.qml    rolling time-series canvas (single or mirrored)
scan.sh          inventory as JSON
stats.sh         system metrics as JSON
agent-set.sh     records the default agent without launching it
```
