import QtQuick 2.15

JsonStore {
    id: settingsStore

    filePath: "/home/root/xovi/exthome/appload/habit-tracker/settings.json"

    // Whether the app overwrites the device suspend image with the grid.
    // Opt-in: off until the user turns it on in Settings.
    property bool suspendImageEnabled: false

    // The backend this client syncs with. Empty = standalone (no sync attempts).
    property string serverUrl: ""

    // Reveal private habits on the main grid. Device-local by design — privacy is
    // per-surface, so it never syncs.
    property bool showPrivateHabits: false

    serialize: function () {
        return {
            suspendImageEnabled: settingsStore.suspendImageEnabled,
            serverUrl: settingsStore.serverUrl,
            showPrivateHabits: settingsStore.showPrivateHabits
        };
    }

    applyLoaded: function (data) {
        if (!data || typeof data !== "object") {
            return;
        }

        if (typeof data.suspendImageEnabled === "boolean") {
            settingsStore.suspendImageEnabled = data.suspendImageEnabled;
        }
        if (typeof data.serverUrl === "string") {
            settingsStore.serverUrl = data.serverUrl;
        }
        if (typeof data.showPrivateHabits === "boolean") {
            settingsStore.showPrivateHabits = data.showPrivateHabits;
        }
    }

    // Settings write through immediately rather than on JsonStore's debounce — a change the
    // user just committed should survive an immediate quit. But the settings commit applies
    // every dirty field in one tick, and overlapping async writes to the same file interleave
    // and corrupt it, so same-tick setter calls coalesce into a single write of the final
    // state (Qt.callLater collapses repeated calls to the same function).
    function _saveCoalesced() {
        Qt.callLater(settingsStore._doSave);
    }

    function setSuspendImageEnabled(value) {
        const next = !!value;
        if (next === settingsStore.suspendImageEnabled) {
            return;
        }

        settingsStore.suspendImageEnabled = next;
        settingsStore._saveCoalesced();
    }

    function setShowPrivateHabits(value) {
        const next = !!value;
        if (next === settingsStore.showPrivateHabits) {
            return;
        }

        settingsStore.showPrivateHabits = next;
        settingsStore._saveCoalesced();
    }

    function setServerUrl(value) {
        const next = (value || "").trim();
        if (next === settingsStore.serverUrl) {
            return;
        }

        settingsStore.serverUrl = next;
        settingsStore._saveCoalesced();
    }
}
