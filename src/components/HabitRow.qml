import QtQuick 2.15
import ".." as App

Row {
    id: habitRow

    property string name: ""
    property bool editing: false
    signal removeClicked

    width: App.Theme.habitsWidth
    height: App.Theme.boxSize
    spacing: App.Theme.boxSpacing

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

    Text {
        width: habitRow.width - (habitRow.editing ? App.Theme.deleteButtonSize + habitRow.spacing : 0)
        height: habitRow.height
        text: habitRow.name
        font.pixelSize: App.Theme.labelFont
        color: App.Theme.fg
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
