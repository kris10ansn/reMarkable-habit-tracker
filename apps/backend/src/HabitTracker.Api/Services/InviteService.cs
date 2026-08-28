using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Services;

/// <summary>Mints admin-only, single-use invite codes (AUTH_PLAN decision 2).</summary>
public class InviteService
{
    private static readonly TimeSpan InviteLifetime = TimeSpan.FromDays(7);
    private const int MaxCodeGenerationAttempts = 10;

    private readonly HabitTrackerDbContext _db;
    private readonly CurrentUser _currentUser;

    public InviteService(HabitTrackerDbContext db, CurrentUser currentUser)
    {
        _db = db;
        _currentUser = currentUser;
    }

    /// <summary>
    /// Mints a 7-day invite as the calling (admin) user. Returned once — there is no endpoint that
    /// re-reads a code, so a caller that loses the response has to mint a new one.
    /// </summary>
    public async Task<InviteDto> MintInviteAsync(CancellationToken cancellationToken = default)
    {
        var code = await GenerateUniqueCodeAsync(cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var expiresAt = now + InviteLifetime;

        _db.Invites.Add(
            new Invite
            {
                Id = Guid.NewGuid(),
                Code = code,
                CreatedByUserId = _currentUser.UserId,
                CreatedAt = now,
                ExpiresAt = expiresAt,
            }
        );
        await _db.SaveChangesAsync(cancellationToken);

        return new InviteDto(code, expiresAt.ToUnixTimeMilliseconds());
    }

    // The EF in-memory provider (used by tests) doesn't enforce the unique index on Code, so this
    // explicit collision check is what actually gets exercised — on Postgres it's cheap insurance.
    private async Task<string> GenerateUniqueCodeAsync(CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxCodeGenerationAttempts; attempt++)
        {
            var candidate = AuthTokens.NewInviteCode();
            if (!await _db.Invites.AnyAsync(i => i.Code == candidate, cancellationToken))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException(
            $"Could not generate a unique invite code after {MaxCodeGenerationAttempts} attempts."
        );
    }
}
