import QtQuick 2.15
import ".." as App

Text {
    property string name: ""

    width: App.Theme.habitsWidth
    height: App.Theme.boxSize
    text: name
    font.pixelSize: App.Theme.labelFont
    color: App.Theme.fg
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
}
