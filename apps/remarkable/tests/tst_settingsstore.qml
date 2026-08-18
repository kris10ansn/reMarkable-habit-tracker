import QtQuick 2.15
import QtTest 1.2
import "../src" as App
import "../src/js/Storage.js" as Storage
import "TestPaths.js" as TestPaths

TestCase {
    id: testCase
    name: "SettingsStore"

    Component {
        id: settingsStoreComponent

        App.SettingsStore {}
    }

    function path(name) {
        return TestPaths.tmpPath(`settings-${name}`);
    }

    function makeStore(name) {
        const store = settingsStoreComponent.createObject(testCase, { filePath: path(name) });
        tryVerify(() => store.isLoaded, 2000);

        return store;
    }

    function readBack(target) {
        tryVerify(() => !Storage.isMissing(Storage.readJson(target)), 2000, `nothing written to ${target}`);

        return Storage.readJson(target);
    }

    // Waiting for "not missing" isn't enough between writes to the same file — it can observe
    // an earlier write's landing rather than the one under test. Wait for the exact body each
    // step should have produced, exactly as JsonStore writers are expected to (see CLAUDE.md).
    function readBackExact(target, expected) {
        const body = JSON.stringify(expected);
        tryVerify(() => Storage.readFile(target) === body, 2000, `${target} never took the written body`);

        return Storage.readJson(target);
    }

    // Both settings are opt-in: suspend-image writing stays off and the client stays standalone
    // until the user says otherwise (ADR 0001).
    function test_defaultsAreOptOut() {
        const store = makeStore("defaults.json");

        compare(store.suspendImageEnabled, false);
        compare(store.serverUrl, "");
        compare(store.showPrivateHabits, false);

        store.destroy();
    }

    // Settings are written immediately rather than debounced — there is no run of rapid edits to
    // coalesce, and a settings change the user just made should survive an immediate quit.
    function test_settersWriteImmediately() {
        const target = path("write-through.json");
        const store = makeStore("write-through.json");

        store.setSuspendImageEnabled(true);
        readBackExact(target, { suspendImageEnabled: true, serverUrl: "", showPrivateHabits: false });

        store.setServerUrl("http://192.168.1.50:5000");
        readBackExact(target, { suspendImageEnabled: true, serverUrl: "http://192.168.1.50:5000", showPrivateHabits: false });

        store.setShowPrivateHabits(true);
        const written = readBackExact(target, { suspendImageEnabled: true, serverUrl: "http://192.168.1.50:5000", showPrivateHabits: true });
        compare(written.suspendImageEnabled, true);
        compare(written.serverUrl, "http://192.168.1.50:5000");
        compare(written.showPrivateHabits, true);

        store.destroy();
    }

    function test_settersRoundTripThroughDisk() {
        const target = path("round-trip.json");
        const first = makeStore("round-trip.json");
        first.setSuspendImageEnabled(true);
        readBackExact(target, { suspendImageEnabled: true, serverUrl: "", showPrivateHabits: false });
        first.setServerUrl("http://example.test");
        readBackExact(target, { suspendImageEnabled: true, serverUrl: "http://example.test", showPrivateHabits: false });
        first.setShowPrivateHabits(true);
        readBackExact(target, { suspendImageEnabled: true, serverUrl: "http://example.test", showPrivateHabits: true });
        first.destroy();

        const second = makeStore("round-trip.json");
        compare(second.suspendImageEnabled, true);
        compare(second.serverUrl, "http://example.test");
        compare(second.showPrivateHabits, true);

        second.destroy();
    }

    function test_setShowPrivateHabitsWritesImmediately() {
        const store = makeStore("show-private.json");

        store.setShowPrivateHabits(true);

        const written = readBack(path("show-private.json"));
        compare(written.showPrivateHabits, true);

        store.destroy();
    }

    // The settings commit applies every dirty field in one tick. Same-tick setter calls must
    // coalesce into one write — overlapping async writes to the same file corrupt it.
    function test_sameTickSettersCoalesceIntoOneWrite() {
        const target = path("coalesced.json");
        const store = makeStore("coalesced.json");
        const spy = savedSpy.createObject(testCase, { target: store });

        store.setServerUrl("http://example.test");
        store.setShowPrivateHabits(true);

        readBackExact(target, { suspendImageEnabled: false, serverUrl: "http://example.test", showPrivateHabits: true });
        tryCompare(spy, "count", 1);
        wait(200);
        compare(spy.count, 1);

        spy.destroy();
        store.destroy();
    }

    function test_setServerUrlTrims() {
        const store = makeStore("trimmed.json");

        store.setServerUrl("   http://example.test   ");

        compare(store.serverUrl, "http://example.test");

        store.destroy();
    }

    function test_settersIgnoreANoOpChange() {
        const store = makeStore("no-op.json");
        const spy = savedSpy.createObject(testCase, { target: store });

        store.setSuspendImageEnabled(false);
        store.setServerUrl("");
        store.setShowPrivateHabits(false);

        wait(200);
        compare(spy.count, 0);

        spy.destroy();
        store.destroy();
    }

    // A settings file this version cannot read falls back to the defaults rather than crashing.
    // Unlike the habit data there is nothing here worth refusing over — losing a server URL is
    // recoverable, losing a month of entries is not.
    function test_junkOnDiskFallsBackToDefaults() {
        [42, "nonsense", null, { suspendImageEnabled: "yes", serverUrl: 7, showPrivateHabits: "yes" }].forEach((junk, index) => {
            const target = path(`junk-${index}.json`);
            Storage.writeJson(target, junk);
            readBack(target);

            const store = makeStore(`junk-${index}.json`);
            compare(store.suspendImageEnabled, false, `suspendImageEnabled from ${JSON.stringify(junk)}`);
            compare(store.serverUrl, "", `serverUrl from ${JSON.stringify(junk)}`);
            compare(store.showPrivateHabits, false, `showPrivateHabits from ${JSON.stringify(junk)}`);

            store.destroy();
        });
    }

    function test_aPartialFileKeepsTheOtherDefault() {
        const target = path("partial.json");
        Storage.writeJson(target, { serverUrl: "http://only-this.test" });
        readBack(target);

        const store = makeStore("partial.json");

        compare(store.serverUrl, "http://only-this.test");
        compare(store.suspendImageEnabled, false);
        compare(store.showPrivateHabits, false);

        store.destroy();
    }

    // A settings.json written before showPrivateHabits existed keeps the setting's default rather
    // than failing to load — additive fields never require a migration (unlike the habit data).
    function test_aFileMissingShowPrivateHabitsKeepsTheDefault() {
        const target = path("missing-show-private.json");
        Storage.writeJson(target, { suspendImageEnabled: true, serverUrl: "http://example.test" });
        readBack(target);

        const store = makeStore("missing-show-private.json");

        compare(store.suspendImageEnabled, true);
        compare(store.serverUrl, "http://example.test");
        compare(store.showPrivateHabits, false);

        store.destroy();
    }

    Component {
        id: savedSpy

        SignalSpy {
            signalName: "saved"
        }
    }
}
