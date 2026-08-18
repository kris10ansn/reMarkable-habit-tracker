// Shared habit vocabulary — see the monorepo-root CONTEXT.md glossary. Mobile stores the backend's
// shape exactly: these interfaces are the same types as the wire's `HabitDto` / `EntryDto`
// (apps/backend Dtos/HabitDtos.cs), so sync is an identity map with no mappers or casts — asserted
// at compile time in src/api/contract.ts. The X/O reading is a render concern (see marks.ts).
//
// The backend's one server-owned field, the `UpdatedAt` audit stamp, has no DTO and never crosses
// the wire, so it has no counterpart here. Everything below is client-owned and stored verbatim.

// These spellings are the backend's enum member names verbatim (apps/backend Entities/Outcome.cs,
// Entities/Polarity.cs). The API serialises enums with a bare `JsonStringEnumConverter` — no naming
// policy — so `"Success"`/`"Positive"` is exactly what the wire carries and what Postgres stores.
// Matching it byte-for-byte is what keeps sync a mapping-free identity. Client-local unions that
// never leave the device (`MarkKind`, `MarkAction["type"]` in marks.ts) stay lowercase per TS idiom.
export type Outcome = "Success" | "Failure";
export type Polarity = "Positive" | "Negative";

// A tracked behaviour. Mirrors the backend Habit / HabitDto: a stable client-minted id (== the
// backend Guid PK), an explicit sort position, an epoch-ms create-time, an edit-time (the
// last-write-wins merge key), and a soft-delete timestamp. `createdAt` anchors a negative habit's
// streak (see marks.ts / repo.getStreaks); `editedAt` is stamped on every write and drives sync
// conflict resolution; `deletedAt` (null when alive) holds the delete-time on a tombstone.
export interface Habit {
    id: string;
    name: string;
    polarity: Polarity;
    position: number;
    // Hidden from glanceable surfaces on devices that render them (reMarkable's suspend image and
    // main grid). Synced verbatim; mobile persists it but has no UI for it yet.
    isPrivate: boolean;
    createdAt: number;
    editedAt: number;
    deletedAt: number | null;
}

// One day's recorded result for a habit, keyed by (habitId, date). Absence of an alive row is the
// Unmarked state; a tombstone (`deletedAt` non-null) also reads as Unmarked. Mirrors backend
// Entry / EntryDto, with `editedAt` as the last-write-wins merge key.
export interface Entry {
    habitId: string;
    date: string; // YYYY-MM-DD
    outcome: Outcome;
    editedAt: number;
    deletedAt: number | null;
}
