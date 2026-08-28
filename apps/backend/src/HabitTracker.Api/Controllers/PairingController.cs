using HabitTracker.Api.Authentication;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HabitTracker.Api.Controllers;

[ApiController]
[Route("api/pairing")]
public class PairingController(PairingService _pairing, ILogger<PairingController> _logger)
    : ControllerBase
{
    /// <summary>Unauthenticated: a device (the tablet) requests a code to display and poll.</summary>
    [HttpPost("code")]
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.PairingCodeRequest)]
    public async Task<ActionResult<PairingCodeResponse>> RequestCode(
        PairingCodeRequest request,
        CancellationToken cancellationToken
    )
    {
        var response = await _pairing.RequestCodeAsync(request.DeviceName, cancellationToken);
        // Never log the code itself.
        _logger.LogInformation("Issued pairing code for device {DeviceName}", request.DeviceName);

        return Ok(response);
    }

    /// <summary>Unauthenticated: the requesting device polls for approval.</summary>
    [HttpPost("poll")]
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.PairingPoll)]
    public async Task<ActionResult<PairingPollResponse>> Poll(
        PairingCodeStatusRequest request,
        CancellationToken cancellationToken
    )
    {
        var response = await _pairing.PollAsync(request.Code, cancellationToken);
        return Ok(response);
    }

    /// <summary>
    /// Authenticated: what the approving phone sees before approving — which device asked, and by
    /// when the code expires. Beyond the plan's endpoint table: decision 6 requires showing the
    /// requesting device's name before approval, which the other three endpoints can't satisfy.
    /// </summary>
    [HttpGet("{code}")]
    [EnableRateLimiting(RateLimitPolicies.PairingApproval)]
    public async Task<ActionResult<PairingRequestInfo>> GetPairingRequest(
        string code,
        CancellationToken cancellationToken
    )
    {
        var info = await _pairing.LookupAsync(code, cancellationToken);
        if (info is null)
        {
            _logger.LogInformation("Pairing code not found or expired for lookup");
            return NotFound();
        }

        return Ok(info);
    }

    /// <summary>Authenticated: the phone approves. Mints no token and creates no session.</summary>
    [HttpPost("approve")]
    [EnableRateLimiting(RateLimitPolicies.PairingApproval)]
    public async Task<IActionResult> Approve(
        PairingCodeStatusRequest request,
        CancellationToken cancellationToken
    )
    {
        var outcome = await _pairing.ApproveAsync(request.Code, cancellationToken);
        _logger.LogInformation("Pairing approval outcome: {Outcome}", outcome);

        return outcome switch
        {
            PairingApprovalOutcome.Approved => NoContent(),
            PairingApprovalOutcome.NotFound => NotFound(),
            PairingApprovalOutcome.Expired => NotFound(),
            PairingApprovalOutcome.AlreadyApproved => Conflict(),
            _ => throw new InvalidOperationException($"Unhandled pairing approval outcome: {outcome}"),
        };
    }
}
