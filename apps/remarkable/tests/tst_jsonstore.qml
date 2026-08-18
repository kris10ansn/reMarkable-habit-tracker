import QtQuick 2.15
import QtTest 1.2
import "../src" as App
import "../src/js/Storage.js" as Storage
import "TestPaths.js" as TestPaths

// The persistence scaffolding every store inherits: deferred first load, 200 ms debounced save,
// the saved/saveFailed signals, and the isUnwritable block that keeps a file this version cannot
// read from being overwritten (ADR 0006).
TestCase {
    id: testCase
    name: "JsonStore"

    // Stores are built per test rather than declared, so each one loads against a path this test
    // chose. A declared store would run its deferred reload against an empty filePath first.
    Component {
        id: jsonStoreComponent

        App.JsonStore {
            property var writes: ({})

            serialize: function () {
                return writes;
            }
            applyLoaded: function (data) {
                loaded = data;
            }

            property var loaded: undefined
        }
    }

    // No serialize hook assigned — the base's own throwing default.
    Component {
        id: bareStoreComponent

        App.JsonStore {}
    }

    function path(name) {
        return TestPaths.tmpPath(`jsonstore-${name}`);
    }

    function makeStore(name, writes) {
        const store = jsonStoreComponent.createObject(testCase, { filePath: path(name) });
        store.writes = writes || { value: 1 };
        tryVerify(() => store.isLoaded, 2000, "store never finished its deferred load");

        return store;
    }

    function readBack(target) {
        tryVerify(() => !Storage.isMissing(Storage.readJson(target)), 2000, `nothing written to ${target}`);

        return Storage.readJson(target);
    }

    // --- loading --------------------------------------------------------------------------------

    // The first read is deferred past first paint, so a store is not loaded the instant it exists.
    function test_theFirstLoadIsDeferred() {
        const store = jsonStoreComponent.createObject(testCase, { filePath: path("deferred.json") });

        compare(store.isLoaded, false);
        tryVerify(() => store.isLoaded, 2000);

        store.destroy();
    }

    function test_loadHandsTheMissingSentinelToApplyLoaded() {
        const store = makeStore("absent.json");

        verify(Storage.isMissing(store.loaded));

        store.destroy();
    }

    function test_reloadRereadsTheFile() {
        const target = path("reread.json");
        Storage.writeJson(target, { generation: 1 });
        readBack(target);

        const store = makeStore("reread.json");
        compare(store.loaded.generation, 1);

        Storage.writeJson(target, { generation: 2 });
        tryVerify(() => Storage.readJson(target).generation === 2, 2000);
        store.reload();

        compare(store.loaded.generation, 2);

        store.destroy();
    }

    // --- debounced saving -----------------------------------------------------------------------

    // Rapid edits (a run of grid taps) must coalesce into one write, or e-ink stutters.
    function test_scheduleSaveIsDebounced() {
        const store = makeStore("debounced.json", { value: "first" });

        store.scheduleSave();
        verify(Storage.isMissing(Storage.readJson(path("debounced.json"))), "wrote before the debounce elapsed");

        store.writes = { value: "last" };
        store.scheduleSave();

        compare(readBack(path("debounced.json")).value, "last");

        store.destroy();
    }

    function test_savedSignalFiresOnce() {
        const store = makeStore("saved-signal.json");
        const spy = savedSpy.createObject(testCase, { target: store });

        store.scheduleSave();
        store.scheduleSave();
        store.scheduleSave();

        tryCompare(spy, "count", 1, 2000);
        wait(300);
        compare(spy.count, 1);

        spy.destroy();
        store.destroy();
    }

    // Quitting flushes rather than losing the pending edit.
    function test_flushPendingSaveWritesImmediately() {
        const store = makeStore("flushed.json", { value: "pending" });

        store.scheduleSave();
        store.flushPendingSave();

        // No tryVerify on the timer: the write itself is still an async PUT, but the debounce
        // must already be over by the time flushPendingSave returns.
        compare(readBack(path("flushed.json")).value, "pending");

        store.destroy();
    }

    function test_flushPendingSaveDoesNothingWithNoPendingEdit() {
        const store = makeStore("nothing-pending.json");
        const spy = savedSpy.createObject(testCase, { target: store });

        store.flushPendingSave();

        wait(300);
        compare(spy.count, 0);
        verify(Storage.isMissing(Storage.readJson(path("nothing-pending.json"))));

        spy.destroy();
        store.destroy();
    }

    // --- failure paths ---------------------------------------------------------------------------

    // The base has no safe default serialize: writing a fallback would clobber the file, so it
    // throws until a subclass assigns the hook, and _doSave turns that into saveFailed.
    function test_theDefaultSerializeRefusesToWrite() {
        const store = bareStoreComponent.createObject(testCase, { filePath: path("no-serialize.json") });
        tryVerify(() => store.isLoaded, 2000);

        const spy = saveFailedSpy.createObject(testCase, { target: store });
        store._doSave();

        compare(spy.count, 1);
        verify(Storage.isMissing(Storage.readJson(path("no-serialize.json"))));

        spy.destroy();
        store.destroy();
    }

    // The whole point of the flag: what is in memory is not what is on disk, so a write would
    // destroy real data. Saves stay off until the file is replaced off-device.
    function test_isUnwritableBlocksEveryWrite() {
        const target = path("unwritable.json");
        Storage.writeJson(target, { original: "keep me" });
        tryVerify(() => Storage.readJson(target).original === "keep me", 2000);

        const store = makeStore("unwritable.json", { replacement: "clobber" });
        store.isUnwritable = true;

        const spy = saveFailedSpy.createObject(testCase, { target: store });
        store.scheduleSave();
        tryCompare(spy, "count", 1, 2000);

        wait(200);
        compare(Storage.readJson(target).original, "keep me");
        compare(Storage.readJson(target).replacement, undefined);
        verify(spy.signalArguments[0][0].indexOf(target) !== -1, "the message should name the file");

        spy.destroy();
        store.destroy();
    }

    // The regression: a write into a missing dir used to report a clean save. Storage threw from
    // the request's own callback, which throws into the event loop where _doSave's catch cannot
    // see it, so the session carried on believing it had persisted.
    function test_aSaveIntoAMissingDirectoryFails() {
        const store = jsonStoreComponent.createObject(testCase, {
            filePath: `${TestPaths.tmpDir()}/no-such-dir/roster.json`
        });
        tryVerify(() => store.isLoaded, 2000);
        store.writes = { value: 1 };

        const failed = saveFailedSpy.createObject(testCase, { target: store });
        const saved = savedSpy.createObject(testCase, { target: store });
        store._doSave();

        tryCompare(failed, "count", 1, 2000);
        compare(saved.count, 0, "a save that never landed must not report success");
        verify(failed.signalArguments[0][0].indexOf("data/ folder") !== -1, "the message should name the likely cause");

        saved.destroy();
        failed.destroy();
        store.destroy();
    }

    // `saved` means the bytes are on disk, not merely queued.
    function test_savedFiresOnlyOnceTheWriteLands() {
        const store = makeStore("saved-means-landed.json", { value: "landed" });
        const spy = savedSpy.createObject(testCase, { target: store });

        store._doSave();

        tryCompare(spy, "count", 1, 2000);
        compare(Storage.readJson(path("saved-means-landed.json")).value, "landed");

        spy.destroy();
        store.destroy();
    }

    // Every read re-decides the flag, so navigating off an unreadable file and back onto a
    // readable one lifts the block.
    function test_reloadLiftsTheUnwritableBlock() {
        const store = makeStore("lift-block.json");
        store.isUnwritable = true;

        store.reload();

        compare(store.isUnwritable, false);

        store.destroy();
    }

    Component {
        id: savedSpy

        SignalSpy {
            signalName: "saved"
        }
    }

    Component {
        id: saveFailedSpy

        SignalSpy {
            signalName: "saveFailed"
        }
    }
}
