using HabitTracker.Api.Data;
using HabitTracker.Api.Dtos;
using HabitTracker.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace HabitTracker.Api.Services;

/// <summary>
/// Habit CRUD scoped to the current user. Talks to the DbContext directly — at this
/// size DbContext is already a Unit-of-Work + repository, so no extra abstraction.
/// </summary>
public class HabitService
{
    private readonly HabitTrackerDbContext _db;
    private readonly CurrentUser _currentUser;

    public HabitService(HabitTrackerDbContext db, CurrentUser currentUser)
    {
        _db = db;
        _currentUser = currentUser;
    }

    public async Task<IReadOnlyList<HabitDto>> GetHabitsAsync(
        CancellationToken cancellationToken = default
    )
    {
        // Materialize before projecting: the epoch-ms conversion has no SQL translation. The
        // tie-break matches Sync's, so both surfaces agree on roster order (see SyncService).
        var habits = await OwnedHabits()
            .OrderBy(h => h.Position)
            .ThenBy(h => h.CreatedAt)
            .ThenBy(h => h.Id)
            .ToListAsync(cancellationToken);

        return habits.Select(ToDto).ToList();
    }

    public async Task<HabitDto?> GetHabitAsync(
        Guid id,
        CancellationToken cancellationToken = default
    )
    {
        var habit = await FindOwnedAsync(id, cancellationToken);
        return habit is null ? null : ToDto(habit);
    }

    public async Task<HabitDto> CreateHabitAsync(
        CreateHabitRequest request,
        CancellationToken cancellationToken = default
    )
    {
        var maxPosition = await OwnedHabits()
            .Select(h => (int?)h.Position)
            .MaxAsync(cancellationToken);

        var habit = new Habit
        {
            Id = Guid.NewGuid(),
            UserId = _currentUser.UserId,
            Name = request.Name,
            Polarity = request.Polarity,
            Position = (maxPosition ?? -1) + 1,
            EditedAt = DateTimeOffset.UtcNow,
        };

        _db.Habits.Add(habit);
        await _db.SaveChangesAsync(cancellationToken);

        return ToDto(habit);
    }

    public async Task<HabitDto?> UpdateHabitAsync(
        Guid id,
        UpdateHabitRequest request,
        CancellationToken cancellationToken = default
    )
    {
        var habit = await FindOwnedAsync(id, cancellationToken);
        if (habit is null)
        {
            return null;
        }

        habit.Name = request.Name;
        habit.Polarity = request.Polarity;
        habit.Position = request.Position;
        habit.EditedAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync(cancellationToken);

        return ToDto(habit);
    }

    public async Task<bool> DeleteHabitAsync(
        Guid id,
        CancellationToken cancellationToken = default
    )
    {
        var habit = await FindOwnedAsync(id, cancellationToken);
        if (habit is null)
        {
            return false;
        }

        // Soft-delete: a tombstone the next sync can propagate, not a hard delete that would
        // let another device resurrect the habit.
        var now = DateTimeOffset.UtcNow;
        habit.EditedAt = now;
        habit.DeletedAt = now;
        await _db.SaveChangesAsync(cancellationToken);

        return true;
    }


    /// <summary>Alive entries for one owned habit, oldest first. Null when the habit isn't there.</summary>
    public async Task<IReadOnlyList<EntryDto>?> GetEntriesAsync(
        Guid id,
        CancellationToken cancellationToken = default
    )
    {
        var habit = await FindOwnedAsync(id, cancellationToken);
        if (habit is null)
        {
            return null;
        }

        var entries = await _db
            .Entries.Where(e => e.HabitId == habit.Id && e.DeletedAt == null)
            .OrderBy(e => e.Date)
            .ToListAsync(cancellationToken);

        return entries.Select(ToDto).ToList();
    }

    private IQueryable<Habit> OwnedHabits() =>
        _db.Habits.Where(h => h.UserId == _currentUser.UserId && h.DeletedAt == null);

    private Task<Habit?> FindOwnedAsync(Guid id, CancellationToken cancellationToken) =>
        OwnedHabits().FirstOrDefaultAsync(h => h.Id == id, cancellationToken);

    // These endpoints serve alive rows only, so DeletedAt is null on everything they project.
    private static HabitDto ToDto(Habit habit) =>
        new(
            habit.Id,
            habit.Name,
            habit.Polarity,
            habit.Position,
            habit.IsPrivate,
            ToUnixMs(habit.CreatedAt),
            ToUnixMs(habit.EditedAt),
            null
        );

    private static EntryDto ToDto(Entry entry) =>
        new(entry.HabitId, entry.Date, entry.Outcome, ToUnixMs(entry.EditedAt), null);

    private static long ToUnixMs(DateTimeOffset value) => value.ToUnixTimeMilliseconds();
}
