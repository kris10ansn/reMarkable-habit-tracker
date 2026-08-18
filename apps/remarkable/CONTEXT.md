# reMarkable Client — Device Context

Terms unique to the reMarkable 1 client — a pure-QML scene loaded inside xochitl via
XOVI + rm-appload. The shared habit vocabulary (Habit, Polarity, Entry, X/O marks, Unmarked,
Default habits) lives in the [root glossary](../../CONTEXT.md). This file covers only what's specific to running on
the device: the suspend image, settings, and edit mode.

Presentation note: this client lays habits as **rows** and days-of-the-**viewed month** as
**columns** (landscape). Only when the viewed month is the current month is today's column
highlighted; other months show no highlight. A negative habit's name carries a `(−)` suffix and
its future days render muted.

## Language

**Suspend image**:
The full-screen image xochitl shows while the device sleeps. The app overwrites it with the
current habit grid so the habits are the first thing the user sees on waking the device.
_Avoid_: sleep screen, sleep image, lock screen, wallpaper, suspended.png.

**Private**:
Per-habit toggle (`isPrivate` in code; the edit-mode `P` control) marking a habit hidden from
glanceable surfaces. A private habit never appears in the suspend image, and is also hidden from
the main grid — including edit mode — unless the device's **Show private habits** setting is on.
The flag itself syncs like name or polarity; see the [backend glossary](../backend/CONTEXT.md)'s
Private entry for the shared-intent-vs-presentation split.
_Avoid_: hideFromSleep (the field's device-local predecessor), suspend visibility, hidden, sleep-
screen visibility.

**Show private habits**:
The device-local, never-synced Settings toggle that reveals private habits on this device's grid
and edit mode. It does not affect the suspend image — private habits stay off the suspend image
regardless of this setting.
_Avoid_: reveal setting, unhide toggle.

**Suspend-image writing**:
The app-wide setting for whether the app overwrites the suspend image at all. Opt-in: off by
default, toggled on the Settings page. Enabling takes a suspend-image backup then starts
drawing the grid; disabling restores the backup. Private habits are excluded from the grid it
draws regardless of this setting.
_Avoid_: sleep-screen toggle, suspend mode.

**Suspend-image backup**:
The copy of the original suspend image (`suspended.png.bak`) taken when the user enables
suspend-image writing, and copied back when they disable it. The user's recovery path to the
stock image.
_Avoid_: marker, restore point.

**Settings**:
The app-wide preferences page, reached from the Settings button and left via Back/Done. Holds
the suspend-image writing toggle and the Show private habits toggle. Changes are staged and
applied on Done.
_Avoid_: options, preferences pane, config screen.

**Edit mode**:
The state, toggled by Edit/Done, in which rows become editable — reorder, rename, delete,
toggle polarity, toggle private — and an empty add-row appears at the bottom.

**Current month**:
The real calendar month (`new Date()`). It alone highlights today, drives the suspend image, and
is where the grid opens. Distinct from the viewed month.
_Avoid_: this month, present month.

**Viewed month**:
The month whose entries the grid currently shows — the current month by default, moved by the
header `‹` / `›` arrows. Its entries are loaded into the one in-memory model and its file is the
sync unit; editing works on any viewed month. The **Today** button (shown only off-current)
returns to the current month.
_Avoid_: selected month, shown month, browsed month (in code/UI copy).

**Month navigation**:
Stepping the viewed month backward/forward with the header arrows. Unbounded in both directions;
a month with no data shows an empty grid and writes no file until a box is toggled.
_Avoid_: month switcher, month picker, paging.

### Storage

**Data directory**:
The `data/` subdirectory of the app dir holding all habit persistence (the roster file and the
month files). The deploy creates it; the app cannot, so a missing data directory surfaces as a
visible save failure, never silent loss.
_Avoid_: data folder, storage dir.

**Roster**:
The ordered list of habits with their config — id, name, polarity, private flag, create-time,
edit-time — and nothing about their entries. Array order is display order.
_Avoid_: habit list, config.

**Roster file**:
`data/roster.json`, the `{ "habits": [...] }` envelope that persists the roster. Holds the alive
habits followed by their tombstones, the same split the sync request uses.
_Avoid_: habits.json (the legacy single-file name).

**Habit tombstone**:
A soft-deleted habit: the row it had, with `deletedAt` stamped. Deleting removes the habit from the
in-memory model — so the grid and every index-based store call forget it — and keeps this row in the
roster file until a sync confirms the server owns the delete. Without it another client's stale copy
would resurrect the habit on the next merge.
_Avoid_: deleted habit, trash, archive.

**Entry row**:
One marked day as stored and sent: `{ habitId, date, outcome, editedAt, deletedAt }`, the backend's
`EntryDto` shape. `deletedAt` is null while alive and holds the clear's edit-time on a tombstone —
a cleared day keeps a row rather than dropping the key, so the next sync can push the clear. See
[ADR 0005](docs/adr/0005-backend-shaped-entry-rows.md).
_Avoid_: cell, entry object, state object.

**Month file**:
`data/YYYY-MM.json`, `{ "month": "2026-07", "entries": [ …entry rows ] }` — one calendar month's
entry rows, which is exactly the wire format's month payload. Exactly one month's file — the viewed
month — is loaded at a time; navigating re-points to another.
_Avoid_: entries file, day file.

**Migration script**:
A one-shot Node script in `scripts/` that converts a backup of the data directory from an older
storage format to the current one, run on the user's computer with the app closed. The app itself
carries no migration code and cannot read an older format — it refuses the file instead. Deleted
once the device has been migrated. See [ADR 0006](docs/adr/0006-external-one-shot-migrations.md).
_Avoid_: migration, upgrade path, converter (in-app anything).

**Unreadable file**:
A data file that is not the shape this version writes — an un-migrated file, or a corrupt one. It is
never folded in as empty: writes to it are blocked, sync is held off, and the grid reports which file
and why. The distinction that matters is against a **missing** file, which is normal (first run, or a
month never marked) and simply loads as empty.
_Avoid_: bad file, invalid data, broken save.

### Sync

**Server URL**:
The user-entered address of the backend this client syncs with, set on the Settings page and stored
in `settings.json`. Empty means **standalone** — the app runs fully local and makes no sync attempts.
The shared Sync / Tombstone / Edit-time vocabulary lives in the
[backend glossary](../../apps/backend/CONTEXT.md).
_Avoid_: host, endpoint, API URL, server address.

**Sync status**:
The ambient status line shown beneath the suspend status, reporting last-sync / offline state. Quiet
by design: normal offline is silent here, and only genuine misconfiguration (malformed Server URL,
server rejection) is raised loudly as a modal.
_Avoid_: connection indicator, sync banner, online status.
