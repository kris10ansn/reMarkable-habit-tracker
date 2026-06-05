pragma Singleton
import QtQuick 2.15

QtObject {
    property int margin: 40
    property int habitsWidth: 360
    property int boxSize: 80
    property int boxSpacing: 12
    property int rowSpacing: 24
    property int labelGap: 20
    property int buttonWidth: 80
    property int buttonGap: 20
    property int dayLabelHeight: 32

    property int titleFont: 48
    property int subtitleFont: 24
    property int labelFont: 28
    property int dayLabelFont: 22
    property int buttonFont: 28
    property int scrollFont: 64

    property color fg: "black"
    property color bg: "white"

    property int borderWidth: 2
    property int buttonBorderWidth: 3

    property real fadedOpacity: 0.3

    property int quitButtonWidth: 160
    property int quitButtonHeight: 60

    property int deleteButtonSize: 60
    property int inputPadding: 12
}
