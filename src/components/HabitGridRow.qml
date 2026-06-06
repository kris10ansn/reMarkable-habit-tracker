import QtQuick 2.15
import ".." as App
import "../js/DateUtils.js" as DateUtils

Row {
    id: gridRow

    property int daysInMonth: 0
    property int currentDay: 0
    property int year: 0
    property int month: 0
    property bool negative: false
    property var entries: ({})

    signal dayClicked(int day)

    spacing: App.Theme.boxSpacing

    Repeater {
        model: gridRow.daysInMonth

        Rectangle {
            id: box
            width: App.Theme.boxSize
            height: App.Theme.boxSize
            color: App.Theme.bg
            border.color: App.Theme.fg
            border.width: App.Theme.borderWidth

            readonly property int day: index + 1
            readonly property bool isFuture: day > gridRow.currentDay
            readonly property string entry: (gridRow.entries || {})[DateUtils.dateKey(gridRow.year, gridRow.month, day)] || ""
            readonly property string mark: entry === "x" ? "X" : entry === "o" ? "O" : gridRow.negative ? "X" : ""
            readonly property bool faded: mark === "O" || isFuture

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -App.Theme.boxSpacing / 2
                anchors.rightMargin: -App.Theme.boxSpacing / 2
                anchors.topMargin: -App.Theme.rowSpacing / 2
                anchors.bottomMargin: -App.Theme.rowSpacing / 2
                color: box.day === gridRow.currentDay ? App.Theme.fg : "transparent"
                z: -1
            }

            Text {
                anchors.centerIn: parent
                text: box.mark
                font.pixelSize: App.Theme.boxSize * 0.7
                font.bold: true
                color: App.Theme.fg
                opacity: box.faded ? App.Theme.fadedOpacity : 1.0
            }

            MouseArea {
                anchors.fill: parent
                onClicked: gridRow.dayClicked(box.day)
            }
        }
    }
}
