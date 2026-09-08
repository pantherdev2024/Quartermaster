# OmaKit

An RPG equip screen for Omarchy. Slot in themes, backgrounds, fonts and
defaults, watch a miniature desktop re-fit itself as you browse, fit what you
like, then deploy the whole fitting for real. Save a fitting as a loadout and
swap between them in one move.

![The OmaKit equip screen, with the Style category open](preview.png)

## Install

```sh
omarchy plugin add https://github.com/pantherdev2024/OmaKit.git --enable
```

Adding shows you the code before anything runs, and a plugin lands disabled
unless you pass `--enable`. Once it is on, the screen answers to the shell:

```sh
omarchy-shell shell toggle io.github.pantherdev2024.loadout
```

That command is the whole interface. It is also the only way in a plugin can
offer on its own, because a manifest cannot claim a key or a menu row, so the
two comfortable ways in are yours to add. Both are one line.

A keybinding, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + L", "OmaKit", "omarchy-shell shell toggle io.github.pantherdev2024.loadout")
```

A row under **Style** in the Omarchy menu, in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"style.loadout": {"icon":"󰆓","label":"OmaKit","aliases":["omakit","loadout","equip"],"description":"Equip themes, backgrounds and fonts with a live preview","action":"omarchy-shell shell toggle io.github.pantherdev2024.loadout"},
```

## What it needs and what it touches

Nothing beyond Omarchy itself. `jq`, Hyprland, Quickshell and the JetBrains
Mono Nerd Font the glyphs are drawn from are already hard dependencies of the
`omarchy` package; everything else the scripts reach for is coreutils. There is
no service to start, no installer, no remote build, and no network access at
any point.

What it does have is your desktop, so it is worth being plain about which half
of the screen does what. Browsing and fitting are inert — they repaint the mock
desktop and touch nothing else. Only `D` runs anything, and what it runs are
the ordinary Omarchy commands, the same ones the Omarchy menu runs:
`omarchy-theme-set`, `omarchy-theme-bg-set`, `omarchy-font-set`,
`omarchy-display-text-size`, `omarchy-bar position` and `transparent`,
`omarchy plugin enable` / `disable`, `omarchy bar move`, and
`omarchy-default-terminal` / `-editor` / `-browser`. Each is handed its
arguments as a list rather than a shell string, and every value in that list is
an id the inventory itself produced.

Opening the screen only reads: those same commands with no argument, plus
`omarchy-plugin-catalog`, `~/.config/omarchy/shell.json`, the two theme
directories, and the current-theme and current-background links. Where Omarchy
ships an `omarchy-installed-service-*` check, that runs too, under a two second
timeout — which is what keeps a widget with nothing behind it out of the
catalogue.

OmaKit writes in three places of its own: saved loadouts under
`~/.local/share/omarchy/loadouts/`, a log and the last deploy's result under
`~/.local/state/omarchy/loadout/`, and the default agent in
`~/.config/omarchy/defaults/agent`, written directly for the reason given
under Categories and slots.

None of this asks for root: there is no `sudo` or `pkexec` anywhere in the
plugin, and Omarchy's installer never runs plugin code. What is true of every
Omarchy plugin is true of this one, though — it shares the long-running
`omarchy-shell` process and runs unsandboxed with your user's permissions, so
read the code before you enable it.

## Remove

```sh
omarchy plugin remove io.github.pantherdev2024.loadout
```

That takes the plugin out of `~/.config/omarchy/plugins` and out of
`shell.json`, and it undoes none of what you deployed. Every change OmaKit
makes it makes by running the ordinary Omarchy command, so a theme, font or
default it applied stays applied exactly as if you had run that command
yourself.

Two directories are yours rather than the plugin's, so they are left where
they are and a reinstall finds your loadouts again:

- `~/.local/share/omarchy/loadouts/` — one JSON file per saved loadout
- `~/.local/state/omarchy/loadout/` — the deploy log and the last result

Delete those by hand if you want them gone, and take the binding and the menu
row back out of your own config.

## Usage

- Summon it with the command above, or with whichever of the binding and the
  menu row you set up
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

Three steps, on purpose. **Browsing previews**: the mini desktop repaints as
you arrow along a row and nothing else moves; leave the slot without fitting
and the preview snaps back. **ENTER fits**: the item locks into the slot and
the fitting is what you are building, still touching nothing. **D deploys**:
the fitting's commands run and the screen closes. Nothing on the real system
changes before D.

Theme and background are the exception: they repaint on the fit rather than on
the browse. Arrowing along those two rows moves the cursor and names the item,
and the mock desktop follows once you press `ENTER`, where every other row
follows the cursor itself. Fitting is still free — it touches nothing real and
`ESC` discards it — so trying a theme on and backing out costs a keypress
rather than a change.

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
| | Bar mods | every usable `bar-widget` plugin in the catalogue | `omarchy plugin enable` / `disable`, `omarchy bar move` |
| **Cyberware** | Terminal | installed alacritty / foot / ghostty / kitty | `omarchy-default-terminal` |
| | Editor | installed editors `omarchy default editor` knows | `omarchy-default-editor` |
| | Browser | installed browsers `omarchy default browser` knows | `omarchy-default-browser` |
| | Agent | coding agents on `PATH` | `agent-set.sh` |

Style is what the desktop wears — its palette, its wallpaper and its type,
face and size together — Shell is the frame it hangs on, and Cyberware is the
tooling wired into it. Style and Shell both show on the mini desktop: it
repaints, scales its type, moves its bar, drops the bar fill, and mirrors the
bar's widget layout — the type, the bar and its layout as you browse, the
palette and the wallpaper once you fit them.

### Deploying

`D` hands the fitting to `deploy.sh`, which runs one Omarchy command per
fitted slot, in a fixed order: theme first (the background depends on it),
then the bar and text size, then the default apps, and the font last. The
font goes last because `omarchy-font-set` restarts the shell, and OmaKit
lives inside the shell: anything still queued there would die with it. For
the same reason the runner is detached from the shell (`setsid -f`), and
the screen closes before the commands run. The runner reports back with a
desktop notification ("OmaKit deployed · 3 changes", or which command
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
that is. On a vertical bar those sections land at the top, the middle and the
bottom of the screen, so each bin carries that name too — `LEFT / TOP`,
`CENTER / MIDDLE`, `RIGHT / BOTTOM` — and you can read the bin either way
without having to hold the mapping in your head.

Drag a tile into a bin, between two tiles, or back to the inventory, or take
it off the bar with the small cross that comes up in its corner — the same
cross a saved-loadout card carries, shown while the pointer or the keyboard
cursor is on the tile. A tile in the inventory is already off, so it gets
none. With the keyboard, `← →` walk the whole bar — off the end of LEFT into CENTER, off the
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

A widget can front a service that is not on the machine, and enabling it would
succeed and leave a tile with nothing to say. A bar widget is a plugin and its
dependencies are generally opaque, but where Omarchy ships an
`omarchy-installed-service-<name>` check the answer is knowable, so a widget
that fails its own check is left out of the catalogue — Dropbox and Tailscale
today. The exception is a widget the bar is already carrying: leaving that out
would stop the fitting describing, or undoing, what is really there, so it
stays listed however its check answers.

Two things it does not do. A widget's layout entry can carry settings (the
clock's format strings, say); disabling drops the entry, settings and all,
and re-enabling gets defaults. OmaKit warns on such a widget's item data
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
it with the keyboard, previews it on the character — its font, type size and
bar at once, with its theme and wallpaper following on the fit the way those
two slots do on their own; `ENTER` fits every slot it recorded that differs
from what is live; `D` deploys. The card whose
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
Loadout.qml        overlay entry: categories, slots, staging, loadouts, apply queue
BarLayout.js       the bar layout: its string form, the workbench's edits, the commands
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
preview.png        the marketplace card: the screen on a 1920x1080 monitor
LICENSE            MIT
tests/run.sh       every test below, in order
tests/*-test.sh    manifest, qmllint, the bar layout model, and the four scripts
```

`tests/run.sh` needs nothing installed and changes nothing: every test that
runs a script builds a home and an Omarchy of its own under `mktemp -d`, and
the two scripts that run commands are pointed at stubs that record what they
were called with. The bar layout model needs none of that, being plain
JavaScript that touches nothing, and its suite is skipped where node is
missing. The deploy test refuses outright to run a plan naming an absolute
path outside its stub directory, because a plan is executed as written and one
naming a real command would deploy it against the machine running the test.
