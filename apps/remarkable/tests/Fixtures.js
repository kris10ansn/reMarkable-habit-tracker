// Shared builders for the shapes the app passes around. Timestamps are fixed so tests compare
// exact values; the app's own Date.now() call sites are asserted by range instead.

const EPOCH = 1750000000000;

// The duck-typed { count, get(i) } slice of ListModel that HabitsModel.js actually uses, so its
// projections can be tested without a QML component. tools/suspend-writer/main.cpp builds the
// same stand-in to drive the renderer off-device.
function fakeModel(rows) {
    return {
        count: rows.length,
        get: (index) => rows[index],
    };
}

// A model row: identity + config + the per-habit entry slice indexed by date.
function habitRow(overrides) {
    return Object.assign(
        {
            id: "habit-1",
            name: "Read 20 pages",
            polarity: "Positive",
            isPrivate: false,
            createdAt: EPOCH,
            editedAt: EPOCH,
            deletedAt: null,
            entriesByDate: {},
        },
        overrides || {},
    );
}

// A normalized entry row, as persisted in the month file and carried on the wire.
function entryRow(overrides) {
    return Object.assign(
        {
            habitId: "habit-1",
            date: "2026-08-01",
            outcome: "x",
            editedAt: EPOCH,
            deletedAt: null,
        },
        overrides || {},
    );
}

// A roster row as it appears in roster.json — no entriesByDate, deletedAt set for a tombstone.
function rosterRow(overrides) {
    return Object.assign(
        {
            id: "habit-1",
            name: "Read 20 pages",
            polarity: "Positive",
            isPrivate: false,
            createdAt: EPOCH,
            editedAt: EPOCH,
            deletedAt: null,
        },
        overrides || {},
    );
}
