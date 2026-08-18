import QtQuick 2.15
import QtTest 1.2
import "../src" as App
import "../src/js/Storage.js" as Storage
import "../src/js/Entries.js" as Entries
import "../src/js/Polarity.js" as Polarity
import "TestPaths.js" as TestPaths
import "Fixtures.js" as Fixtures

// The facade over the roster file and the viewed month's file. What is pinned here is the set of
// invariants the ADRs exist to protect: refuse rather than fold an unreadable file (0006), flush
// to the old month before re-pointing (0004), and keep the model alive-only so index-based APIs
// stay in step with the grid (0002/0005).
TestCase {
    id: testCase
    name: "HabitsStore"

    // Every test gets its own month so the shared working dir cannot leak a month file between
    // them; roster.json is shared, so each test writes the roster it wants before building a store.
    readonly property string workingDir: TestPaths.tmpPath("habits")
    readonly property string emptyDir: TestPaths.tmpPath("habits-seed")

    property var store: null

    Component {
        id: habitsStoreComponent

        App.HabitsStore {}
    }

    // A store outliving its test could fire a pending debounce into the shared roster file. There
    // is no cancel, but a blocked file turns any late _doSave into a no-op.
    function cleanup() {
        if (!store) {
            return;
        }

        store._roster.isUnwritable = true;
        store._month.isUnwritable = true;
        store.destroy();
        store = null;
    }

    function makeStore(dir, year, month) {
        store = habitsStoreComponent.createObject(testCase, {
            dataDir: dir,
            today: new Date(year, month, 15),
            viewYear: year,
            viewMonth: month
        });
        tryVerify(() => store.isLoaded, 2000, "store never finished its deferred load");

        return store;
    }

    function rosterPath(dir) {
        return `${dir}/roster.json`;
    }

    function monthPath(dir, year, month) {
        return `${dir}/${year}-${month < 9 ? "0" : ""}${month + 1}.json`;
    }

    // Writes are async PUTs and roster.json is shared, so waiting for "a file exists" would let a
    // store load the previous test's roster. Wait for this exact body instead.
    function writeAndSettle(target, value) {
        writeRawAndSettle(target, JSON.stringify(value));
    }

    function writeRawAndSettle(target, body) {
        Storage.writeFile(target, body);
        tryVerify(() => Storage.readFile(target) === body, 2000, `${target} never took the written body`);
    }

    function readSettled(target) {
        tryVerify(() => !Storage.isMissing(Storage.readJson(target)), 2000, `nothing written to ${target}`);

        return Storage.readJson(target);
    }

    // --- loading and folding -------------------------------------------------------------------

    // First run: no roster on disk. The seeded defaults carry name and polarity only, so ids and
    // timestamps are minted here and the file is written straight away.
    function test_seedsDefaultHabitsOnAFirstRun() {
        makeStore(emptyDir, 2026, 0);

        verify(store.habits.count > 0);
        compare(store.hasUnreadableData, false);

        const written = readSettled(rosterPath(emptyDir));
        compare(written.habits.length, store.habits.count);
        verify(!!written.habits[0].id);
        verify(!!written.habits[0].createdAt);
        compare(written.habits[0].editedAt, written.habits[0].createdAt);
        compare(written.habits[0].deletedAt, null);
    }

    // The two files load in parallel and are joined by habit id once both resolve. A month file
    // holds flat rows; the model holds them sliced per habit, because that is the only per-habit
    // reactive vehicle QML gives us (ADR 0005).
    function test_foldsMonthEntriesOntoTheRosterById() {
        const year = 2026;
        const month = 1;
        writeAndSettle(rosterPath(workingDir), {
            habits: [Fixtures.rosterRow({ id: "a", name: "Alpha" }), Fixtures.rosterRow({ id: "b", name: "Beta" })]
        });
        writeAndSettle(monthPath(workingDir, year, month), {
            month: "2026-02",
            entries: [
                Fixtures.entryRow({ habitId: "a", date: "2026-02-01", outcome: Entries.X }),
                Fixtures.entryRow({ habitId: "a", date: "2026-02-03", outcome: Entries.O }),
                Fixtures.entryRow({ habitId: "b", date: "2026-02-01", outcome: Entries.O })
            ]
        });

        makeStore(workingDir, year, month);

        compare(store.habits.count, 2);
        compare(store.monthKey, "2026-02");
        compare(Object.keys(store.habits.get(0).entriesByDate).length, 2);
        compare(store.habits.get(0).entriesByDate["2026-02-03"].outcome, Entries.O);
        compare(Object.keys(store.habits.get(1).entriesByDate).length, 1);
        compare(store.habits.get(1).entriesByDate["2026-02-01"].habitId, "b");
    }

    // Tombstoned habits are read back into habitTombstones, not the model — the model is alive-only
    // so the grid and every index-based API forget a deleted habit.
    function test_loadSplitsTombstonesOutOfTheModel() {
        const year = 2026;
        const month = 2;
        writeAndSettle(rosterPath(workingDir), {
            habits: [
                Fixtures.rosterRow({ id: "alive", name: "Alive" }),
                Fixtures.rosterRow({ id: "gone", name: "Gone", deletedAt: 1750000005000 })
            ]
        });

        makeStore(workingDir, year, month);

        compare(store.habits.count, 1);
        compare(store.habits.get(0).id, "alive");
        compare(store.habitTombstones.length, 1);
        compare(store.habitTombstones[0].id, "gone");
        compare(store.habitTombstones[0].deletedAt, 1750000005000);
    }

    // --- refusal, not tolerance (ADR 0006) -------------------------------------------------------

    // The envelope alone does not prove the shape: a row still spelling its edit-time `updatedAt`
    // reads back as undefined, renders fine, and then syncs as edit-time 0 — losing every merge.
    function test_refusesARosterThisVersionCannotRead() {
        const year = 2026;
        const month = 3;
        const stale = { habits: [{ id: "a", name: "Alpha", polarity: "Positive", createdAt: 1750000000000, updatedAt: 1750000000000 }] };
        writeAndSettle(rosterPath(workingDir), stale);

        makeStore(workingDir, year, month);

        verify(store.hasUnreadableData, "an un-migrated roster must not be readable");
        verify(store._roster.isUnwritable);
        compare(store.habits.count, 0);
        verify(store.saveError.indexOf(rosterPath(workingDir)) !== -1, "the error should name the file");
        verify(store.saveError.indexOf("migrated") !== -1, "an unrecognised shape should say so");
    }

    // A roster still spelling the flag hideFromSleep (pre-migration) has no isPrivate field, so
    // _isRosterRow's typeof check rejects it — folding it in would silently render private habits
    // publicly and then drop the flags for good on the next save.
    function test_refusesARosterStillSpellingHideFromSleep() {
        const year = 2026;
        const month = 8;
        const stale = { habits: [{ id: "a", name: "Alpha", polarity: "Positive", hideFromSleep: true, createdAt: 1750000000000, editedAt: 1750000000000 }] };
        writeAndSettle(rosterPath(workingDir), stale);

        makeStore(workingDir, year, month);

        verify(store.hasUnreadableData, "a roster still spelling hideFromSleep must not be readable");
        verify(store._roster.isUnwritable);
        compare(store.habits.count, 0);

        wait(300);
        const onDisk = Storage.readJson(rosterPath(workingDir));
        compare(onDisk.habits[0].hideFromSleep, true, "the refused file must never be overwritten");
    }

    function test_refusesAMonthFileThisVersionCannotRead() {
        const year = 2026;
        const month = 4;
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });
        writeAndSettle(monthPath(workingDir, year, month), {
            month: "2026-05",
            entries: [{ habitId: "a", date: "2026-05-01", outcome: "x", updatedAt: 1750000000000 }]
        });

        makeStore(workingDir, year, month);

        verify(store.hasUnreadableData);
        verify(store._month.isUnwritable);
        compare(store.habits.count, 1);
        compare(Object.keys(store.habits.get(0).entriesByDate).length, 0, "the month renders empty, but is not written");
    }

    function test_refusesACorruptFileAndSaysSo() {
        const year = 2026;
        const month = 5;
        writeRawAndSettle(rosterPath(workingDir), "{ truncated");

        makeStore(workingDir, year, month);

        verify(store.hasUnreadableData);
        verify(store.saveError.indexOf("parse") !== -1, `expected a parse error, got "${store.saveError}"`);
    }

    // The invariant the whole refusal machinery exists for: an edit made against a file rendered
    // as empty must never reach that file, or the real data is gone.
    function test_refusedFilesAreNeverOverwritten() {
        const year = 2026;
        const month = 6;
        const stale = { habits: [{ id: "a", name: "Alpha", polarity: "Positive", createdAt: 1750000000000, updatedAt: 1750000000000 }] };
        writeAndSettle(rosterPath(workingDir), stale);

        makeStore(workingDir, year, month);
        verify(store.hasUnreadableData);

        store.add("A habit added against the empty grid", Polarity.POSITIVE);
        store.flushPendingSave();
        wait(300);

        const onDisk = Storage.readJson(rosterPath(workingDir));
        compare(onDisk.habits.length, 1);
        compare(onDisk.habits[0].updatedAt, 1750000000000, "the un-migrated row must survive untouched");
        compare(onDisk.habits[0].name, "Alpha");
    }

    // Navigating off an unreadable month onto a readable one lifts the block: every read
    // re-decides it.
    function test_navigatingOffAnUnreadableMonthLiftsTheBlock() {
        const year = 2026;
        const month = 7;
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });
        writeRawAndSettle(monthPath(workingDir, year, month), "{ truncated");

        makeStore(workingDir, year, month);
        verify(store.hasUnreadableData);

        store.loadMonth(2025, 10);

        compare(store.hasUnreadableData, false);
        compare(store.monthKey, "2025-11");
    }

    // --- month navigation (ADR 0004) --------------------------------------------------------------

    // loadMonth flushes the pending edit while filePath still points at the old month. Reversing
    // those two steps writes the edit into the wrong month's file.
    function test_loadMonthFlushesToTheOldFileFirst() {
        const year = 2026;
        const august = 7;
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });

        makeStore(workingDir, year, august);
        compare(store.monthKey, "2026-08");

        store.toggleEntry(0, "2026-08-05");
        store.loadMonth(year, august + 1);

        compare(store.monthKey, "2026-09");

        const oldMonth = readSettled(monthPath(workingDir, year, august));
        compare(oldMonth.month, "2026-08");
        compare(oldMonth.entries.length, 1);
        compare(oldMonth.entries[0].date, "2026-08-05");
        compare(oldMonth.entries[0].outcome, Entries.X);

        verify(Storage.isMissing(Storage.readJson(monthPath(workingDir, year, august + 1))),
               "the edit must not have followed the view into September");
    }

    function test_loadMonthSwapsTheEntriesInMemory() {
        const year = 2025;
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });
        writeAndSettle(monthPath(workingDir, year, 0), {
            month: "2025-01",
            entries: [Fixtures.entryRow({ habitId: "a", date: "2025-01-04", outcome: Entries.O })]
        });

        makeStore(workingDir, year, 1);
        compare(Object.keys(store.habits.get(0).entriesByDate).length, 0);

        store.loadMonth(year, 0);

        compare(store.monthKey, "2025-01");
        compare(Object.keys(store.habits.get(0).entriesByDate).length, 1);
        compare(store.habits.get(0).entriesByDate["2025-01-04"].outcome, Entries.O);
    }

    // The month arrows gate on hasLoadedOnce rather than isLoaded, so they stay live while a
    // switch briefly tears the grid down.
    function test_hasLoadedOnceStaysTrueAcrossATeardown() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });

        makeStore(workingDir, 2025, 2);
        verify(store.hasLoadedOnce);

        store.beginLoadMonth();

        compare(store.isLoaded, false);
        verify(store.hasLoadedOnce, "the month arrows must stay live across a switch");
    }

    // --- mutators ----------------------------------------------------------------------------------

    function test_toggleEntryCyclesAndPersists() {
        const year = 2025;
        const month = 3;
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });

        makeStore(workingDir, year, month);

        store.toggleEntry(0, "2025-04-02");
        compare(store.habits.get(0).entriesByDate["2025-04-02"].outcome, Entries.X);

        store.toggleEntry(0, "2025-04-02");
        compare(store.habits.get(0).entriesByDate["2025-04-02"].outcome, Entries.O);

        // The third tap clears, which is a tombstone rather than a dropped key.
        store.toggleEntry(0, "2025-04-02");
        compare(Entries.outcomeOf(store.habits.get(0).entriesByDate["2025-04-02"]), Entries.UNMARKED);
        verify(store.habits.get(0).entriesByDate["2025-04-02"].deletedAt !== null);

        store.flushPendingSave();
        const written = readSettled(monthPath(workingDir, year, month));
        compare(written.entries.length, 1);
        verify(written.entries[0].deletedAt !== null, "a cleared day persists as a tombstone");
    }

    // Soft delete: the habit leaves the model so the grid forgets it, and becomes a roster
    // tombstone the next sync pushes.
    function test_removeMovesTheHabitToATombstone() {
        writeAndSettle(rosterPath(workingDir), {
            habits: [Fixtures.rosterRow({ id: "a", name: "Alpha" }), Fixtures.rosterRow({ id: "b", name: "Beta" })]
        });

        makeStore(workingDir, 2025, 4);

        store.remove(0);

        compare(store.habits.count, 1);
        compare(store.habits.get(0).id, "b", "the surviving habit shifts down, so indices stay in step");
        compare(store.habitTombstones.length, 1);
        compare(store.habitTombstones[0].id, "a");
        verify(store.habitTombstones[0].deletedAt > 0);
        compare(store.habitTombstones[0].editedAt, store.habitTombstones[0].deletedAt);
    }

    function test_purgeHabitTombstonesDropsThemOnce() {
        writeAndSettle(rosterPath(workingDir), {
            habits: [Fixtures.rosterRow({ id: "gone", deletedAt: 1750000005000 })]
        });

        makeStore(workingDir, 2025, 5);
        compare(store.habitTombstones.length, 1);

        store.purgeHabitTombstones();

        compare(store.habitTombstones.length, 0);
    }

    function test_addTrimsAndRejectsBlankNames() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });

        makeStore(workingDir, 2025, 6);
        const before = store.habits.count;

        store.add("   ", Polarity.POSITIVE);
        store.add("", Polarity.POSITIVE);
        compare(store.habits.count, before);

        store.add("  Stretch  ", Polarity.NEGATIVE);

        compare(store.habits.count, before + 1);
        compare(store.habits.get(before).name, "Stretch");
        compare(store.habits.get(before).polarity, Polarity.NEGATIVE);
        verify(!!store.habits.get(before).id);
    }

    function test_setNameTrimsAndRefusesToBlank() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a", name: "Alpha" })] });

        makeStore(workingDir, 2025, 7);

        store.setName(0, "   ");
        compare(store.habits.get(0).name, "Alpha");

        store.setName(0, "  Renamed  ");
        compare(store.habits.get(0).name, "Renamed");
        verify(store.habits.get(0).editedAt > 1750000000000, "a rename must restamp the edit-time");
    }

    // Position is the array index at sync time, so every habit whose index shifted needs a fresh
    // edit-time for the reorder to win last-write-wins.
    function test_moveRestampsEveryShiftedHabit() {
        writeAndSettle(rosterPath(workingDir), {
            habits: [
                Fixtures.rosterRow({ id: "a" }),
                Fixtures.rosterRow({ id: "b" }),
                Fixtures.rosterRow({ id: "c" }),
                Fixtures.rosterRow({ id: "d" })
            ]
        });

        makeStore(workingDir, 2025, 8);

        store.move(0, 2);

        compare(store.habits.get(0).id, "b");
        compare(store.habits.get(1).id, "c");
        compare(store.habits.get(2).id, "a");
        verify(store.habits.get(0).editedAt > 1750000000000);
        verify(store.habits.get(1).editedAt > 1750000000000);
        verify(store.habits.get(2).editedAt > 1750000000000);
        compare(store.habits.get(3).editedAt, 1750000000000, "an unshifted habit keeps its edit-time");
    }

    function test_mutatorsIgnoreOutOfBoundsIndices() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });

        makeStore(workingDir, 2025, 9);

        [-1, 1, 99].forEach(index => {
            store.remove(index);
            store.togglePolarity(index);
            store.togglePrivate(index);
            store.setName(index, "Nope");
            store.toggleEntry(index, "2025-10-01");
        });

        compare(store.habits.count, 1);
        compare(store.habits.get(0).name, "Read 20 pages");
        compare(store.habitTombstones.length, 0);
    }

    function test_togglePolarityFlipsAndRestamps() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });

        makeStore(workingDir, 2025, 10);

        store.togglePolarity(0);

        compare(store.habits.get(0).polarity, Polarity.NEGATIVE);
        verify(store.habits.get(0).editedAt > 1750000000000);
    }

    // Sync merges habits whole-row by editedAt last-write-wins, so a privacy flip that does not
    // restamp editedAt would always lose to the server's copy.
    function test_togglePrivateFlipsAndRestamps() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a", isPrivate: false })] });

        makeStore(workingDir, 2025, 0);
        const before = store.habits.get(0).editedAt;

        store.togglePrivate(0);

        compare(store.habits.get(0).isPrivate, true);
        verify(store.habits.get(0).editedAt > before);
    }

    // --- applySynced -----------------------------------------------------------------------------

    // isPrivate is backend-owned now, so the response's copy always wins — a local flag no longer
    // survives a sync the server disagrees with.
    function test_applySyncedTakesIsPrivateFromWire() {
        writeAndSettle(rosterPath(workingDir), {
            habits: [Fixtures.rosterRow({ id: "a", isPrivate: true }), Fixtures.rosterRow({ id: "b" })]
        });

        makeStore(workingDir, 2025, 11);

        const applied = store.applySynced([
            { id: "b", name: "Beta", polarity: "Positive", isPrivate: true, createdAt: 1, editedAt: 2 },
            { id: "a", name: "Alpha", polarity: "Negative", isPrivate: false, createdAt: 3, editedAt: 4 }
        ], {});

        verify(applied);
        compare(store.habits.count, 2);
        compare(store.habits.get(0).id, "b", "the server's order wins");
        compare(store.habits.get(1).id, "a");
        compare(store.habits.get(1).isPrivate, false, "the wire's value wins over the local flag");
        compare(store.habits.get(0).isPrivate, true);
        compare(store.habits.get(1).polarity, "Negative", "everything else comes back authoritative");

        // As above: let the immediate write land before the shared roster.json is touched again.
        wait(300);
    }

    function test_applySyncedReplacesTheViewedMonthsEntries() {
        const year = 2024;
        const month = 0;
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a" })] });
        writeAndSettle(monthPath(workingDir, year, month), {
            month: "2024-01",
            entries: [Fixtures.entryRow({ habitId: "a", date: "2024-01-01", outcome: Entries.X })]
        });

        makeStore(workingDir, year, month);
        compare(Object.keys(store.habits.get(0).entriesByDate).length, 1);

        store.applySynced(
            [{ id: "a", name: "Alpha", polarity: "Positive", isPrivate: false, createdAt: 1, editedAt: 2 }],
            { "a": { "2024-01-09": Fixtures.entryRow({ habitId: "a", date: "2024-01-09", outcome: Entries.O }) } });

        compare(Object.keys(store.habits.get(0).entriesByDate).length, 1);
        compare(store.habits.get(0).entriesByDate["2024-01-09"].outcome, Entries.O);
        compare(store.habits.get(0).entriesByDate["2024-01-01"], undefined);

        // applySynced writes both files immediately (not debounced); roster.json is shared across
        // every test in this suite, so a later test's read must not race this one's landing write.
        wait(300);
    }

    function test_applySyncedClearsPushedTombstones() {
        writeAndSettle(rosterPath(workingDir), {
            habits: [Fixtures.rosterRow({ id: "a" }), Fixtures.rosterRow({ id: "gone", deletedAt: 1750000005000 })]
        });

        makeStore(workingDir, 2024, 1);
        compare(store.habitTombstones.length, 1);

        store.applySynced([{ id: "a", name: "Alpha", polarity: "Positive", isPrivate: false, createdAt: 1, editedAt: 2 }], {});

        compare(store.habitTombstones.length, 0);

        // As above: let the immediate write land before the shared roster.json is touched again.
        wait(300);
    }

    // Validate before writing, not after: an older backend whose response omits a field this
    // version requires would otherwise be written to roster.json and refused on next launch,
    // turning a version mismatch into an unreadable file.
    function test_applySyncedRefusesAHabitItCannotStore() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a", name: "Alpha" })] });

        makeStore(workingDir, 2024, 2);

        const applied = store.applySynced([{ id: "b", name: "Beta", polarity: "Positive", createdAt: 1 }], {});

        compare(applied, false);
        compare(store.habits.count, 1);
        compare(store.habits.get(0).id, "a", "nothing may be touched when the response is refused");

        wait(300);
        const onDisk = Storage.readJson(rosterPath(workingDir));
        compare(onDisk.habits[0].id, "a");
    }

    // An older backend's response has no isPrivate field at all — the same _isRosterRow guard must
    // refuse it rather than fold the row in with the flag defaulted to false.
    function test_applySyncedRefusesAResponseMissingIsPrivate() {
        writeAndSettle(rosterPath(workingDir), { habits: [Fixtures.rosterRow({ id: "a", name: "Alpha" })] });

        // A prior test's applySynced writes both files immediately (not debounced); give that a
        // moment to land so it cannot race this store's read of the shared roster.json.
        wait(300);

        makeStore(workingDir, 2024, 3);

        const applied = store.applySynced([{ id: "a", name: "Alpha Updated", polarity: "Negative", createdAt: 1, editedAt: 2 }], {});

        compare(applied, false);
        compare(store.habits.count, 1);
        compare(store.habits.get(0).name, "Alpha", "nothing may be touched when the response is refused");

        wait(300);
        const onDisk = Storage.readJson(rosterPath(workingDir));
        compare(onDisk.habits[0].name, "Alpha");
    }
}
