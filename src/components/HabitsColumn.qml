import QtQuick 2.15
import ".." as App

Column {
    id: habitsColumn

    property var habits: []
    property bool editing: false

    signal removeRequested(int index)
    signal negativeToggled(int index)
    signal nameEdited(int index, string newName)
    signal moveRequested(int from, int to)
    signal addRequested(string name, bool negative)

    spacing: App.Theme.rowSpacing

    Item {
        width: App.Theme.habitsWidth
        height: App.Theme.dayLabelHeight
    }

    Repeater {
        model: habitsColumn.habits

        HabitRow {
            name: modelData.name
            negative: modelData.negative
            editing: habitsColumn.editing
            canMoveUp: index > 0
            canMoveDown: index < habitsColumn.habits.length - 1
            onRemoveClicked: habitsColumn.removeRequested(index)
            onNegativeToggled: habitsColumn.negativeToggled(index)
            onNameEdited: habitsColumn.nameEdited(index, newName)
            onMoveUpClicked: habitsColumn.moveRequested(index, index - 1)
            onMoveDownClicked: habitsColumn.moveRequested(index, index + 1)
        }
    }

    HabitAddRow {
        visible: habitsColumn.editing
        onAddRequested: habitsColumn.addRequested(name, negative)
    }
}
