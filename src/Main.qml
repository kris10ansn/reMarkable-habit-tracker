import QtQuick 2.15
import "." as App
import "components" as App
import "js/DateUtils.js" as DateUtils
import "js/habits.js" as Habits

Rectangle {
    id: root
    anchors.fill: parent
    color: App.Theme.bg

    signal close
    function unloading() {
        console.log("Habit Tracker unloading");
    }

    Component.onCompleted: console.log("Habit Tracker loaded; size:", width, "x", height)

    Item {
        id: landscape
        anchors.centerIn: parent
        width: parent.height
        height: parent.width
        rotation: 90

        property date today: new Date()
        property int daysInMonth: DateUtils.daysInMonth(today)
        property int currentDay: today.getDate()

        property int viewportWidth: width - 2 * App.Theme.margin - App.Theme.habitsWidth - App.Theme.labelGap - 2 * App.Theme.buttonWidth - 2 * App.Theme.buttonGap
        property int contentWidth: daysInMonth * App.Theme.boxSize + (daysInMonth - 1) * App.Theme.boxSpacing
        property int maxScrollX: Math.max(0, contentWidth - viewportWidth)
        property int scrollX: 0

        function clampScroll(x) {
            return Math.max(0, Math.min(maxScrollX, x))
        }
        function scrollByBoxes(n) {
            scrollX = clampScroll(scrollX + n * (App.Theme.boxSize + App.Theme.boxSpacing))
        }
        function scrollToDay(day) {
            var target = (day - 1) * (App.Theme.boxSize + App.Theme.boxSpacing) - viewportWidth / 2 + App.Theme.boxSize / 2
            scrollX = clampScroll(target)
        }

        Component.onCompleted: scrollToDay(currentDay)

        Column {
            anchors.fill: parent
            anchors.margins: App.Theme.margin
            spacing: App.Theme.rowSpacing

            App.MonthHeader {
                date: landscape.today
            }

            Row {
                spacing: App.Theme.buttonGap

                Column {
                    spacing: App.Theme.rowSpacing

                    Item {
                        width: App.Theme.habitsWidth
                        height: App.Theme.dayLabelHeight
                    }

                    Repeater {
                        model: Habits.habits

                        App.HabitRow {
                            name: modelData
                        }
                    }
                }

                App.AppButton {
                    width: App.Theme.buttonWidth
                    height: gridStack.height
                    text: "‹"
                    fontSize: App.Theme.scrollFont
                    fadeOpacity: landscape.scrollX > 0 ? 1.0 : App.Theme.fadedOpacity
                    onClicked: landscape.scrollByBoxes(-7)
                }

                Item {
                    width: landscape.viewportWidth
                    height: gridStack.height
                    clip: true

                    Column {
                        id: gridStack
                        x: -landscape.scrollX
                        spacing: App.Theme.rowSpacing

                        App.DayLabelsRow {
                            daysInMonth: landscape.daysInMonth
                            currentDay: landscape.currentDay
                        }

                        Repeater {
                            model: Habits.habits

                            App.HabitGridRow {
                                daysInMonth: landscape.daysInMonth
                                currentDay: landscape.currentDay
                            }
                        }
                    }
                }

                App.AppButton {
                    width: App.Theme.buttonWidth
                    height: gridStack.height
                    text: "›"
                    fontSize: App.Theme.scrollFont
                    fadeOpacity: landscape.scrollX < landscape.maxScrollX ? 1.0 : App.Theme.fadedOpacity
                    onClicked: landscape.scrollByBoxes(7)
                }
            }
        }

        App.AppButton {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: App.Theme.margin
            width: App.Theme.quitButtonWidth
            height: App.Theme.quitButtonHeight
            text: "Quit"
            onClicked: root.close()
        }
    }
}
