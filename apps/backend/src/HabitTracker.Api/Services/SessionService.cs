using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Services;

/// <summary>
/// The single choke point for minting, listing, and revoking sessions — every path that hands a
/// client a bearer token (signup, login, pairing approval) goes through
/// <see cref="CreateSessionAsync"/>, so "how a token is minted and stored" lives in exactly one
/// place.
/// </summary>
public class SessionService
{
    private readonly HabitTrackerDbContext _db;
    private readonly CurrentUser _currentUser;

    public SessionService(HabitTrackerDbContext db, CurrentUser currentUser)
    {
        _db = db;
        _currentUser = currentUser;
    }

    /// <summary>
    /// Mints a new session for <paramref name="userId"/> and returns the plaintext token alongside
    /// the stored row. The token is never persisted — only <see cref="AuthTokens.HashToken"/> of it
    /// is — so this is the only moment it exists outside the caller's response.
    /// </summary>
    public async Task<(Session Session, string Token)> CreateSessionAsync(
        Guid userId,
        string deviceName,
        CancellationToken cancellationToken = default
    )
    {
        var token = AuthTokens.NewSessionToken();
        var now = DateTimeOffset.UtcNow;

        var session = new Session
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            TokenHash = AuthTokens.HashToken(token),
            DeviceName = deviceName,
            CreatedAt = now,
            LastUsedAt = now,
        };

        _db.Sessions.Add(session);
        await _db.SaveChangesAsync(cancellationToken);

        return (session, token);
    }

    /// <summary>The calling user's sessions (linked devices), newest first.</summary>
    public async Task<IReadOnlyList<SessionDto>> ListSessionsAsync(
        CancellationToken cancellationToken = default
    )
    {
        var sessions = await _db
            .Sessions.Where(s => s.UserId == _currentUser.UserId)
            .OrderByDescending(s => s.CreatedAt)
            .ToListAsync(cancellationToken);

        return sessions.Select(ToDto).ToList();
    }

    /// <summary>
    /// Revokes one of the calling user's own sessions. Scoped to the caller so a client can never
    /// revoke another user's session; an id that isn't the caller's is indistinguishable from an
    /// unknown one, so this returns <c>false</c> (-&gt; 404) rather than leaking existence via 403.
    /// </summary>
    public async Task<bool> RevokeSessionAsync(
        Guid sessionId,
        CancellationToken cancellationToken = default
    )
    {
        var session = await _db.Sessions.FirstOrDefaultAsync(
            s => s.Id == sessionId && s.UserId == _currentUser.UserId,
            cancellationToken
        );
        if (session is null)
        {
            return false;
        }

        _db.Sessions.Remove(session);
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }

    private SessionDto ToDto(Session session) =>
        new(
            session.Id,
            session.DeviceName,
            session.CreatedAt.ToUnixTimeMilliseconds(),
            session.LastUsedAt.ToUnixTimeMilliseconds(),
            session.Id == _currentUser.SessionId
        );
}
