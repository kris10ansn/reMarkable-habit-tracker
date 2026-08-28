using System.Text.Encodings.Web;
using HabitTracker.Api.Authentication;
using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace HabitTracker.Api.Tests;

public class BearerTokenAuthenticationHandlerTests
{
    private static HabitTrackerDbContext NewDb() => AuthTestContext.NewEmptyDb("bearer-handler");

    private static async Task<BearerTokenAuthenticationHandler> NewHandlerAsync(
        HabitTrackerDbContext db,
        HttpContext httpContext
    )
    {
        var handler = new BearerTokenAuthenticationHandler(
            new StaticOptionsMonitor<AuthenticationSchemeOptions>(new AuthenticationSchemeOptions()),
            NullLoggerFactory.Instance,
            UrlEncoder.Default,
            db
        );
        var scheme = new AuthenticationScheme(
            BearerTokenDefaults.AuthenticationScheme,
            BearerTokenDefaults.AuthenticationScheme,
            typeof(BearerTokenAuthenticationHandler)
        );
        await handler.InitializeAsync(scheme, httpContext);
        return handler;
    }

    private static HttpContext ContextWithAuthorizationHeader(string? headerValue)
    {
        var context = new DefaultHttpContext();
        if (headerValue is not null)
        {
            context.Request.Headers.Authorization = headerValue;
        }
        return context;
    }

    /// <summary>Adds a user and a session for it directly (bypassing SessionService), so the test
    /// controls the token/hash relationship and the session's LastUsedAt precisely.</summary>
    private static Session AddSession(
        HabitTrackerDbContext db,
        string token,
        bool isAdmin,
        DateTimeOffset lastUsedAt
    )
    {
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = $"{Guid.NewGuid()}@example.com",
            PasswordHash = "placeholder-hash",
            IsAdmin = isAdmin,
        };
        var session = new Session
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            User = user,
            TokenHash = AuthTokens.HashToken(token),
            DeviceName = "Device",
            CreatedAt = lastUsedAt,
            LastUsedAt = lastUsedAt,
        };
        db.Users.Add(user);
        db.Sessions.Add(session);
        db.SaveChanges();
        return session;
    }

    [Fact]
    public async Task AuthenticateAsync_NoAuthorizationHeader_ReturnsNoResult()
    {
        using var db = NewDb();
        var handler = await NewHandlerAsync(db, ContextWithAuthorizationHeader(null));

        var result = await handler.AuthenticateAsync();

        Assert.True(result.None);
    }

    [Fact]
    public async Task AuthenticateAsync_ANonBearerScheme_ReturnsNoResult()
    {
        using var db = NewDb();
        var handler = await NewHandlerAsync(db, ContextWithAuthorizationHeader("Basic dXNlcjpwYXNz"));

        var result = await handler.AuthenticateAsync();

        Assert.True(result.None);
    }

    [Fact]
    public async Task AuthenticateAsync_BearerWithAnEmptyToken_Fails()
    {
        using var db = NewDb();
        var handler = await NewHandlerAsync(db, ContextWithAuthorizationHeader("Bearer "));

        var result = await handler.AuthenticateAsync();

        Assert.False(result.Succeeded);
        Assert.False(result.None);
    }

    [Fact]
    public async Task AuthenticateAsync_AnUnknownToken_Fails()
    {
        using var db = NewDb();
        var handler = await NewHandlerAsync(
            db,
            ContextWithAuthorizationHeader("Bearer not-a-real-token")
        );

        var result = await handler.AuthenticateAsync();

        Assert.False(result.Succeeded);
        Assert.False(result.None);
    }

    [Fact]
    public async Task AuthenticateAsync_AValidToken_SucceedsWithTheExpectedClaims()
    {
        using var db = NewDb();
        const string token = "a-valid-looking-token";
        var session = AddSession(db, token, isAdmin: false, DateTimeOffset.UtcNow);
        var handler = await NewHandlerAsync(db, ContextWithAuthorizationHeader($"Bearer {token}"));

        var result = await handler.AuthenticateAsync();

        Assert.True(result.Succeeded);
        Assert.Equal(
            session.UserId.ToString(),
            result.Principal!.FindFirst(BearerTokenDefaults.UserIdClaim)!.Value
        );
        Assert.Equal(
            session.Id.ToString(),
            result.Principal!.FindFirst(BearerTokenDefaults.SessionIdClaim)!.Value
        );
    }

    [Fact]
    public async Task AuthenticateAsync_AnAdminsToken_CarriesTheAdminClaim_AndANonAdminsDoesNot()
    {
        using var adminDb = NewDb();
        const string adminToken = "admin-token";
        AddSession(adminDb, adminToken, isAdmin: true, DateTimeOffset.UtcNow);
        var adminHandler = await NewHandlerAsync(
            adminDb,
            ContextWithAuthorizationHeader($"Bearer {adminToken}")
        );
        var adminResult = await adminHandler.AuthenticateAsync();
        Assert.NotNull(adminResult.Principal!.FindFirst(BearerTokenDefaults.IsAdminClaim));

        using var memberDb = NewDb();
        const string memberToken = "member-token";
        AddSession(memberDb, memberToken, isAdmin: false, DateTimeOffset.UtcNow);
        var memberHandler = await NewHandlerAsync(
            memberDb,
            ContextWithAuthorizationHeader($"Bearer {memberToken}")
        );
        var memberResult = await memberHandler.AuthenticateAsync();
        Assert.Null(memberResult.Principal!.FindFirst(BearerTokenDefaults.IsAdminClaim));
    }

    [Fact]
    public async Task AuthenticateAsync_DoesNotRewriteLastUsedAt_ForASessionUsedWithinTheTouchInterval()
    {
        using var db = NewDb();
        const string token = "fresh-session-token";
        var recentlyUsed = DateTimeOffset.UtcNow;
        var session = AddSession(db, token, isAdmin: false, recentlyUsed);
        var handler = await NewHandlerAsync(db, ContextWithAuthorizationHeader($"Bearer {token}"));

        await handler.AuthenticateAsync();

        Assert.Equal(recentlyUsed, session.LastUsedAt);
    }

    [Fact]
    public async Task AuthenticateAsync_RewritesLastUsedAt_ForASessionOlderThanTheTouchInterval()
    {
        using var db = NewDb();
        const string token = "stale-session-token";
        // Older than BearerTokenAuthenticationHandler's 5-minute touch interval.
        var staleLastUsed = DateTimeOffset.UtcNow.AddMinutes(-10);
        var session = AddSession(db, token, isAdmin: false, staleLastUsed);
        var handler = await NewHandlerAsync(db, ContextWithAuthorizationHeader($"Bearer {token}"));

        await handler.AuthenticateAsync();

        Assert.True(session.LastUsedAt > staleLastUsed);
    }

    /// <summary>
    /// The handler needs an <see cref="IOptionsMonitor{TOptions}"/> to construct
    /// (<c>AuthenticationHandler&lt;TOptions&gt;</c>'s base constructor requires one); the
    /// framework's only ready-made implementations come from DI registration, which these tests
    /// deliberately skip to construct the handler directly. This is the minimal stand-in.
    /// </summary>
    private sealed class StaticOptionsMonitor<T>(T currentValue) : IOptionsMonitor<T>
    {
        public T CurrentValue { get; } = currentValue;

        public T Get(string? name) => CurrentValue;

        public IDisposable OnChange(Action<T, string?> listener) => NoopDisposable.Instance;

        private sealed class NoopDisposable : IDisposable
        {
            public static readonly NoopDisposable Instance = new();

            public void Dispose() { }
        }
    }
}
