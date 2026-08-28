using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace HabitTracker.Api.Tests;

public class AuthServiceTests
{
    // PasswordHasher<User> does real, deliberately slow-ish hashing (PBKDF2 iterations) —
    // construct it once for the whole class rather than per assertion.
    private static readonly IPasswordHasher<User> PasswordHasher = new PasswordHasher<User>();

    private static HabitTrackerDbContext NewEmptyDb() => AuthTestContext.NewEmptyDb("auth-service");

    private static AuthService NewAuth(HabitTrackerDbContext db, CurrentUser currentUser) =>
        new(
            db,
            new SessionService(db, currentUser),
            PasswordHasher,
            currentUser,
            NullLogger<AuthService>.Instance
        );

    // --- Bootstrap (AUTH_PLAN decision 3) ---

    [Fact]
    public async Task SignupAsync_IntoAnEmptyUsersTable_SucceedsWithoutAnInviteCode_AndTheNewUserIsAdmin()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);

        var result = await auth.SignupAsync(
            new SignupRequest("owner@example.com", "correct-horse-battery", "Laptop", null)
        );

        Assert.Equal(SignupOutcome.Success, result.Outcome);
        Assert.True(result.Response!.User.IsAdmin);
    }

    [Fact]
    public async Task SignupAsync_ASecondSignupWithNoInviteCode_IsRejected_AndTheFirstUserStaysTheOnlyAdmin()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        await auth.SignupAsync(
            new SignupRequest("owner@example.com", "correct-horse-battery", "Laptop", null)
        );

        var second = await auth.SignupAsync(
            new SignupRequest("stranger@example.com", "another-long-password", "Phone", null)
        );

        Assert.Equal(SignupOutcome.InviteRequired, second.Outcome);
        var onlyUser = Assert.Single(db.Users);
        Assert.True(onlyUser.IsAdmin);
    }

    // --- Invite lifecycle (AUTH_PLAN decision 2) ---

    [Fact]
    public async Task SignupAsync_WithAnAdminMintedInvite_LetsASecondUserSignUp_AsNonAdmin_AndMarksTheInviteUsed()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        var adminSignup = await auth.SignupAsync(
            new SignupRequest("admin@example.com", "correct-horse-battery", "Laptop", null)
        );
        var adminId = adminSignup.Response!.User.Id;
        var invite = await new InviteService(db, new CurrentUser(adminId)).MintInviteAsync();

        var second = await auth.SignupAsync(
            new SignupRequest("member@example.com", "another-long-password", "Phone", invite.Code)
        );

        Assert.Equal(SignupOutcome.Success, second.Outcome);
        Assert.False(second.Response!.User.IsAdmin);

        var storedInvite = await db.Invites.SingleAsync(i => i.Code == invite.Code);
        Assert.Equal(second.Response!.User.Id, storedInvite.UsedByUserId);
        Assert.NotNull(storedInvite.UsedAt);
    }

    [Fact]
    public async Task SignupAsync_ReusingAnAlreadyUsedInviteCode_IsRejected()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        var adminSignup = await auth.SignupAsync(
            new SignupRequest("admin@example.com", "correct-horse-battery", "Laptop", null)
        );
        var invite = await new InviteService(
            db,
            new CurrentUser(adminSignup.Response!.User.Id)
        ).MintInviteAsync();
        await auth.SignupAsync(
            new SignupRequest("member@example.com", "another-long-password", "Phone", invite.Code)
        );

        var reuse = await auth.SignupAsync(
            new SignupRequest("intruder@example.com", "yet-another-password", "Tablet", invite.Code)
        );

        Assert.Equal(SignupOutcome.InviteInvalid, reuse.Outcome);
    }

    [Fact]
    public async Task SignupAsync_WithAnExpiredInvite_IsRejected()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        var adminSignup = await auth.SignupAsync(
            new SignupRequest("admin@example.com", "correct-horse-battery", "Laptop", null)
        );
        db.Invites.Add(
            new Invite
            {
                Id = Guid.NewGuid(),
                Code = "EXPIREDCODE1",
                CreatedByUserId = adminSignup.Response!.User.Id,
                CreatedAt = DateTimeOffset.UtcNow.AddDays(-8),
                ExpiresAt = DateTimeOffset.UtcNow.AddDays(-1),
            }
        );
        await db.SaveChangesAsync();

        var result = await auth.SignupAsync(
            new SignupRequest("member@example.com", "another-long-password", "Phone", "EXPIREDCODE1")
        );

        Assert.Equal(SignupOutcome.InviteInvalid, result.Outcome);
    }

    [Fact]
    public async Task SignupAsync_WithAnUnknownInviteCode_IsRejected()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        await auth.SignupAsync(
            new SignupRequest("admin@example.com", "correct-horse-battery", "Laptop", null)
        );

        var result = await auth.SignupAsync(
            new SignupRequest("member@example.com", "another-long-password", "Phone", "NOSUCHCODE12")
        );

        Assert.Equal(SignupOutcome.InviteInvalid, result.Outcome);
    }

    [Fact]
    public async Task SignupAsync_WhenTheInviteRowChangedSinceItWasRead_TreatsTheLostRaceAsInviteInvalid()
    {
        // The EF in-memory provider cannot reproduce a genuine two-connections database race (two
        // requests' SELECTs both landing before either's UPDATE commits) -- but it DOES honour
        // concurrency tokens, and that mechanism is exactly what Invite.UsedByUserId being one now
        // depends on. This test provokes a REAL DbUpdateConcurrencyException by lying to this
        // context's change tracker about the invite's original UsedByUserId (as if this context had
        // read the row before some other redemption, when in fact nothing redeemed it) and then
        // driving SignupAsync's normal code path -- SignupAsync's own query still finds the invite
        // (the store row is genuinely still unused), so it proceeds to redeem it and hits the save,
        // whose WHERE clause now carries the lied-about original value and matches zero rows. That
        // is a real DbUpdateConcurrencyException flowing through AuthService's actual catch block,
        // not just a simulation of the outcome. (We don't also assert the User row was rolled
        // back: the in-memory provider has no real transactions, so unlike Postgres a failed
        // SaveChangesAsync there is not atomic across every entry in the same call -- that's a
        // limitation of the test double, not something this test is trying to prove either way.)
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        var adminSignup = await auth.SignupAsync(
            new SignupRequest("admin@example.com", "correct-horse-battery", "Laptop", null)
        );
        var invite = await new InviteService(
            db,
            new CurrentUser(adminSignup.Response!.User.Id)
        ).MintInviteAsync();

        var trackedInvite = await db.Invites.SingleAsync(i => i.Code == invite.Code);
        db.Entry(trackedInvite).Property(i => i.UsedByUserId).OriginalValue = Guid.NewGuid();

        var result = await auth.SignupAsync(
            new SignupRequest("member@example.com", "another-long-password", "Phone", invite.Code)
        );

        Assert.Equal(SignupOutcome.InviteInvalid, result.Outcome);
        Assert.Null(result.Response);
    }

    [Fact]
    public async Task SignupAsync_WithALowercaseRenderingOfARealInviteCode_StillWorks()
    {
        // Codes are minted uppercase-only (AuthTokens.CodeAlphabet) and normalized on lookup — a
        // deliberate rescue for a phone keyboard auto-lowercasing what the tablet/admin displayed.
        // Pin that behaviour directly rather than only implicitly through AuthTokens.NormalizeCode.
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        var adminSignup = await auth.SignupAsync(
            new SignupRequest("admin@example.com", "correct-horse-battery", "Laptop", null)
        );
        var invite = await new InviteService(
            db,
            new CurrentUser(adminSignup.Response!.User.Id)
        ).MintInviteAsync();

        var result = await auth.SignupAsync(
            new SignupRequest(
                "member@example.com",
                "another-long-password",
                "Phone",
                invite.Code.ToLowerInvariant()
            )
        );

        Assert.Equal(SignupOutcome.Success, result.Outcome);
    }

    // --- Duplicate email ---

    [Fact]
    public async Task SignupAsync_AnEmailDifferingOnlyByCaseOrSurroundingWhitespace_IsRejected()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        await auth.SignupAsync(
            new SignupRequest("owner@example.com", "correct-horse-battery", "Laptop", null)
        );

        var result = await auth.SignupAsync(
            new SignupRequest("  OWNER@Example.com  ", "another-long-password", "Phone", null)
        );

        Assert.Equal(SignupOutcome.EmailAlreadyRegistered, result.Outcome);
    }

    // --- Login / token verification ---

    [Fact]
    public async Task LoginAsync_WithCorrectCredentials_ReturnsAToken_AndOnlyItsHashIsStoredAnywhere()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        await auth.SignupAsync(
            new SignupRequest("owner@example.com", "correct-horse-battery", "Laptop", null)
        );

        var response = await auth.LoginAsync(
            new LoginRequest("owner@example.com", "correct-horse-battery", "Phone")
        );

        Assert.NotNull(response);
        var session = await db.Sessions.SingleAsync(s => s.DeviceName == "Phone");
        Assert.Equal(AuthTokens.HashToken(response!.Token), session.TokenHash);
        Assert.DoesNotContain(db.Sessions, s => s.TokenHash == response.Token);
    }

    [Fact]
    public async Task LoginAsync_WithAWrongPassword_ReturnsNull_IndistinguishableFromAnUnknownEmail()
    {
        using var db = NewEmptyDb();
        var auth = NewAuth(db, CurrentUser.Anonymous);
        await auth.SignupAsync(
            new SignupRequest("owner@example.com", "correct-horse-battery", "Laptop", null)
        );

        var wrongPassword = await auth.LoginAsync(
            new LoginRequest("owner@example.com", "totally-wrong-password", "Phone")
        );
        var unknownEmail = await auth.LoginAsync(
            new LoginRequest("nobody@example.com", "correct-horse-battery", "Phone")
        );

        // Both must be indistinguishable to the caller — a distinct null-vs-something shape would
        // let an attacker enumerate registered emails.
        Assert.Null(wrongPassword);
        Assert.Null(unknownEmail);
    }

    [Fact]
    public async Task LoginAsync_WithAnUnknownEmail_StillVerifiesAPasswordHash_SoTheTwoFailuresCostTheSame()
    {
        // The shared 401 only hides which failure occurred if both paths do the same work. Timing
        // itself is too flaky to assert, so this pins the mechanism instead: exactly one hash
        // verification, whether or not the email resolves to a user.
        using var db = NewEmptyDb();
        var countingHasher = new CountingPasswordHasher();
        var auth = new AuthService(
            db,
            new SessionService(db, CurrentUser.Anonymous),
            countingHasher,
            CurrentUser.Anonymous,
            NullLogger<AuthService>.Instance
        );

        await auth.LoginAsync(new LoginRequest("nobody@example.com", "any-password", "Phone"));

        Assert.Equal(1, countingHasher.VerifyCount);
    }

    private sealed class CountingPasswordHasher : IPasswordHasher<User>
    {
        private readonly IPasswordHasher<User> _inner = new PasswordHasher<User>();

        internal int VerifyCount { get; private set; }

        public string HashPassword(User user, string password) => _inner.HashPassword(user, password);

        public PasswordVerificationResult VerifyHashedPassword(
            User user,
            string hashedPassword,
            string providedPassword
        )
        {
            VerifyCount++;
            return _inner.VerifyHashedPassword(user, hashedPassword, providedPassword);
        }
    }

    // --- Logout ---

    [Fact]
    public async Task LogoutAsync_DeletesExactlyTheCallingSession_AndLeavesTheUsersOtherSessionsAlone()
    {
        using var db = NewEmptyDb();
        var bootstrapAuth = NewAuth(db, CurrentUser.Anonymous);
        var signup = await bootstrapAuth.SignupAsync(
            new SignupRequest("owner@example.com", "correct-horse-battery", "Laptop", null)
        );
        var userId = signup.Response!.User.Id;
        var (otherSession, _) = await new SessionService(db, new CurrentUser(userId)).CreateSessionAsync(
            userId,
            "Phone"
        );
        var callingSessionId = (await db.Sessions.SingleAsync(s => s.DeviceName == "Laptop")).Id;
        var auth = NewAuth(db, new CurrentUser(userId, callingSessionId, isAdmin: true));

        await auth.LogoutAsync();

        Assert.False(await db.Sessions.AnyAsync(s => s.Id == callingSessionId));
        Assert.True(await db.Sessions.AnyAsync(s => s.Id == otherSession.Id));
    }
}
