import QtQuick 2.15
import ".." as App
import "../js/SuspendRender.js" as SuspendRender
import "../js/SuspendDraw.js" as SuspendDraw

Canvas {
    id: canvas

    readonly property string targetPath: "/usr/share/remarkable/suspended.png"
    readonly property string backupPath: "/usr/share/remarkable/suspended.png.bak"

    property var habits: []
    property date today: new Date()
    property bool lastRenderFailed: false
    property bool rendering: false
    property bool pendingRender: false
    property bool saveAfterPaint: false

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
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image

    onPaint: SuspendDraw.draw(getContext("2d"), canvas.width, canvas.height, canvas.habits, canvas.today, canvas.drawConfig)

    onPainted: {
        if (!canvas.saveAfterPaint) return
        canvas.saveAfterPaint = false
        Qt.callLater(canvas._saveNow)
    }

    function _saveNow() {
        const ok = canvas.save(canvas.targetPath)
        canvas.rendering = false
        canvas.lastRenderFailed = !ok
        if (!ok) console.warn("SuspendCanvas: save failed for", canvas.targetPath)

        if (canvas.pendingRender) {
            canvas.pendingRender = false
            canvas.render()
        }
    }

    function render() {
        if (canvas.rendering) {
            canvas.pendingRender = true
            return
        }
        canvas.rendering = true

        SuspendRender.ensureBackup(canvas.targetPath, canvas.backupPath)

        canvas.saveAfterPaint = true
        canvas.requestPaint()
    }
}
