using System.Security.Claims;

namespace HabitTracker.Api.Authentication;

/// <summary>
/// Names shared between <see cref="BearerTokenAuthenticationHandler"/> (which writes these claims)
/// and <see cref="Services.CurrentUser"/> (which reads them back) — the two halves of the bearer
/// auth seam.
/// </summary>
public static class BearerTokenDefaults
{
    public const string AuthenticationScheme = "Bearer";

    /// <summary>The authenticated user's id. Uses the standard name-identifier claim type.</summary>
    public const string UserIdClaim = ClaimTypes.NameIdentifier;

    /// <summary>The <c>Session</c> row backing the current bearer token.</summary>
    public const string SessionIdClaim = "sid";

    /// <summary>Present with value <c>"true"</c> only when the session's user is an admin.</summary>
    public const string IsAdminClaim = "admin";

    /// <summary>Authorization policy requiring <see cref="IsAdminClaim"/> to equal <c>"true"</c>.</summary>
    public const string AdminPolicy = "Admin";
}
