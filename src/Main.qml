import QtQuick 2.15
import "." as App
import "components" as App
import "js/DateUtils.js" as DateUtils
import "js/Scroll.js" as Scroll

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
        property int currentYear: today.getFullYear()
        property int currentMonth: today.getMonth()
        property bool editing: false
        property int pendingDeleteIndex: -1

        property int step: App.Theme.boxSize + App.Theme.boxSpacing
        property int viewportWidth: width - 2 * App.Theme.margin - App.Theme.habitsWidth - App.Theme.labelGap - 2 * App.Theme.buttonWidth - 2 * App.Theme.buttonGap
        property int contentWidth: daysInMonth * App.Theme.boxSize + (daysInMonth - 1) * App.Theme.boxSpacing
        property int maxScrollX: Math.max(0, contentWidth - viewportWidth)
        property int scrollX: 0

        onViewportWidthChanged: scrollX = Scroll.centerOnDay(currentDay, viewportWidth, App.Theme.boxSize, App.Theme.boxSpacing, maxScrollX)

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

                App.HabitsColumn {
                    habits: habitsStore.habits
                    editing: landscape.editing
                    onRemoveRequested: landscape.pendingDeleteIndex = index
                    onNegativeToggled: habitsStore.setNegative(index, !habitsStore.habits[index].negative)
                    onNameEdited: habitsStore.setName(index, newName)
                    onMoveRequested: habitsStore.move(from, to)
                    onAddRequested: habitsStore.add(name, negative)
                }

                App.SideScrollButton {
                    text: "‹"
                    fadeOpacity: landscape.scrollX > 0 ? 1.0 : App.Theme.fadedOpacity
                    contentHeight: grid.contentHeight
                    onClicked: landscape.scrollX = Scroll.scrollByBoxes(landscape.scrollX, -7, landscape.step, landscape.maxScrollX)
                }

                App.HabitsGrid {
                    id: grid
                    width: landscape.viewportWidth
                    height: contentHeight
                    habits: habitsStore.habits
                    daysInMonth: landscape.daysInMonth
                    currentDay: landscape.currentDay
                    year: landscape.currentYear
                    month: landscape.currentMonth
                    editing: landscape.editing
                    scrollX: landscape.scrollX
                    onEntryToggled: habitsStore.toggleEntry(index, dateKey)
                }

                App.SideScrollButton {
                    text: "›"
                    fadeOpacity: landscape.scrollX < landscape.maxScrollX ? 1.0 : App.Theme.fadedOpacity
                    contentHeight: grid.contentHeight
                    onClicked: landscape.scrollX = Scroll.scrollByBoxes(landscape.scrollX, 7, landscape.step, landscape.maxScrollX)
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

        App.AppButton {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: App.Theme.margin
            width: App.Theme.quitButtonWidth
            height: App.Theme.quitButtonHeight
            text: landscape.editing ? "Done" : "Edit"
            onClicked: landscape.editing = !landscape.editing
        }

        App.ConfirmDialog {
            visible: landscape.pendingDeleteIndex >= 0
            message: visible
                ? "Delete “" + habitsStore.habits[landscape.pendingDeleteIndex].name + "”?"
                : ""
            confirmText: "Delete"
            onConfirmed: {
                habitsStore.remove(landscape.pendingDeleteIndex)
                landscape.pendingDeleteIndex = -1
            }
            onCancelled: landscape.pendingDeleteIndex = -1
        }
    }
}
