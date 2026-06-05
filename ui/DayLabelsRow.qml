import QtQuick 2.15
import "." as App

Row {
    id: labels

    property int daysInMonth: 0
    property int currentDay: 0

    spacing: App.Theme.boxSpacing

    Repeater {
        model: labels.daysInMonth

        Text {
            width: App.Theme.boxSize
            height: App.Theme.dayLabelHeight
            text: index + 1
            font.pixelSize: App.Theme.dayLabelFont
            font.bold: index + 1 === labels.currentDay
            color: App.Theme.fg
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
