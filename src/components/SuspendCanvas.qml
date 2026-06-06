import QtQuick 2.15
import ".." as App
import "../js/SuspendRender.js" as SuspendRender
import "../js/SuspendDraw.js" as SuspendDraw

Canvas {
    id: canvas

    readonly property string targetPath: "/usr/share/remarkable/suspended.png"
    readonly property string backupPath: "/usr/share/remarkable/suspended.png.bak"
    readonly property string markerPath: "/home/root/xovi/exthome/appload/habit-tracker/.backup-done"
    readonly property string signaturePath: "/home/root/xovi/exthome/appload/habit-tracker/.sleep-sig"

    property var habits: []
    property date today: new Date()
    property bool lastRenderFailed: false
    property bool saveQueued: false
    property string phase: ""
    property int remainingSeconds: 0
    property string lastRenderedSignature: ""

    readonly property string statusText: {
        switch (canvas.phase) {
        case "pending": return canvas.remainingSeconds > 0
            ? "Saving sleep image in " + canvas.remainingSeconds + "s"
            : "Saving sleep image..."
        case "saving": return "Saving sleep image..."
        case "saved": return "Sleep image saved"
        default: return ""
        }
    }

    readonly property var drawConfig: ({
        margin: App.Theme.margin,
        habitsWidth: App.Theme.habitsWidth,
        boxSize: 40,
        boxSpacing: 5,
        rowSpacing: App.Theme.rowSpacing,
        buttonGap: App.Theme.buttonGap,
        dayLabelHeight: App.Theme.dayLabelHeight,
        titleFont: App.Theme.titleFont,
        subtitleFont: App.Theme.subtitleFont,
        labelFont: App.Theme.labelFont,
        dayLabelFont: App.Theme.dayLabelFont,
        borderWidth: App.Theme.borderWidth,
        fg: "#000000",
        bg: "#ffffff"
    })

    width: 1404
    height: 1872
    x: -2000
    visible: true
    renderStrategy: Canvas.Cooperative
    renderTarget: Canvas.Image

    Component.onCompleted: {
        SuspendRender.ensureBackup(canvas.targetPath, canvas.backupPath, canvas.markerPath)
        canvas.lastRenderedSignature = SuspendRender.readSignature(canvas.signaturePath)
    }

    Timer {
        id: debounceTimer
        interval: 3000
        repeat: false
        onTriggered: {
            statusTickTimer.stop()
            canvas.phase = "saving"
            canvas._beginAsyncRender()
        }
    }

    Timer {
        id: statusTickTimer
        interval: 1000
        repeat: true
        onTriggered: canvas.remainingSeconds = Math.max(0, canvas.remainingSeconds - 1)
    }

    onPaint: _draw()

    onPainted: {
        if (!canvas.saveQueued) return
        canvas.saveQueued = false
        Qt.callLater(canvas._save)
    }

    function scheduleRender() {
        if (_upToDate()) { _cancelPending(); return }
        canvas.phase = "pending"
        canvas.remainingSeconds = debounceTimer.interval / 1000
        debounceTimer.restart()
        statusTickTimer.restart()
    }

    function renderAsync() {
        if (!_beginSaving()) return
        _beginAsyncRender()
    }

    function renderSync() {
        if (!_beginSaving()) return
        _draw()
        canvas.saveQueued = false
        _save()
    }

    function _upToDate() {
        return SuspendDraw.computeSignature(canvas.habits, canvas.today) === canvas.lastRenderedSignature
    }

    function _beginSaving() {
        if (_upToDate()) { _cancelPending(); return false }
        debounceTimer.stop()
        statusTickTimer.stop()
        canvas.phase = "saving"
        return true
    }

    function _cancelPending() {
        debounceTimer.stop()
        statusTickTimer.stop()
        if (canvas.phase === "pending") canvas.phase = ""
    }

    function _draw() {
        SuspendDraw.draw(canvas.getContext("2d"), canvas.width, canvas.height, canvas.habits, canvas.today, canvas.drawConfig)
    }

    function _beginAsyncRender() {
        canvas.saveQueued = true
        canvas.requestPaint()
    }

    function _save() {
        const ok = canvas.save(canvas.targetPath)
        canvas.lastRenderFailed = !ok
        canvas.phase = ok ? "saved" : ""
        if (!ok) {
            console.warn("SuspendCanvas: save failed for", canvas.targetPath)
            return
        }
        canvas.lastRenderedSignature = SuspendDraw.computeSignature(canvas.habits, canvas.today)
        SuspendRender.writeSignature(canvas.signaturePath, canvas.lastRenderedSignature)
    }
}
