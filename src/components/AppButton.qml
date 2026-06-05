import QtQuick 2.15
import ".." as App

Rectangle {
    id: button

    property string text: ""
    property int fontSize: App.Theme.buttonFont
    property real fadeOpacity: 1.0
    signal clicked

    color: App.Theme.bg
    border.color: App.Theme.fg
    border.width: App.Theme.buttonBorderWidth
    opacity: fadeOpacity

    Text {
        anchors.centerIn: parent
        text: button.text
        font.pixelSize: button.fontSize
        color: App.Theme.fg
    }

    MouseArea {
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
