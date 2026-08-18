.import "Entries.js" as Entries

// Projections of the in-memory habits ListModel onto serializable shapes. The model is the single
// source of truth; each store serializes its own slice. Habit rows carry identity + config +
// create-time + an editedAt edit-time; entries are normalized rows held per habit by date key.

function toSuspendHabits(model) {
    if (!model || typeof model.count !== "number") return [];

    const out = [];
    for (let i = 0; i < model.count; i++) {
        const habit = model.get(i);
        out.push({
            name: habit.name,
            polarity: habit.polarity,
            isPrivate: !!habit.isPrivate,
            entries: Entries.outcomesByDate(habit.entriesByDate),
        });
    }
    return out;
}

// Model rows are always alive, so `deletedAt` is null for them; HabitsStore keeps tombstoned rows
// of this same shape in habitTombstones.
function rosterRow(habit) {
    return {
        id: habit.id,
        name: habit.name,
        polarity: habit.polarity,
        isPrivate: !!habit.isPrivate,
        createdAt: habit.createdAt,
        editedAt: habit.editedAt,
        deletedAt: habit.deletedAt || null,
    };
}

// Array order is Position.
function toRoster(model) {
    if (!model || typeof model.count !== "number") return [];

    const out = [];
    for (let i = 0; i < model.count; i++) {
        out.push(rosterRow(model.get(i)));
    }
    return out;
}

// Tombstones are kept — they are what the next sync pushes. Rows whose habit is no longer in the
// roster are dropped, which is how a deleted habit's entries eventually leave the month files
// (see ADR 0002).
function toMonthEntryRows(model) {
    if (!model || typeof model.count !== "number") return [];

    const rows = [];
    for (let i = 0; i < model.count; i++) {
        const entriesByDate = model.get(i).entriesByDate || {};
        Object.keys(entriesByDate).forEach((dateKey) => rows.push(entriesByDate[dateKey]));
    }
    return rows;
}
