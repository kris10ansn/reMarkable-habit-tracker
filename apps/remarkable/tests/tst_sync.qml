import QtQuick 2.15
import QtTest 1.2
import "../src/js/Sync.js" as Sync
import "../src/js/Entries.js" as Entries
import "Fixtures.js" as Fixtures

TestCase {
    name: "Sync"

    // --- outcome respelling (ADR 0005: x/o on disk, Success/Failure on the wire) -------------

    function test_outcomeRoundTripsThroughTheWire() {
        compare(Sync.outcomeFromWire(Sync.outcomeToWire(Entries.X)), Entries.X);
        compare(Sync.outcomeFromWire(Sync.outcomeToWire(Entries.O)), Entries.O);
        compare(Sync.outcomeToWire(Entries.X), "Success");
        compare(Sync.outcomeToWire(Entries.O), "Failure");
    }

    // Both directions are total but lossy: anything that is not the success spelling collapses to
    // failure. Safe only because an unmarked day is never sent as a live row — it is a tombstone,
    // and the backend ignores a deleted row's payload. Pinned so the asymmetry stays deliberate.
    function test_outcomeMappingIsTotalAndCollapsesTheUnknown() {
        compare(Sync.outcomeToWire(Entries.UNMARKED), "Failure");
        compare(Sync.outcomeToWire(undefined), "Failure");
        compare(Sync.outcomeFromWire("nonsense"), Entries.O);
    }

    // --- buildRequest -------------------------------------------------------------------------

    function test_buildRequestNumbersPositionsByRosterIndex() {
        const roster = [
            Fixtures.rosterRow({ id: "a" }),
            Fixtures.rosterRow({ id: "b" }),
            Fixtures.rosterRow({ id: "c" })
        ];

        const request = Sync.buildRequest(roster, [], [], "2026-08");

        compare(request.habits.length, 3);
        compare(request.habits[0].position, 0);
        compare(request.habits[1].position, 1);
        compare(request.habits[2].position, 2);
        compare(request.habits[1].id, "b");
    }

    // isPrivate is backend-owned now — it rides the wire like every other shared field, on both
    // alive rows and tombstones.
    function test_buildRequestCarriesIsPrivate() {
        const roster = [Fixtures.rosterRow({ id: "a", isPrivate: true })];
        const tombstones = [Fixtures.rosterRow({ id: "gone", isPrivate: true, deletedAt: 1750000005000, editedAt: 1750000005000 })];

        const request = Sync.buildRequest(roster, tombstones, [], "2026-08");

        compare(request.habits[0].isPrivate, true);
        compare(request.habits[0].createdAt, 1750000000000);
        compare(request.habits[0].editedAt, 1750000000000);
        compare(request.habits[1].isPrivate, true);
    }

    function test_buildRequestMarksAliveHabitsUndeleted() {
        const request = Sync.buildRequest([Fixtures.rosterRow()], [], [], "2026-08");

        compare(request.habits[0].deletedAt, null);
    }

    // Tombstones ride along after the alive rows so the delete can win a merge. Their payload is
    // ignored by the backend, so position is not meaningful and is sent as 0.
    function test_buildRequestAppendsTombstonesWithTheirDeleteStamp() {
        const roster = [Fixtures.rosterRow({ id: "a" })];
        const tombstones = [Fixtures.rosterRow({ id: "gone", deletedAt: 1750000005000, editedAt: 1750000005000 })];

        const request = Sync.buildRequest(roster, tombstones, [], "2026-08");

        compare(request.habits.length, 2);
        compare(request.habits[0].id, "a");
        compare(request.habits[1].id, "gone");
        compare(request.habits[1].deletedAt, 1750000005000);
        compare(request.habits[1].position, 0);
    }

    function test_buildRequestSendsExactlyOneMonth() {
        const request = Sync.buildRequest([], [], [], "2026-08");

        compare(request.months.length, 1);
        compare(request.months[0].month, "2026-08");
        compare(request.months[0].entries.length, 0);
    }

    function test_buildRequestRespellsEntryOutcomes() {
        const entryRows = [
            Fixtures.entryRow({ date: "2026-08-01", outcome: Entries.X }),
            Fixtures.entryRow({ date: "2026-08-02", outcome: Entries.O })
        ];

        const entries = Sync.buildRequest([], [], entryRows, "2026-08").months[0].entries;

        compare(entries[0].outcome, "Success");
        compare(entries[1].outcome, "Failure");
        compare(entries[0].date, "2026-08-01");
        compare(entries[0].habitId, "habit-1");
    }

    // An undefined deletedAt would serialize as a missing field; the backend wants an explicit null.
    function test_buildRequestNormalisesEntryDeleteStamps() {
        const rows = [
            Fixtures.entryRow({ date: "2026-08-01", deletedAt: undefined }),
            Fixtures.entryRow({ date: "2026-08-02", deletedAt: 1750000009000 })
        ];

        const entries = Sync.buildRequest([], [], rows, "2026-08").months[0].entries;

        compare(entries[0].deletedAt, null);
        compare(entries[1].deletedAt, 1750000009000);
    }

    function test_buildRequestToleratesEveryArrayBeingAbsent() {
        const request = Sync.buildRequest(undefined, undefined, undefined, "2026-08");

        compare(request.habits.length, 0);
        compare(request.months.length, 1);
        compare(request.months[0].entries.length, 0);
    }

    // --- applyResponse ------------------------------------------------------------------------

    function test_applyResponseFoldsTheRosterInServerOrder() {
        const response = {
            habits: [
                { id: "b", name: "Second", polarity: "Negative", isPrivate: true, position: 0, createdAt: 1, editedAt: 2 },
                { id: "a", name: "First", polarity: "Positive", isPrivate: false, position: 1, createdAt: 3, editedAt: 4 }
            ],
            months: []
        };

        const applied = Sync.applyResponse(response, "2026-08");

        compare(applied.roster.length, 2);
        compare(applied.roster[0].id, "b");
        compare(applied.roster[1].id, "a");
        compare(applied.roster[0].polarity, "Negative");
        compare(applied.roster[0].editedAt, 2);
        compare(applied.roster[0].isPrivate, true);
        compare(applied.roster[1].isPrivate, false);

        // Order is the array itself; the wire's Position field is not carried into the model.
        compare(applied.roster[0].position, undefined);
    }

    function test_applyResponsePicksTheRequestedMonth() {
        const response = {
            habits: [],
            months: [
                { month: "2026-07", entries: [{ habitId: "a", date: "2026-07-01", outcome: "Success", editedAt: 1 }] },
                { month: "2026-08", entries: [{ habitId: "a", date: "2026-08-01", outcome: "Failure", editedAt: 2 }] }
            ]
        };

        const applied = Sync.applyResponse(response, "2026-08");

        compare(Object.keys(applied.entriesByHabitId["a"]).length, 1);
        compare(applied.entriesByHabitId["a"]["2026-08-01"].outcome, Entries.O);
        compare(applied.entriesByHabitId["a"]["2026-07-01"], undefined);
    }

    function test_applyResponseIndexesEntriesByHabitThenDate() {
        const response = {
            habits: [],
            months: [{
                month: "2026-08",
                entries: [
                    { habitId: "a", date: "2026-08-01", outcome: "Success", editedAt: 1 },
                    { habitId: "a", date: "2026-08-02", outcome: "Failure", editedAt: 2 },
                    { habitId: "b", date: "2026-08-01", outcome: "Success", editedAt: 3 }
                ]
            }]
        };

        const byHabitId = Sync.applyResponse(response, "2026-08").entriesByHabitId;

        compare(Object.keys(byHabitId).length, 2);
        compare(byHabitId["a"]["2026-08-01"].outcome, Entries.X);
        compare(byHabitId["a"]["2026-08-02"].outcome, Entries.O);
        compare(byHabitId["b"]["2026-08-01"].editedAt, 3);
    }

    // The response carries alive rows only, so every row folds in undeleted — a local tombstone
    // the server has accepted must not survive the fold and get pushed again.
    function test_applyResponseFoldsEveryRowInAlive() {
        const response = {
            habits: [],
            months: [{ month: "2026-08", entries: [{ habitId: "a", date: "2026-08-01", outcome: "Success", editedAt: 1 }] }]
        };

        compare(Sync.applyResponse(response, "2026-08").entriesByHabitId["a"]["2026-08-01"].deletedAt, null);
    }

    function test_applyResponseToleratesAnEmptyOrMismatchedResponse() {
        [undefined, {}, { habits: [], months: [] }, { habits: [], months: [{ month: "2026-01", entries: [] }] }].forEach(response => {
            const applied = Sync.applyResponse(response, "2026-08");

            compare(applied.roster.length, 0);
            compare(Object.keys(applied.entriesByHabitId).length, 0);
        });
    }

    // --- responseChangesLocal -------------------------------------------------------------------

    function test_responseChangesLocalIsFalseWhenTheServerAgrees() {
        const request = Sync.buildRequest(
            [Fixtures.rosterRow({ id: "a" })],
            [],
            [Fixtures.entryRow({ habitId: "a" })],
            "2026-08");

        verify(!Sync.responseChangesLocal(request, request));
    }

    // Order-insensitive by design: the server may return a different Position ordering without
    // that being a change worth overwriting the model (and repainting e-ink) for.
    function test_responseChangesLocalIgnoresOrder() {
        const first = Fixtures.rosterRow({ id: "a" });
        const second = Fixtures.rosterRow({ id: "b", editedAt: 1750000002000 });

        const request = Sync.buildRequest([first, second], [], [], "2026-08");
        const response = Sync.buildRequest([second, first], [], [], "2026-08");

        verify(!Sync.responseChangesLocal(request, response));
    }

    function test_responseChangesLocalDetectsANewEditTime() {
        const request = Sync.buildRequest([Fixtures.rosterRow({ id: "a" })], [], [], "2026-08");
        const response = Sync.buildRequest([Fixtures.rosterRow({ id: "a", editedAt: 1750000009000 })], [], [], "2026-08");

        verify(Sync.responseChangesLocal(request, response));
    }

    function test_responseChangesLocalDetectsAddedAndRemovedHabits() {
        const one = Sync.buildRequest([Fixtures.rosterRow({ id: "a" })], [], [], "2026-08");
        const two = Sync.buildRequest([Fixtures.rosterRow({ id: "a" }), Fixtures.rosterRow({ id: "b" })], [], [], "2026-08");

        verify(Sync.responseChangesLocal(one, two));
        verify(Sync.responseChangesLocal(two, one));
    }

    function test_responseChangesLocalDetectsEntryEdits() {
        const request = Sync.buildRequest([], [], [Fixtures.entryRow()], "2026-08");
        const response = Sync.buildRequest([], [], [Fixtures.entryRow({ editedAt: 1750000009000 })], "2026-08");

        verify(Sync.responseChangesLocal(request, response));
    }

    // The same date under a different habit is a different entry, so the key must carry all three
    // of month, habit and date.
    function test_responseChangesLocalKeysEntriesByMonthHabitAndDate() {
        const request = Sync.buildRequest([], [], [Fixtures.entryRow({ habitId: "a" })], "2026-08");
        const response = Sync.buildRequest([], [], [Fixtures.entryRow({ habitId: "b" })], "2026-08");

        verify(Sync.responseChangesLocal(request, response));
    }

    // A tombstone we pushed that the server accepted is absent from its answer. That is agreement,
    // not a change — comparing deleted rows would resync forever.
    function test_responseChangesLocalIgnoresDeletedRowsOnBothSides() {
        const request = Sync.buildRequest(
            [],
            [Fixtures.rosterRow({ id: "gone", deletedAt: 1750000005000 })],
            [Fixtures.entryRow({ deletedAt: 1750000005000 })],
            "2026-08");
        const response = Sync.buildRequest([], [], [], "2026-08");

        verify(!Sync.responseChangesLocal(request, response));
    }
}
