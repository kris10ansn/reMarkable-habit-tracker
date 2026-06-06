const pad2 = (n) => (n < 10 ? `0${n}` : `${n}`);

function daysInMonth(d) {
    return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
}

function monthName(d) {
    return Qt.formatDate(d, "MMMM yyyy");
}

function dateKey(year, month, day) {
    return `${year}-${pad2(month + 1)}-${pad2(day)}`;
}
