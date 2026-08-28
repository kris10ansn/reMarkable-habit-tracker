using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Tests;

public class SessionServiceTests
{
    private static HabitTrackerDbContext NewDb() => AuthTestContext.NewEmptyDb("session-service");

    private static async Task<Guid> AddUserAsync(HabitTrackerDbContext db, string email)
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            PasswordHash = "placeholder-hash",
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user.Id;
    }

    [Fact]
    public async Task ListSessionsAsync_ReturnsTheCallersSessions_WithIsCurrentDeviceSetOnlyForTheCallingSession()
    {
        using var db = NewDb();
        var userId = await AddUserAsync(db, "owner@example.com");
        var minting = new SessionService(db, new CurrentUser(userId));
        var (laptopSession, _) = await minting.CreateSessionAsync(userId, "Laptop");
        var (phoneSession, _) = await minting.CreateSessionAsync(userId, "Phone");

        var caller = new SessionService(db, new CurrentUser(userId, phoneSession.Id, isAdmin: false));
        var listed = await caller.ListSessionsAsync();

        Assert.Equal(2, listed.Count);
        Assert.True(Assert.Single(listed, s => s.Id == phoneSession.Id).IsCurrentDevice);
        Assert.False(Assert.Single(listed, s => s.Id == laptopSession.Id).IsCurrentDevice);
    }

    [Fact]
    public async Task RevokeSessionAsync_RemovesTheSession()
    {
        using var db = NewDb();
        var userId = await AddUserAsync(db, "owner@example.com");
        var sessions = new SessionService(db, new CurrentUser(userId));
        var (session, _) = await sessions.CreateSessionAsync(userId, "Laptop");

        var revoked = await sessions.RevokeSessionAsync(session.Id);

        Assert.True(revoked);
        Assert.False(await db.Sessions.AnyAsync(s => s.Id == session.Id));
    }

    [Fact]
    public async Task RevokeSessionAsync_ForAnotherUsersSessionId_ReturnsFalse_AndLeavesThatRowIntact()
    {
        using var db = NewDb();
        var ownerId = await AddUserAsync(db, "owner@example.com");
        var strangerId = await AddUserAsync(db, "stranger@example.com");
        var (ownerSession, _) = await new SessionService(
            db,
            new CurrentUser(ownerId)
        ).CreateSessionAsync(ownerId, "Laptop");

        var strangerSessions = new SessionService(db, new CurrentUser(strangerId));
        var revoked = await strangerSessions.RevokeSessionAsync(ownerSession.Id);

        Assert.False(revoked);
        Assert.True(await db.Sessions.AnyAsync(s => s.Id == ownerSession.Id));
    }
}
