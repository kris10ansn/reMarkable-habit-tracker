import QtQuick 2.15
import "." as App
import "components" as App
import "js/DateUtils.js" as DateUtils

Rectangle {
    id: root
    anchors.fill: parent
    color: App.Theme.bg

    signal close
    function unloading() {
        console.log("Habit Tracker unloading");
    }

    Component.onCompleted: console.log("Habit Tracker loaded; size:", width, "x", height)

    App.HabitsStore {
        id: habitsStore
    }

    Item {
        id: landscape
        anchors.centerIn: parent
        width: parent.height
        height: parent.width
        rotation: 90

        property date today: new Date()
        property int daysInMonth: DateUtils.daysInMonth(today)
        property int currentDay: today.getDate()
        property bool editing: false

        property int viewportWidth: width - 2 * App.Theme.margin - App.Theme.habitsWidth - App.Theme.labelGap - 2 * App.Theme.buttonWidth - 2 * App.Theme.buttonGap
        property int contentWidth: daysInMonth * App.Theme.boxSize + (daysInMonth - 1) * App.Theme.boxSpacing
        property int maxScrollX: Math.max(0, contentWidth - viewportWidth)
        property int scrollX: 0

        function clampScroll(x) {
            return Math.max(0, Math.min(maxScrollX, x));
        }
        function scrollByBoxes(n) {
            scrollX = clampScroll(scrollX + n * (App.Theme.boxSize + App.Theme.boxSpacing));
        }
        function scrollToDay(day) {
            var target = (day - 1) * (App.Theme.boxSize + App.Theme.boxSpacing) - viewportWidth / 2 + App.Theme.boxSize / 2;
            scrollX = clampScroll(target);
        }

        onViewportWidthChanged: scrollToDay(currentDay)

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
                        model: habitsStore.habits

                        App.HabitRow {
                            name: modelData.name
                            negative: modelData.negative
                            editing: landscape.editing
                            onRemoveClicked: habitsStore.remove(index)
                            onNegativeToggled: habitsStore.setNegative(index, !modelData.negative)
                        }
                    }

                    App.HabitAddRow {
                        visible: landscape.editing
                        onAddRequested: habitsStore.add(name, negative)
                    }
                }

                Column {
                    spacing: App.Theme.rowSpacing

                    Item {
                        width: App.Theme.buttonWidth
                        height: App.Theme.dayLabelHeight
                    }

                    App.AppButton {
                        width: App.Theme.buttonWidth
                        height: gridStack.height - App.Theme.dayLabelHeight - App.Theme.rowSpacing
                        text: "‹"
                        fontSize: App.Theme.scrollFont
                        fadeOpacity: landscape.scrollX > 0 ? 1.0 : App.Theme.fadedOpacity
                        onClicked: landscape.scrollByBoxes(-7)
                    }
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
                            model: habitsStore.habits

                            App.HabitGridRow {
                                daysInMonth: landscape.daysInMonth
                                currentDay: landscape.currentDay
                            }
                        }

                        Item {
                            visible: landscape.editing
                            width: 1
                            height: App.Theme.boxSize
                        }
                    }

                    // Draw vertical lines every 7 days
                    Repeater {
                        model: Math.floor((landscape.daysInMonth - 1) / 7)

                        Rectangle {
                            width: App.Theme.borderWidth
                            height: gridStack.height
                            x: -landscape.scrollX + (index + 1) * 7 * (App.Theme.boxSize + App.Theme.boxSpacing) - App.Theme.boxSpacing / 2 - width / 2
                            color: App.Theme.fg
                        }
                    }
                }

                Column {
                    spacing: App.Theme.rowSpacing

                    Item {
                        width: App.Theme.buttonWidth
                        height: App.Theme.dayLabelHeight
                    }

                    App.AppButton {
                        width: App.Theme.buttonWidth
                        height: gridStack.height - App.Theme.dayLabelHeight - App.Theme.rowSpacing
                        text: "›"
                        fontSize: App.Theme.scrollFont
                        fadeOpacity: landscape.scrollX < landscape.maxScrollX ? 1.0 : App.Theme.fadedOpacity
                        onClicked: landscape.scrollByBoxes(7)
                    }
                }
            }
        }

        App.AppButton {
            id: quitButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: App.Theme.margin
            width: App.Theme.quitButtonWidth
            height: App.Theme.quitButtonHeight
            text: "Quit"
            onClicked: root.close()
        }

        App.AppButton {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: App.Theme.margin
            width: App.Theme.quitButtonWidth
            height: App.Theme.quitButtonHeight
            text: landscape.editing ? "Done" : "Edit"
            onClicked: landscape.editing = !landscape.editing
        }
    }
}
