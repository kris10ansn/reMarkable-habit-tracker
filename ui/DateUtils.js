.pragma library

function daysInMonth(d) {
    return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
}

function monthName(d) {
    return Qt.formatDate(d, "MMMM yyyy")
}
