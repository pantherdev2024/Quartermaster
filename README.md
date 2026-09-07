# Loadout

An RPG equip screen for Omarchy. Slot in themes, backgrounds, fonts and
defaults, watch a miniature desktop re-fit itself as you browse, fit what you
like, then deploy the whole fitting for real. Save a fitting as a loadout and
swap between them in one move.

## Usage

- `SUPER + SHIFT + L`, or the Omarchy menu → **Style → Loadout**
- `TAB` / `SHIFT+TAB` (or `1` `2` `3`) switch equipment category
- `↑ ↓` move between slots (the saved-loadouts row across the top is always
  the last stop), `← →` browse that slot's inventory
- BAR MODS has no inventory to browse: `← →` do nothing there and `ENTER`
  opens its workbench, which takes over the screen
- `ENTER` fits the item under the cursor into its slot (or fits a whole
  saved loadout)
- `D` deploys the fitting for real and closes the screen; clicking the pill
  in the top corner does the same
- `ESC` closes; if anything is fitted but not deployed it asks first
- `S` saves the fitting on screen as a loadout, `X` (or the cross on a card)
  deletes the selected one, after asking

The screen opens on Hyprland's focused monitor. A summon payload can name an
output instead, which is handy for scripting and screenshots:

```
omarchy-shell shell toggle io.github.pantherdev2024.loadout '{"screen":"eDP-1"}'
```

Three steps, on purpose. **Browsing previews**: the mini desktop repaints and
nothing else moves; leave the slot without fitting and the preview snaps back.
**ENTER fits**: the item locks into the slot and the fitting is what you are
building, still touching nothing. **D deploys**: the fitting's commands run
and the screen closes. Nothing on the real system changes before D.

## Categories and slots

Slots are grouped into three categories, picked from the glyph pills across
the top of the left column. The active pill spells out its name.

| Category | Slot | Inventory source | Applied with |
|----------|------|------------------|--------------|
| **Style** | Theme | `~/.config/omarchy/themes` + `/usr/share/omarchy/themes` | `omarchy-theme-set` |
| | Background | the fitted theme's `backgrounds/` | `omarchy-theme-bg-set` |
| | Font | `omarchy font list` | `omarchy-font-set` |
| | Text size | 9–20 px | `omarchy-display-text-size` |
| **Shell** | Bar position | top / bottom / left / right | `omarchy-bar position` |
| | Bar surface | solid / transparent | `omarchy-bar transparent` |
| | Bar mods | every `bar-widget` plugin in the catalogue | `omarchy plugin enable` / `disable`, `omarchy bar move` |
| **Cyberware** | Terminal | installed alacritty / foot / ghostty / kitty | `omarchy-default-terminal` |
| | Editor | installed editors `omarchy default editor` knows | `omarchy-default-editor` |
| | Browser | installed browsers `omarchy default browser` knows | `omarchy-default-browser` |
| | Agent | coding agents on `PATH` | `agent-set.sh` |

Style is what the desktop wears — its palette, its wallpaper and its type,
face and size together — Shell is the frame it hangs on, and Cyberware is the
tooling wired into it. Style and Shell both preview live: the mini desktop
repaints, scales its type, moves its bar, drops the bar fill, and mirrors the
bar's widget layout.

### Deploying

`D` hands the fitting to `deploy.sh`, which runs one Omarchy command per
fitted slot, in a fixed order: theme first (the background depends on it),
then the bar and text size, then the default apps, and the font last. The
font goes last because `omarchy-font-set` restarts the shell, and Loadout
lives inside the shell: anything still queued there would die with it. For
the same reason the runner is detached from the shell (`setsid -f`), and
the screen closes before the commands run. The runner reports back with a
desktop notification ("Loadout deployed · 3 changes", or which command
failed), a log in `~/.local/state/omarchy/loadout/deploy.log`, and a result
file the next open folds into the status pill.

### Bar mods

Bar mods is the one multi-select slot. What it holds is not an item off a row
but a whole arrangement, so it has no inventory to browse: in its place sits a
button that opens the workbench, with what the bar currently carries beside it.
Its value is the whole layout as one string (`left:a,b|center:c|right:d`), so
previewing, fitting, saving and "is it live" work exactly as for every other
slot, and a saved loadout records the entire bar arrangement. On the button,
the item data panel describes the slot rather than a widget: how the fitting
is spread across the bar and the bench.

`ENTER` on the slot, or a click on the button, opens the **workbench**, which
takes the whole screen: bar mods edits the whole bar, so the slot column, the
character and the saved-loadouts row stand down while it is open. It is laid
out in the shape of the thing it edits. Across the top is the **rail** — the
fitting drawn as a bar, in the previewed theme, tagged with the edge the bar
is really on and whether it is solid; a clear bar lets the previewed wallpaper
through exactly as it would on the desktop. Under it sit the three section
bins, LEFT, CENTER and RIGHT, as equal thirds of the rail, each tethered to
the stretch of rail it governs; under those, one **inventory** pane the rail's
full width holding everything that is off; and at the foot, the item data
panel for the tile under the cursor. Tiles shrink from 64px to a floor of 38
until all of it fits the screen, so the workbench never scrolls.

A vertical bar still draws as a horizontal rail. LEFT, CENTER and RIGHT are
the bar's own section names rather than directions on the screen, so they keep
those names whichever edge the bar is on, and the rail's tag says which edge
that is.

Drag a tile into a bin, between two tiles, or back to the inventory. With the
keyboard, `← →` walk the whole bar — off the end of LEFT into CENTER, off the
end of RIGHT back to the start — and walk the inventory when the cursor is
there; `↑ ↓` cross between the bar and the inventory, landing on whatever tile
stands nearest in the cursor's column; `1` `2` `3` send the tile under the
cursor to a section, `BACKSPACE` benches it, `SHIFT+← →` nudge it along,
`SPACE` toggles. All of that edits the preview, and the rail follows: the
widget under the cursor lights on the rail as well as in its bin, so a tile
and its real place on the bar read as the same thing. Hovering a token on the
rail moves the cursor to it. `ENTER` fits the arrangement and closes the
workbench, `ESC` drops the preview, `D` fits and deploys. The bins are data,
so another slot could open a workbench of its own.

Deploying diffs the live layout against the fitted one and runs, in order:
`omarchy plugin disable` for every widget leaving, `omarchy plugin enable
--section --index` for every widget joining at its final spot, then
`omarchy bar move --section --index` for anything else out of place, walked
left to right so each index is final when issued. All three are live calls
into the running shell: the bar re-renders in place and nothing restarts.

Two things it does not do. A widget's layout entry can carry settings (the
clock's format strings, say); disabling drops the entry, settings and all,
and re-enabling gets defaults. Loadout warns on such a widget's item data
but does not preserve the settings. And the spacer, which a bar may carry
several of, is left out of the tiles: it stays wherever it is.

The agent slot writes `~/.config/omarchy/defaults/agent` directly rather than
calling `omarchy-default-agent`, because that command also launches the agent
in a terminal, which is not what "apply" should do from an equip screen.

Adding a slot means adding one entry to `slotDefs` in `Loadout.qml` (with its
category, glyph and apply-command prefix) and a matching branch in
`itemsFor()`. The fitted item id is appended to the prefix as the final
argument. New slots appear in the character view's callouts automatically.

## Loadouts

The row across the top centre holds saved loadouts, one small card each with
the loadout's theme as its thumbnail and the name you gave it. A loadout
records the fitting as shown on screen as a map of slot id to item id in
`~/.local/share/omarchy/loadouts/<id>.json`. Hovering a card, or moving onto
it with the keyboard, previews it on the character; `ENTER` fits every slot
it recorded that differs from what is live; `D` deploys. The card whose
fitting the desktop is actually wearing is ringed. The nameplate under the
character names the loadout it currently represents; a hand-picked change
clears that until you save again.

## How it works

`scan.sh` emits the whole inventory as one JSON document: themes with their
parsed `colors.toml` palettes, preview images and wallpapers, the installed
tools each default slot can take, the shell options, and the saved loadouts
from `loadouts.sh list`.

The centre of the character view is a *mock* desktop, not a screen capture. A
capture can only show what is already applied, and this overlay covers the
screen anyway. Mocking it is what makes previewing an unapplied fitting
possible: it moves its bar, drops the bar fill, scales its type and repaints
in the previewed palette. Around it, one callout per slot names what is worn,
previewed or fitted, tethered by a leader line that turns accent under the cursor and the
warning colour when fitted.

Every frame is a `TechFrame`: a chamfered outline with an optional heavy edge
and corner brackets, drawn on a Canvas so it recolours with the theme.

The callouts flank the viewport on every screen that can hold them. Whether a
screen can is worked out rather than assumed: flanking costs the viewport's
share of the width plus, on each side, a gutter and a card at its floor, so a
1280-wide laptop panel flanks and a roomier spacing scale falls back on its own
to a stack, a three-column grid under the viewport with each card tethered to
the one above it. A card narrower than about 170 px drops the tag word for a
small state square.

The layout is built to take more slots than it has. Style keeps the left,
Cyberware the right and Shell the foot, because that grouping is the point, but
a side column only holds what fits beside the viewport; past that a slot is
cheaper at the foot, where one row holds several, so the excess spills there.
The foot row may run out to the pane's full width and wrap, and when it runs
wider than the viewport's channel it starts below the side columns rather than
beside them. The whole arrangement is centred on the union of the stack and the
columns, so a tall column pushes it down instead of off the top.

On the left, the item data panel is the first thing to go when the column is
short: every slot shows before any description does. The inventory cells then
shrink until the tallest category fits its column together with the dock, so no
screen has to scroll a slot list; scrolling remains only as a last resort.

## Notes

The screen's own chrome follows the live Omarchy theme through the shared
`Color` and `Style` singletons, the same way the stock menu and clipboard
overlays do: menu surface colours, the theme's font and type scale, its corner
radius and control-border tokens. Only the mini desktop repaints in the
*previewed* theme, because that is the preview.

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
LoadoutDock.qml    the row of saved-loadout cards across the top
BarWorkbench.qml   the workbench: the bar as a rail, its sections as bins, an inventory
BarRail.qml        a bar's widget tokens, drawn for the mock desktop and the rail
MiniDesktop.qml    the miniature mock desktop
SlotPanel.qml      one equipment slot + its inventory row, or its workbench button
ItemData.qml       description panel for whatever the cursor is on
TechFrame.qml      chamfered frame with heavy edge and corner brackets
scan.sh            inventory as JSON (widgets and bar layout included)
loadouts.sh        list / save / delete saved loadouts
deploy.sh          runs a fitting's commands detached from the shell and reports back
agent-set.sh       records the default agent without launching it
```
