.import "Entries.js" as Entries

// Translation between the client's roster/month state and the backend sync wire format.
// Pure functions only — the QML SyncStore does the I/O. Timestamps are epoch ms UTC.
// The wire spells every shared field exactly as this client stores it — polarity, isPrivate,
// createdAt, editedAt, deletedAt alike — so what is left at this edge is small: the X/O <-> Outcome
// mapping (a deliberate on-disk spelling, ADR 0005) and Position as the roster index.

const SUCCESS = "Success";
const FAILURE = "Failure";

const outcomeToWire = (outcome) => (outcome === Entries.X ? SUCCESS : FAILURE);
const outcomeFromWire = (outcome) => (outcome === SUCCESS ? Entries.X : Entries.O);

// Build the sync request. roster: alive habit rows in display order (index becomes Position).
// tombstones: soft-deleted habit rows carrying deletedAt. entryRows: the viewed month's entry rows,
// tombstones included — a row with deletedAt becomes a deleted entry.
function buildRequest(roster, tombstones, entryRows, monthKey) {
    const habits = (roster || []).map((habit, position) => ({
        id: habit.id,
        name: habit.name,
        polarity: habit.polarity,
        isPrivate: !!habit.isPrivate,
        position: position,
        createdAt: habit.createdAt,
        editedAt: habit.editedAt,
        deletedAt: null,
    }));

    // A tombstone's payload fields are ignored by the merge, so its position is not meaningful.
    const habitTombstones = (tombstones || []).map((tombstone) => ({
        id: tombstone.id,
        name: tombstone.name,
        polarity: tombstone.polarity,
        isPrivate: !!tombstone.isPrivate,
        position: 0,
        createdAt: tombstone.createdAt,
        editedAt: tombstone.editedAt,
        deletedAt: tombstone.deletedAt,
    }));

    return {
        habits: habits.concat(habitTombstones),
        months: [
            { month: monthKey, entries: (entryRows || []).map(entryToWire) },
        ],
    };
}

const entryToWire = (row) => ({
    habitId: row.habitId,
    date: row.date,
    outcome: outcomeToWire(row.outcome),
    editedAt: row.editedAt,
    deletedAt: row.deletedAt || null,
});

// Fold an authoritative response into the shapes HabitsStore.applySynced wants: roster habit rows
// (already in the server's Position order) and entriesByHabitId { habitId: { dateKey: row } } for
// the given month. The response carries alive rows only, so every row folds in with deletedAt null.
function applyResponse(response, monthKey) {
    const habits = (response && response.habits) || [];
    const roster = habits.map((habit) => ({
        id: habit.id,
        name: habit.name,
        polarity: habit.polarity,
        isPrivate: !!habit.isPrivate,
        createdAt: habit.createdAt,
        editedAt: habit.editedAt,
    }));

    const months = (response && response.months) || [];
    const month = months.filter(
        (responseMonth) => responseMonth.month === monthKey,
    )[0];
    const entries = (month && month.entries) || [];

    const entriesByHabitId = entries.reduce((byHabitId, entry) => {
        byHabitId[entry.habitId] = byHabitId[entry.habitId] || {};
        byHabitId[entry.habitId][entry.date] = {
            habitId: entry.habitId,
            date: entry.date,
            outcome: outcomeFromWire(entry.outcome),
            editedAt: entry.editedAt,
            deletedAt: null,
        };
        return byHabitId;
    }, {});

    return { roster: roster, entriesByHabitId: entriesByHabitId };
}

// Did the server's authoritative state differ from what we sent? If not, skip overwriting the
// model (and its e-ink redraw). Compares alive rows by edit-time, order-insensitively — exact,
// since the server stores client edit-times verbatim.
function responseChangesLocal(request, response) {
    return (
        !sameMap(
            aliveHabitMap(request.habits),
            aliveHabitMap(response.habits),
        ) ||
        !sameMap(aliveEntryMap(request.months), aliveEntryMap(response.months))
    );
}

const aliveHabitMap = (habits) =>
    (habits || []).reduce((byId, habit) => {
        if (!habit.deletedAt) byId[habit.id] = habit.editedAt;
        return byId;
    }, {});

const aliveEntryMap = (months) =>
    (months || []).reduce((byMonthHabitDate, month) => {
        (month.entries || []).forEach((entry) => {
            if (!entry.deletedAt)
                byMonthHabitDate[
                    `${month.month}|${entry.habitId}|${entry.date}`
                ] = entry.editedAt;
        });
        return byMonthHabitDate;
    }, {});

const sameMap = (a, b) => {
    const ak = Object.keys(a);
    const bk = Object.keys(b);
    if (ak.length !== bk.length) return false;
    return ak.every((k) => b.hasOwnProperty(k) && b[k] === a[k]);
};
