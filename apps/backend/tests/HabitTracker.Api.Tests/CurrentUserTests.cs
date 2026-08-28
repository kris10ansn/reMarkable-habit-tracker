using System.Security.Claims;
using HabitTracker.Api.Authentication;
using HabitTracker.Api.Services;

namespace HabitTracker.Api.Tests;

public class CurrentUserTests
{
    [Fact]
    public void FromPrincipal_Null_YieldsAnonymous()
    {
        var currentUser = CurrentUser.FromPrincipal(null);

        Assert.False(currentUser.IsAuthenticated);
        Assert.Throws<InvalidOperationException>(() => currentUser.UserId);
    }

    [Fact]
    public void FromPrincipal_AnUnauthenticatedPrincipal_YieldsAnonymous()
    {
        // A ClaimsIdentity built without an authenticationType is unauthenticated per .NET's own
        // rule (Identity.IsAuthenticated is false), regardless of what claims it carries.
        var principal = new ClaimsPrincipal(
            new ClaimsIdentity(
                [
                    new Claim(BearerTokenDefaults.UserIdClaim, Guid.NewGuid().ToString()),
                    new Claim(BearerTokenDefaults.SessionIdClaim, Guid.NewGuid().ToString()),
                ]
            )
        );

        var currentUser = CurrentUser.FromPrincipal(principal);

        Assert.False(currentUser.IsAuthenticated);
    }

    [Fact]
    public void FromPrincipal_APrincipalBuiltTheWayTheBearerHandlerBuildsOne_RoundTripsUserIdSessionIdAndAdminFlag()
    {
        var userId = Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        var claims = new[]
        {
            new Claim(BearerTokenDefaults.UserIdClaim, userId.ToString()),
            new Claim(BearerTokenDefaults.SessionIdClaim, sessionId.ToString()),
            new Claim(BearerTokenDefaults.IsAdminClaim, "true"),
        };
        var principal = new ClaimsPrincipal(
            new ClaimsIdentity(claims, BearerTokenDefaults.AuthenticationScheme)
        );

        var currentUser = CurrentUser.FromPrincipal(principal);

        Assert.True(currentUser.IsAuthenticated);
        Assert.Equal(userId, currentUser.UserId);
        Assert.Equal(sessionId, currentUser.SessionId);
        Assert.True(currentUser.IsAdmin);
    }

    [Fact]
    public void FromPrincipal_NoAdminClaim_YieldsIsAdminFalse()
    {
        var claims = new[]
        {
            new Claim(BearerTokenDefaults.UserIdClaim, Guid.NewGuid().ToString()),
            new Claim(BearerTokenDefaults.SessionIdClaim, Guid.NewGuid().ToString()),
        };
        var principal = new ClaimsPrincipal(
            new ClaimsIdentity(claims, BearerTokenDefaults.AuthenticationScheme)
        );

        var currentUser = CurrentUser.FromPrincipal(principal);

        Assert.False(currentUser.IsAdmin);
    }

    [Fact]
    public void FromPrincipal_ClaimsThatDontParseAsGuids_YieldsAnonymous_RatherThanABogusUser()
    {
        var claims = new[]
        {
            new Claim(BearerTokenDefaults.UserIdClaim, "not-a-guid"),
            new Claim(BearerTokenDefaults.SessionIdClaim, Guid.NewGuid().ToString()),
        };
        var principal = new ClaimsPrincipal(
            new ClaimsIdentity(claims, BearerTokenDefaults.AuthenticationScheme)
        );

        var currentUser = CurrentUser.FromPrincipal(principal);

        Assert.False(currentUser.IsAuthenticated);
    }
}
