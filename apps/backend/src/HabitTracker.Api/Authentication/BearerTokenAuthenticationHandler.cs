using System.Security.Claims;
using System.Text.Encodings.Web;
using HabitTracker.Api.Data;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace HabitTracker.Api.Authentication;

/// <summary>
/// Resolves <c>Authorization: Bearer &lt;token&gt;</c> against the <c>Sessions</c> table. This is
/// the only place a bearer token is looked up; everything downstream reads the resulting
/// <see cref="Services.CurrentUser"/> instead.
/// </summary>
public sealed class BearerTokenAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    /// <summary>
    /// How often <c>LastUsedAt</c> is written for a session actually in use. A client that syncs or
    /// polls every few seconds would otherwise turn every authenticated read into a write; the
    /// column only needs to be roughly current for the "linked devices" list, not exact.
    /// </summary>
    private static readonly TimeSpan LastUsedTouchInterval = TimeSpan.FromMinutes(5);

    private const string BearerPrefix = "Bearer ";

    private readonly HabitTrackerDbContext _db;

    public BearerTokenAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        HabitTrackerDbContext db
    )
        : base(options, logger, encoder)
    {
        _db = db;
    }

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var headerValues))
        {
            return AuthenticateResult.NoResult();
        }

        var header = headerValues.ToString();
        if (!header.StartsWith(BearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return AuthenticateResult.NoResult();
        }

        var token = header[BearerPrefix.Length..].Trim();
        if (token.Length == 0)
        {
            return AuthenticateResult.Fail("Bearer token is empty.");
        }

        // Never log the token or its hash — either is enough to impersonate the session.
        var tokenHash = AuthTokens.HashToken(token);
        var session = await _db
            .Sessions.Include(s => s.User)
            .FirstOrDefaultAsync(s => s.TokenHash == tokenHash);

        if (session is null)
        {
            return AuthenticateResult.Fail("Unknown bearer token.");
        }

        var now = DateTimeOffset.UtcNow;
        if (now - session.LastUsedAt >= LastUsedTouchInterval)
        {
            session.LastUsedAt = now;
            await _db.SaveChangesAsync();
        }

        var claims = new List<Claim>
        {
            new(BearerTokenDefaults.UserIdClaim, session.UserId.ToString()),
            new(BearerTokenDefaults.SessionIdClaim, session.Id.ToString()),
        };
        if (session.User.IsAdmin)
        {
            claims.Add(new Claim(BearerTokenDefaults.IsAdminClaim, "true"));
        }

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, Scheme.Name);

        return AuthenticateResult.Success(ticket);
    }

    protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.Headers["WWW-Authenticate"] = BearerTokenDefaults.AuthenticationScheme;
        await base.HandleChallengeAsync(properties);
    }
}
