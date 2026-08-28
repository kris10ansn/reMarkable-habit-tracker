namespace HabitTracker.Api.Entities;

/// <summary>
/// A single-use invite code. Minted by an admin, expires 7 days after creation. Signup requires
/// a valid invite once the Users table is non-empty (first user bootstrap exception in decision 3).
/// <para>
/// A server-clock row: not <see cref="ITimestamped"/> and has no <c>UpdatedAt</c>. Its
/// timestamps are set explicitly by the service that creates/redeems it, unlike the
/// client-stamped Edit-time on Habit/Entry (see the Edit-time vs. audit-<c>UpdatedAt</c>
/// distinction in <c>apps/backend/CONTEXT.md</c>).
/// </para>
/// </summary>
public class Invite
{
    public Guid Id { get; set; }

    /// <summary>The unique invite code (e.g. "ABC123"). Single-use.</summary>
    public string Code { get; set; } = string.Empty;

    /// <summary>The admin user who created this invite.</summary>
    public Guid CreatedByUserId { get; set; }
    public User CreatedByUser { get; set; } = null!;

    /// <summary>When this invite was created (UTC).</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When this invite expires (UTC). 7 days after creation.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>The user who redeemed this invite (null if unused).</summary>
    public Guid? UsedByUserId { get; set; }
    public User? UsedByUser { get; set; }

    /// <summary>When this invite was redeemed (UTC; null if unused).</summary>
    public DateTimeOffset? UsedAt { get; set; }
}
