namespace HabitTracker.Api.Services;

/// <summary>
/// Names of the fixed-window rate-limit policies registered in <c>Program.cs</c>, applied via
/// <c>[EnableRateLimiting]</c> to the unauthenticated endpoints where an attacker could otherwise
/// brute-force a password or a short pairing/invite code.
/// </summary>
public static class RateLimitPolicies
{
    /// <summary>Signup and login: 10 attempts / 5 minutes per caller IP.</summary>
    public const string Authentication = "Authentication";

    /// <summary>Pairing-code requests: 10 / 5 minutes per caller IP.</summary>
    public const string PairingCodeRequest = "PairingCodeRequest";

    /// <summary>Pairing-code polls: 40 / 1 minute per caller IP.</summary>
    public const string PairingPoll = "PairingPoll";

    /// <summary>
    /// Pairing lookup and approval: 30 / 5 minutes per caller IP. The other three policies guard
    /// anonymous endpoints; this one guards <c>GET /api/pairing/{code}</c> and
    /// <c>POST /api/pairing/approve</c>, which are authenticated but otherwise unlimited — without
    /// it, any signed-in account could enumerate live pairing codes and approve someone else's
    /// pending tablet. Partitioning by user id would be a better key than IP, but the rate limiter
    /// middleware runs before authentication in the pipeline, so <c>HttpContext.User</c> isn't
    /// populated yet when the partition key is chosen.
    /// </summary>
    public const string PairingApproval = "PairingApproval";
}
