# Nuzi Raid

Raid frames, but with less stock nonsense and fewer "why is that important thing hidden?" moments.

`Nuzi Raid` gives you standalone custom raid frames with the controls you actually want nearby:

- custom raid frame rendering with separate vitals and metadata refresh
- event-driven refreshes for health, mana, and roster changes
- settings window with live apply
- backup, import, and reset controls
- quick open through the `NR` button or chat command

## Install

1. Drop the `nuzi-raid` folder into your AAClassic `Addon` directory.
2. Make sure the addon is enabled in game.
3. Click the `NR` button or use `!pr`, `!polarraid`, or `!nuziraid`.

Saved data lives in `nuzi-raid/.data` so your frame layout and backups survive updates.

## Quick Start

1. Open the settings with `NR`.
2. Enable the frames if needed.
3. Adjust the layout and style settings.
4. Use `Apply` when you want to push the current settings live.
5. Save a backup once the frames look the way you want.

If something goes sideways, `Import` pulls the latest backup back in without requiring a spiritual reset.

## How To

### Opening Settings

Use any of these:

- `NR`
- `!pr`
- `!polarraid`
- `!nuziraid`

### Settings And Backups

The settings window includes:

- `Apply`
- `Save`
- `Backup`
- `Import`
- `Reset Raid`
- `Reset Style`
- `Reset All`

That keeps experimentation much safer than raw file surgery.

### Frame Updates

The addon splits its work into separate update paths for:

- vitals
- metadata
- roster
- target updates

That keeps the frames responsive without hammering every bit of data at the same cadence.

## Notes

- Runtime capability checks are built in, so behavior can vary slightly with what the client exposes.
- Right-click on a custom raid frame now falls back to the stock target popup path on current clients.
- If the UI has just reloaded, one extra reload is sometimes the fastest route back to sanity.

2.0.0
