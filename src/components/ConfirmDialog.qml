import QtQuick 2.15
import ".." as App

Rectangle {
    id: dialog

    property string message: ""
    property string confirmText: "Delete"
    property string cancelText: "Cancel"
    signal confirmed
    signal cancelled

    anchors.fill: parent
    color: "transparent"
    z: 100

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.cancelled()
    }

    Rectangle {
        anchors.fill: parent
        color: App.Theme.bg
        opacity: 0.7
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Math.min(parent.width - 4 * App.Theme.margin, 800)
        height: messageText.height + buttons.height + 3 * App.Theme.margin
        color: App.Theme.bg
        border.color: App.Theme.fg
        border.width: App.Theme.buttonBorderWidth

        MouseArea {
            anchors.fill: parent
        }

        Text {
            id: messageText
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: App.Theme.margin
            text: dialog.message
            font.pixelSize: App.Theme.labelFont
            color: App.Theme.fg
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Row {
            id: buttons
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: App.Theme.margin
            spacing: App.Theme.buttonGap

            AppButton {
                width: App.Theme.quitButtonWidth
                height: App.Theme.quitButtonHeight
                text: dialog.cancelText
                onClicked: dialog.cancelled()
            }

            AppButton {
                width: App.Theme.quitButtonWidth
                height: App.Theme.quitButtonHeight
                text: dialog.confirmText
                onClicked: dialog.confirmed()
            }
        }
    }
}
