import QtQuick 2.15
import ".." as App

Row {
    id: addRow

    signal addRequested(string name)

    width: App.Theme.habitsWidth
    height: App.Theme.boxSize
    spacing: App.Theme.boxSpacing

    function submit() {
        var value = input.text;
        if (!value || value.replace(/^\s+|\s+$/g, "").length === 0) return;
        addRow.addRequested(value);
        input.text = "";
    }

    Rectangle {
        width: addRow.width - addButton.width - addRow.spacing
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

    AppButton {
        id: addButton
        width: App.Theme.deleteButtonSize
        height: addRow.height
        text: "+"
        onClicked: addRow.submit()
    }
}
