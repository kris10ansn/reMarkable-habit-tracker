import QtQuick 2.15
import ".." as App

Row {
    id: addRow

    property bool negative: false
    signal addRequested(string name, bool negative)

    width: App.Theme.habitsWidth
    height: App.Theme.boxSize
    spacing: App.Theme.boxSpacing

    onVisibleChanged: if (!visible) {
        input.focus = false
        Qt.inputMethod.hide()
        addRow.negative = false
    }

    function submit() {
        var value = input.text;
        if (!value || value.replace(/^\s+|\s+$/g, "").length === 0) return;
        addRow.addRequested(value, addRow.negative);
        input.text = "";
        addRow.negative = false;
    }

    Rectangle {
        width: addRow.width
               - addButton.width - addRow.spacing
               - negativeButton.width - addRow.spacing
        height: addRow.height
        color: App.Theme.bg
        border.color: App.Theme.fg
        border.width: App.Theme.borderWidth

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: App.Theme.inputPadding
            font.pixelSize: App.Theme.labelFont
            color: App.Theme.fg
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            onAccepted: addRow.submit()
        }

        Text {
            anchors.fill: input
            text: "New habit…"
            color: App.Theme.fg
            opacity: App.Theme.fadedOpacity
            font.pixelSize: input.font.pixelSize
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0 && !input.activeFocus
        }
    }

    Rectangle {
        id: negativeButton
        width: App.Theme.deleteButtonSize
        height: addRow.height
        color: addRow.negative ? App.Theme.fg : App.Theme.bg
        border.color: App.Theme.fg
        border.width: App.Theme.buttonBorderWidth

        Text {
            anchors.centerIn: parent
            text: "−"
            font.pixelSize: App.Theme.buttonFont
            color: addRow.negative ? App.Theme.bg : App.Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            onClicked: addRow.negative = !addRow.negative
        }
    }

    AppButton {
        id: addButton
        width: App.Theme.deleteButtonSize
        height: addRow.height
        text: "+"
        onClicked: addRow.submit()
    }
}
