using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Tests;

public class PairingServiceTests
{
    private static HabitTrackerDbContext NewDb() => AuthTestContext.NewEmptyDb("pairing-service");

    private static PairingService NewPairing(HabitTrackerDbContext db, CurrentUser currentUser) =>
        new(db, currentUser, new SessionService(db, currentUser));

    [Fact]
    public async Task PairingFlow_RequestPollLookupApprovePoll_EndsWithATokenThatAuthenticatesAsTheApprover_AndIsOneShot()
    {
        using var db = NewDb();
        var anonymousPairing = NewPairing(db, CurrentUser.Anonymous);

        var codeResponse = await anonymousPairing.RequestCodeAsync("reMarkable");

        var firstPoll = await anonymousPairing.PollAsync(codeResponse.Code);
        Assert.Equal(PairingStatus.Pending, firstPoll.Status);
        Assert.Null(firstPoll.Token);

        var approverId = Guid.NewGuid();
        db.Users.Add(
            new User
            {
                Id = approverId,
                Email = "phone@example.com",
                PasswordHash = "placeholder-hash",
            }
        );
        await db.SaveChangesAsync();
        var approverPairing = NewPairing(db, new CurrentUser(approverId));

        var lookup = await approverPairing.LookupAsync(codeResponse.Code);
        Assert.NotNull(lookup);
        Assert.Equal("reMarkable", lookup!.DeviceName);

        var approval = await approverPairing.ApproveAsync(codeResponse.Code);
        Assert.Equal(PairingApprovalOutcome.Approved, approval);

        var secondPoll = await anonymousPairing.PollAsync(codeResponse.Code);
        Assert.Equal(PairingStatus.Approved, secondPoll.Status);
        Assert.NotNull(secondPoll.Token);

        var mintedSession = await db.Sessions.SingleAsync(s =>
            s.TokenHash == AuthTokens.HashToken(secondPoll.Token!)
        );
        Assert.Equal(approverId, mintedSession.UserId);
        Assert.Equal("reMarkable", mintedSession.DeviceName);

        // One-shot invariant: the poll that observed approval already deleted the pairing row, so
        // a second poll of the same code finds nothing and reports Expired — and no second
        // session is minted for it.
        var thirdPoll = await anonymousPairing.PollAsync(codeResponse.Code);
        Assert.Equal(PairingStatus.Expired, thirdPoll.Status);
        Assert.Null(thirdPoll.Token);
        Assert.Equal(1, await db.Sessions.CountAsync());
    }

    [Fact]
    public async Task PollAsync_AnAlreadyConsumedApprovedCode_PolledAgain_AnswersExpired_WithNoSecondSessionMinted()
    {
        // Pins the HANDLING PollAsync now has for a lost race (catch DbUpdateConcurrencyException
        // around the mint-and-delete save, answer Expired). Unlike Invite.UsedByUserId (an explicit
        // concurrency token, decoupled from the row's existence), PairingCode's delete concurrency
        // check is about the ROW EXISTING at all -- and PollAsync's own read is an unconditional
        // lookup by Code with no extra filter, so a row already deleted by a "concurrent" poll is
        // simply invisible to the next poll's own fresh read too. That makes it impossible to force
        // a genuine DbUpdateConcurrencyException through PollAsync itself with the single-threaded,
        // single (or even multiple-context) in-memory provider -- whatever poll observes the row
        // gone takes the pre-existing "pairing is null" branch instead, which already answers
        // Expired. So this test pins the END-TO-END answer instead: whichever branch produces it,
        // a second poll of an already-consumed code must answer Expired, with no token, and there
        // must never be a second Session for the same code.
        using var db = NewDb();
        var pairing = NewPairing(db, CurrentUser.Anonymous);
        var approverId = Guid.NewGuid();
        db.Users.Add(
            new User
            {
                Id = approverId,
                Email = "phone3@example.com",
                PasswordHash = "placeholder-hash",
            }
        );
        db.PairingCodes.Add(
            new PairingCode
            {
                Id = Guid.NewGuid(),
                Code = "APPRVD1",
                DeviceName = "reMarkable",
                CreatedAt = DateTimeOffset.UtcNow,
                ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5),
                ApprovedByUserId = approverId,
                ApprovedAt = DateTimeOffset.UtcNow,
            }
        );
        await db.SaveChangesAsync();

        var firstPoll = await pairing.PollAsync("APPRVD1");
        Assert.Equal(PairingStatus.Approved, firstPoll.Status);
        Assert.NotNull(firstPoll.Token);

        var secondPoll = await pairing.PollAsync("APPRVD1");

        Assert.Equal(PairingStatus.Expired, secondPoll.Status);
        Assert.Null(secondPoll.Token);
        Assert.Equal(1, await db.Sessions.CountAsync());
    }

    [Fact]
    public async Task PollAsync_AnExpiredCode_ReportsExpired_AndSweepsTheRow()
    {
        using var db = NewDb();
        var pairing = NewPairing(db, CurrentUser.Anonymous);
        db.PairingCodes.Add(
            new PairingCode
            {
                Id = Guid.NewGuid(),
                Code = "EXPIRED1",
                DeviceName = "reMarkable",
                CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-10),
                ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-5),
            }
        );
        await db.SaveChangesAsync();

        var poll = await pairing.PollAsync("EXPIRED1");

        Assert.Equal(PairingStatus.Expired, poll.Status);
        Assert.Null(poll.Token);
        Assert.False(await db.PairingCodes.AnyAsync(p => p.Code == "EXPIRED1"));
    }

    [Fact]
    public async Task ApproveAsync_AnExpiredCode_ReportsExpired_RatherThanApproving()
    {
        // Deliberately a fresh code that has never been polled — PollAsync itself sweeps an
        // expired row (see the test above), so this pins ApproveAsync's OWN expiry check, which
        // only matters for the code the phone still finds sitting in the table.
        using var db = NewDb();
        db.PairingCodes.Add(
            new PairingCode
            {
                Id = Guid.NewGuid(),
                Code = "EXPIRED2",
                DeviceName = "reMarkable",
                CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-10),
                ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-5),
            }
        );
        var approverId = Guid.NewGuid();
        db.Users.Add(
            new User
            {
                Id = approverId,
                Email = "phone2@example.com",
                PasswordHash = "placeholder-hash",
            }
        );
        await db.SaveChangesAsync();

        var approval = await NewPairing(db, new CurrentUser(approverId)).ApproveAsync("EXPIRED2");

        Assert.Equal(PairingApprovalOutcome.Expired, approval);
    }

    [Fact]
    public async Task PollAsync_AnUnknownCode_ReportsExpired_SameAsAConsumedOne()
    {
        // Deliberately indistinguishable (see PairingService.PollAsync's own doc comment): a code
        // that never existed and one that was already consumed both answer Expired, so polling
        // leaks nothing about which case occurred. Pin both answers together.
        using var db = NewDb();
        var pairing = NewPairing(db, CurrentUser.Anonymous);

        var poll = await pairing.PollAsync("NOSUCH");

        Assert.Equal(PairingStatus.Expired, poll.Status);
        Assert.Null(poll.Token);
    }

    [Fact]
    public async Task RequestCodeAsync_MintsA6CharacterCode_DrawnOnlyFromTheCodeAlphabet_NeverAmbiguousGlyphs()
    {
        using var db = NewDb();
        var pairing = NewPairing(db, CurrentUser.Anonymous);

        for (var i = 0; i < 50; i++)
        {
            var response = await pairing.RequestCodeAsync("reMarkable");

            Assert.Equal(6, response.Code.Length);
            Assert.All(response.Code, c => Assert.True(AuthTokens.CodeAlphabet.Contains(c)));
            Assert.False(response.Code.Contains('0'));
            Assert.False(response.Code.Contains('O'));
            Assert.False(response.Code.Contains('1'));
            Assert.False(response.Code.Contains('I'));
        }
    }
}
