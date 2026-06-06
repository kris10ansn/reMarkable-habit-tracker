import QtQuick 2.15
import ".." as App
import "../js/SuspendRender.js" as SuspendRender
import "../js/SuspendDraw.js" as SuspendDraw

Canvas {
    id: canvas

    readonly property string targetPath: "/usr/share/remarkable/suspended.png"
    readonly property string backupPath: "/usr/share/remarkable/suspended.png.bak"
    readonly property string markerPath: "/home/root/xovi/exthome/appload/habit-tracker/.backup-done"

    property var habits: []
    property date today: new Date()
    property bool lastRenderFailed: false
    property bool saveQueued: false

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

    Timer {
        id: debounceTimer
        interval: 3000
        repeat: false
        onTriggered: canvas._beginAsyncRender()
    }

    onPaint: SuspendDraw.draw(getContext("2d"), canvas.width, canvas.height, canvas.habits, canvas.today, canvas.drawConfig)

    onPainted: {
        if (!canvas.saveQueued) return
        canvas.saveQueued = false
        Qt.callLater(canvas._save)
    }

    function scheduleRender() {
        debounceTimer.restart()
    }

    function renderNow() {
        debounceTimer.stop()
        _beginAsyncRender()
    }

    function flushNow() {
        debounceTimer.stop()
        SuspendRender.ensureBackup(canvas.targetPath, canvas.backupPath, canvas.markerPath)
        SuspendDraw.draw(canvas.getContext("2d"), canvas.width, canvas.height, canvas.habits, canvas.today, canvas.drawConfig)
        canvas.saveQueued = false
        _save()
    }

    function _beginAsyncRender() {
        SuspendRender.ensureBackup(canvas.targetPath, canvas.backupPath, canvas.markerPath)
        canvas.saveQueued = true
        canvas.requestPaint()
    }

    function _save() {
        const ok = canvas.save(canvas.targetPath)
        canvas.lastRenderFailed = !ok
        if (!ok) console.warn("SuspendCanvas: save failed for", canvas.targetPath)
    }
}
