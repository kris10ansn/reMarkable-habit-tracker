namespace HabitTracker.Api.Entities;

/// <summary>
/// A tracked behaviour owned by a single User. Every client-owned field crosses the wire
/// verbatim; only per-device presentation settings (e.g. the reveal setting for private
/// habits) stay client-side.
/// </summary>
public class Habit : ITimestamped
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }
    public User User { get; set; } = null!;

    public string Name { get; set; } = string.Empty;
    public Polarity Polarity { get; set; }

    /// <summary>Explicit sort order within the owner's list — shared intent, meant to sync.</summary>
    public int Position { get; set; }

    /// <summary>
    /// Hidden from glanceable surfaces (suspend image, main grid) unless a device-local reveal
    /// setting is on. Shared user intent, so it syncs — the reveal setting doesn't.
    /// </summary>
    public bool IsPrivate { get; set; }

    /// <summary>
    /// The client's edit-time (UTC) for this row's current state — the last-write-wins merge key
    /// for sync. Stored verbatim from the editing client, so it lives in a different clock domain
    /// from the server-stamped <see cref="UpdatedAt"/> audit field.
    /// </summary>
    public DateTimeOffset EditedAt { get; set; }

    /// <summary>Tombstone: non-null once soft-deleted, holding the delete's edit-time.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<Entry> Entries { get; set; } = new List<Entry>();
}
