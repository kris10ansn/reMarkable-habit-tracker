using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Services;

/// <summary>What a signup attempt produced — internal plumbing, not the wire shape (see <see cref="Dtos"/>).</summary>
public enum SignupOutcome
{
    Success,
    EmailAlreadyRegistered,
    InviteRequired,
    InviteInvalid,
}

public record SignupResult(SignupOutcome Outcome, AuthenticationResponse? Response);

/// <summary>
/// Signup, login, and logout. <see cref="PasswordHasher{TUser}"/> (framework-provided, used
/// standalone — no ASP.NET Identity stack) is the only place a password is hashed or verified.
/// </summary>
public class AuthService
{
    private readonly HabitTrackerDbContext _db;
    private readonly SessionService _sessions;
    private readonly IPasswordHasher<User> _passwordHasher;
    private readonly CurrentUser _currentUser;

    public AuthService(
        HabitTrackerDbContext db,
        SessionService sessions,
        IPasswordHasher<User> passwordHasher,
        CurrentUser currentUser
    )
    {
        _db = db;
        _sessions = sessions;
        _passwordHasher = passwordHasher;
        _currentUser = currentUser;
    }

    /// <summary>
    /// Creates a user and logs them in. Bootstrap (AUTH_PLAN decision 3): while <c>Users</c> is
    /// empty, no invite is required and the new user becomes an admin; every signup after that
    /// requires an unused, unexpired invite.
    /// </summary>
    public async Task<SignupResult> SignupAsync(
        SignupRequest request,
        CancellationToken cancellationToken = default
    )
    {
        var email = request.Email.Trim().ToLowerInvariant();

        // The in-memory provider (used by tests) has no transaction support; only wrap on a real
        // (relational) database. Two clients racing the bootstrap check below — both seeing an
        // empty Users table and both becoming admin — is a benign race at this scale (fixable by
        // hand afterward). The transaction's actual job is atomicity: it keeps the new User row and
        // the Invite redemption (or the rollback of both) together as one unit. The guarantee that a
        // concurrent redemption of the same code can't succeed twice comes from a different
        // mechanism — Invite.UsedByUserId being a concurrency token (see
        // HabitTrackerDbContext.OnModelCreating) — caught below, not from this transaction.
        var useTransaction = _db.Database.IsRelational();
        await using var transaction = useTransaction
            ? await _db.Database.BeginTransactionAsync(cancellationToken)
            : null;

        if (await _db.Users.AnyAsync(u => u.Email == email, cancellationToken))
        {
            return new SignupResult(SignupOutcome.EmailAlreadyRegistered, null);
        }

        var isFirstUser = !await _db.Users.AnyAsync(cancellationToken);

        Invite? invite = null;
        if (!isFirstUser)
        {
            // Normalize before deciding "no code supplied" so that trailing whitespace alone still
            // counts as no code (Trim() collapses it to an empty string, caught below) rather than
            // being treated as some non-empty candidate code.
            var inviteCode = request.InviteCode is null
                ? null
                : AuthTokens.NormalizeCode(request.InviteCode);

            if (string.IsNullOrWhiteSpace(inviteCode))
            {
                return new SignupResult(SignupOutcome.InviteRequired, null);
            }

            var now = DateTimeOffset.UtcNow;
            invite = await _db.Invites.FirstOrDefaultAsync(
                i => i.Code == inviteCode && i.UsedByUserId == null && i.ExpiresAt > now,
                cancellationToken
            );

            if (invite is null)
            {
                return new SignupResult(SignupOutcome.InviteInvalid, null);
            }
        }

        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            IsAdmin = isFirstUser,
        };
        user.PasswordHash = _passwordHasher.HashPassword(user, request.Password);
        _db.Users.Add(user);

        if (invite is not null)
        {
            invite.UsedByUserId = user.Id;
            invite.UsedAt = DateTimeOffset.UtcNow;
        }

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            // Invite.UsedByUserId is a concurrency token (see HabitTrackerDbContext), so EF's
            // UPDATE carried "AND UsedByUserId IS NULL" and matched zero rows: another signup
            // redeemed this exact code between our read above and this save. From the caller's
            // point of view the code was already used — which is exactly what happened — so this
            // is not a fault, just the outcome the loser of the race gets. The `await using`
            // transaction above rolls back automatically on this early return.
            return new SignupResult(SignupOutcome.InviteInvalid, null);
        }
        catch (DbUpdateException)
        {
            // The AnyAsync pre-check above is a fast path, not a guarantee: a concurrent duplicate
            // signup can still lose to the IX_Users_Email unique index right here. That index is
            // the actual guarantee against duplicate emails. This catch is broader than ideal — a
            // DbUpdateConcurrencyException for the invite case above is caught separately (and more
            // derived types are matched first), so what reaches here in practice is the email
            // unique-violation, but telling a real unique-violation apart from other DbUpdateException
            // causes would need a Npgsql-specific dependency (e.g. inspecting a PostgresException's
            // SqlState), which this layer deliberately does not take. Widening this catch is the
            // trade-off for staying provider-agnostic.
            return new SignupResult(SignupOutcome.EmailAlreadyRegistered, null);
        }

        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        var (_, token) = await _sessions.CreateSessionAsync(
            user.Id,
            request.DeviceName,
            cancellationToken
        );

        return new SignupResult(SignupOutcome.Success, new AuthenticationResponse(ToDto(user), token));
    }

    /// <summary>
    /// Verifies credentials and mints a session. Returns null for BOTH an unknown email and a wrong
    /// password — the caller must answer both with the same generic 401, or the response shape
    /// itself would let an attacker enumerate registered emails.
    /// </summary>
    public async Task<AuthenticationResponse?> LoginAsync(
        LoginRequest request,
        CancellationToken cancellationToken = default
    )
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == email, cancellationToken);
        if (user is null)
        {
            return null;
        }

        var verification = _passwordHasher.VerifyHashedPassword(user, user.PasswordHash, request.Password);
        if (verification == PasswordVerificationResult.Failed)
        {
            return null;
        }

        if (verification == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = _passwordHasher.HashPassword(user, request.Password);
            await _db.SaveChangesAsync(cancellationToken);
        }

        var (_, token) = await _sessions.CreateSessionAsync(
            user.Id,
            request.DeviceName,
            cancellationToken
        );

        return new AuthenticationResponse(ToDto(user), token);
    }

    /// <summary>Deletes the calling session — the one the request authenticated with.</summary>
    public Task LogoutAsync(CancellationToken cancellationToken = default) =>
        _sessions.RevokeSessionAsync(_currentUser.SessionId, cancellationToken);

    private static UserDto ToDto(User user) => new(user.Id, user.Email, user.Name, user.IsAdmin);
}
