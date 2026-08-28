namespace HabitTracker.Api.Entities;

/// <summary>
/// The account that owns a set of habits — the unit of ownership and authentication.
/// </summary>
public class User : ITimestamped
{
    public Guid Id { get; set; }

    public string? Name { get; set; }

    /// <summary>Unique email address used for authentication.</summary>
    public string Email { get; set; } = string.Empty;

    /// <summary>
    /// Hashed password, produced by PasswordHasher&lt;User&gt;. Never transmitted or logged.
    /// </summary>
    public string PasswordHash { get; set; } = string.Empty;

    /// <summary>Whether this user can mint invites and perform admin operations.</summary>
    public bool IsAdmin { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<Habit> Habits { get; set; } = new List<Habit>();
    public ICollection<Session> Sessions { get; set; } = new List<Session>();
}
