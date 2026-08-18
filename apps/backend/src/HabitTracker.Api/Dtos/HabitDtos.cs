using HabitTracker.Api.Entities;

namespace HabitTracker.Api.Dtos;

// The canonical wire shapes for a Habit and an Entry, used by BOTH the REST endpoints and Sync.
// There is deliberately one shape per concept, not one per endpoint: every client stores these
// fields under these names, so decoding is an identity map with no mapper on either side.
//
// The rule for what crosses: the wire carries every client-owned field verbatim. The backend
// withholds only ownership (`Habit.UserId`, the `User`/`Entries` navigation properties) and its own
// audit clock (`UpdatedAt`, server-stamped and meaningless in a client's clock domain).
//
// Timestamps are epoch milliseconds UTC. The entities keep `DateTimeOffset` — Postgres wants
// `timestamptz` and the month-range queries need real dates — so the one conversion lives here at
// the projection edge, backend-side. Clients convert nothing.

/// <summary>
/// A habit as every client holds it. `CreatedAt` and `EditedAt` are the creating/editing client's
/// own clock, stored verbatim; `EditedAt` is the last-write-wins merge key. `IsPrivate` is shared
/// user intent (hidden from glanceable surfaces unless a device-local reveal setting is on) and
/// syncs like `Name`/`Polarity`/`Position`. `DeletedAt` is the tombstone: null while alive, holding
/// the delete-time once soft-deleted. Sync responses carry the authoritative ALIVE state only, so
/// `DeletedAt` is always null on the way out.
/// </summary>
public record HabitDto(
    Guid Id,
    string Name,
    Polarity Polarity,
    int Position,
    bool IsPrivate,
    long CreatedAt,
    long EditedAt,
    long? DeletedAt
);

/// <summary>
/// One day's recorded result, keyed by (HabitId, Date). No create-time: neither client stores one
/// for an entry, and adding a field no client holds would break the identity map for no gain.
/// `DeletedAt` non-null is a cleared cell, which reads as Unmarked.
/// </summary>
public record EntryDto(
    Guid HabitId,
    DateOnly Date,
    Outcome Outcome,
    long EditedAt,
    long? DeletedAt
);

// Inbound REST only. These genuinely differ from HabitDto rather than duplicating it: the server
// mints the id and stamps the times, so the caller supplies neither.

public record CreateHabitRequest(string Name, Polarity Polarity);

public record UpdateHabitRequest(string Name, Polarity Polarity, int Position);
