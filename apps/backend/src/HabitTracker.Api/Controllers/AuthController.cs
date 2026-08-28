using HabitTracker.Api.Authentication;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HabitTracker.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(AuthService _auth, ILogger<AuthController> _logger) : ControllerBase
{
    [HttpPost("signup")]
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Authentication)]
    public async Task<ActionResult<AuthenticationResponse>> Signup(
        SignupRequest request,
        CancellationToken cancellationToken
    )
    {
        var result = await _auth.SignupAsync(request, cancellationToken);

        switch (result.Outcome)
        {
            case SignupOutcome.Success:
                _logger.LogInformation("Signed up user {UserId}", result.Response!.User.Id);
                return Ok(result.Response);

            case SignupOutcome.EmailAlreadyRegistered:
                _logger.LogInformation("Signup rejected: email already registered");
                return Problem(
                    title: "Email already registered.",
                    statusCode: StatusCodes.Status409Conflict
                );

            case SignupOutcome.InviteRequired:
                _logger.LogInformation("Signup rejected: invite code required");
                return Problem(
                    title: "An invite code is required.",
                    statusCode: StatusCodes.Status400BadRequest
                );

            case SignupOutcome.InviteInvalid:
                _logger.LogInformation("Signup rejected: invite code invalid, used, or expired");
                return Problem(
                    title: "The invite code is invalid, already used, or expired.",
                    statusCode: StatusCodes.Status400BadRequest
                );

            default:
                throw new InvalidOperationException($"Unhandled signup outcome: {result.Outcome}");
        }
    }

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting(RateLimitPolicies.Authentication)]
    public async Task<ActionResult<AuthenticationResponse>> Login(
        LoginRequest request,
        CancellationToken cancellationToken
    )
    {
        var response = await _auth.LoginAsync(request, cancellationToken);
        if (response is null)
        {
            // Same 401 for "no such email" and "wrong password" — a distinct message either way
            // would let a caller enumerate registered emails.
            _logger.LogInformation("Login failed");
            return Problem(
                title: "Invalid email or password.",
                statusCode: StatusCodes.Status401Unauthorized
            );
        }

        _logger.LogInformation("Logged in user {UserId}", response.User.Id);
        return Ok(response);
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout(CancellationToken cancellationToken)
    {
        await _auth.LogoutAsync(cancellationToken);
        return NoContent();
    }
}
