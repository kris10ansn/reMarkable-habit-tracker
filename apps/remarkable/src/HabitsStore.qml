import QtQuick 2.15
import "js/Storage.js" as Storage
import "js/habits.js" as DefaultHabits
import "js/HabitsModel.js" as HabitsModel
import "js/DateUtils.js" as DateUtils
import "js/Entries.js" as Entries
import "js/Polarity.js" as Polarity
import "js/Ids.js" as Ids

// Facade over month-partitioned persistence. Keeps the public store API
// (habits, isLoaded, the mutators) but splits storage across two files: a
// roster (identity + config + habit tombstones) and the viewed month's entry
// rows. The ListModel is the single in-memory source of truth; each child store
// serializes a projection of it (see HabitsModel). Config edits save the roster;
// entry toggles save the month.
QtObject {
    id: store

    // Assignable only so the tests can point a store at a scratch dir; the app never sets it.
    property string dataDir: "/home/root/xovi/exthome/appload/habit-tracker/data"
    property date today: new Date()

    // The month the grid is currently viewing. Starts on the real current month;
    // month navigation re-points it (see loadMonth). monthKey — and thus the month
    // file path and the sync unit — follow it.
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    readonly property string monthKey: DateUtils.monthKey(viewYear, viewMonth)

    // Alive habits only, in display order. A deleted habit leaves the model and lives on in
    // habitTombstones, so every index-based API here stays in step with what the grid renders.
    property ListModel habits: ListModel {
        dynamicRoles: true
    }

    // Soft-deleted habits, in roster-row shape with deletedAt set. Persisted alongside the alive
    // rows in roster.json — the same "alive rows + tombstones" split the sync wire format uses —
    // and dropped once a sync confirms the server owns them.
    property var habitTombstones: []

    readonly property bool isLoaded: _roster.isLoaded && _month.isLoaded

    // True while either file holds data this version cannot read. Those files are rendered as empty
    // and never written to, so sync must stay off as well — it would push the empty month to the
    // server and pull the server's answer back over the real data.
    readonly property bool hasUnreadableData: _roster.isUnwritable || _month.isUnwritable

    // Sticky: true once the first load ever completes, and never false again — even
    // while a month switch briefly drops isLoaded to tear the grid down. The month
    // arrows gate on this (not isLoaded) so they stay live across switches.
    property bool hasLoadedOnce: false
    onIsLoadedChanged: if (store.isLoaded)
        store.hasLoadedOnce = true

    signal saved

    property string saveError: ""
    function clearSaveError() {
        store.saveError = "";
    }

    // Load is parallel; the month's entry rows are folded onto habits by id once both
    // files have resolved, in whichever order they arrive.
    property bool _rosterApplied: false
    property bool _monthApplied: false
    property var _pendingEntriesByHabitId: ({})

    property JsonStore _roster: JsonStore {
        filePath: store.dataDir + "/roster.json"
        serialize: function () {
            return {
                habits: HabitsModel.toRoster(store.habits).concat(store.habitTombstones)
            };
        }
        applyLoaded: function (data) {
            store._applyRoster(data);
        }
        onSaved: store.saved()
        onSaveFailed: store.saveError = message
    }

    property JsonStore _month: JsonStore {
        filePath: store.dataDir + "/" + store.monthKey + ".json"
        serialize: function () {
            return {
                month: store.monthKey,
                entries: HabitsModel.toMonthEntryRows(store.habits)
            };
        }
        applyLoaded: function (data) {
            store._applyMonth(data);
        }
        onSaved: store.saved()
        onSaveFailed: store.saveError = message
    }

    // A habit that came off disk or off the wire, as a model row. Both sources carry every field,
    // so nothing is defaulted here — only the entry slice is optional, the roster holding none.
    function _storedItem(habit) {
        return {
            id: habit.id,
            name: habit.name,
            polarity: habit.polarity,
            isPrivate: !!habit.isPrivate,
            createdAt: habit.createdAt,
            editedAt: habit.editedAt,
            deletedAt: null,
            entriesByDate: habit.entriesByDate || ({})
        };
    }

    // A habit that does not exist yet: the only place identity and create-time are minted.
    function _newItem(name, polarity) {
        const createdAt = Date.now();

        return {
            id: Ids.newId(),
            name: name,
            polarity: polarity,
            isPrivate: false,
            createdAt: createdAt,
            editedAt: createdAt,
            deletedAt: null,
            entriesByDate: ({})
        };
    }

    // The envelope alone does not prove the shape: a pre-polarity roster is also `{ habits: [ … ] }`,
    // so accepting it on `Array.isArray` would render every negative habit as positive and drop
    // `negative` from the file on the next save — the silent overwrite ADR 0006 exists to prevent.
    // Both files therefore test a field only the shape this version writes has. `editedAt` earns its
    // place in both: a row still spelling it `updatedAt` reads back as undefined, renders fine, and
    // then syncs as edit-time 0 — losing every merge and pulling the server's copy over real data.
    // `isPrivate` earns its place the same way: a roster still spelling the flag `hideFromSleep`
    // must be refused, not folded in with every flag false — folding it in would silently render
    // private habits publicly and then drop the flags for good on the next save (the exact
    // silent-overwrite ADR 0006 exists to prevent). This same guard runs on wire rows in
    // applySynced, so a response from an older backend that has no `isPrivate` field is refused too.
    function _isRosterRow(habit) {
        return !!habit && !!habit.id && !!habit.name && !!habit.polarity && !!habit.createdAt && !!habit.editedAt && typeof habit.isPrivate === "boolean";
    }

    function _isMonthRow(row) {
        return !!row && !!row.habitId && !!row.date && !!row.editedAt;
    }

    function _applyRoster(data) {
        if (data && Array.isArray(data.habits) && data.habits.every(store._isRosterRow)) {
            const alive = data.habits.filter(habit => !habit.deletedAt).map(habit => store._storedItem(habit));
            const tombstones = data.habits.filter(habit => !!habit.deletedAt).map(habit => HabitsModel.rosterRow(habit));

            store._setRoster(alive, tombstones);
            return;
        }

        if (!Storage.isMissing(data)) {
            store._reject(store._roster, data);
            store._setRoster([], []);
            return;
        }

        // First run: no roster on disk. The seeded defaults carry name and polarity only, so those
        // rows are minted rather than read, and the file is written straight away.
        store._setRoster(DefaultHabits.habits.map(habit => store._newItem(habit.name, habit.polarity)), []);
        store._roster._doSave();
    }

    function _setRoster(items, tombstones) {
        store.habitTombstones = tombstones;

        // Bulk append — one rowsInserted vs N avoids per-row e-ink flash.
        store.habits.clear();
        if (items.length > 0) {
            store.habits.append(items);
        }

        store._rosterApplied = true;
        store._fold();
    }

    function _applyMonth(data) {
        if (data && Array.isArray(data.entries) && data.entries.every(store._isMonthRow)) {
            store._setMonthEntries(data.entries);
            return;
        }

        if (!Storage.isMissing(data)) {
            store._reject(store._month, data);
        }

        store._setMonthEntries([]);
    }

    function _setMonthEntries(rows) {
        store._pendingEntriesByHabitId = Entries.byHabitId(rows);
        store._monthApplied = true;
        store._fold();
    }

    // A file this version cannot read — unparseable, or parsed but not the shape it writes, e.g. an
    // un-migrated month — must not be folded in as empty: the next toggle would overwrite the real
    // data. Block writes to it and say why. The grid still loads, rendering the file as empty.
    function _reject(file, data) {
        file.isUnwritable = true;

        if (Storage.isCorrupt(data)) {
            store.saveError = "Couldn’t parse " + file.filePath + ". Nothing will be written to it.";
            return;
        }

        store.saveError = "Unrecognised data in " + file.filePath + ". Nothing will be written to it until it has been migrated.";
    }

    function _fold() {
        if (!store._rosterApplied || !store._monthApplied) {
            return;
        }

        const entriesByHabitId = store._pendingEntriesByHabitId || {};
        for (let i = 0; i < store.habits.count; i++) {
            const id = store.habits.get(i).id;
            store.habits.setProperty(i, "entriesByDate", entriesByHabitId[id] || ({}));
        }
    }

    function _inBounds(i) {
        return i >= 0 && i < habits.count;
    }

    function add(name, polarity) {
        const trimmed = (name || "").trim();
        if (!trimmed) {
            return;
        }

        habits.append(store._newItem(trimmed, polarity));

        _roster.scheduleSave();
    }

    function move(from, to) {
        if (!_inBounds(from) || !_inBounds(to) || from === to) {
            return;
        }

        habits.move(from, to, 1);

        // Position is the array index at sync time, so every habit whose index shifted needs a
        // fresh edit-time for the reorder to win last-write-wins.
        const now = Date.now();
        for (let i = Math.min(from, to); i <= Math.max(from, to); i++) {
            habits.setProperty(i, "editedAt", now);
        }

        _roster.scheduleSave();
    }

    // Soft delete: the habit leaves the model (so the grid and every index-based API forget it)
    // and becomes a roster tombstone the next sync pushes, so the delete can win a merge instead
    // of being resurrected by another client's stale copy.
    function remove(index) {
        if (!_inBounds(index)) {
            return;
        }

        const deletedAt = Date.now();
        const tombstone = HabitsModel.rosterRow(habits.get(index));
        tombstone.editedAt = deletedAt;
        tombstone.deletedAt = deletedAt;

        store.habitTombstones = store.habitTombstones.concat([tombstone]);
        habits.remove(index);

        _roster.scheduleSave();
    }

    // The server owns the pushed tombstones now, so stop resending them.
    function purgeHabitTombstones() {
        if (store.habitTombstones.length === 0) {
            return;
        }

        store.habitTombstones = [];
        store._roster.scheduleSave();
    }

    function togglePolarity(index) {
        if (!_inBounds(index)) {
            return;
        }
        habits.setProperty(index, "polarity", Polarity.toggled(habits.get(index).polarity));
        habits.setProperty(index, "editedAt", Date.now());
        _roster.scheduleSave();
    }

    // Stamps editedAt like togglePolarity: sync merges habits whole-row by editedAt last-write-wins,
    // so without the stamp a privacy flip would always lose to the server's copy.
    function togglePrivate(index) {
        if (!_inBounds(index)) {
            return;
        }
        habits.setProperty(index, "isPrivate", !habits.get(index).isPrivate);
        habits.setProperty(index, "editedAt", Date.now());
        _roster.scheduleSave();
    }

    function setName(index, name) {
        const trimmed = (name || "").trim();
        if (!_inBounds(index) || !trimmed) {
            return;
        }
        habits.setProperty(index, "name", trimmed);
        habits.setProperty(index, "editedAt", Date.now());
        _roster.scheduleSave();
    }

    function toggleEntry(index, dateKey) {
        if (!_inBounds(index)) {
            return;
        }

        const habit = habits.get(index);
        const entriesByDate = habit.entriesByDate || {};
        const row = Entries.toggledRow(habit.id, dateKey, habit.polarity, entriesByDate[dateKey]);

        habits.setProperty(index, "entriesByDate", Entries.withRow(entriesByDate, row));
        _month.scheduleSave();
    }

    // Overwrite local state with the authoritative result of a sync: rebuild the
    // roster in the server's order and replace the viewed month's entries. Persists both
    // files immediately. Returns false without touching anything if the server sent a habit this
    // version cannot store — the same `_isRosterRow` test the roster reader applies, run *before*
    // the save rather than after it. Without this an older backend (one whose response omits a
    // field this version requires, e.g. `isPrivate`) would be written to roster.json and then
    // refused on next launch, turning a version mismatch into an unreadable file.
    function applySynced(roster, entriesByHabitId) {
        if (!(roster || []).every(store._isRosterRow)) {
            return false;
        }

        const items = (roster || []).map(habit => {
                return store._storedItem({
                    id: habit.id,
                    name: habit.name,
                    polarity: habit.polarity,
                    isPrivate: !!habit.isPrivate,
                    createdAt: habit.createdAt,
                    editedAt: habit.editedAt,
                    entriesByDate: (entriesByHabitId || {})[habit.id] || ({})
                });
            });

        store.habits.clear();
        if (items.length > 0) {
            store.habits.append(items);
        }

        store.habitTombstones = [];

        store._roster._doSave();
        store._month._doSave();

        return true;
    }

    // Tear the grid Loader down now (drop the month store's isLoaded) so the
    // "Loading…" screen paints this frame — the instant half of a month switch.
    // The blocking read is deferred by the caller and runs in loadMonth (ADR 0004).
    function beginLoadMonth() {
        store._month.isLoaded = false;
    }

    // Swap the in-memory entries to another month's file. Flush any pending edit
    // to the *old* file first (filePath still points there until viewYear/Month
    // change), then re-point and re-read, folding the new month's entry rows onto the
    // roster. The roster (identity/config) is month-independent and stays put.
    //
    // This holds the blocking read, so the caller defers it past the teardown paint
    // (see Main.goToMonth). reload restores isLoaded to true, rebuilding the grid
    // async against the new month. No same-month early-return: after a teardown the
    // read must run to restore isLoaded even when the viewed month is unchanged
    // (e.g. hopping forward then back before the deferred load fires).
    function loadMonth(year, month) {
        store._month.flushPendingSave();

        store.viewYear = year;
        store.viewMonth = month;

        store._monthApplied = false;
        store._month.reload();
    }

    function flushPendingSave() {
        _roster.flushPendingSave();
        _month.flushPendingSave();
    }
}
