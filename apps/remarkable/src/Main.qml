import QtQuick 2.15
import "." as App
import "components" as App
import "js/DateUtils.js" as DateUtils
import "js/Scroll.js" as Scroll
import "js/SuspendStatus.js" as SuspendStatus

Rectangle {
    id: root
    anchors.fill: parent
    color: App.Theme.bg

    readonly property string suspendStatusText: SuspendStatus.text(suspendCanvas.phase, suspendCanvas.remainingSeconds)

    signal close

    function _waitForPendingOperations() {
        const syncInProgress = syncStore.isRequestInFlight || syncStore.status === "pending";
        const renderInProgress = suspendCanvas.phase === "saving" || suspendCanvas.phase === "pending";

        if (syncInProgress || renderInProgress) {
            Qt.callLater(() => root._waitForPendingOperations());
            return;
        }

        root.close();
    }

    function quit() {
        habitsStore.flushPendingSave();
        settingsStore.flushPendingSave();
        syncStore.flushPendingSave();

        if (landscape.canRenderSuspend) {
            suspendCanvas.renderAsync();
        }

        if (!syncStore.hasSyncedSuccessfully) {
            syncStore.abortSync();
        }

        root._waitForPendingOperations();
    }

    // Teardown flushes local state only — deliberately never syncs. A network round-trip here has
    // no frame left to report into and no way to apply the merged response, so a sync on quit can
    // only lose the result. Pending edits reach the server on the next launch's load-sync instead.
    function unloading() {
        console.log("Habit Tracker unloading");
        habitsStore.flushPendingSave();
        settingsStore.flushPendingSave();
        syncStore.flushPendingSave();
        if (landscape.canRenderSuspend)
            suspendCanvas.renderSync();
    }

    // Sync once both the habits and the sync sidecar have loaded — never before, or a first sync
    // could miss pending tombstones. Guarded to run once per launch.
    property bool _syncedOnLoad: false
    function _maybeSyncOnLoad() {
        if (root._syncedOnLoad || !habitsStore.isLoaded || !syncStore.isLoaded)
            return;

        root._syncedOnLoad = true;
        syncStore.syncNow();
    }

    function applySuspendSetting(enabled) {
        if (!enabled) {
            settingsStore.setSuspendImageEnabled(false);
            suspendCanvas.invalidateSignature();
            suspendCanvas.restore();
            return;
        }

        // The setting turns on only once the stock image is safely backed up — enabling it after a
        // failed backup overwrites an image nothing can restore (ADR 0001). The backup reports
        // asynchronously, so this cannot be a guard clause.
        suspendCanvas.backup(ok => {
            if (ok)
                settingsStore.setSuspendImageEnabled(true);
        });
    }

    Component.onCompleted: console.log("Habit Tracker loaded; size:", width, "x", height)

    App.HabitsStore {
        id: habitsStore
    }

    App.SettingsStore {
        id: settingsStore
    }

    App.SyncStore {
        id: syncStore
        filePath: habitsStore.dataDir + "/sync.json"
        habitsStore: habitsStore
        settingsStore: settingsStore
        monthKey: habitsStore.monthKey
    }

    App.SuspendCanvas {
        id: suspendCanvas
        habits: habitsStore.habits
    }

    Connections {
        target: habitsStore
        function onSaved() {
            if (!landscape.editing && landscape.canRenderSuspend)
                suspendCanvas.scheduleRender();
            syncStore.scheduleSync();
        }
        function onIsLoadedChanged() {
            root._maybeSyncOnLoad();
        }
    }

    Connections {
        target: syncStore
        function onIsLoadedChanged() {
            root._maybeSyncOnLoad();
        }
    }

    // Render once the feature becomes enabled — covers both the Settings commit
    // and settings.json loading after the grid is already built.
    Connections {
        target: settingsStore
        function onSuspendImageEnabledChanged() {
            if (landscape.canRenderSuspend && landscape.gridReady && !landscape.editing)
                suspendCanvas.renderAsync();
        }
    }

    Item {
        id: landscape
        anchors.centerIn: parent
        width: parent.height
        height: parent.width
        rotation: 90

        property date today: new Date()
        property int currentDay: today.getDate()
        property int currentYear: today.getFullYear()
        property int currentMonth: today.getMonth()
        property bool editing: false
        property int pendingDeleteIndex: -1
        property string currentView: "grid"

        // The month on screen. Starts on the real current month; the header arrows
        // move it. The grid, the day count, and (via habitsStore) the loaded entries
        // and sync unit all follow it. Only the real current month highlights today
        // and drives the suspend image.
        property int viewYear: currentYear
        property int viewMonth: currentMonth
        readonly property bool isCurrentMonth: viewYear === currentYear && viewMonth === currentMonth
        readonly property bool viewIsAfterCurrent: viewYear > currentYear || (viewYear === currentYear && viewMonth > currentMonth)
        readonly property date viewDate: isCurrentMonth ? today : new Date(viewYear, viewMonth, 1)
        property int daysInMonth: DateUtils.daysInMonth(viewDate)

        readonly property int highlightDay: isCurrentMonth ? currentDay : 0
        readonly property int lastNonFutureDay: isCurrentMonth ? currentDay : (viewIsAfterCurrent ? 0 : daysInMonth)

        // The precondition every suspend render shares: the feature is on, the real current month
        // is on screen, and the grid is showing what is actually on disk — an unreadable file
        // renders as an empty month, which must never reach the suspend image.
        readonly property bool canRenderSuspend: settingsStore.suspendImageEnabled && isCurrentMonth && !habitsStore.hasUnreadableData

        // Tear the grid down and repoint the header this frame for instant feedback,
        // then defer the blocking month read past the paint (mirrors the deferred
        // first-open read). Qt.callLater dedups, so rapid hops collapse to a single
        // load of the final month; _loadViewedMonth reads whatever month is on screen.
        function goToMonth(year, month) {
            if (landscape.viewYear === year && landscape.viewMonth === month)
                return;

            habitsStore.beginLoadMonth();
            landscape.viewYear = year;
            landscape.viewMonth = month;

            Qt.callLater(landscape._loadViewedMonth);
        }

        function _loadViewedMonth() {
            habitsStore.loadMonth(landscape.viewYear, landscape.viewMonth);
            landscape.recenterScroll();

            // Pull the arrived-at month from the server (no-op when standalone).
            syncStore.syncNow();

            if (!landscape.canRenderSuspend) {
                // A render debounced against the current month must not fire now that the model
                // holds another month — or a month that could not be read.
                suspendCanvas.cancelPending();
                return;
            }

            // Back on the current month: refresh the suspend image if it drifted
            // while we were away (e.g. suspend enabled mid-browse). scheduleRender
            // self-dedups, so an unchanged current month costs nothing.
            if (!landscape.editing)
                suspendCanvas.scheduleRender();
        }

        function goToPreviousMonth() {
            const previous = new Date(landscape.viewYear, landscape.viewMonth - 1, 1);
            landscape.goToMonth(previous.getFullYear(), previous.getMonth());
        }

        function goToNextMonth() {
            const next = new Date(landscape.viewYear, landscape.viewMonth + 1, 1);
            landscape.goToMonth(next.getFullYear(), next.getMonth());
        }

        function goToCurrentMonth() {
            landscape.goToMonth(landscape.currentYear, landscape.currentMonth);
        }

        function recenterScroll() {
            landscape.scrollX = landscape.isCurrentMonth
                ? Scroll.centerOnDay(landscape.currentDay, landscape.viewportWidth, App.Theme.boxSize, App.Theme.boxSpacing, landscape.maxScrollX)
                : 0;
        }

        onEditingChanged: if (!editing && canRenderSuspend)
            suspendCanvas.renderAsync()

        property int step: App.Theme.boxSize + App.Theme.boxSpacing
        property int habitsRowWidth: App.Theme.habitsWidth + (editing ? App.Theme.editingExtraWidth : 0)
        property int viewportWidth: width - 2 * App.Theme.margin - habitsRowWidth - App.Theme.labelGap - 2 * App.Theme.buttonWidth - 2 * App.Theme.buttonGap - (canScrollY ? App.Theme.buttonWidth + App.Theme.buttonGap : 0)
        property int contentWidth: daysInMonth * App.Theme.boxSize + (daysInMonth - 1) * App.Theme.boxSpacing
        property int maxScrollX: Math.max(0, contentWidth - viewportWidth)
        property int scrollX: 0

        readonly property bool gridReady: gridLoader.status === Loader.Ready
        readonly property bool loading: !gridReady

        // The month-nav arrows gate on the store's first-ever load only, not on the
        // per-switch teardown/rebuild — so you can keep hopping while a switch is in
        // flight (hasLoadedOnce stays true across the transient isLoaded drop).
        readonly property bool dataLoading: !habitsStore.hasLoadedOnce

        onViewportWidthChanged: recenterScroll()

        // Vertical scrolling for when the habit rows overflow the available height.
        property int viewportHeight: height - 2 * App.Theme.margin - monthHeaderRow.height - App.Theme.quitButtonHeight - 2 * App.Theme.rowSpacing
        property int bodyViewportHeight: viewportHeight - App.Theme.dayLabelHeight - App.Theme.rowSpacing
        property int rowStep: App.Theme.boxSize + App.Theme.rowSpacing
        property int scrollRows: Math.max(1, Math.floor(bodyViewportHeight / rowStep) - 1)
        property int maxScrollY: Math.max(0, (gridLoader.item ? gridLoader.item.bodyContentHeight : 0) - bodyViewportHeight)
        property bool canScrollY: maxScrollY > 0
        property int scrollY: 0

        onMaxScrollYChanged: if (scrollY > maxScrollY)
            scrollY = maxScrollY

        Item {
            id: gridView
            anchors.fill: parent
            visible: landscape.currentView === "grid"

            // Hide keyboard if clicked outside of input
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: Qt.inputMethod.hide()
            }

            Column {
                anchors.fill: parent
                anchors.margins: App.Theme.margin
                spacing: App.Theme.rowSpacing

                App.MonthNavHeader {
                    id: monthHeaderRow
                    date: landscape.viewDate
                    isCurrentMonth: landscape.isCurrentMonth
                    warn: suspendCanvas.lastRenderFailed
                    disabled: landscape.dataLoading
                    onPreviousRequested: landscape.goToPreviousMonth()
                    onNextRequested: landscape.goToNextMonth()
                    onCurrentRequested: landscape.goToCurrentMonth()
                }

                Row {
                    spacing: App.Theme.buttonGap

                    App.HabitsColumn {
                        habits: habitsStore.habits
                        editing: landscape.editing
                        showPrivateHabits: settingsStore.showPrivateHabits
                        rowWidth: landscape.habitsRowWidth
                        viewportHeight: landscape.viewportHeight
                        scrollY: landscape.scrollY
                        onRemoveRequested: landscape.pendingDeleteIndex = index
                        onPolarityToggled: habitsStore.togglePolarity(index)
                        onPrivateToggled: habitsStore.togglePrivate(index)
                        onNameEdited: habitsStore.setName(index, newName)
                        onMoveRequested: habitsStore.move(from, to)
                        onAddRequested: habitsStore.add(name, polarity)
                    }

                    App.SideScrollButton {
                        text: "‹"
                        disabled: landscape.loading || landscape.scrollX <= 0
                        contentHeight: landscape.viewportHeight
                        onClicked: landscape.scrollX = Scroll.scrollByBoxes(landscape.scrollX, -7, landscape.step, landscape.maxScrollX)
                    }

                    // Async + gated + hidden-until-Ready: builds the ~600-item
                    // subtree off the main thread against a populated model, and
                    // never exposes partial e-ink state. Canvas paint chains off
                    // onLoaded to avoid main-thread contention with the build.
                    Loader {
                        id: gridLoader
                        width: landscape.viewportWidth
                        height: landscape.viewportHeight
                        asynchronous: true
                        active: habitsStore.isLoaded
                        visible: status === Loader.Ready
                        onLoaded: if (landscape.canRenderSuspend)
                            suspendCanvas.renderAsync()

                        sourceComponent: Component {
                            App.HabitsGrid {
                                width: landscape.viewportWidth
                                viewportHeight: landscape.viewportHeight
                                habits: habitsStore.habits
                                showPrivateHabits: settingsStore.showPrivateHabits
                                daysInMonth: landscape.daysInMonth
                                highlightDay: landscape.highlightDay
                                lastNonFutureDay: landscape.lastNonFutureDay
                                year: landscape.viewYear
                                month: landscape.viewMonth
                                editing: landscape.editing
                                scrollX: landscape.scrollX
                                scrollY: landscape.scrollY
                                onEntryToggled: habitsStore.toggleEntry(index, dateKey)
                            }
                        }
                    }

                    // Occupies the grid's exact footprint while the async Loader
                    // builds, so the invisible Loader doesn't collapse the Row and
                    // jam the ‹ / › buttons together.
                    App.AppButton {
                        width: landscape.viewportWidth
                        height: landscape.viewportHeight
                        visible: !landscape.gridReady
                        text: "Loading…"
                        fontSize: App.Theme.titleFont
                        disabled: true
                    }

                    App.SideScrollButton {
                        text: "›"
                        disabled: landscape.loading || landscape.scrollX >= landscape.maxScrollX
                        contentHeight: landscape.viewportHeight
                        onClicked: landscape.scrollX = Scroll.scrollByBoxes(landscape.scrollX, 7, landscape.step, landscape.maxScrollX)
                    }

                    // Vertical ↑ / ↓ buttons scroll a page of habits; shown only when they overflow the height.
                    App.VerticalScrollButtons {
                        visible: landscape.canScrollY
                        buttonHeight: (landscape.bodyViewportHeight - App.Theme.rowSpacing) / 2
                        upDisabled: landscape.loading || landscape.scrollY <= 0
                        downDisabled: landscape.loading || landscape.scrollY >= landscape.maxScrollY
                        onScrollUp: landscape.scrollY = Scroll.scrollByBoxes(landscape.scrollY, -landscape.scrollRows, landscape.rowStep, landscape.maxScrollY)
                        onScrollDown: landscape.scrollY = Scroll.scrollByBoxes(landscape.scrollY, landscape.scrollRows, landscape.rowStep, landscape.maxScrollY)
                    }
                }
            }

            App.GridBottomBar {
                anchors.fill: parent
                editing: landscape.editing
                loading: landscape.loading
                suspendStatusText: root.suspendStatusText
                syncStatusText: syncStore.statusText
                onEditToggled: landscape.editing = !landscape.editing
                onSettingsRequested: landscape.currentView = "settings"
                onQuitRequested: quit()
            }

            App.ConfirmDialog {
                visible: landscape.pendingDeleteIndex >= 0
                message: visible ? "Delete “" + habitsStore.habits.get(landscape.pendingDeleteIndex).name + "”?" : ""
                confirmText: "Delete"
                onConfirmed: {
                    habitsStore.remove(landscape.pendingDeleteIndex);
                    landscape.pendingDeleteIndex = -1;
                }
                onCancelled: landscape.pendingDeleteIndex = -1
            }
        }

        App.SettingsPage {
            anchors.fill: parent
            visible: landscape.currentView === "settings"
            suspendImageEnabled: settingsStore.suspendImageEnabled
            showPrivateHabits: settingsStore.showPrivateHabits
            serverUrl: settingsStore.serverUrl
            syncStatusText: syncStore.statusText
            onApplyRequested: root.applySuspendSetting(value)
            onShowPrivateHabitsApplied: settingsStore.setShowPrivateHabits(value)
            onServerUrlApplied: {
                settingsStore.setServerUrl(url);
                syncStore.syncNow();
            }
            onSyncNowRequested: syncStore.syncNow()
            onBackRequested: landscape.currentView = "grid"
        }

        App.ConfirmDialog {
            visible: habitsStore.saveError !== ""
            acknowledgeOnly: true
            confirmText: "Dismiss"
            message: "Couldn’t save to storage — your changes are only in memory.\n\n" + habitsStore.saveError
            onConfirmed: habitsStore.clearSaveError()
            onCancelled: habitsStore.clearSaveError()
        }

        App.ConfirmDialog {
            visible: syncStore.status === "error" && syncStore.errorMessage !== ""
            acknowledgeOnly: true
            confirmText: "Dismiss"
            message: "Sync failed: " + syncStore.errorMessage + ". Check the sync server address in Settings."
            onConfirmed: syncStore.clearError()
            onCancelled: syncStore.clearError()
        }
    }
}
