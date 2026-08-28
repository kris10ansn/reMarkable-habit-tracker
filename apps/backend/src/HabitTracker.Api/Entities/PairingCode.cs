namespace HabitTracker.Api.Entities;

/// <summary>
/// A device-code for tablet pairing (RFC 8628 in spirit, simplified). The tablet displays this code,
/// polls for approval; the phone enters the code and approves; the tablet's next poll returns its bearer token.
/// Codes are single-approval and expire 5 minutes after creation.
/// <para>
/// Deliberately has no token column: the session token is minted on the poll that observes the
/// approval, and that same save deletes this row — so a bearer token is never at rest in
/// plaintext. Do not add one back.
/// </para>
/// <para>
/// A server-clock row: not <see cref="ITimestamped"/> and has no <c>UpdatedAt</c>. Its
/// timestamps are set explicitly by the service that creates/approves it, unlike the
/// client-stamped Edit-time on Habit/Entry (see the Edit-time vs. audit-<c>UpdatedAt</c>
/// distinction in <c>apps/backend/CONTEXT.md</c>).
/// </para>
/// </summary>
public class PairingCode
{
    public Guid Id { get; set; }

    /// <summary>
    /// The 6-character unambiguous code (excludes 0/O/1/I) that the tablet displays and the phone enters.
    /// Single-approval, deleted on use or expiry.
    /// </summary>
    public string Code { get; set; } = string.Empty;

    /// <summary>Name of the device requesting pairing (e.g. "reMarkable").</summary>
    public string DeviceName { get; set; } = string.Empty;

    /// <summary>When this code was created (UTC).</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When this code expires (UTC). 5 minutes after creation.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>The user who approved this pairing (null if not yet approved).</summary>
    public Guid? ApprovedByUserId { get; set; }
    public User? ApprovedByUser { get; set; }

    /// <summary>When this pairing was approved (UTC; null if not yet approved).</summary>
    public DateTimeOffset? ApprovedAt { get; set; }
}
