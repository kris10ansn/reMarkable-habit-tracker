using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using HabitTracker.Api.Authentication;
using HabitTracker.Api.Data;
using HabitTracker.Api.Entities;
using HabitTracker.Api.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.RateLimiting;
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

    // Describes the bearer scheme and attaches it to every operation except [AllowAnonymous] ones
    // — see the type for why this needs both a document and an operation transformer.
    options.AddDocumentTransformer<BearerSecuritySchemeTransformer>();
    options.AddOperationTransformer<BearerSecuritySchemeTransformer>();
});

builder.Services.AddDbContext<HabitTrackerDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("HabitTracker"))
);

builder.Services.AddHttpContextAccessor();

// PasswordHasher<T> ships in the ASP.NET Core shared framework (Microsoft.Extensions.Identity.Core)
// and is used standalone here — no ASP.NET Identity stack, per AUTH_PLAN decision 4/9.
builder.Services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();

// CurrentUser is the single seam user resolution lives behind (see Services/CurrentUser.cs): a
// scoped factory rebuilds it from the bearer-authenticated principal on every request.
builder.Services.AddScoped(sp =>
    CurrentUser.FromPrincipal(sp.GetRequiredService<IHttpContextAccessor>().HttpContext?.User)
);
builder.Services.AddScoped<HabitService>();
builder.Services.AddScoped<SyncService>();
builder.Services.AddScoped<SessionService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<InviteService>();
builder.Services.AddScoped<PairingService>();

builder
    .Services.AddAuthentication(BearerTokenDefaults.AuthenticationScheme)
    .AddScheme<AuthenticationSchemeOptions, BearerTokenAuthenticationHandler>(
        BearerTokenDefaults.AuthenticationScheme,
        options => { }
    );

builder.Services.AddAuthorization(options =>
{
    // [Authorize] is the default for every endpoint (AUTH_PLAN decision 9); only signup, login,
    // and the two anonymous pairing endpoints opt out with [AllowAnonymous].
    options.FallbackPolicy = new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build();

    options.AddPolicy(
        BearerTokenDefaults.AdminPolicy,
        policy =>
            policy.RequireAuthenticatedUser().RequireClaim(BearerTokenDefaults.IsAdminClaim, "true")
    );
});

// Off by default — only set to true in production (see apps/backend/DEPLOY.md step 5's
// api.env). Trusting a client-settable X-Forwarded-* header is only sound there because Kestrel
// binds 127.0.0.1:5000 via ASPNETCORE_URLS, so only a process on the same host can connect to it
// at all — and that process is cloudflared, so there is no untrusted hop that could forge the
// header before it reaches us. In every other environment (local dev, tests) the connection's own
// RemoteIpAddress is already correct and must not be overridden by a header any caller could set.
var trustProxyHeaders = builder.Configuration.GetValue<bool>("Network:TrustProxyHeaders");

if (trustProxyHeaders)
{
    builder.Services.Configure<ForwardedHeadersOptions>(options =>
    {
        options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;

        // ASP.NET Core only trusts a forwarded header from a proxy in KnownNetworks/KnownProxies;
        // clearing both means "trust whoever connects" instead of listing cloudflared's address
        // explicitly. That's safe ONLY because Kestrel has no other inbound path (see comment
        // above) — bound to 127.0.0.1, "whoever connects" is already narrowed to same-host
        // processes, and cloudflared is structurally the only one that ever does.
        // (KnownIPNetworks is the non-obsolete successor to KnownNetworks as of .NET 10 — same
        // "trusted network allowlist" being cleared.)
        options.KnownIPNetworks.Clear();
        options.KnownProxies.Clear();
    });
}

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    // Every policy below is partitioned per caller (RateLimitPartition.GetFixedWindowLimiter keyed
    // on the caller's IP) rather than registered with AddFixedWindowLimiter, which creates ONE
    // shared limiter for the whole app: a single attacker spending a policy's permits would
    // otherwise lock out every other caller sharing it — every user's login, or the tablet's own
    // pairing polls — until the window rolls over.
    void AddPerCallerFixedWindow(string policyName, int permitLimit, TimeSpan window) =>
        options.AddPolicy<string>(
            policyName,
            httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    PartitionKeyOf(httpContext),
                    _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = permitLimit,
                        Window = window,
                        QueueLimit = 0,
                        AutoReplenishment = true,
                    }
                )
        );

    AddPerCallerFixedWindow(RateLimitPolicies.Authentication, 10, TimeSpan.FromMinutes(5));
    AddPerCallerFixedWindow(RateLimitPolicies.PairingCodeRequest, 10, TimeSpan.FromMinutes(5));

    // The tablet polls every 3s while its settings page is visible (20/min), so 40/min leaves room
    // for a second device polling concurrently. Against a 32^6 ≈ 1.07e9-code space, a brute-forcer
    // capped here gets at most ~200 guesses over a code's whole 5-minute life — nowhere close.
    AddPerCallerFixedWindow(RateLimitPolicies.PairingPoll, 40, TimeSpan.FromMinutes(1));

    // Guards the authenticated pairing lookup/approve endpoints (see RateLimitPolicies.PairingApproval
    // for why these can't be partitioned by user id instead).
    AddPerCallerFixedWindow(RateLimitPolicies.PairingApproval, 30, TimeSpan.FromMinutes(5));

    options.OnRejected = (context, cancellationToken) =>
    {
        context.HttpContext.RequestServices.GetRequiredService<ILogger<Program>>()
            .LogWarning(
                "Rate limit exceeded for {CallerAddress} on {Path}",
                context.HttpContext.Connection.RemoteIpAddress,
                context.HttpContext.Request.Path
            );

        return ValueTask.CompletedTask;
    };
});

// Shared by every partitioned rate-limit policy above: with UseForwardedHeaders wired in (see
// trustProxyHeaders), this reads the real client IP forwarded by cloudflared instead of
// cloudflared's own loopback address, which would otherwise collapse every caller into one
// partition.
static string PartitionKeyOf(HttpContext httpContext) =>
    httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";

builder.Logging.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "HH:mm:ss ";
});

var app = builder.Build();

// Must run before anything else touches the connection's remote address (including
// UseHttpsRedirection, which otherwise redirects based on cloudflared's own scheme) — see the
// trustProxyHeaders comment above for why this is safe only because cloudflared is the sole
// process able to reach Kestrel's loopback binding.
if (trustProxyHeaders)
{
    app.UseForwardedHeaders();
}

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    // Anonymous: the fallback authorization policy otherwise locks a developer out of the API docs.
    app.MapOpenApi().AllowAnonymous();
    app.MapScalarApiReference().AllowAnonymous();
}

app.UseHttpsRedirection();

app.UseRateLimiter();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

// Top-level statements generate an `internal` Program class by default. Microsoft.AspNetCore.
// Mvc.Testing's WebApplicationFactory<TEntryPoint> (used by the HTTP-level auth tests) needs a
// `public` one to reference as the test host's entry point — this partial declaration only
// widens visibility, it adds no behaviour.
public partial class Program { }
