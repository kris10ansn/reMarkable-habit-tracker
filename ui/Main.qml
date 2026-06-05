import QtQuick 2.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    signal close
    function unloading() {
        console.log("Habit Tracker unloading");
    }

    Component.onCompleted: console.log("Habit Tracker loaded; size:", width, "x", height)

    Item {
        id: landscape
        anchors.centerIn: parent
        width: parent.height
        height: parent.width
        rotation: 90

        property int margin: 40
        property int goalsWidth: 360
        property int boxSize: 40
        property int boxSpacing: 6
        property int rowSpacing: 24

        property var today: new Date()
        property int daysInMonth: new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
        property int currentDay: today.getDate()
        property string monthName: today.toLocaleString(Qt.locale(), "MMMM yyyy")

        ListModel {
            id: goalsModel
            ListElement { name: "Read 20 pages" }
            ListElement { name: "Exercise" }
            ListElement { name: "Meditate" }
            ListElement { name: "No screens after 22:00" }
            ListElement { name: "Journal" }
        }

        Column {
            anchors.fill: parent
            anchors.margins: landscape.margin
            spacing: landscape.rowSpacing

            Column {
                spacing: 4

                Text {
                    text: landscape.monthName
                    font.pixelSize: 48
                    font.bold: true
                    color: "black"
                }

                Text {
                    text: landscape.daysInMonth + " days · today is day " + landscape.currentDay
                    font.pixelSize: 24
                    color: "black"
                }
            }

            Repeater {
                model: goalsModel

                Row {
                    spacing: 20
                    height: landscape.boxSize

                    Text {
                        width: landscape.goalsWidth
                        height: landscape.boxSize
                        text: model.name
                        font.pixelSize: 28
                        color: "black"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: landscape.boxSpacing

                        Repeater {
                            model: landscape.daysInMonth

                            Rectangle {
                                width: landscape.boxSize
                                height: landscape.boxSize
                                color: "white"
                                border.color: "black"
                                border.width: 2

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: -landscape.boxSpacing / 2
                                    anchors.rightMargin: -landscape.boxSpacing / 2
                                    anchors.topMargin: -landscape.rowSpacing / 2
                                    anchors.bottomMargin: -landscape.rowSpacing / 2
                                    color: index + 1 === landscape.currentDay ? "black" : "transparent"
                                    z: -1
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: landscape.margin
            width: 160
            height: 60
            color: "white"
            border.color: "black"
            border.width: 3

            Text {
                anchors.centerIn: parent
                text: "Quit"
                font.pixelSize: 28
                color: "black"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }
    }
}
