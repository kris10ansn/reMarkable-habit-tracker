using System.ComponentModel.DataAnnotations;
using HabitTracker.Api.Entities;

namespace HabitTracker.Api.Dtos;

// Wire shapes for signup/login/logout, the linked-devices list, invites, and tablet pairing.
//
// Timestamps here are epoch milliseconds UTC, same encoding as HabitDto/EntryDto — but a different
// clock domain. Session/Invite/PairingCode are server-owned rows (see the "server-clock row" note
// on each entity): every timestamp below is the SERVER's clock, stamped by the service that created
// or touched the row, never a value a client supplied. That is the opposite of HabitDto/EntryDto's
// CreatedAt/EditedAt, which are the client's own clock and stored verbatim (see the Edit-time vs.
// audit-clock distinction in apps/backend/CONTEXT.md). Don't reuse these DTOs' fields as a merge key
// — there is no merge here, only server-authoritative rows.
//
// Validation is DataAnnotations on positional records, targeting the constructor PARAMETER — i.e.
// bare `[Required]`, not `[property: Required]`. That's the opposite of the usual "positional
// record attribute" advice: [ApiController] binds a record via its primary constructor and reads
// validation metadata from the parameter, and Microsoft.AspNetCore.Mvc.ModelBinding actively throws
// InvalidOperationException at request time ("has validation metadata defined on property … that
// will be ignored") if it instead finds `[property: ...]` here. Verified empirically against this
// .NET 10 build — get the target right or every one of these requests 500s.

public record UserDto(Guid Id, string Email, string? Name, bool IsAdmin);

/// <summary>
/// The result of signup/login/pairing approval. <see cref="Token"/> is shown to the client exactly
/// once, here — it is never re-readable afterward, only its SHA-256 hash persists server-side.
/// </summary>
public record AuthenticationResponse(UserDto User, string Token);

public record SignupRequest(
    [Required, EmailAddress, MaxLength(256)] string Email,
    // 10-char minimum, no composition rules, per AUTH_PLAN decision 4/defaults.
    [Required, MinLength(10), MaxLength(256)] string Password,
    [Required, MaxLength(120)] string DeviceName,
    [MaxLength(32)] string? InviteCode
);

public record LoginRequest(
    [Required, EmailAddress, MaxLength(256)] string Email,
    // Deliberately no [MinLength] here: enforcing the signup policy on login would leak it and
    // reject a legacy password minted under a since-tightened rule.
    [Required, MaxLength(256)] string Password,
    [Required, MaxLength(120)] string DeviceName
);

public record SessionDto(
    Guid Id,
    string DeviceName,
    long CreatedAt,
    long LastUsedAt,
    bool IsCurrentDevice
);

/// <summary>An invite code, returned once by the minting endpoint (there is no re-read endpoint).</summary>
public record InviteDto(string Code, long ExpiresAt);

public record PairingCodeRequest([Required, MaxLength(120)] string DeviceName);

public record PairingCodeResponse(string Code, long ExpiresAt, int PollIntervalSeconds);

public record PairingCodeStatusRequest([Required, MaxLength(16)] string Code);

/// <summary>
/// One poll's answer. <see cref="Token"/> is non-null on exactly one <see cref="PairingStatus.Approved"/>
/// response — the poll that observes approval deletes the underlying code in the same save, so a
/// second poll finds nothing and reports <see cref="PairingStatus.Expired"/> instead.
/// </summary>
public record PairingPollResponse(PairingStatus Status, string? Token);

/// <summary>What the approving phone sees before it approves: which device asked, and by when.</summary>
public record PairingRequestInfo(string DeviceName, long ExpiresAt);
