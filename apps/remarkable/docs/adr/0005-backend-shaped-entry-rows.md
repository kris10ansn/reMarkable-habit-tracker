# 5. Entries are backend-shaped rows; month partitioning stays

Status: accepted; its read-tolerance consequence superseded by
[ADR 0006](0006-external-one-shot-migrations.md), its timestamp naming by
[ADR 0007](0007-edited-at-timestamp-name.md), its device-local-field consequence by
[ADR 0008](0008-private-habits.md)

Amends [ADR 0002](0002-month-partitioned-habit-storage.md) — the _shape_ inside a month file, not
its partitioning.

The shapes below stand. What changed is how the app meets an old one: it refuses it and a one-shot
external script converts it, rather than tolerating it on read (ADR 0006).

## Context

The habit domain is now shared with a backend (`apps/backend/`), which owns the canonical records
and reconciles them. It keeps habits and entries in one normalized shape: a roster row per habit and
a `(HabitId, Date)`-keyed entry row, with an explicit `Polarity` enum and a nullable `DeletedAt`
tombstone stamp. This client had drifted from it in four ways:

- polarity was a `negative` boolean with Positive implied,
- there was no `createdAt`,
- habits were **hard**-deleted from the roster, with pending deletes tracked in a separate
  `sync.json` tombstone sidecar,
- entries were nested two levels deep inside the month file (`{ habitId: { dateKey: { state,
updatedAt } } }`), with `state: ""` as the cleared marker.

Every one of those needed translating at the sync edge, and the `state: ""` marker had no backend
counterpart at all.

The obvious fix — collapse everything into one flat `entries.json`, exactly mirroring the backend —
was measured against this device first. At the user's current usage (9 habits, ~155 marked cells per
month) a normalized row costs ~130 bytes, so one month is ~20 KB flat and the log reaches ~1.2 MB
after five years and grows without bound. On an rM1 (1 GHz Cortex-A9, 512 MB shared with xochitl)
that is paid in the worst two places:

- **Launch.** `Storage.readFile` is a _synchronous_ XHR plus `JSON.parse` on xochitl's UI thread —
  the read ADR 0004 defers behind a single `Loading…` frame. It would grow from 8.6 KB to the whole
  history.
- **Every tap.** A toggle would `JSON.stringify` and blocking-write all of history instead of one
  month — precisely the cost ADR 0002 was written to remove.

## Decision

Adopt the backend's **row shape**; keep ADR 0002's **month partitioning**.

- **Entry row** — `{ habitId, date, outcome, updatedAt, deletedAt }`, mirroring the backend's
  `SyncEntry`. `outcome` stays `"x"` / `"o"` (see below); `deletedAt` is null while alive and holds
  the clear's edit-time on a tombstone, replacing the `state: ""` marker.
  <br>_(The backend has since folded `SyncEntry` into one canonical `EntryDto` shared by Sync and
  REST, and `updatedAt` is spelled `editedAt` per ADR 0007. The row this ADR describes is otherwise
  unchanged — the mirroring is now exact.)_
- **Month file** — `data/YYYY-MM.json` becomes `{ "month": "2026-07", "entries": [ …rows ] }`, the
  wire format's `SyncMonth` down to the field names, with only `outcome` still spelled differently
  (see below). File, wire and in-memory value are now one shape. Still one file per month, still
  only the viewed month loaded.
- **Habit row** — gains `polarity` (`"Positive"` / `"Negative"`, the backend's enum spelling, in
  place of `negative`), `createdAt`, and `deletedAt`.
- **Habit deletes are soft.** `HabitsStore.remove` moves the habit out of the ListModel and into
  `habitTombstones`, persisted alongside the alive rows in `roster.json` — the same "alive rows +
  tombstones" split the sync request uses. The `sync.json` tombstone sidecar and the `habitRemoved`
  signal are gone; `sync.json` now holds only `lastSyncedAt`. A successful sync calls
  `purgeHabitTombstones()`.
- **Tombstoned habits stay out of the ListModel.** The model holds alive habits only, so every
  index-based store API (`setName`, `toggleEntry`, `pendingDeleteIndex`, …) stays in step with what
  the grid renders, and no view needs to filter.
- **In memory, each habit's rows are indexed by date on its ListModel row** (`entriesByDate`).
  That slice is the only per-habit reactive vehicle QML offers: replacing one habit's slice
  re-evaluates that row's ~31 cell bindings, where a single grid-wide index would re-evaluate all
  ~600 on every tap.

`updatedAt` remains the single client timestamp and the merge key the wire format exchanges. The
backend separately keeps a server-stamped audit `UpdatedAt`; splitting this client's field into
`editedAt` + audit is deferred until multi-client sync actually needs it.

> Superseded by [ADR 0007](0007-edited-at-timestamp-name.md): the field is spelled `editedAt` on
> disk and on the wire. It is still a single client timestamp — the split above stays deferred.

`outcome` keeps the `"x"` / `"o"` marks rather than the backend's `Success` / `Failure`. The X/O
reading is this client's domain vocabulary (root `CONTEXT.md`) and mapping it is one function in
`Sync.js`; aligning the enum is a coordinated wire-format change, not a storage one.

## Considered options

- **One flat `entries.json`** (full mirror of the backend) — rejected on the measurements above:
  unbounded launch parse and whole-history rewrite per tap, on the device least able to absorb
  either, for no rendering benefit since the grid only ever shows one month.
- **A flat `entries-index.json` beside the month files** — rejected: two persisted sources of truth
  for the same rows, needing reconciliation on every load and save.
- **A grid-wide in-memory entry index** instead of per-habit slices — rejected for the ~20×
  binding-invalidation increase per tap described above.
- **Keeping tombstoned habits in the ListModel and filtering in the views** — rejected: it
  desynchronizes view indices from store indices, and every index-based API and the delete
  confirmation would have to translate between them.
- **Purging habit tombstones while standalone** (no Server URL) — rejected: a delete made before
  sync is ever configured must still be pushable, or the habit is resurrected by the first sync.
  Tombstone count is bounded by deletes, so roster growth is negligible.

## Consequences

- The sync edge shrinks to the X/O ↔ Outcome mapping; polarity, position, tombstones and edit-times
  now pass through unchanged.
- Per-toggle and startup cost stay bounded to one month, and corruption is still isolated to one
  month. Both ADR 0002 guarantees survive intact.
- **A file in the old shape is refused, not read.** The danger this addresses is real — a legacy
  month read as empty would be overwritten by the next toggle, losing that month — but the answer is
  to block the write rather than convert on load. An external one-shot script does the conversion;
  see [ADR 0006](0006-external-one-shot-migrations.md), which supersedes the read-tolerance this ADR
  originally chose.
- `createdAt` is device-local for now: the sync wire format carries no `CreatedAt`, so `applySynced`
  preserves the local value the way it already preserves `hideFromSleep`. It exists so a future
  streak feature and the other clients share one clock reference.

    > No longer true. The wire now carries `createdAt`, stored verbatim from the creating client, so
    > `applySynced` takes it from the response instead of preserving a local value — and a habit
    > arriving from another device keeps its real create-time rather than being stamped at sync.
    > `hideFromSleep` is now the only device-local field the wire has no room for.

    > Also no longer true, per [ADR 0008](0008-private-habits.md): `hideFromSleep` became the synced
    > `isPrivate` flag, so no habit field remains that the wire has no room for.
