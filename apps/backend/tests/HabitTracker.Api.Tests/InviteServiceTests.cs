using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Tests;

public class InviteServiceTests
{
    private static HabitTrackerDbContext NewDb() => AuthTestContext.NewEmptyDb("invite-service");

    [Fact]
    public async Task MintInviteAsync_CreatesA7DayCode_AttributedToTheCallingAdmin_DrawnFromTheCodeAlphabet()
    {
        using var db = NewDb();
        var adminId = Guid.NewGuid();
        db.Users.Add(
            new User
            {
                Id = adminId,
                Email = "admin@example.com",
                PasswordHash = "placeholder-hash",
                IsAdmin = true,
            }
        );
        await db.SaveChangesAsync();
        var invites = new InviteService(db, new CurrentUser(adminId));

        var before = DateTimeOffset.UtcNow;
        var invite = await invites.MintInviteAsync();
        var after = DateTimeOffset.UtcNow;

        Assert.All(invite.Code, c => Assert.True(AuthTokens.CodeAlphabet.Contains(c)));

        var stored = await db.Invites.SingleAsync(i => i.Code == invite.Code);
        Assert.Equal(adminId, stored.CreatedByUserId);
        Assert.Null(stored.UsedByUserId);
        Assert.InRange(stored.ExpiresAt, before.AddDays(7), after.AddDays(7));
        Assert.Equal(stored.ExpiresAt.ToUnixTimeMilliseconds(), invite.ExpiresAt);
    }
}
