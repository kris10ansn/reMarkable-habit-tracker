using System.Text.Json.Serialization;

namespace HabitTracker.Api.Entities;

/// <summary>
/// What a tablet's poll of a <see cref="PairingCode"/> reports back. Not a column on
/// <see cref="PairingCode"/> itself — the row's presence/expiry/approval state is derived into one
/// of these by <see cref="Services.PairingService.PollAsync"/>.
/// </summary>
// Same reasoning as Outcome/Polarity: declaring the string encoding on the type is what puts
// member names verbatim ("Pending"/"Approved"/"Expired") in the OpenAPI document.
[JsonConverter(typeof(JsonStringEnumConverter<PairingStatus>))]
public enum PairingStatus
{
    Pending,
    Approved,
    Expired,
}
