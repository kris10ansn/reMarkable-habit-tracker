using System.Text.Json;
using System.Text.Json.Serialization;
using HabitTracker.Api.Controllers;
using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace HabitTracker.Api.Tests;

public class SyncControllerTests
{
    private static HabitTrackerDbContext NewDb() => SyncTestContext.NewDb("sync-controller");

    private static SyncController NewController(HabitTrackerDbContext db) =>
        new(
            new SyncService(db, new CurrentUser(), NullLogger<SyncService>.Instance),
            NullLogger<SyncController>.Instance
        )
        {
            // Outside the MVC pipeline HttpContext is null by default; the controller now reads
            // HttpContext.Connection.RemoteIpAddress for the sync-source log line, so give it one.
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
        };

    private static SyncRequest OneHabitAt(long editedAt) =>
        new(
            [
                new HabitDto(
                    Guid.NewGuid(),
                    "Read",
                    Polarity.Positive,
                    0,
                    false,
                    editedAt,
                    editedAt,
                    null
                ),
            ],
            []
        );

    [Fact]
    public async Task Sync_ReturnsTheAuthoritativeState()
    {
        using var db = NewDb();
        var controller = NewController(db);

        var result = await controller.Sync(
            OneHabitAt(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()),
            CancellationToken.None
        );

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var response = Assert.IsType<SyncResponse>(ok.Value);
        Assert.Equal("Read", Assert.Single(response.Habits).Name);
    }

    [Fact]
    public async Task Sync_TurnsAnUnusableClientClockIntoABadRequest()
    {
        using var db = NewDb();
        var controller = NewController(db);

        var result = await controller.Sync(
            OneHabitAt(SyncTestContext.FarAheadEditTime()),
            CancellationToken.None
        );

        var badRequest = Assert.IsType<BadRequestObjectResult>(result.Result);
        var problem = Assert.IsType<ProblemDetails>(badRequest.Value);
        Assert.Equal(400, problem.Status);
        Assert.Empty(db.Habits);
    }

    [Fact]
    public async Task Sync_AHabitJsonOmittingIsPrivate_BindsToFalse_AndSucceeds()
    {
        // Pins System.Text.Json's positional-record default binding: an old client's payload that
        // predates the field must still deserialize and sync, rather than throwing or failing to bind.
        using var db = NewDb();
        var controller = NewController(db);
        var editedAt = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        var json =
            $$"""
            {
                "habits": [
                    {
                        "id": "{{Guid.NewGuid()}}",
                        "name": "Read",
                        "polarity": "Positive",
                        "position": 0,
                        "createdAt": {{editedAt}},
                        "editedAt": {{editedAt}},
                        "deletedAt": null
                    }
                ],
                "months": []
            }
            """;
        var jsonOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        jsonOptions.Converters.Add(new JsonStringEnumConverter());
        var request = JsonSerializer.Deserialize<SyncRequest>(json, jsonOptions)!;
        Assert.False(Assert.Single(request.Habits).IsPrivate);

        var result = await controller.Sync(request, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var response = Assert.IsType<SyncResponse>(ok.Value);
        Assert.False(Assert.Single(response.Habits).IsPrivate);
    }
}
