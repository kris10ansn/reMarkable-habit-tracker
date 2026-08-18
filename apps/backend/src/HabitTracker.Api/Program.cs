using System.Text.Json.Serialization;
using HabitTracker.Api.Data;
using HabitTracker.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder
    .Services.AddControllers()
    .AddJsonOptions(options =>
        options.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter())
    );

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi(options =>
{
    // .NET 10 describes every integer as `type: ["integer", "string"]` with a digits pattern,
    // because the Web API default `JsonNumberHandling.AllowReadingFromString` means a quoted
    // number would also be accepted on the way IN. Responses only ever emit real JSON numbers, and
    // one schema describes both directions, so the union makes every client generate
    // `number | string` for fields that are always numbers — `editedAt`, `position`, `deletedAt`.
    //
    // Narrow the document back to `integer` (keeping a nullable's `null` member). This rewrites the
    // description only: the API still accepts a quoted number at runtime, it just no longer
    // advertises it and no longer forces that slack onto every generated client.
    options.AddSchemaTransformer(
        (schema, context, cancellationToken) =>
        {
            if (
                schema.Type is { } type
                && type.HasFlag(JsonSchemaType.Integer)
                && type.HasFlag(JsonSchemaType.String)
            )
            {
                schema.Type = type & ~JsonSchemaType.String;
                schema.Pattern = null;
            }

            return Task.CompletedTask;
        }
    );
});

builder.Services.AddDbContext<HabitTrackerDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("HabitTracker"))
);

// Auth is deferred: every request acts as the seeded stub user (see CurrentUser).
builder.Services.AddScoped<CurrentUser>();
builder.Services.AddScoped<HabitService>();
builder.Services.AddScoped<SyncService>();

builder.Logging.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "HH:mm:ss ";
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();

app.Run();
