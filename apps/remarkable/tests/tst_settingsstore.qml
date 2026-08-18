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

    // Both settings are opt-in: suspend-image writing stays off and the client stays standalone
    // until the user says otherwise (ADR 0001).
    function test_defaultsAreOptOut() {
        const store = makeStore("defaults.json");

        compare(store.suspendImageEnabled, false);
        compare(store.serverUrl, "");

        store.destroy();
    }

    // Settings are written immediately rather than debounced — there is no run of rapid edits to
    // coalesce, and a settings change the user just made should survive an immediate quit.
    function test_settersWriteImmediately() {
        const store = makeStore("write-through.json");

        store.setSuspendImageEnabled(true);
        store.setServerUrl("http://192.168.1.50:5000");

        const written = readBack(path("write-through.json"));
        compare(written.suspendImageEnabled, true);
        compare(written.serverUrl, "http://192.168.1.50:5000");

        store.destroy();
    }

    function test_settersRoundTripThroughDisk() {
        const first = makeStore("round-trip.json");
        first.setSuspendImageEnabled(true);
        first.setServerUrl("http://example.test");
        readBack(path("round-trip.json"));
        first.destroy();

        const second = makeStore("round-trip.json");
        compare(second.suspendImageEnabled, true);
        compare(second.serverUrl, "http://example.test");

        second.destroy();
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

        wait(200);
        compare(spy.count, 0);

        spy.destroy();
        store.destroy();
    }

    // A settings file this version cannot read falls back to the defaults rather than crashing.
    // Unlike the habit data there is nothing here worth refusing over — losing a server URL is
    // recoverable, losing a month of entries is not.
    function test_junkOnDiskFallsBackToDefaults() {
        [42, "nonsense", null, { suspendImageEnabled: "yes", serverUrl: 7 }].forEach((junk, index) => {
            const target = path(`junk-${index}.json`);
            Storage.writeJson(target, junk);
            readBack(target);

            const store = makeStore(`junk-${index}.json`);
            compare(store.suspendImageEnabled, false, `suspendImageEnabled from ${JSON.stringify(junk)}`);
            compare(store.serverUrl, "", `serverUrl from ${JSON.stringify(junk)}`);

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

        store.destroy();
    }

    Component {
        id: savedSpy

        SignalSpy {
            signalName: "saved"
        }
    }
}
