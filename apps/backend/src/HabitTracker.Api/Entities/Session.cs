namespace HabitTracker.Api.Entities;

/// <summary>
/// An authenticated session backed by an opaque bearer token. Non-expiring; revocation-based.
/// Each session corresponds to one client device — this table doubles as the "linked devices"
/// list. Deleting a session logs out that device.
/// <para>
/// A server-clock row: not <see cref="ITimestamped"/> and has no <c>UpdatedAt</c>. Its
/// timestamps are set explicitly by the service that creates/touches it, unlike the
/// client-stamped Edit-time on Habit/Entry (see the Edit-time vs. audit-<c>UpdatedAt</c>
/// distinction in <c>apps/backend/CONTEXT.md</c>).
/// </para>
/// </summary>
public class Session
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }
    public User User { get; set; } = null!;

    /// <summary>
    /// SHA-256 hash of the bearer token. The token itself is never stored; this hash is the lookup key.
    /// </summary>
    public string TokenHash { get; set; } = string.Empty;

    /// <summary>Name of the device holding this session (e.g. "Pixel 7", "reMarkable").</summary>
    public string DeviceName { get; set; } = string.Empty;

    /// <summary>When this session was created (UTC).</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When this session was last used (UTC). Updated on authenticated requests.</summary>
    public DateTimeOffset LastUsedAt { get; set; }
}
