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
                return Conflict(
                    new ProblemDetails
                    {
                        Status = StatusCodes.Status409Conflict,
                        Title = "Email already registered.",
                    }
                );

            case SignupOutcome.InviteRequired:
                _logger.LogInformation("Signup rejected: invite code required");
                return BadRequest(
                    new ProblemDetails
                    {
                        Status = StatusCodes.Status400BadRequest,
                        Title = "An invite code is required.",
                    }
                );

            case SignupOutcome.InviteInvalid:
                _logger.LogInformation("Signup rejected: invite code invalid, used, or expired");
                return BadRequest(
                    new ProblemDetails
                    {
                        Status = StatusCodes.Status400BadRequest,
                        Title = "The invite code is invalid, already used, or expired.",
                    }
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
            return Unauthorized(
                new ProblemDetails
                {
                    Status = StatusCodes.Status401Unauthorized,
                    Title = "Invalid email or password.",
                }
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
