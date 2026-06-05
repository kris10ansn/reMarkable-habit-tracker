import QtQuick 2.15
import "." as App

Row {
    id: gridRow

    property int daysInMonth: 0
    property int currentDay: 0

    spacing: App.Theme.boxSpacing

    Repeater {
        model: gridRow.daysInMonth

        Rectangle {
            width: App.Theme.boxSize
            height: App.Theme.boxSize
            color: App.Theme.bg
            border.color: App.Theme.fg
            border.width: App.Theme.borderWidth

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -App.Theme.boxSpacing / 2
                anchors.rightMargin: -App.Theme.boxSpacing / 2
                anchors.topMargin: -App.Theme.rowSpacing / 2
                anchors.bottomMargin: -App.Theme.rowSpacing / 2
                color: index + 1 === gridRow.currentDay ? App.Theme.fg : "transparent"
                z: -1
            }
        }
    }
}
