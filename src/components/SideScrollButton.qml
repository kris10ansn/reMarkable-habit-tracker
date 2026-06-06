import QtQuick 2.15
import ".." as App

Column {
    id: scrollColumn

    property string text: ""
    property real fadeOpacity: 1.0
    property int contentHeight: 0
    signal clicked

    spacing: App.Theme.rowSpacing

    Item {
        width: App.Theme.buttonWidth
        height: App.Theme.dayLabelHeight
    }

    AppButton {
        width: App.Theme.buttonWidth
        height: scrollColumn.contentHeight - App.Theme.dayLabelHeight - App.Theme.rowSpacing
        text: scrollColumn.text
        fontSize: App.Theme.scrollFont
        fadeOpacity: scrollColumn.fadeOpacity
        onClicked: scrollColumn.clicked()
    }
}
