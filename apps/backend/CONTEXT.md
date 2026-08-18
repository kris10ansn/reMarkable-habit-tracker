# Backend — Persistence & Sync Context

The C# / ASP.NET Core + EF Core service that owns the canonical Habit/Entry records and syncs them
to every client. The shared habit vocabulary (Habit, Polarity, Entry, X/O marks, Unmarked, Default
habits) lives in the [root glossary](../../CONTEXT.md). This file covers only terms the backend adds
or reframes, and is the source of truth for the sync contract both clients speak.

## Language

**User**:
The account that owns a set of habits. The unit of ownership and (later) authentication. Every
Habit belongs to exactly one User. Auth is not built yet — a stub/seed identity stands in.
_Avoid_: account, profile, owner-as-a-separate-thing.

**Outcome**:
An entry's recorded result, **Success** or **Failure**, independent of polarity. The backend's
canonical form of the clients' X/O marks: X → Success, O → Failure for both polarities. Absence
of an entry is the Unmarked/default state (clients interpret that absence per polarity — a
negative habit's implicit "stayed clean" is never a stored Success). The log is permissive: any
Outcome may be stored against any habit; "negative habits only record Failure" is a client
convention, not a backend rule.
_Avoid_: mark, x/o, state, status.

**Position**:
A habit's explicit sort order within its User's list. Shared user intent — a reorder is meant to
sync across devices — not per-client presentation (unlike grid orientation).
_Avoid_: index, rank, sortKey (an implementation detail of how Position is encoded).

**Private**:
A habit's `IsPrivate` flag: hidden from glanceable surfaces (a device's suspend image, its main
grid) on the device that renders it. Shared user intent, like Position — marking a habit private is
meant to sync across devices, so it's a column on `Habit` and a `HabitDto` field like any other. The
per-device reveal setting that lets a device show its private habits anyway is per-client
presentation and stays out of the backend entirely, the same way grid orientation does.
_Avoid_: hidden, suspended, hideFromSleep (the field's device-local predecessor).

## Sync

**Sync**:
The reconciliation that merges a client's submitted state with the canonical store and returns the
authoritative merged result. State-based and last-write-wins, resolved per row.
_Avoid_: push, pull (those name directions within one Sync), replication, backup.

**Edit-time**:
The UTC instant a client last changed a Habit or Entry, stamped by that client and stored verbatim
as the row's last-write-wins merge key. Spelled `EditedAt` on the entity and `editedAt` on the sync
wire — deliberately not `UpdatedAt`, which is the server-stamped audit field and never leaves the
server. The two are different clock domains, and Edit-time is the only one a Sync compares. An
edit-time far ahead of the server's own clock is refused rather than merged: it would out-rank every
later edit until wall-clock caught up.
_Avoid_: updatedAt (the audit column), modified, timestamp.

**Tombstone**:
A timestamped soft-delete marker (a `DeletedAt`) kept so a deletion can win or lose against a dated
edit during a Sync, rather than a row simply vanishing and risking resurrection.
_Avoid_: hard delete, removal flag, archived.
