# Loadout

An RPG equip screen for Omarchy. Slot in themes, backgrounds, fonts and
defaults, watch a miniature desktop re-fit itself as you browse, then equip
for real. Save a fitting as a loadout and swap between them in one move.

## Usage

- `SUPER + SHIFT + L`, or the Omarchy menu → **Style → Loadout**
- `TAB` / `SHIFT+TAB` (or `1` `2` `3`) switch equipment category
- `↑ ↓` move between slots (the saved-loadouts dock is always the last stop),
  `← →` browse that slot's inventory
- `ENTER` equips everything staged, `ESC` discards and closes
- `S` saves the current fitting as a loadout, `X` deletes the selected one

The screen opens on Hyprland's focused monitor. A summon payload can name an
output instead, which is handy for scripting and screenshots:

```
omarchy-shell shell toggle io.github.pantherdev2024.loadout '{"screen":"eDP-1"}'
```

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
argument. New slots appear in the character view's callouts automatically.

## Loadouts

The dock at the foot of the slot list holds saved loadouts. A loadout records
the fitting as it stands, staged choices included, as a map of slot id to item
id in `~/.local/share/omarchy/loadouts/<id>.json`. Moving onto a saved card
stages every slot it recorded that differs from what is live, so equipping one
is: pick it, press `ENTER`. The nameplate under the character names the loadout
it currently represents; a hand-picked change clears that until you save again.

## How it works

`scan.sh` emits the whole inventory as one JSON document: themes with their
parsed `colors.toml` palettes, preview images and wallpapers, the installed
tools each default slot can take, the chassis options, and the saved loadouts
from `loadouts.sh list`.

The centre of the character view is a *mock* desktop, not a screen capture. A
capture can only show what is already applied, and this overlay covers the
screen anyway. Mocking it is what makes previewing an unapplied fitting
possible: it moves its bar, drops the bar fill, scales its type and repaints
in the staged palette. Around it, one callout per slot names what is worn or
staged, tethered by a leader line that turns accent under the cursor and the
warning colour when staged.

Every frame is a `TechFrame`: a chamfered outline with an optional heavy edge
and corner brackets, drawn on a Canvas so it recolours with the theme.

On a narrow output (under about 1500 px at the theme's spacing scale, so a
1280-wide laptop panel) the screen drops to a compact tier: the callouts form
a three-column grid under the viewport, one category per row, each tethered to
the card above it, and the tag word becomes a small state square. On the left,
the item data panel is the first thing to go when the column is short: every
slot shows before any description does, and the slot list scrolls to keep the
focused slot in view if a category still overflows.

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
manifest.json      overlay plugin declaration
Loadout.qml        overlay entry: categories, slots, staging, loadouts, apply queue, layout
CharacterView.qml  the character: viewport, callouts, leader lines, nameplate
MiniDesktop.qml    the miniature mock desktop
SlotPanel.qml      one equipment slot + its inventory row (also the loadouts dock)
ItemData.qml       description panel for whatever the cursor is on
TechFrame.qml      chamfered frame with heavy edge and corner brackets
scan.sh            inventory as JSON
loadouts.sh        list / save / delete saved loadouts
agent-set.sh       records the default agent without launching it
```
