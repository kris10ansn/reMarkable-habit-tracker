using System.Globalization;
using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Services;

/// <summary>
/// State-based, last-write-wins sync for the current user. The client submits its
/// roster plus the month(s) it holds — alive rows and tombstones, each carrying a UTC edit-time —
/// and the server merges per row by edit-time, then returns the authoritative ALIVE state for the
/// client to overwrite local with. Tombstones live durably here, never in the response.
/// </summary>
public class SyncService
{
    /// <summary>
    /// How far ahead of the server clock a submitted edit-time may run before the whole Sync is
    /// refused. Generous, because a device that has been asleep drifts; the point is to catch a
    /// clock that is wrong by a wide margin, not to police seconds.
    /// </summary>
    public static readonly TimeSpan ClockSkewTolerance = TimeSpan.FromMinutes(5);

    private readonly HabitTrackerDbContext _db;
    private readonly CurrentUser _currentUser;
    private readonly ILogger<SyncService> _logger;

    public SyncService(
        HabitTrackerDbContext db,
        CurrentUser currentUser,
        ILogger<SyncService> logger
    )
    {
        _db = db;
        _currentUser = currentUser;
        _logger = logger;
    }

    public async Task<SyncResponse> SyncAsync(
        SyncRequest request,
        CancellationToken cancellationToken = default
    )
    {
        RejectSkewedEditTimes(request);

        var habitCounts = await MergeHabitsAsync(request.Habits, cancellationToken);
        await _db.SaveChangesAsync(cancellationToken);

        var entryCounts = await MergeEntriesAsync(request.Months, cancellationToken);
        await _db.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "Merged habits: {HabitsCreated} created, {HabitsUpdated} updated, {HabitsUnchanged} unchanged ({HabitTombstones} tombstones); entries: {EntriesCreated} created, {EntriesUpdated} updated, {EntriesUnchanged} unchanged, {EntriesDropped} dropped (unowned habit)",
            habitCounts.Created,
            habitCounts.Updated,
            habitCounts.Unchanged,
            habitCounts.Tombstones,
            entryCounts.Created,
            entryCounts.Updated,
            entryCounts.Unchanged,
            entryCounts.Dropped
        );

        return await BuildResponseAsync(request.Months, cancellationToken);
    }

    /// <summary>
    /// Counts of what a merge did to the store, for the one-line summary logged in
    /// <see cref="SyncAsync"/>. Not part of the wire contract — purely for observability.
    /// </summary>
    private readonly record struct HabitMergeCounts(
        int Created,
        int Updated,
        int Unchanged,
        int Tombstones
    );

    private readonly record struct EntryMergeCounts(
        int Created,
        int Updated,
        int Unchanged,
        int Dropped
    );

    private async Task<HabitMergeCounts> MergeHabitsAsync(
        IReadOnlyList<HabitDto> incoming,
        CancellationToken cancellationToken
    )
    {
        var existing = await _db
            .Habits.Where(h => h.UserId == _currentUser.UserId)
            .ToDictionaryAsync(h => h.Id, cancellationToken);

        int created = 0,
            updated = 0,
            unchanged = 0,
            tombstones = 0;

        foreach (var dto in incoming)
        {
            var editedAt = FromUnixMs(dto.EditedAt);

            if (!existing.TryGetValue(dto.Id, out var habit))
            {
                _db.Habits.Add(
                    new Habit
                    {
                        Id = dto.Id,
                        UserId = _currentUser.UserId,
                        Name = dto.Name,
                        Polarity = dto.Polarity,
                        Position = dto.Position,
                        IsPrivate = dto.IsPrivate,
                        // Verbatim: the creating client owns the create-time (see ITimestamped).
                        CreatedAt = FromUnixMs(dto.CreatedAt),
                        EditedAt = editedAt,
                        DeletedAt = FromUnixMsOrNull(dto.DeletedAt),
                    }
                );
                created++;
                if (dto.DeletedAt is not null)
                {
                    tombstones++;
                }
                continue;
            }

            if (editedAt <= habit.EditedAt)
            {
                unchanged++;
                continue; // stored row is newer-or-equal — it wins
            }

            habit.EditedAt = editedAt;
            habit.DeletedAt = FromUnixMsOrNull(dto.DeletedAt);

            if (dto.DeletedAt is null)
            {
                habit.Name = dto.Name;
                habit.Polarity = dto.Polarity;
                habit.Position = dto.Position;
                habit.IsPrivate = dto.IsPrivate;
            }
            else
            {
                tombstones++;
            }

            updated++;
        }

        return new HabitMergeCounts(created, updated, unchanged, tombstones);
    }

    private async Task<EntryMergeCounts> MergeEntriesAsync(
        IReadOnlyList<SyncMonth> months,
        CancellationToken cancellationToken
    )
    {
        var ownedHabitIds = (
            await _db
                .Habits.Where(h => h.UserId == _currentUser.UserId)
                .Select(h => h.Id)
                .ToListAsync(cancellationToken)
        ).ToHashSet();

        var allIncoming = months.SelectMany(m => m.Entries).ToList();
        var incoming = allIncoming.Where(e => ownedHabitIds.Contains(e.HabitId)).ToList();
        var dropped = allIncoming.Count - incoming.Count;

        if (incoming.Count == 0)
        {
            return new EntryMergeCounts(0, 0, 0, dropped);
        }

        var habitIds = incoming.Select(e => e.HabitId).Distinct().ToList();
        var dates = incoming.Select(e => e.Date).Distinct().ToList();
        var existing = (
            await _db
                .Entries.Where(e => habitIds.Contains(e.HabitId) && dates.Contains(e.Date))
                .ToListAsync(cancellationToken)
        ).ToDictionary(e => (e.HabitId, e.Date));

        int created = 0,
            updated = 0,
            unchanged = 0;

        foreach (var dto in incoming)
        {
            var editedAt = FromUnixMs(dto.EditedAt);

            if (!existing.TryGetValue((dto.HabitId, dto.Date), out var entry))
            {
                _db.Entries.Add(
                    new Entry
                    {
                        HabitId = dto.HabitId,
                        Date = dto.Date,
                        Outcome = dto.Outcome,
                        EditedAt = editedAt,
                        DeletedAt = FromUnixMsOrNull(dto.DeletedAt),
                    }
                );
                created++;
                continue;
            }

            if (editedAt <= entry.EditedAt)
            {
                unchanged++;
                continue;
            }

            entry.EditedAt = editedAt;
            entry.DeletedAt = FromUnixMsOrNull(dto.DeletedAt);

            if (dto.DeletedAt is null)
            {
                entry.Outcome = dto.Outcome;
            }

            updated++;
        }

        return new EntryMergeCounts(created, updated, unchanged, dropped);
    }

    private async Task<SyncResponse> BuildResponseAsync(
        IReadOnlyList<SyncMonth> months,
        CancellationToken cancellationToken
    )
    {
        // Position alone is not a total order: two clients editing offline can both mint a habit at
        // the same position, and the merge stores each verbatim. Break the tie deterministically so
        // every client that syncs sees the same roster order rather than whatever the database
        // happened to return.
        var habitEntities = await _db
            .Habits.Where(h => h.UserId == _currentUser.UserId && h.DeletedAt == null)
            .OrderBy(h => h.Position)
            .ThenBy(h => h.CreatedAt)
            .ThenBy(h => h.Id)
            .ToListAsync(cancellationToken);

        // Alive rows only, so every DeletedAt below is null — a delete reaches the client as absence.
        var habits = habitEntities
            .Select(h => new HabitDto(
                h.Id,
                h.Name,
                h.Polarity,
                h.Position,
                h.IsPrivate,
                ToUnixMs(h.CreatedAt),
                ToUnixMs(h.EditedAt),
                null
            ))
            .ToList();

        var responseMonths = new List<SyncMonth>();
        foreach (var month in months)
        {
            var (start, end) = MonthRange(month.Month);

            var entryEntities = await _db
                .Entries.Where(e =>
                    e.Habit.UserId == _currentUser.UserId
                    && e.Habit.DeletedAt == null
                    && e.DeletedAt == null
                    && e.Date >= start
                    && e.Date < end
                )
                .ToListAsync(cancellationToken);

            var entries = entryEntities
                .Select(e => new EntryDto(e.HabitId, e.Date, e.Outcome, ToUnixMs(e.EditedAt), null))
                .ToList();

            responseMonths.Add(new SyncMonth(month.Month, entries));
        }

        return new SyncResponse(habits, responseMonths);
    }

    private static (DateOnly start, DateOnly end) MonthRange(string month)
    {
        var start = DateOnly.ParseExact(month + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture);
        return (start, start.AddMonths(1));
    }

    /// <summary>
    /// Refuse a Sync whose newest edit-time runs further ahead of the server than
    /// <see cref="ClockSkewTolerance"/>. A client stamps its edit-time before the request leaves
    /// the device, so a future one means a fast clock — and since edit-time is the only value a
    /// merge compares, a badly skewed one would out-rank every later edit until wall-clock caught
    /// up. Refusing keeps that out of the store; drift inside the tolerance is merged but logged.
    /// </summary>
    private void RejectSkewedEditTimes(SyncRequest request)
    {
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var skewMs = request.LatestEditedAt(nowMs) - nowMs;

        if (skewMs <= 0)
        {
            return;
        }

        if (skewMs > (long)ClockSkewTolerance.TotalMilliseconds)
        {
            throw new ClockSkewException(skewMs, ClockSkewTolerance);
        }

        _logger.LogWarning(
            "Client clock runs {SkewMs}ms ahead of the server; edit-time is the merge key, so this drift decides conflicts",
            skewMs
        );
    }

    private static DateTimeOffset FromUnixMs(long ms) => DateTimeOffset.FromUnixTimeMilliseconds(ms);

    private static DateTimeOffset? FromUnixMsOrNull(long? ms) =>
        ms is null ? null : FromUnixMs(ms.Value);

    private static long ToUnixMs(DateTimeOffset value) => value.ToUnixTimeMilliseconds();
}
