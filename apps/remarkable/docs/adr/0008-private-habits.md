# 8. Private habits: a synced flag replaces suspend visibility

Status: accepted

Amends [ADR 0001](0001-opt-in-suspend-image-writing.md) — the per-habit toggle it described as
gated on suspend-image writing is no longer gated. Supersedes the device-local-field consequences
of [ADR 0005](0005-backend-shaped-entry-rows.md) and
[ADR 0007](0007-edited-at-timestamp-name.md), which called `hideFromSleep` the one habit field the
wire has no room for — it now has room for it.

## Context

`hideFromSleep` (ADR 0001's "Suspend visibility") was a per-habit, device-local toggle: hidden from
the suspend image, still shown everywhere else in the app, and never sent over the wire — `Sync.js`
dropped it, and `HabitsStore.applySynced` re-attached it from a local by-id map after every sync.
ADR 0005 and ADR 0007 both noted it as the one habit field the wire had no room for.

That was adequate while "hide from the lock screen" was the whole need. It stops being adequate
once the same intent — a habit whose existence someone would rather glance-proof — should apply
everywhere the habit is glanceable (the main grid, edit mode, not just the suspend image) and
should travel with the habit across devices, the way a rename or a reorder does.

## Decision

Replace `hideFromSleep` with a synced, backend-owned flag, `isPrivate` (`HabitDto.IsPrivate`,
merged like any other habit field under the existing whole-row `editedAt` LWW — see the backend
glossary's Private entry).

- **Never on suspend, unconditionally.** A private habit is dropped from the suspend image
  regardless of any reveal setting — `SuspendDraw.js`'s filter and the suspend-writer's roster/month
  join both apply this.
- **Hidden from the grid too, but revealable per device.** A private habit is also dropped from the
  main grid — including edit mode — unless the device-local, never-synced setting
  `showPrivateHabits` ("Show private habits" on the Settings page) is on for that device. Privacy
  itself is shared user intent and syncs; whether *this* device currently shows its private habits
  anyway is presentation, so the reveal setting stays local and unsynced — the same split the
  backend glossary draws between Position (shared) and grid orientation (per-client).
- **The per-habit toggle is always visible in edit mode.** ADR 0001 hid the (then) suspend-visibility
  control while suspend-image writing was off, because it meant nothing otherwise. Private habits
  mean something with or without suspend writing, so the toggle (glyph now "P", was "Z") is no
  longer gated on that setting.
- **Toggling stamps `editedAt`.** `togglePrivate` sets `editedAt: Date.now()` on the row, mirroring
  `togglePolarity`. Without the stamp, sync's whole-row `editedAt` LWW would let the server's older
  copy of the row overwrite the flip on the next merge — the toggle would silently not stick.
- **Filtering is delegate-level `visible:`, not a proxy model.** Both `HabitsColumn` and
  `HabitsGrid` keep iterating the full, unfiltered `ListModel`; each delegate sets
  `visible: showPrivateHabits || !model.isPrivate`. QML's `Column` positioners skip invisible
  children entirely (no height, no doubled spacing), so both columns collapse in lockstep, and
  every index-based callback (reorder, entry toggle, delete confirmation, …) keeps using the real
  store index.
- **The roster guard now checks `isPrivate`.** `_isRosterRow` requires
  `typeof habit.isPrivate === "boolean"`; a roster still spelling `hideFromSleep` is refused, not
  silently folded with every flag false (ADR 0006). The same guard runs on wire rows inside
  `applySynced`, so a response from a pre-`isPrivate` backend is refused too, rather than resetting
  every habit to public.
- **Migration is external, one-shot.** `scripts/migrate-is-private.mjs`, per ADR 0006, renames
  `hideFromSleep` → `isPrivate` in a `make backup` copy; the user runs it, checks the report, and
  pushes the result back.
- **The suspend-writer rebuild is part of migration, not optional.** An old binary reading migrated
  data would see `hideFromSleep` absent — falsy — and draw private habits on the lock screen, so
  `refusesShape` gained an `isPrivate`-presence check: pre-migration data now exits 2 instead of
  rendering.

## Considered options

- **A filtered proxy model over the `ListModel`** — rejected: it desyncs view indices from store
  indices, the same failure mode ADR 0005 rejected when it kept tombstoned habits out of the model
  rather than filtering them in the views. Delegate-level `visible:` gets the identical layout for
  free because QML's positioners already collapse invisible children.
- **Sync the reveal setting too** — rejected: privacy is shared intent about the habit, but whether
  *this* device currently shows its private habits is per-surface presentation, not a fact about the
  habit. Syncing it would mean revealing on one device silently reveals on every device.
- **Let the reveal setting also un-hide the suspend image** — rejected: the suspend image is a
  passive, ambient surface anyone near a sleeping device can see; the grid is only visible to
  whoever is actively holding the tablet. Private stays off the lock screen even when its owner has
  revealed private habits to themselves on the grid.
- **Keep `hideFromSleep` alongside the new flag** — rejected: two overlapping per-habit visibility
  flags recreate the exact confusion "private" is meant to resolve. One flag, migrated once.

## Consequences

- The wire/DTO change reaches all three apps: the backend gains `IsPrivate` on `Habit` and
  `HabitDto` plus an EF migration; mobile regenerates its client and persists the field verbatim
  with no UI yet; this client's roster row, `Sync.js`, `SuspendDraw.js`, and the suspend-writer's
  roster/month join all gain it.
- **Reordering past a hidden neighbor looks like a one-press no-op.** In edit mode with
  `showPrivateHabits` off, dragging a row past an invisible private neighbor is a real reorder — the
  private row's position changes even though nothing visibly moved on screen. This is a deliberately
  unmitigated quirk; the workaround is revealing private habits before reordering.
- **All-private renders like an empty grid.** If `showPrivateHabits` is off and every habit is
  private, the grid shows nothing — already a tolerated state (an empty month renders the same way
  under ADR 0004), not a new failure mode here.
- **A narrow skew window on mixed-version clients.** An old, pre-ADR-0008 client editing a habit
  sends a request with no `isPrivate`, which the backend's positional bind defaults to `false`, so a
  synced habit's privacy resets to public. Accepted for a single-user deployment doing a coordinated
  upgrade; not something a multi-user deployment could accept as-is.
- **The suspend-writer rebuild and redeploy is now a mandatory migration step**, not a follow-up —
  see the README's "Upgrading across a storage-format change".
