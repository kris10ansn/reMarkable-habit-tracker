using HabitTracker.Api.Dtos;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace HabitTracker.Api.Controllers;

[ApiController]
[Route("api/sessions")]
public class SessionsController(SessionService _sessions, ILogger<SessionsController> _logger)
    : ControllerBase
{
    /// <summary>The calling user's linked devices — this doubles as the "linked devices" list.</summary>
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<SessionDto>>> GetSessions(
        CancellationToken cancellationToken
    )
    {
        var sessions = await _sessions.ListSessionsAsync(cancellationToken);
        _logger.LogInformation("Returned {SessionCount} sessions", sessions.Count);

        return Ok(sessions);
    }

    /// <summary>Revokes one of the calling user's own sessions (signs that device out).</summary>
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteSession(Guid id, CancellationToken cancellationToken)
    {
        var revoked = await _sessions.RevokeSessionAsync(id, cancellationToken);
        if (!revoked)
        {
            _logger.LogInformation("Session {SessionId} not found for revoke", id);
            return NotFound();
        }

        _logger.LogInformation("Revoked session {SessionId}", id);
        return NoContent();
    }
}
