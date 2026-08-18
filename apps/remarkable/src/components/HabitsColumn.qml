import QtQuick 2.15
import ".." as App

Item {
    id: habitsColumn

    property var habits: []
    property bool editing: false
    property bool showPrivateHabits: false
    property int rowWidth: App.Theme.habitsWidth
    property int scrollY: 0
    property real viewportHeight: 0

    signal removeRequested(int index)
    signal polarityToggled(int index)
    signal privateToggled(int index)
    signal nameEdited(int index, string newName)
    signal moveRequested(int from, int to)
    signal addRequested(string name, string polarity)

    width: rowWidth
    height: viewportHeight
    clip: true

    Item {
        id: header
        width: habitsColumn.rowWidth
        height: App.Theme.dayLabelHeight
    }

    Item {
        id: bodyViewport
        y: header.height + App.Theme.rowSpacing
        width: habitsColumn.rowWidth
        height: habitsColumn.height - y
        clip: true

        Column {
            id: body
            y: -habitsColumn.scrollY
            spacing: App.Theme.rowSpacing

            Repeater {
                model: habitsColumn.habits

                HabitRow {
                    width: habitsColumn.rowWidth
                    visible: habitsColumn.showPrivateHabits || !model.isPrivate
                    name: model.name
                    polarity: model.polarity
                    isPrivate: !!model.isPrivate
                    editing: habitsColumn.editing
                    canMoveUp: index > 0
                    canMoveDown: index < habitsColumn.habits.count - 1
                    onRemoveClicked: habitsColumn.removeRequested(index)
                    onPolarityToggled: habitsColumn.polarityToggled(index)
                    onPrivateToggled: habitsColumn.privateToggled(index)
                    onNameEdited: habitsColumn.nameEdited(index, newName)
                    onMoveUpClicked: habitsColumn.moveRequested(index, index - 1)
                    onMoveDownClicked: habitsColumn.moveRequested(index, index + 1)
                }
            }

            HabitAddRow {
                width: habitsColumn.rowWidth
                visible: habitsColumn.editing
                onAddRequested: habitsColumn.addRequested(name, polarity)
            }
        }
    }
}
