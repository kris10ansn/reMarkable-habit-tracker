import QtQuick 2.15
import ".." as App
import "../js/DateUtils.js" as DateUtils

Item {
    id: grid

    property var habits: []
    property int daysInMonth: 0
    property int currentDay: 0
    property int year: 0
    property int month: 0
    property bool editing: false
    property int scrollX: 0
    property real boxSize: App.Theme.boxSize
    property real boxSpacing: App.Theme.boxSpacing

    property alias contentHeight: stack.height

    signal entryToggled(int index, string dateKey)

    height: stack.height + App.Theme.rowSpacing / 2
    clip: true

    Column {
        id: stack
        x: -grid.scrollX
        spacing: App.Theme.rowSpacing

        DayLabelsRow {
            daysInMonth: grid.daysInMonth
            currentDay: grid.currentDay
            boxSize: grid.boxSize
            boxSpacing: grid.boxSpacing
        }

        Repeater {
            model: grid.habits

            HabitGridRow {
                daysInMonth: grid.daysInMonth
                currentDay: grid.currentDay
                year: grid.year
                month: grid.month
                negative: modelData.negative
                entries: modelData.entries || ({})
                boxSize: grid.boxSize
                boxSpacing: grid.boxSpacing
                onDayClicked: grid.entryToggled(index, DateUtils.dateKey(grid.year, grid.month, day))
            }
        }

        Item {
            visible: grid.editing
            width: 1
            height: grid.boxSize
        }
    }

    Repeater {
        model: Math.floor((grid.daysInMonth - 1) / 7)

        Rectangle {
            width: App.Theme.borderWidth
            height: grid.height
            x: -grid.scrollX + (index + 1) * 7 * (grid.boxSize + grid.boxSpacing) - grid.boxSpacing / 2 - width / 2
            color: App.Theme.fg
        }
    }
}
