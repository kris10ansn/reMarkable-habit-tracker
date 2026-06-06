import QtQuick 2.15
import ".." as App

Column {
    id: habitsColumn

    property var habits: []
    property bool editing: false
    property int rowWidth: App.Theme.habitsWidth

    signal removeRequested(int index)
    signal negativeToggled(int index)
    signal hideFromSleepToggled(int index)
    signal nameEdited(int index, string newName)
    signal moveRequested(int from, int to)
    signal addRequested(string name, bool negative)

    spacing: App.Theme.rowSpacing

    Item {
        width: habitsColumn.rowWidth
        height: App.Theme.dayLabelHeight
    }

    Repeater {
        model: habitsColumn.habits

        HabitRow {
            width: habitsColumn.rowWidth
            name: modelData.name
            negative: modelData.negative
            hideFromSleep: !!modelData.hideFromSleep
            editing: habitsColumn.editing
            canMoveUp: index > 0
            canMoveDown: index < habitsColumn.habits.length - 1
            onRemoveClicked: habitsColumn.removeRequested(index)
            onNegativeToggled: habitsColumn.negativeToggled(index)
            onHideFromSleepToggled: habitsColumn.hideFromSleepToggled(index)
            onNameEdited: habitsColumn.nameEdited(index, newName)
            onMoveUpClicked: habitsColumn.moveRequested(index, index - 1)
            onMoveDownClicked: habitsColumn.moveRequested(index, index + 1)
        }
    }

    HabitAddRow {
        width: habitsColumn.rowWidth
        visible: habitsColumn.editing
        onAddRequested: habitsColumn.addRequested(name, negative)
    }
}
