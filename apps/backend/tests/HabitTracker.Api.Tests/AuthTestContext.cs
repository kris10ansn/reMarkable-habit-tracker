using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Tests;

/// <summary>
/// Fixtures shared by the auth suites. Unlike <see cref="SyncTestContext.NewDb"/>, <see
/// cref="NewEmptyDb"/> seeds nothing — the bootstrap tests (in <c>AuthServiceTests</c>) need a
/// genuinely empty <c>Users</c> table to exercise the first-user-becomes-admin path, and every
/// other auth test builds its own users explicitly so it controls their
/// email/password/<c>IsAdmin</c>.
/// </summary>
internal static class AuthTestContext
{
    /// <summary>
    /// A fresh in-memory database with no seeded user. <paramref name="suiteName"/> only labels
    /// the database; the appended guid is what keeps two tests from sharing state.
    /// </summary>
    internal static HabitTrackerDbContext NewEmptyDb(string suiteName)
    {
        var options = new DbContextOptionsBuilder<HabitTrackerDbContext>()
            .UseInMemoryDatabase($"{suiteName}-{Guid.NewGuid()}")
            .Options;

        var db = new HabitTrackerDbContext(options);
        db.Database.EnsureCreated();
        return db;
    }

    /// <summary>
    /// Adds and saves a user with a real password hash, for tests that need one already in the
    /// store (login, sessions, invites minted by an admin, ...) without going through
    /// <c>AuthService.SignupAsync</c>.
    /// </summary>
    internal static User AddUser(
        HabitTrackerDbContext db,
        IPasswordHasher<User> passwordHasher,
        string email,
        string password,
        bool isAdmin = false
    )
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            IsAdmin = isAdmin,
        };
        user.PasswordHash = passwordHasher.HashPassword(user, password);
        db.Users.Add(user);
        db.SaveChanges();
        return user;
    }
}
