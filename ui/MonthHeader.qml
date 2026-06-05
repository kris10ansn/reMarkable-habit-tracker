import QtQuick 2.15
import "." as App
import "DateUtils.js" as DateUtils

Column {
    id: header

    property date date: new Date()

    spacing: 4

    Text {
        text: DateUtils.monthName(header.date)
        font.pixelSize: App.Theme.titleFont
        font.bold: true
        color: App.Theme.fg
    }

    Text {
        text: DateUtils.daysInMonth(header.date) + " days · today is day " + header.date.getDate()
        font.pixelSize: App.Theme.subtitleFont
        color: App.Theme.fg
    }
}
