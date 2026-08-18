using HabitTracker.Api.Dtos;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Mvc;

namespace HabitTracker.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SyncController(SyncService _sync, ILogger<SyncController> _logger) : ControllerBase
{
    /// <summary>
    /// One round-trip sync for the current (stub) user: merge the submitted roster + month(s)
    /// last-write-wins by edit-time, then return the authoritative alive state to overwrite local
    /// with. A request whose edit-times run too far ahead of the server clock is refused with a
    /// 400 instead of merged — see <see cref="SyncService.ClockSkewTolerance"/>.
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<SyncResponse>> Sync(
        SyncRequest request,
        CancellationToken cancellationToken
    )
    {
        _logger.LogInformation(
            "Sync received from {CallerAddress}: {HabitCount} habits across months {Months}",
            HttpContext.Connection.RemoteIpAddress,
            request.Habits.Count,
            string.Join(", ", request.Months.Select(m => m.Month))
        );

        try
        {
            var response = await _sync.SyncAsync(request, cancellationToken);

            _logger.LogInformation(
                "Sync returned {HabitCount} habits across {MonthCount} months",
                response.Habits.Count,
                response.Months.Count
            );

            return Ok(response);
        }
        catch (ClockSkewException skew)
        {
            _logger.LogWarning("Sync rejected: {Reason}", skew.Message);

            return BadRequest(
                new ProblemDetails
                {
                    Status = StatusCodes.Status400BadRequest,
                    Title = "Client clock is too far ahead",
                    Detail = skew.Message,
                }
            );
        }
    }
}
