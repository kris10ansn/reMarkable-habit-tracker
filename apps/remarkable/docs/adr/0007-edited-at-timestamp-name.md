# 7. The stored timestamp is `editedAt`

Status: accepted; its device-local-field consequence superseded by
[ADR 0008](0008-private-habits.md)

Supersedes the timestamp-naming consequence of
[ADR 0005](0005-backend-shaped-entry-rows.md), which kept the field spelled `updatedAt`.

## Context

ADR 0005 aligned this client's stored rows with the backend's — polarity enum, tombstones, flat
`(habitId, date)` entry rows — but left the timestamp alone: "`updatedAt` remains the single client
timestamp and the merge key the wire format exchanges." That was true of the wire at the time. The
backend's DTOs also called the field `UpdatedAt`, even though the value has always been the
client-stamped **edit-time**: the last-write-wins merge key, never a server audit stamp.

The backend keeps a second, unrelated `UpdatedAt` — server-stamped, never sent to a client. One name
for two clock domains is the confusion the backend has now removed by renaming the sync wire field
to `editedAt` (its `CONTEXT.md` glossary entry for Edit-time). Had this client kept `updatedAt` on
disk, `Sync.js` would have grown a rename in each direction: a new translation, at the exact edge
the last two ADRs were written to thin out, for a field whose meaning never differed.

Splitting the client's timestamp into an edit-time _and_ a local audit stamp is still not needed —
this is one field, renamed.

## Decision

Store the edit-time as `editedAt`, in both `data/roster.json` habit rows and `data/YYYY-MM.json`
entry rows. The sync wire carries the same name, so the timestamp now passes through `Sync.js`
untouched in both directions.

- **Shape guards test it.** `HabitsStore._isRosterRow` requires `editedAt`, and `_applyMonth` gained
  a per-row `_isMonthRow` check — the month file previously trusted `Array.isArray(entries)` alone.
  Without both, a file still spelling `updatedAt` would load with the field undefined, render
  perfectly, then sync as edit-time `0`: every row would lose its merge and the server's copy would
  overwrite real local data. That silent path is exactly what ADR 0006 refuses.
- **The suspend-writer refuses it too.** `tools/suspend-writer/main.cpp`'s `refusesShape` checks
  `editedAt` on roster and entry rows, keeping its "older shapes are refused, not rendered" promise
  honest.
- **A one-shot external script migrates the device**, per
  [ADR 0006](0006-external-one-shot-migrations.md): `scripts/migrate-edited-at.mjs` renames the key
  in a copy of `data/`, preserving values and key order, and refuses data that is already migrated
  or predates ADR 0005.

## Considered options

- **Keep `updatedAt` on disk and rename at the sync edge** — rejected: it adds a translation to
  `Sync.js` for a field that means the same thing on both sides, and leaves the client's on-disk
  vocabulary contradicting the glossary it claims to follow. The X/O ↔ Outcome mapping stays because
  X/O is this client's own domain reading (root `CONTEXT.md`); `updatedAt` was never that — it was
  just the older name.
- **Split into `editedAt` + a local audit `updatedAt`** — rejected as speculative. Nothing on this
  device reads an audit stamp; the backend keeps its own. ADR 0005's deferral still holds.
- **Tolerate both names on read** — rejected by [ADR 0006](0006-external-one-shot-migrations.md).

## Consequences

- The sync edge is one translation smaller. What remains there is the X/O ↔ Outcome mapping and the
  shapes the wire has no field for: `deletedAt` → the `deleted` flag, Position → the roster index,
  and the device-local `hideFromSleep` / `createdAt` that `applySynced` re-attaches.

    > `hideFromSleep` no longer belongs in that list, per [ADR 0008](0008-private-habits.md): it
    > became the synced `isPrivate` flag, so `applySynced` no longer re-attaches it locally.
- **The device must be migrated before the new build runs**, with the app closed: `make backup`,
  then `node scripts/migrate-edited-at.mjs <backup> <out>`, then push `<out>` back (see the README's
  "Upgrading across a storage-format change"). An un-migrated file is refused and named in a modal,
  and sync stays blocked while it is — a dialog, never data loss.
- **The suspend-writer must be rebuilt and redeployed** (`make suspend-writer-device`,
  `make suspend-writer-deploy`): it hosts the same JS modules and its shape guard changed.
- Backend and both clients now spell the merge key `editedAt`, so root `CLAUDE.md`'s claim that they
  do is finally true of this client.
