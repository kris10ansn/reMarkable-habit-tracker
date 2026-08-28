using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace HabitTracker.Api.Services;

/// <summary>
/// The only crypto in the app. Bearer session tokens, their storage hash, and the human-readable
/// codes used by invites and tablet pairing all originate here — nothing else may call
/// <see cref="SHA256"/>, <see cref="RandomNumberGenerator"/>, or <see cref="Random"/> for auth
/// purposes.
/// </summary>
public static class AuthTokens
{
    /// <summary>
    /// 32 unambiguous characters for human-typed codes (invites, pairing). Deliberately excludes
    /// <c>0</c>/<c>O</c> and <c>1</c>/<c>I</c>, which are easy to confuse with each other on a
    /// small e-ink screen — a person copying a pairing code off a reMarkable display should never
    /// have to guess which glyph they're looking at.
    /// </summary>
    public const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    /// <summary>
    /// A fresh 256-bit bearer session token, URL-safe base64 encoded. Returned to a client exactly
    /// once (at signup, login, or the pairing poll that observes approval) and never stored —
    /// <see cref="HashToken"/> is what persists.
    /// </summary>
    public static string NewSessionToken() => Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));

    /// <summary>
    /// Lowercase hex SHA-256 of <paramref name="token"/> — always 64 characters, which is why
    /// <c>Session.TokenHash</c> is <c>maxLength: 64</c>. Plain SHA-256 (not a password KDF like
    /// PBKDF2/bcrypt) is the right tool here, and only here, because the input is a 256-bit random
    /// token with no guessable structure, not a human-chosen secret — there is nothing for a slow
    /// hash to protect against that a fast one doesn't already defeat via the token's own entropy.
    /// </summary>
    public static string HashToken(string token) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    /// <summary>A 6-character tablet pairing code, readable off an e-ink screen.</summary>
    public static string NewPairingCode() => NewCode(6);

    /// <summary>A 12-character single-use invite code.</summary>
    public static string NewInviteCode() => NewCode(12);

    private static string NewCode(int length) =>
        new(RandomNumberGenerator.GetItems<char>(CodeAlphabet, length));

    /// <summary>
    /// Normalizes a user-typed invite or pairing code before comparing it against the database:
    /// trims surrounding whitespace, then upper-cases. Lossless because <see cref="CodeAlphabet"/>
    /// is uppercase-only, so no valid code is altered by upper-casing — this only rescues the common
    /// case of a phone keyboard auto-lowercasing what the tablet displays in uppercase. Never apply
    /// this to a bearer token, which is case-sensitive base64.
    /// </summary>
    public static string NormalizeCode(string code) => code.Trim().ToUpperInvariant();
}
