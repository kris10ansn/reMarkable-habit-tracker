using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Tests;

/// <summary>
/// Fixtures shared by the Sync suites: a throwaway database per test, and the one edit-time both
/// need — far enough ahead of the server clock that <see cref="SyncService"/> refuses the request.
/// </summary>
internal static class SyncTestContext
{
    /// <summary>
    /// A fresh in-memory database seeded with one test <see cref="User"/>. <paramref
    /// name="suiteName"/> only labels the database; the appended guid is what keeps two tests
    /// from sharing state. Pass the returned <paramref name="userId"/> into <see
    /// cref="CurrentUser"/> at every construction site — there is no seeded stub user anymore.
    /// </summary>
    internal static HabitTrackerDbContext NewDb(string suiteName, out Guid userId)
    {
        var options = new DbContextOptionsBuilder<HabitTrackerDbContext>()
            .UseInMemoryDatabase($"{suiteName}-{Guid.NewGuid()}")
            .Options;

        var db = new HabitTrackerDbContext(options);
        db.Database.EnsureCreated();

        var user = new User
        {
            Id = Guid.NewGuid(),
            Name = "Test User",
            Email = "test@example.com",
            PasswordHash = "placeholder-hash",
            IsAdmin = false,
        };
        db.Users.Add(user);
        db.SaveChanges();

        userId = user.Id;
        return db;
    }

    /// <summary>A minute past the tolerance — far enough ahead that the server refuses it.</summary>
    internal static long FarAheadEditTime() =>
        DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
        + (long)SyncService.ClockSkewTolerance.TotalMilliseconds
        + 60_000;
}
