using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using HabitTracker.Api.Dtos;

namespace HabitTracker.Api.Tests;

/// <summary>
/// HTTP-level coverage for what only the ASP.NET Core pipeline can prove — the fallback
/// authorization policy and the rate limiter are middleware, unreachable by constructing a
/// controller directly the way the rest of this suite does. Everything here goes through
/// <see cref="AuthTestWebApplicationFactory"/>, which swaps in the EF Core in-memory provider so
/// no Docker/Postgres is needed (apps/backend/CLAUDE.md).
/// </summary>
public class AuthEndpointsTests
{
    private static async Task<string> SignUpAndGetTokenAsync(
        HttpClient client,
        string email,
        string password,
        string deviceName,
        string? inviteCode = null
    )
    {
        var response = await client.PostAsJsonAsync(
            "/api/auth/signup",
            new SignupRequest(email, password, deviceName, inviteCode)
        );
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<AuthenticationResponse>();
        return body!.Token;
    }

    private static void Authorize(HttpClient client, string token) =>
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

    [Fact]
    public async Task ProtectedEndpoints_WithNoAuthorizationHeader_Return401()
    {
        using var factory = new AuthTestWebApplicationFactory();
        using var client = factory.CreateClient();

        foreach (var (method, path) in ProtectedEndpoints())
        {
            var response = await client.SendAsync(new HttpRequestMessage(method, path));
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
    }

    [Fact]
    public async Task ProtectedEndpoints_WithAGarbageBearerToken_Return401()
    {
        using var factory = new AuthTestWebApplicationFactory();
        using var client = factory.CreateClient();
        Authorize(client, "this-token-was-never-issued");

        foreach (var (method, path) in ProtectedEndpoints())
        {
            var response = await client.SendAsync(new HttpRequestMessage(method, path));
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
    }

    private static IEnumerable<(HttpMethod Method, string Path)> ProtectedEndpoints()
    {
        yield return (HttpMethod.Get, "/api/habits");
        yield return (HttpMethod.Post, "/api/sync");
        yield return (HttpMethod.Get, "/api/sessions");
        yield return (HttpMethod.Post, "/api/pairing/approve");
    }

    [Fact]
    public async Task GetHabits_WithATokenFromSignup_Returns200()
    {
        using var factory = new AuthTestWebApplicationFactory();
        using var client = factory.CreateClient();
        var token = await SignUpAndGetTokenAsync(
            client,
            "owner@example.com",
            "correct-horse-battery",
            "Laptop"
        );
        Authorize(client, token);

        var response = await client.GetAsync("/api/habits");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Signup_WithA9CharacterPassword_Returns400_ButA10CharacterPasswordIsAccepted()
    {
        // The minimum length is enforced by [MinLength(10)] DataAnnotations on SignupRequest (see
        // Dtos/AuthDtos.cs) — [ApiController]'s automatic ModelState validation is what turns a
        // violation into this 400, not AuthService. That's the layer this test pins.
        using var factory = new AuthTestWebApplicationFactory();
        using var client = factory.CreateClient();

        var tooShort = await client.PostAsJsonAsync(
            "/api/auth/signup",
            new SignupRequest("short@example.com", "123456789", "Device", null)
        );
        Assert.Equal(HttpStatusCode.BadRequest, tooShort.StatusCode);

        var longEnough = await client.PostAsJsonAsync(
            "/api/auth/signup",
            new SignupRequest("long-enough@example.com", "1234567890", "Device", null)
        );
        Assert.Equal(HttpStatusCode.OK, longEnough.StatusCode);
    }

    [Fact]
    public async Task CreateInvite_Returns403ForASignedInNonAdmin_SucceedsForAnAdmin_And401Anonymous()
    {
        using var factory = new AuthTestWebApplicationFactory();

        // First signup bootstraps the admin (empty Users table, AUTH_PLAN decision 3).
        using var adminClient = factory.CreateClient();
        var adminToken = await SignUpAndGetTokenAsync(
            adminClient,
            "admin@example.com",
            "admin-password-long",
            "Admin Device"
        );
        Authorize(adminClient, adminToken);

        var mintedByAdmin = await adminClient.PostAsync("/api/invites", null);
        Assert.Equal(HttpStatusCode.Created, mintedByAdmin.StatusCode);
        var invite = await mintedByAdmin.Content.ReadFromJsonAsync<InviteDto>();

        // A second, non-admin user signs up using the invite the admin just minted.
        using var memberClient = factory.CreateClient();
        var memberToken = await SignUpAndGetTokenAsync(
            memberClient,
            "member@example.com",
            "member-password-long",
            "Member Device",
            invite!.Code
        );
        Authorize(memberClient, memberToken);

        var deniedForMember = await memberClient.PostAsync("/api/invites", null);
        Assert.Equal(HttpStatusCode.Forbidden, deniedForMember.StatusCode);

        using var anonymousClient = factory.CreateClient();
        var deniedAnonymous = await anonymousClient.PostAsync("/api/invites", null);
        Assert.Equal(HttpStatusCode.Unauthorized, deniedAnonymous.StatusCode);
    }

    [Fact]
    public async Task Login_ExceedingThePermitLimit_Returns429ForTheSurplusRequests()
    {
        // Own factory instance (not shared with any other test in this class) so this burst of
        // login attempts can't spend permits from — or be starved by — another test's rate-limit
        // partition.
        //
        // RateLimitPolicies.Authentication partitions per caller IP (Program.cs's PartitionKeyOf,
        // keyed on HttpContext.Connection.RemoteIpAddress). Under WebApplicationFactory's in-process
        // TestServer there is no real remote endpoint, so RemoteIpAddress is null for every request
        // and PartitionKeyOf's fallback ("unknown") gives every request in this test the SAME
        // partition key. That collapse is a property of the in-process test host, not a bug in the
        // limiter — a real deployment sees distinct caller IPs — so this test relies on the
        // collapse (it's what makes one client's burst hit one shared bucket) rather than working
        // around it.
        using var factory = new AuthTestWebApplicationFactory();
        using var client = factory.CreateClient();

        // An unknown email fails fast in AuthService (no password hash to verify), which keeps
        // this test's 15 sequential requests cheap; the limiter only counts requests, not outcomes.
        var login = new LoginRequest("nobody@example.com", "wrong-password-1234", "Device");

        var statusCodes = new List<HttpStatusCode>();
        for (var i = 0; i < 15; i++)
        {
            var response = await client.PostAsJsonAsync("/api/auth/login", login);
            statusCodes.Add(response.StatusCode);
        }

        // RateLimitPolicies.Authentication: 10 permits per 5-minute window.
        Assert.Equal(10, statusCodes.Count(s => s == HttpStatusCode.Unauthorized));
        Assert.Equal(5, statusCodes.Count(s => s == HttpStatusCode.TooManyRequests));
    }
}
