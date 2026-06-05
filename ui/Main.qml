import QtQuick 2.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"

    signal close
    function unloading() {
        console.log("rmhello unloading");
    }

    Component.onCompleted: console.log("rmhello loaded; size:", width, "x", height)

    Item {
        id: landscape
        anchors.centerIn: parent
        width: parent.height
        height: parent.width
        rotation: 90

        property int margin: 40
        property int goalsWidth: 360
        property int boxSize: 80
        property int boxSpacing: 12
        property int rowSpacing: 24
        property int labelGap: 20
        property int buttonWidth: 80
        property int buttonGap: 20

        property var today: new Date()
        property int daysInMonth: new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
        property int currentDay: today.getDate()
        property string monthName: today.toLocaleString(Qt.locale(), "MMMM yyyy")

        property int viewportWidth: width - 2 * margin - goalsWidth - labelGap - 2 * buttonWidth - 2 * buttonGap
        property int contentWidth: daysInMonth * boxSize + (daysInMonth - 1) * boxSpacing
        property int maxScrollX: Math.max(0, contentWidth - viewportWidth)
        property int scrollX: 0

        function clampScroll(x) {
            return Math.max(0, Math.min(maxScrollX, x))
        }
        function scrollByBoxes(n) {
            scrollX = clampScroll(scrollX + n * (boxSize + boxSpacing))
        }
        function scrollToDay(day) {
            var target = (day - 1) * (boxSize + boxSpacing) - viewportWidth / 2 + boxSize / 2
            scrollX = clampScroll(target)
        }

        Component.onCompleted: scrollToDay(currentDay)

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

            Row {
                spacing: landscape.buttonGap

                Column {
                    spacing: landscape.rowSpacing

                    Repeater {
                        model: goalsModel

                        Text {
                            width: landscape.goalsWidth
                            height: landscape.boxSize
                            text: model.name
                            font.pixelSize: 28
                            color: "black"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    width: landscape.buttonWidth
                    height: goalsList.height
                    color: "white"
                    border.color: "black"
                    border.width: 3
                    opacity: landscape.scrollX > 0 ? 1.0 : 0.3

                    Text {
                        anchors.centerIn: parent
                        text: "‹"
                        font.pixelSize: 64
                        color: "black"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: landscape.scrollByBoxes(-7)
                    }
                }

                Item {
                    width: landscape.viewportWidth
                    height: goalsList.height
                    clip: true

                    Column {
                        id: goalsList
                        x: -landscape.scrollX
                        spacing: landscape.rowSpacing

                        Repeater {
                            model: goalsModel

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
                    width: landscape.buttonWidth
                    height: goalsList.height
                    color: "white"
                    border.color: "black"
                    border.width: 3
                    opacity: landscape.scrollX < landscape.maxScrollX ? 1.0 : 0.3

                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        font.pixelSize: 64
                        color: "black"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: landscape.scrollByBoxes(7)
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
