import QtQuick 2.15
import QtTest 1.2
import "../src/js/Entries.js" as Entries
import "../src/js/Polarity.js" as Polarity
import "Fixtures.js" as Fixtures

TestCase {
    name: "Entries"

    function test_outcomeOfReadsAliveRowsOnly() {
        compare(Entries.outcomeOf(Fixtures.entryRow({ outcome: Entries.X })), Entries.X);
        compare(Entries.outcomeOf(Fixtures.entryRow({ outcome: Entries.O })), Entries.O);
        compare(Entries.outcomeOf(undefined), Entries.UNMARKED);
    }

    // A tombstone keeps the outcome it had so the backend can see what was cleared, but locally
    // it must read as unmarked — otherwise a cleared day keeps rendering its old glyph.
    function test_outcomeOfIgnoresTombstonedRows() {
        const tombstone = Fixtures.entryRow({ outcome: Entries.X, deletedAt: 1750000001000 });

        compare(Entries.outcomeOf(tombstone), Entries.UNMARKED);
    }

    function test_positiveHabitsCycleUnmarkedXO() {
        compare(Entries.nextOutcome(Polarity.POSITIVE, Entries.UNMARKED), Entries.X);
        compare(Entries.nextOutcome(Polarity.POSITIVE, Entries.X), Entries.O);
        compare(Entries.nextOutcome(Polarity.POSITIVE, Entries.O), Entries.UNMARKED);
    }

    // A negative habit renders an unmarked day as X already, so it only needs the slip state.
    function test_negativeHabitsCycleUnmarkedO() {
        compare(Entries.nextOutcome(Polarity.NEGATIVE, Entries.UNMARKED), Entries.O);
        compare(Entries.nextOutcome(Polarity.NEGATIVE, Entries.O), Entries.UNMARKED);
    }

    function test_markForRendersStoredOutcomes() {
        compare(Entries.markFor(Entries.X, false), "X");
        compare(Entries.markFor(Entries.O, false), "O");
        compare(Entries.markFor(Entries.UNMARKED, false), Entries.UNMARKED);
    }

    // The implicit X is what a negative habit shows for a past day it has not slipped on. It never
    // overrides a stored outcome — an explicit O must still read as O.
    function test_markForImplicitX() {
        compare(Entries.markFor(Entries.UNMARKED, true), "X");
        compare(Entries.markFor(Entries.O, true), "O");
    }

    function test_toggledRowStampsEditTime() {
        const before = Date.now();
        const row = Entries.toggledRow("habit-1", "2026-08-09", Polarity.POSITIVE, undefined);
        const after = Date.now();

        compare(row.habitId, "habit-1");
        compare(row.date, "2026-08-09");
        compare(row.outcome, Entries.X);
        compare(row.deletedAt, null);
        verify(row.editedAt >= before && row.editedAt <= after, `editedAt ${row.editedAt} out of range`);
    }

    // Clearing writes a tombstone rather than dropping the key, so the next sync can push the
    // clear; the tombstone keeps the outcome it had.
    function test_toggledRowClearingWritesATombstone() {
        const marked = Fixtures.entryRow({ outcome: Entries.O });
        const row = Entries.toggledRow("habit-1", "2026-08-01", Polarity.POSITIVE, marked);

        compare(row.outcome, Entries.O);
        verify(row.deletedAt !== null);
        compare(row.deletedAt, row.editedAt);
    }

    function test_toggledRowRevivesATombstone() {
        const tombstone = Fixtures.entryRow({ outcome: Entries.X, deletedAt: 1750000001000 });
        const row = Entries.toggledRow("habit-1", "2026-08-01", Polarity.POSITIVE, tombstone);

        // The tombstone reads as unmarked, so the cycle restarts at X rather than advancing to O.
        compare(row.outcome, Entries.X);
        compare(row.deletedAt, null);
    }

    function test_byHabitIdIndexesByHabitThenDate() {
        const rows = [
            Fixtures.entryRow({ habitId: "a", date: "2026-08-01" }),
            Fixtures.entryRow({ habitId: "a", date: "2026-08-02", outcome: Entries.O }),
            Fixtures.entryRow({ habitId: "b", date: "2026-08-01" })
        ];

        const index = Entries.byHabitId(rows);

        compare(Object.keys(index).length, 2);
        compare(Object.keys(index["a"]).length, 2);
        compare(index["a"]["2026-08-02"].outcome, Entries.O);
        compare(index["b"]["2026-08-01"].habitId, "b");
    }

    function test_byHabitIdToleratesNothing() {
        compare(Object.keys(Entries.byHabitId(undefined)).length, 0);
        compare(Object.keys(Entries.byHabitId([])).length, 0);
    }

    // The slice is replaced wholesale rather than mutated, because it is the value on a ListModel
    // row — mutating in place would not notify the grid's bindings.
    function test_withRowDoesNotMutateTheInput() {
        const original = { "2026-08-01": Fixtures.entryRow({ date: "2026-08-01" }) };
        const added = Fixtures.entryRow({ date: "2026-08-02", outcome: Entries.O });

        const next = Entries.withRow(original, added);

        compare(Object.keys(original).length, 1);
        compare(Object.keys(next).length, 2);
        compare(next["2026-08-02"].outcome, Entries.O);
        verify(next !== original);
    }

    function test_withRowReplacesAnExistingDate() {
        const original = { "2026-08-01": Fixtures.entryRow({ outcome: Entries.X }) };

        const next = Entries.withRow(original, Fixtures.entryRow({ outcome: Entries.O }));

        compare(Object.keys(next).length, 1);
        compare(next["2026-08-01"].outcome, Entries.O);
        compare(original["2026-08-01"].outcome, Entries.X);
    }

    // The suspend canvas dedups on the visible outcome alone, so timestamps and tombstones are
    // dropped before they reach it.
    function test_outcomesByDateKeepsOnlyVisibleOutcomes() {
        const entriesByDate = {
            "2026-08-01": Fixtures.entryRow({ date: "2026-08-01", outcome: Entries.X }),
            "2026-08-02": Fixtures.entryRow({ date: "2026-08-02", outcome: Entries.O }),
            "2026-08-03": Fixtures.entryRow({ date: "2026-08-03", outcome: Entries.X, deletedAt: 1750000001000 })
        };

        const outcomes = Entries.outcomesByDate(entriesByDate);

        compare(Object.keys(outcomes).length, 2);
        compare(outcomes["2026-08-01"], Entries.X);
        compare(outcomes["2026-08-02"], Entries.O);
        compare(outcomes["2026-08-03"], undefined);
    }

    function test_outcomesByDateToleratesNothing() {
        compare(Object.keys(Entries.outcomesByDate(undefined)).length, 0);
    }
}
