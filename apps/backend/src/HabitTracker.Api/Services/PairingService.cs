using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Services;

public enum PairingApprovalOutcome
{
    Approved,
    NotFound,
    Expired,
    AlreadyApproved,
}

/// <summary>
/// The TV-style device-code pairing flow (AUTH_PLAN decision 6): an unauthenticated tablet requests
/// a short code and polls it; an authenticated phone looks the code up, shows the requesting
/// device's name, and approves; the tablet's next poll gets a bearer token — the only time that
/// token exists on the wire for this flow.
/// <para>
/// Every method taking a <c>code</c> runs it through <see cref="AuthTokens.NormalizeCode"/> first —
/// lossless, since codes are minted from the uppercase-only
/// <see cref="AuthTokens.CodeAlphabet"/>, and it rescues a phone keyboard that auto-lowercased what
/// the tablet displayed. Kept here rather than at the HTTP edge so it is impossible for a caller to
/// skip.
/// </para>
/// </summary>
public class PairingService
{
    private static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(5);
    private const int PollIntervalSeconds = 3;
    private const int MaxCodeGenerationAttempts = 10;

    private readonly HabitTrackerDbContext _db;
    private readonly CurrentUser _currentUser;
    private readonly SessionService _sessions;

    public PairingService(HabitTrackerDbContext db, CurrentUser currentUser, SessionService sessions)
    {
        _db = db;
        _currentUser = currentUser;
        _sessions = sessions;
    }

    /// <summary>Unauthenticated: a device asks for a code to display and poll.</summary>
    public async Task<PairingCodeResponse> RequestCodeAsync(
        string deviceName,
        CancellationToken cancellationToken = default
    )
    {
        // Self-cleaning table: every request is a convenient moment to sweep rows nobody will ever
        // poll again, without a background job.
        await DeleteExpiredAsync(cancellationToken);

        var code = await GenerateUniqueCodeAsync(cancellationToken);
        var now = DateTimeOffset.UtcNow;
        var expiresAt = now + CodeLifetime;

        _db.PairingCodes.Add(
            new PairingCode
            {
                Id = Guid.NewGuid(),
                Code = code,
                DeviceName = deviceName,
                CreatedAt = now,
                ExpiresAt = expiresAt,
            }
        );
        await _db.SaveChangesAsync(cancellationToken);

        return new PairingCodeResponse(code, expiresAt.ToUnixTimeMilliseconds(), PollIntervalSeconds);
    }

    /// <summary>Authenticated: what the phone shows before approving. Null when unknown/expired.</summary>
    public async Task<PairingRequestInfo?> LookupAsync(
        string code,
        CancellationToken cancellationToken = default
    )
    {
        var normalizedCode = AuthTokens.NormalizeCode(code);

        var now = DateTimeOffset.UtcNow;
        var pairing = await _db.PairingCodes.FirstOrDefaultAsync(
            p => p.Code == normalizedCode && p.ExpiresAt > now,
            cancellationToken
        );

        return pairing is null
            ? null
            : new PairingRequestInfo(pairing.DeviceName, pairing.ExpiresAt.ToUnixTimeMilliseconds());
    }

    /// <summary>
    /// Authenticated: the phone approves. Mints no token and creates no session — that happens on
    /// the tablet's next <see cref="PollAsync"/>.
    /// </summary>
    public async Task<PairingApprovalOutcome> ApproveAsync(
        string code,
        CancellationToken cancellationToken = default
    )
    {
        var normalizedCode = AuthTokens.NormalizeCode(code);

        var pairing = await _db.PairingCodes.FirstOrDefaultAsync(
            p => p.Code == normalizedCode,
            cancellationToken
        );
        if (pairing is null)
        {
            return PairingApprovalOutcome.NotFound;
        }

        if (pairing.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            return PairingApprovalOutcome.Expired;
        }

        if (pairing.ApprovedByUserId is not null)
        {
            return PairingApprovalOutcome.AlreadyApproved;
        }

        pairing.ApprovedByUserId = _currentUser.UserId;
        pairing.ApprovedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        return PairingApprovalOutcome.Approved;
    }

    /// <summary>
    /// Unauthenticated: the tablet polls. An unknown code and a consumed/expired one look identical
    /// to this caller on purpose — both answer <see cref="PairingStatus.Expired"/>, so polling
    /// leaks nothing about which case occurred.
    /// </summary>
    public async Task<PairingPollResponse> PollAsync(
        string code,
        CancellationToken cancellationToken = default
    )
    {
        var normalizedCode = AuthTokens.NormalizeCode(code);

        var pairing = await _db.PairingCodes.FirstOrDefaultAsync(
            p => p.Code == normalizedCode,
            cancellationToken
        );
        if (pairing is null)
        {
            return new PairingPollResponse(PairingStatus.Expired, null);
        }

        if (pairing.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            _db.PairingCodes.Remove(pairing);
            await _db.SaveChangesAsync(cancellationToken);
            return new PairingPollResponse(PairingStatus.Expired, null);
        }

        if (pairing.ApprovedByUserId is null)
        {
            return new PairingPollResponse(PairingStatus.Pending, null);
        }

        // The one and only token emission for this code. Mark the row for deletion BEFORE minting:
        // SessionService.CreateSessionAsync adds the Session and calls SaveChangesAsync itself, and
        // that single call flushes every pending change on this (scoped, shared) DbContext — so the
        // pairing row's deletion and the session's insertion land in the same save. A crash between
        // "approved" and here leaves the row intact for a retry; nothing can observe a session
        // minted with the row still present. This invariant is why PairingCode has no token column.
        _db.PairingCodes.Remove(pairing);
        try
        {
            var (_, token) = await _sessions.CreateSessionAsync(
                pairing.ApprovedByUserId.Value,
                pairing.DeviceName,
                cancellationToken
            );

            return new PairingPollResponse(PairingStatus.Approved, token);
        }
        catch (DbUpdateConcurrencyException)
        {
            // The DELETE's WHERE clause is keyed on Id, so "0 rows affected" here means another
            // poll of this same code already won the race and deleted the row (and, since that
            // whole save either lands together or not at all, already minted the one session for
            // it) between our read above and this save. Answering Expired is not a lesser answer
            // for the loser — it's the exact answer a poll a moment later would have gotten anyway,
            // now that the code is consumed. The save rolling back on this exception is what
            // guarantees this losing poll cannot also mint a second session.
            return new PairingPollResponse(PairingStatus.Expired, null);
        }
    }

    private async Task DeleteExpiredAsync(CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var expired = await _db
            .PairingCodes.Where(p => p.ExpiresAt < now)
            .ToListAsync(cancellationToken);

        if (expired.Count == 0)
        {
            return;
        }

        _db.PairingCodes.RemoveRange(expired);
        await _db.SaveChangesAsync(cancellationToken);
    }

    // The EF in-memory provider (used by tests) doesn't enforce the unique index on Code, so this
    // explicit collision check is what actually gets exercised — on Postgres it's cheap insurance.
    private async Task<string> GenerateUniqueCodeAsync(CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxCodeGenerationAttempts; attempt++)
        {
            var candidate = AuthTokens.NewPairingCode();
            if (!await _db.PairingCodes.AnyAsync(p => p.Code == candidate, cancellationToken))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException(
            $"Could not generate a unique pairing code after {MaxCodeGenerationAttempts} attempts."
        );
    }
}
