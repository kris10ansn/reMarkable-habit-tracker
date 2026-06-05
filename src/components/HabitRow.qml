import QtQuick 2.15
import ".." as App

Row {
    id: habitRow

    property string name: ""
    property bool negative: false
    property bool editing: false
    property bool canMoveUp: false
    property bool canMoveDown: false
    signal removeClicked
    signal negativeToggled
    signal nameEdited(string newName)
    signal moveUpClicked
    signal moveDownClicked

    width: App.Theme.habitsWidth
    height: App.Theme.boxSize
    spacing: App.Theme.boxSpacing

    Column {
        id: reorderColumn
        width: App.Theme.deleteButtonSize
        height: App.Theme.boxSize
        spacing: App.Theme.boxSpacing
        visible: habitRow.editing

        Rectangle {
            width: parent.width
            height: (App.Theme.boxSize - App.Theme.boxSpacing) / 2
            color: App.Theme.bg
            border.color: App.Theme.fg
            border.width: App.Theme.buttonBorderWidth
            opacity: habitRow.canMoveUp ? 1.0 : App.Theme.fadedOpacity

            Text {
                anchors.centerIn: parent
                text: "↑"
                font.pixelSize: App.Theme.buttonFont
                color: App.Theme.fg
            }

            MouseArea {
                anchors.fill: parent
                enabled: habitRow.canMoveUp
                onClicked: habitRow.moveUpClicked()
            }
        }

        Rectangle {
            width: parent.width
            height: (App.Theme.boxSize - App.Theme.boxSpacing) / 2
            color: App.Theme.bg
            border.color: App.Theme.fg
            border.width: App.Theme.buttonBorderWidth
            opacity: habitRow.canMoveDown ? 1.0 : App.Theme.fadedOpacity

            Text {
                anchors.centerIn: parent
                text: "↓"
                font.pixelSize: App.Theme.buttonFont
                color: App.Theme.fg
            }

            MouseArea {
                anchors.fill: parent
                enabled: habitRow.canMoveDown
                onClicked: habitRow.moveDownClicked()
            }
        }
    }

    Rectangle {
        id: deleteButton
        width: App.Theme.deleteButtonSize
        height: App.Theme.deleteButtonSize
        anchors.verticalCenter: parent.verticalCenter
        visible: habitRow.editing
        color: App.Theme.bg
        border.color: App.Theme.fg
        border.width: App.Theme.buttonBorderWidth

        Text {
            anchors.centerIn: parent
            text: "×"
            font.pixelSize: App.Theme.buttonFont
            color: App.Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            onClicked: habitRow.removeClicked()
        }
    }

    Item {
        id: nameSlot
        width: habitRow.width
               - (habitRow.editing ? 3 * (App.Theme.deleteButtonSize + habitRow.spacing) : 0)
        height: habitRow.height

        Text {
            anchors.fill: parent
            visible: !habitRow.editing
            text: habitRow.name
            font.pixelSize: App.Theme.labelFont
            color: App.Theme.fg
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Rectangle {
            anchors.fill: parent
            visible: habitRow.editing
            color: App.Theme.bg
            border.color: App.Theme.fg
            border.width: App.Theme.borderWidth

            TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.margins: App.Theme.inputPadding
                text: habitRow.name
                font.pixelSize: App.Theme.labelFont
                color: App.Theme.fg
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true

                onEditingFinished: {
                    var trimmed = text.replace(/^\s+|\s+$/g, "");
                    if (trimmed && trimmed !== habitRow.name) {
                        habitRow.nameEdited(trimmed);
                    } else {
                        text = habitRow.name;
                    }
                }
            }
        }
    }

    Rectangle {
        id: negativeButton
        width: App.Theme.deleteButtonSize
        height: App.Theme.deleteButtonSize
        anchors.verticalCenter: parent.verticalCenter
        visible: habitRow.editing
        color: habitRow.negative ? App.Theme.fg : App.Theme.bg
        border.color: App.Theme.fg
        border.width: App.Theme.buttonBorderWidth

        Text {
            anchors.centerIn: parent
            text: "−"
            font.pixelSize: App.Theme.buttonFont
            color: habitRow.negative ? App.Theme.bg : App.Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            onClicked: habitRow.negativeToggled()
        }
    }
}
