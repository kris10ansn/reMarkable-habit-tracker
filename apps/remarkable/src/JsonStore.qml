import QtQuick 2.15
import "js/Storage.js" as Storage

// Persistence scaffolding shared by the concrete stores. A subclass sets
// `filePath` and assigns the `serialize` / `applyLoaded` hooks; it inherits the
// deferred initial load, debounced save, `saved` signal, and flush-on-quit.
QtObject {
    id: jsonStore

    property string filePath: ""
    property bool isLoaded: false

    // Set by applyLoaded when the file holds something this version cannot read. What is in memory
    // is then not what is on disk, so a write would destroy the real data — saves stay off until
    // the file is replaced off-device. The rejecting store reports the cause; this base only
    // enforces the block.
    property bool isUnwritable: false

    signal saved
    signal saveFailed(string message)

    // serialize() -> the value to write. applyLoaded(data) folds a just-read
    // value (or a Storage MISSING/CORRUPT sentinel) into in-memory state.
    // serialize has no safe default: writing its fallback would clobber the
    // file, so the base throws until a subclass assigns the hook.
    property var serialize: (function () {
            throw new Error("JsonStore: subclass must assign serialize before saving");
        })
    property var applyLoaded: (function (data) {})

    property Timer _saveTimer: Timer {
        interval: 200
        repeat: false
        onTriggered: jsonStore._doSave()
    }

    // Defer past first paint.
    Component.onCompleted: Qt.callLater(jsonStore.reload)

    // Read the (possibly re-pointed) file into memory — once on startup, and again whenever a
    // store swaps filePath at runtime, e.g. month navigation. Restores isLoaded to true; a caller
    // that wants the dependent Loader to tear down and rebuild first sets isLoaded false before
    // calling (see HabitsStore.loadMonth). Every read re-decides isUnwritable, so navigating off
    // an unreadable file and back onto a readable one lifts the block.
    function reload() {
        jsonStore.isUnwritable = false;
        jsonStore.applyLoaded(Storage.readJson(jsonStore.filePath));
        jsonStore.isLoaded = true;
    }

    function scheduleSave() {
        jsonStore._saveTimer.restart();
    }

    function flushPendingSave() {
        if (!jsonStore._saveTimer.running) {
            return;
        }

        jsonStore._saveTimer.stop();
        jsonStore._doSave();
    }

    function _doSave() {
        if (jsonStore.isUnwritable) {
            jsonStore.saveFailed("Nothing is written to " + jsonStore.filePath + " while its contents are unreadable.");
            return;
        }

        try {
            Storage.writeJson(jsonStore.filePath, jsonStore.serialize(), jsonStore._onWriteDone);
        } catch (e) {
            jsonStore._onWriteDone(String(e));
        }
    }

    // The write only reports once it has landed, so `saved` means the bytes are on disk rather
    // than merely queued — which is what makes a missing data/ dir a visible modal instead of a
    // silent no-op the session then believes it persisted.
    function _onWriteDone(error) {
        if (error) {
            console.warn("JsonStore: save failed for", jsonStore.filePath, "-", error);
            jsonStore.saveFailed("Check that the data/ folder exists on the device.\n\n" + error);
            return;
        }

        jsonStore.saved();
    }
}
