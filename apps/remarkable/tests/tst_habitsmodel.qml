import QtQuick 2.15
import QtTest 1.2
import "../src/js/HabitsModel.js" as HabitsModel
import "Fixtures.js" as Fixtures

TestCase {
    name: "HabitsModel"

    // Every projection guards on the duck-typed ListModel slice it uses, so a store that has not
    // built its model yet projects to nothing instead of throwing mid-serialize.
    function test_projectionsGuardOnAMissingModel() {
        [undefined, null, {}, { count: "3" }].forEach(bad => {
            compare(HabitsModel.toRoster(bad).length, 0);
            compare(HabitsModel.toMonthEntryRows(bad).length, 0);
            compare(HabitsModel.toSuspendHabits(bad).length, 0);
        });
    }

    // Array order is Position — the roster file and the sync wire both read order off the index.
    function test_toRosterPreservesModelOrder() {
        const model = Fixtures.fakeModel([
            Fixtures.habitRow({ id: "a", name: "First" }),
            Fixtures.habitRow({ id: "b", name: "Second" }),
            Fixtures.habitRow({ id: "c", name: "Third" })
        ]);

        const roster = HabitsModel.toRoster(model);

        compare(roster.length, 3);
        compare(roster[0].id, "a");
        compare(roster[1].id, "b");
        compare(roster[2].id, "c");
    }

    // entriesByDate is in-memory only: the roster file holds identity and config, the month file
    // holds the entries. Leaking it into the roster row would duplicate every entry on disk.
    function test_rosterRowDropsTheEntrySlice() {
        const row = HabitsModel.rosterRow(Fixtures.habitRow({
            entriesByDate: { "2026-08-01": Fixtures.entryRow() }
        }));

        compare(row.entriesByDate, undefined);
        compare(row.id, "habit-1");
        compare(row.name, "Read 20 pages");
        compare(row.polarity, "Positive");
        compare(row.createdAt, 1750000000000);
        compare(row.editedAt, 1750000000000);
    }

    function test_rosterRowNormalisesOptionalFields() {
        const row = HabitsModel.rosterRow({ id: "a", name: "A", polarity: "Positive", createdAt: 1, editedAt: 2 });

        compare(row.isPrivate, false);
        compare(row.deletedAt, null);
    }

    function test_rosterRowKeepsATombstoneStamp() {
        const row = HabitsModel.rosterRow(Fixtures.habitRow({ deletedAt: 1750000005000 }));

        compare(row.deletedAt, 1750000005000);
    }

    function test_toMonthEntryRowsFlattensEveryHabitsSlice() {
        const model = Fixtures.fakeModel([
            Fixtures.habitRow({
                id: "a",
                entriesByDate: {
                    "2026-08-01": Fixtures.entryRow({ habitId: "a", date: "2026-08-01" }),
                    "2026-08-02": Fixtures.entryRow({ habitId: "a", date: "2026-08-02" })
                }
            }),
            Fixtures.habitRow({
                id: "b",
                entriesByDate: { "2026-08-01": Fixtures.entryRow({ habitId: "b", date: "2026-08-01" }) }
            })
        ]);

        const rows = HabitsModel.toMonthEntryRows(model);

        compare(rows.length, 3);
        compare(rows.filter(row => row.habitId === "a").length, 2);
        compare(rows.filter(row => row.habitId === "b").length, 1);
    }

    // Tombstones are what the next sync pushes, so they stay in the month file.
    function test_toMonthEntryRowsKeepsTombstones() {
        const model = Fixtures.fakeModel([
            Fixtures.habitRow({
                entriesByDate: { "2026-08-01": Fixtures.entryRow({ deletedAt: 1750000009000 }) }
            })
        ]);

        const rows = HabitsModel.toMonthEntryRows(model);

        compare(rows.length, 1);
        compare(rows[0].deletedAt, 1750000009000);
    }

    function test_toMonthEntryRowsToleratesHabitsWithNoEntries() {
        const model = Fixtures.fakeModel([Fixtures.habitRow({ entriesByDate: undefined })]);

        compare(HabitsModel.toMonthEntryRows(model).length, 0);
    }

    // The suspend renderer wants visible outcomes by date, not entry rows — timestamps and
    // tombstones are already gone by the time they reach it.
    function test_toSuspendHabitsProjectsOutcomesOnly() {
        const model = Fixtures.fakeModel([
            Fixtures.habitRow({
                name: "Exercise",
                polarity: "Negative",
                entriesByDate: {
                    "2026-08-01": Fixtures.entryRow({ date: "2026-08-01", outcome: "o" }),
                    "2026-08-02": Fixtures.entryRow({ date: "2026-08-02", outcome: "x", deletedAt: 1750000009000 })
                }
            })
        ]);

        const habits = HabitsModel.toSuspendHabits(model);

        compare(habits.length, 1);
        compare(habits[0].name, "Exercise");
        compare(habits[0].polarity, "Negative");
        compare(habits[0].isPrivate, false);
        compare(habits[0].entries["2026-08-01"], "o");
        compare(habits[0].entries["2026-08-02"], undefined);
    }

    // Kept rather than filtered: SuspendDraw.js is what drops private habits, and computeSignature
    // has to see the flag flip to know the image needs redrawing.
    function test_toSuspendHabitsCarriesIsPrivate() {
        const model = Fixtures.fakeModel([Fixtures.habitRow({ isPrivate: true })]);

        const habits = HabitsModel.toSuspendHabits(model);

        compare(habits.length, 1);
        compare(habits[0].isPrivate, true);
    }
}
