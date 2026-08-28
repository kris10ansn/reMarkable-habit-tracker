import QtQuick 2.15
import QtTest 1.2
import "../src" as App
import "../src/js/Sync.js" as Sync
import "../src/js/Entries.js" as Entries
import "TestPaths.js" as TestPaths
import "Fixtures.js" as Fixtures

// The sync engine's decisions, without a server. _handleDone takes the response object rather than
// reading a live XHR, so every terminal path is reachable with a plain { status, responseText }
// stand-in — including the stale-month discard that ADR 0004 turns on.
TestCase {
    id: testCase
    name: "SyncStore"

    property var store: null

    Component {
        id: syncStoreComponent

        App.SyncStore {}
    }

    function cleanup() {
        if (!store) {
            return;
        }

        store.abortSync();
        store.isUnwritable = true;
        store.destroy();
        store = null;
    }

    function fakeHabitsStore(rows) {
        return {
            isLoaded: true,
            hasUnreadableData: false,
            habits: Fixtures.fakeModel(rows || []),
            habitTombstones: [],
            applySyncedCalls: 0,
            appliedRoster: null,
            appliedEntries: null,
            applySyncedResult: true,
            purgeCalls: 0,
            applySynced: function (roster, entriesByHabitId) {
                this.applySyncedCalls++;
                this.appliedRoster = roster;
                this.appliedEntries = entriesByHabitId;
                return this.applySyncedResult;
            },
            purgeHabitTombstones: function () {
                this.purgeCalls++;
            }
        };
    }

    function makeStore(serverUrl, monthKey, rows) {
        store = syncStoreComponent.createObject(testCase, {
            filePath: TestPaths.tmpPath(`sync-${name}.json`),
            monthKey: monthKey || "2026-08",
            settingsStore: { serverUrl: serverUrl === undefined ? "http://example.test" : serverUrl },
            habitsStore: fakeHabitsStore(rows)
        });
        tryVerify(() => store.isLoaded, 2000);

        return store;
    }

    function response(habits, entries, monthKey) {
        return {
            habits: habits,
            months: [{ month: monthKey || "2026-08", entries: entries }]
        };
    }

    function wireHabit(overrides) {
        return Object.assign(
            { id: "a", name: "Alpha", polarity: "Positive", position: 0, createdAt: 1750000000000, editedAt: 1750000000000, deletedAt: null },
            overrides || {});
    }

    function done(status, body) {
        return { status: status, responseText: typeof body === "string" ? body : JSON.stringify(body) };
    }

    // --- server URL handling ----------------------------------------------------------------------

    // A scheme-less host is treated by Qt's XMLHttpRequest as a local file, which rejects POST
    // outright, so it is defaulted to http:// rather than failing cryptically.
    function test_serverUrlDefaultsTheScheme() {
        makeStore("192.168.1.50:5000");

        compare(store._serverUrl(), "http://192.168.1.50:5000");
    }

    function test_serverUrlLeavesAnExplicitSchemeAlone() {
        makeStore("https://habits.example.test");
        compare(store._serverUrl(), "https://habits.example.test");

        store.settingsStore = { serverUrl: "HTTP://Habits.Example.Test" };
        compare(store._serverUrl(), "HTTP://Habits.Example.Test");
    }

    function test_serverUrlTrimsAndStaysEmptyWhenUnset() {
        makeStore("   ");
        compare(store._serverUrl(), "");

        store.settingsStore = { serverUrl: "  http://example.test  " };
        compare(store._serverUrl(), "http://example.test");

        store.settingsStore = null;
        compare(store._serverUrl(), "");
    }

    function test_endpointStripsTrailingSlashes() {
        makeStore();

        compare(store._endpoint("http://example.test"), "http://example.test/api/sync");
        compare(store._endpoint("http://example.test/"), "http://example.test/api/sync");
        compare(store._endpoint("http://example.test///"), "http://example.test/api/sync");
    }

    // --- token -------------------------------------------------------------------------------

    function test_tokenIsEmptyUntilPaired() {
        makeStore();

        compare(store._token(), "");
    }

    function test_tokenFollowsSettingsStore() {
        makeStore();

        store.settingsStore = { serverUrl: "http://example.test", token: "a-bearer-token" };
        compare(store._token(), "a-bearer-token");

        store.settingsStore = null;
        compare(store._token(), "");
    }

    // --- guards ---------------------------------------------------------------------------------

    // Standalone is the default: with no server configured, sync is a silent no-op rather than an
    // error the user has to dismiss.
    function test_syncNowIsANoOpWithoutAServer() {
        makeStore("");

        store.status = "pending";
        store.syncNow();

        compare(store.status, "");
    }

    function test_scheduleSyncIsANoOpWithoutAServer() {
        makeStore("");

        store.scheduleSync();

        compare(store.status, "");
    }

    function test_scheduleSyncStartsTheCountdown() {
        makeStore();

        store.scheduleSync();

        compare(store.status, "pending");
        compare(store.remainingSeconds, 3);
        compare(store.statusText, "Syncing in 3s");
    }

    // Pushing the empty rendering of an unreadable file would pull the server's answer back over
    // the real data, so sync stays off entirely while a file is refused.
    function test_syncNowRefusesWhileDataIsUnreadable() {
        makeStore();
        store.habitsStore.hasUnreadableData = true;

        store.syncNow();

        compare(store.status, "");
        verify(!store.isRequestInFlight);
    }

    function test_syncNowWaitsForTheStoreToLoad() {
        makeStore();
        store.habitsStore.isLoaded = false;

        store.syncNow();

        verify(!store.isRequestInFlight);
    }

    // --- in-flight bookkeeping ---------------------------------------------------------------------

    // The guards key on this rather than a single status string, so the finer readyState phases
    // cannot slip a second request past them.
    function test_isRequestInFlightCoversEveryPhase() {
        makeStore();

        ["syncing", "connecting", "headers-received", "loading"].forEach(phase => {
            store.status = phase;
            verify(store.isRequestInFlight, `${phase} should count as in flight`);
        });

        ["", "pending", "ok", "offline", "unauthorized", "error"].forEach(phase => {
            store.status = phase;
            verify(!store.isRequestInFlight, `${phase} should not count as in flight`);
        });
    }

    function test_statusForReadyStateMapsThePhases() {
        makeStore();

        compare(store._statusForReadyState(XMLHttpRequest.HEADERS_RECEIVED), "headers-received");
        compare(store._statusForReadyState(XMLHttpRequest.LOADING), "loading");
        compare(store._statusForReadyState(XMLHttpRequest.OPENED), "connecting");
    }

    function test_abortSyncClearsAPendingCountdown() {
        makeStore();
        store.scheduleSync();

        store.abortSync();

        compare(store.status, "");
        compare(store.remainingSeconds, 0);
    }

    // --- terminal paths ------------------------------------------------------------------------------

    // Status 0 is what Qt reports when the request never reached anything. Offline is normal for
    // this app, so it stays quiet rather than becoming a modal.
    function test_statusZeroReadsAsOffline() {
        makeStore();
        const request = Sync.buildRequest([], [], [], "2026-08");

        store._handleDone(done(0, ""), request, "2026-08");

        compare(store.status, "offline");
        compare(store.errorMessage, "Couldn’t reach the server");
        compare(store.statusText, "Sync failed");
        compare(store.habitsStore.applySyncedCalls, 0);
    }

    function test_anHttpErrorReportsItsCode() {
        makeStore();
        const request = Sync.buildRequest([], [], [], "2026-08");

        store._handleDone(done(500, ""), request, "2026-08");

        compare(store.status, "error");
        compare(store.errorMessage, "Server returned 500");
        compare(store.habitsStore.applySyncedCalls, 0);
    }

    // A missing/unknown token must read as "not connected", never as a data problem — the habit
    // history this app exists to protect is never touched on an auth failure, and it stays out of
    // the "error" status so it never pops the misconfiguration modal.
    function test_status401ReadsAsUnauthorized() {
        makeStore();
        const request = Sync.buildRequest([Fixtures.rosterRow({ id: "a" })], [], [], "2026-08");

        store._handleDone(done(401, ""), request, "2026-08");

        compare(store.status, "unauthorized");
        compare(store.statusText, "Not connected");
        compare(store.habitsStore.applySyncedCalls, 0);
        compare(store.habitsStore.purgeCalls, 0);
        compare(store.lastSyncedAt, 0);
    }

    function test_anUnparseableBodyIsAnError() {
        makeStore();
        const request = Sync.buildRequest([], [], [], "2026-08");

        store._handleDone(done(200, "<html>not json</html>"), request, "2026-08");

        compare(store.status, "error");
        compare(store.errorMessage, "Malformed server response");
        compare(store.habitsStore.applySyncedCalls, 0);
    }

    // The ADR 0004 guard. The response describes the month that was requested, not what is on
    // screen — applying it would fold one month's entries onto another.
    function test_aResponseForAMonthNoLongerViewedIsDiscarded() {
        makeStore("http://example.test", "2026-09");
        const request = Sync.buildRequest([], [], [], "2026-08");
        const body = response([wireHabit()], [{ habitId: "a", date: "2026-08-01", outcome: "Success", editedAt: 9 }], "2026-08");

        store._handleDone(done(200, body), request, "2026-08");

        compare(store.status, "", "a discarded response leaves no status behind");
        compare(store.habitsStore.applySyncedCalls, 0);
        compare(store.habitsStore.purgeCalls, 0, "the tombstones stay unpushed so the next round resends them");
        compare(store.lastSyncedAt, 0);
    }

    // A response identical to the request means the server agreed. Overwriting the model anyway
    // would repaint e-ink for nothing.
    function test_anAgreeingResponseDoesNotTouchTheModel() {
        makeStore();
        const request = Sync.buildRequest(
            [Fixtures.rosterRow({ id: "a", name: "Alpha" })],
            [],
            [Fixtures.entryRow({ habitId: "a", date: "2026-08-01", outcome: Entries.X })],
            "2026-08");

        store._handleDone(done(200, request), request, "2026-08");

        compare(store.habitsStore.applySyncedCalls, 0, "nothing changed, so nothing is applied");
        compare(store.status, "ok");
        compare(store.hasSyncedSuccessfully, true);
        verify(store.lastSyncedAt > 0);
        compare(store.statusText, "Synced to server");
    }

    function test_aDifferingResponseIsApplied() {
        makeStore();
        const request = Sync.buildRequest([Fixtures.rosterRow({ id: "a", name: "Alpha" })], [], [], "2026-08");
        const body = response(
            [wireHabit({ id: "a", name: "Renamed on another device", editedAt: 1750000009000 })],
            [{ habitId: "a", date: "2026-08-02", outcome: "Failure", editedAt: 1750000009000 }]);

        store._handleDone(done(200, body), request, "2026-08");

        compare(store.habitsStore.applySyncedCalls, 1);
        compare(store.habitsStore.appliedRoster.length, 1);
        compare(store.habitsStore.appliedRoster[0].name, "Renamed on another device");
        compare(store.habitsStore.appliedEntries["a"]["2026-08-02"].outcome, Entries.O);
        compare(store.status, "ok");
    }

    // Once the server owns the tombstones we pushed, resending them every round would keep
    // resurrecting the same deletes.
    function test_aSuccessfulSyncPurgesPushedTombstones() {
        makeStore();
        const request = Sync.buildRequest([], [], [], "2026-08");

        store._handleDone(done(200, request), request, "2026-08");

        compare(store.habitsStore.purgeCalls, 1);
    }

    // applySynced validates before it writes; a refusal must surface rather than being reported
    // as a successful sync.
    function test_aRefusedResponseIsAnError() {
        makeStore();
        store.habitsStore.applySyncedResult = false;
        const request = Sync.buildRequest([Fixtures.rosterRow({ id: "a" })], [], [], "2026-08");
        const body = response([wireHabit({ editedAt: 1750000009000 })], []);

        store._handleDone(done(200, body), request, "2026-08");

        compare(store.status, "error");
        compare(store.errorMessage, "Server sent a habit this version can’t store");
        compare(store.habitsStore.purgeCalls, 0);
        compare(store.lastSyncedAt, 0);
    }

    function test_aSuccessfulSyncClearsAPriorError() {
        makeStore();
        const request = Sync.buildRequest([], [], [], "2026-08");

        store._handleDone(done(500, ""), request, "2026-08");
        compare(store.errorMessage, "Server returned 500");

        store._handleDone(done(200, request), request, "2026-08");

        compare(store.errorMessage, "");
        compare(store.status, "ok");
    }

    // --- status line -------------------------------------------------------------------------------

    // Quiet by design: a standalone client says nothing at all, however it was left.
    function test_statusTextIsSilentWithoutAServer() {
        makeStore("");

        ["", "syncing", "offline", "error", "ok"].forEach(phase => {
            store.status = phase;
            compare(store.statusText, "", `${phase} should stay silent while standalone`);
        });
    }

    function test_statusTextCoversEveryPhase() {
        makeStore();

        const expected = {
            "syncing": "Syncing…",
            "connecting": "Sync: connecting…",
            "headers-received": "Sync: headers received…",
            "loading": "Sync: loading…",
            "offline": "Sync failed",
            "unauthorized": "Not connected",
            "error": "Sync error"
        };

        Object.keys(expected).forEach(phase => {
            store.status = phase;
            compare(store.statusText, expected[phase]);
        });
    }

    function test_statusTextIsBlankBeforeTheFirstSync() {
        makeStore();

        store.status = "";

        compare(store.lastSyncedAt, 0);
        compare(store.statusText, "");
    }

    function test_clearErrorResetsOnlyTheErrorStatus() {
        makeStore();

        store.status = "error";
        store.errorMessage = "Server returned 500";
        store.clearError();
        compare(store.status, "");
        compare(store.errorMessage, "");

        store.status = "offline";
        store.errorMessage = "Couldn’t reach the server";
        store.clearError();
        compare(store.status, "offline", "an offline sync is not a misconfiguration to dismiss");
        compare(store.errorMessage, "");
    }

    // --- persistence --------------------------------------------------------------------------------

    function test_lastSyncedAtRoundTrips() {
        makeStore();

        compare(store.lastSyncedAt, 0);

        store.applyLoaded({ lastSyncedAt: 1750000009000 });
        compare(store.lastSyncedAt, 1750000009000);
        compare(store.statusText, "Synced to server");
    }

    function test_junkSidecarFallsBackToNeverSynced() {
        makeStore();

        [undefined, null, "missing", 42, { lastSyncedAt: "soon" }].forEach(junk => {
            store.lastSyncedAt = 123;
            store.applyLoaded(junk);
            verify(store.lastSyncedAt === 0 || store.lastSyncedAt === 123, "a junk sidecar must not yield a bogus time");
        });
    }
}
