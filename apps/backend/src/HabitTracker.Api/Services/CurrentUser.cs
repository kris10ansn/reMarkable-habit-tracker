using HabitTracker.Api.Authentication;
using System.Security.Claims;

namespace HabitTracker.Api.Services;

/// <summary>
/// The User (and Session) on whose behalf the current request acts. This is the single seam the
/// auth layer resolves into — every other service reads identity through here rather than touching
/// <see cref="ClaimsPrincipal"/> or <c>HttpContext</c> directly. Registered as scoped in
/// <c>Program.cs</c>, built once per request from the authenticated principal via
/// <see cref="FromPrincipal"/>.
/// </summary>
public sealed class CurrentUser
{
    private readonly Guid? _userId;
    private readonly Guid? _sessionId;
    private readonly bool _isAdmin;

    public bool IsAuthenticated => _userId is not null;

    public Guid UserId =>
        _userId ?? throw new InvalidOperationException("No authenticated user for this request.");

    /// <summary>
    /// Throws rather than answering <see cref="Guid.Empty"/>, deliberately: an empty id would sail
    /// through a scoped query as a silent no-match, so an anonymous caller reaching a
    /// session-scoped path would delete nothing and be told it worked. Same contract as
    /// <see cref="UserId"/> — the seam fails loudly on both halves or on neither.
    /// </summary>
    public Guid SessionId =>
        _sessionId
        ?? throw new InvalidOperationException("No authenticated session for this request.");

    public bool IsAdmin => _isAdmin;

    /// <summary>The unauthenticated seam value — no anonymous endpoint should need it, but every
    /// scoped registration must produce something.</summary>
    public static CurrentUser Anonymous { get; } = new();

    private CurrentUser()
    {
        _userId = null;
        _sessionId = null;
        _isAdmin = false;
    }

    public CurrentUser(Guid userId, Guid sessionId, bool isAdmin)
    {
        _userId = userId;
        _sessionId = sessionId;
        _isAdmin = isAdmin;
    }

    /// <summary>
    /// Convenience overload for tests that only care about the owning user. Its
    /// <see cref="Guid.Empty"/> session is a real-but-unmatchable id, not the absence
    /// <see cref="Anonymous"/> carries: a test that lists sessions still gets
    /// <c>IsCurrentDevice: false</c> for every row instead of a throw.
    /// </summary>
    public CurrentUser(Guid userId)
        : this(userId, Guid.Empty, isAdmin: false) { }

    /// <summary>
    /// Builds a <see cref="CurrentUser"/> from the bearer-authenticated principal
    /// (<see cref="BearerTokenAuthenticationHandler"/>). Returns <see cref="Anonymous"/> when
    /// <paramref name="principal"/> is null, unauthenticated, or its claims don't parse — an
    /// anonymous endpoint is the only place that should observe that.
    /// </summary>
    public static CurrentUser FromPrincipal(ClaimsPrincipal? principal)
    {
        if (principal?.Identity is not { IsAuthenticated: true })
        {
            return Anonymous;
        }

        var userIdClaim = principal.FindFirst(BearerTokenDefaults.UserIdClaim)?.Value;
        var sessionIdClaim = principal.FindFirst(BearerTokenDefaults.SessionIdClaim)?.Value;
        if (
            !Guid.TryParse(userIdClaim, out var userId)
            || !Guid.TryParse(sessionIdClaim, out var sessionId)
        )
        {
            return Anonymous;
        }

        var isAdmin = principal.FindFirst(BearerTokenDefaults.IsAdminClaim)?.Value == "true";

        return new CurrentUser(userId, sessionId, isAdmin);
    }
}
