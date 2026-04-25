# Nuzi Raid

Custom raid frames for AAClassic. STILL BETA but ready for a full release.

## What It Does

- Replaces the visual raid frame with custom Nuzi raid bars.
- Shows raid member HP, optional MP, names, status text, role badges, raid leader badge, class text, target highlight, and debuff alert badges.
- Supports party columns, single list, compact grid, and party-only layouts.
- Lets you customize role HP colors, MP colors, HP/MP missing backfill colors, bloodlust team color, text colors, background, target highlight, and debuff alert colors.
- Supports raid, player, and NPC-style bar textures.
- Keeps settings, backups, launcher position, and frame position in `nuzi-raid/.data` so updates do not wipe them.
- Opens from the movable launcher icon or chat commands, with adjustable launcher icon size.

## Install

1. Install via Addon Manager.
2. Make sure `nuzi-raid` is enabled in game.
3. Click the Nuzi Raid launcher icon or use `!nr` or `!nuziraid`.

## Quick Start

1. Open settings from the launcher icon.
2. Enable the raid frames if needed.
3. Pick a layout and adjust bar size, text placement, colors, and textures.
4. Click `Apply` to update the frames.
5. Click `Backup` once your layout looks good.

Shift+drag the launcher icon or settings window to move them.

## Settings

The settings window is split into:

- `General`: enable frames, layout mode, launcher icon size, frame position, spacing, and save tools.
- `Bars`: HP/MP size, textures, role colors, missing backfill colors, bloodlust color, and dead/offline bar colors.
- `Text`: name, HP text, status text, class text, role badge, raid leader badge, placement, and text colors.
- `Misc`: background, target highlight, debuff alerts, and range fade.

## Stock Raid Frames

To hide the stock raid display, open the raid manager and uncheck `View Raid Info` under `Status Display`.

## Known Limitations

- Out-of-range raid HP depends on what the addon API and stock raid frame expose. Nuzi Raid tries API data first and uses stock frame data as a fallback, but the client may still hide some values from addons.
- Right-click menus use the client stock popup menu. Nuzi Raid anchors and raises the popup so it appears at the cursor and above the custom bars.
- Role colors are based on Nuzi Raid's role/class rules. Role data should be treated as stable while you are in raid.
- If another addon forces a higher UI layer over menus, it can still interfere with right-click popup visibility.
- After major UI scale changes, use the settings window to re-align frames and save again.

## Commands

- `!nr`
- `!nuziraid`

## Version

2.0.3
