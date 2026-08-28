using HabitTracker.Api.Authentication;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HabitTracker.Api.Controllers;

[ApiController]
[Route("api/invites")]
[Authorize(Policy = BearerTokenDefaults.AdminPolicy)]
public class InvitesController(InviteService _invites, ILogger<InvitesController> _logger)
    : ControllerBase
{
    /// <summary>Mints a 7-day invite code, returned once. No listing endpoint (out of scope).</summary>
    [HttpPost]
    public async Task<ActionResult<InviteDto>> CreateInvite(CancellationToken cancellationToken)
    {
        var invite = await _invites.MintInviteAsync(cancellationToken);
        // Never log the code itself.
        _logger.LogInformation("Minted invite expiring at {ExpiresAt}", invite.ExpiresAt);

        return StatusCode(StatusCodes.Status201Created, invite);
    }
}
