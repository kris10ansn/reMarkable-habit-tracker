# Habit Tracker — Shared Domain

The vocabulary every client and the backend share: what a habit is, how a day's state is recorded,
and what the marks mean. Presentation concerns — grid orientation, e-ink rendering, whether the
suspend image renders a habit at all — are **not** here; each app documents those in its own
`CONTEXT.md`. Domain intent that happens to affect presentation, like **Private**, belongs here
instead: it is shared user intent that syncs, not a per-client rendering choice. This file is a
glossary and nothing else.

The backend reframes some of this for storage and sync (Outcome, Position, Edit-time, Tombstone) —
those terms live in [`apps/backend/CONTEXT.md`](./apps/backend/CONTEXT.md), which is the source of
truth for the shared model and the sync contract.

## Language

**Habit**:
A behaviour the user tracks day-by-day. Has a stable id, a name, a polarity, and a set of entries.
_Avoid_: task, goal, item.

**Habit id**:
A habit's stable, unique identifier — minted once when the habit is created and never changed,
surviving rename and reorder. It is the key entries and the backend use to reference a habit;
because ids are minted client-side, they are random so two offline clients never collide.
_Avoid_: index, position, slug.

**Polarity**:
Whether a habit is positive or negative. Determines what the entry states mean.

**Positive habit**:
A habit the user wants to perform. The default polarity. An unmarked day means nothing
recorded yet.

**Negative habit**:
A habit the user wants to avoid. Every day is implicitly a success ("didn't slip") until
marked otherwise.
_Avoid_: bad habit.

**Entry**:
A habit's recorded state for a single day, keyed by date. Entries exist only for days the user has
marked; a day with no entry is unmarked. Clearing a day leaves a tombstone rather than dropping the
entry, so the clear can be synced — see the backend glossary.
_Avoid_: mark, check, log, record.

**X mark**:
How an entry _reads_ on the grid. On a positive habit it means **done**. On a negative habit a day
with no stored entry is shown as an X meaning "stayed clean today" — nothing is stored there.

**O mark**:
How an entry _reads_ on the grid. On a positive habit it means **explicitly not done**. On a
negative habit it means **slipped up** (the only state the user actively records).

X and O are a **reading, not a storage format**. The recorded value is the backend's **Outcome**
(`Success` / `Failure` — see the [backend glossary](./apps/backend/CONTEXT.md)); each client maps
Outcome → X/O for display and is free to spell it its own way on disk. Never "correct" one client's
on-disk spelling to match another's.

**Unmarked** (no entry, or a tombstoned one):
The default entry state. Positive habits cycle Unmarked → X → O → Unmarked. Negative habits
cycle Unmarked (shown as X) → O → Unmarked.

**Default habits**:
The seed list a client uses the first time it runs with no saved data yet. Each client carries its
own copy — the backend seeds no habits, so a first Sync from a fresh client is what populates the
canonical store.

**Private**:
A habit flagged hidden from glanceable surfaces (a device's suspend/lock-screen image, its main
grid) unless a device-local reveal setting is turned on for that device. The flag itself is shared
user intent and syncs like name or polarity; the reveal setting is per-client presentation and never
syncs — a habit marked private on one device stays hidden on every other device until that device's
own reveal setting is enabled there too.
_Avoid_: hidden, suspended, hideFromSleep (the field's device-local predecessor).
