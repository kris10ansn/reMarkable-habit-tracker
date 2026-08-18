import QtQuick 2.15
import QtTest 1.2
import "../src/js/DateUtils.js" as DateUtils

TestCase {
    name: "DateUtils"

    function test_daysInMonth() {
        compare(DateUtils.daysInMonth(new Date(2026, 0, 15)), 31);
        compare(DateUtils.daysInMonth(new Date(2026, 3, 15)), 30);
        compare(DateUtils.daysInMonth(new Date(2026, 1, 15)), 28);
    }

    function test_daysInMonthHandlesLeapYears() {
        compare(DateUtils.daysInMonth(new Date(2024, 1, 15)), 29);
        compare(DateUtils.daysInMonth(new Date(2000, 1, 15)), 29);
        compare(DateUtils.daysInMonth(new Date(1900, 1, 15)), 28);
    }

    // Month is a 0-based JS month index everywhere in this app; the keys are 1-based and padded,
    // which is what makes the month file name sort and match the wire's month field.
    function test_monthKeyIsOneBasedAndPadded() {
        compare(DateUtils.monthKey(2026, 0), "2026-01");
        compare(DateUtils.monthKey(2026, 7), "2026-08");
        compare(DateUtils.monthKey(2026, 11), "2026-12");
    }

    function test_dateKeyIsOneBasedAndPadded() {
        compare(DateUtils.dateKey(2026, 0, 1), "2026-01-01");
        compare(DateUtils.dateKey(2026, 7, 9), "2026-08-09");
        compare(DateUtils.dateKey(2026, 11, 31), "2026-12-31");
    }

    function test_ordinal() {
        compare(DateUtils.ordinal(1), "1st");
        compare(DateUtils.ordinal(2), "2nd");
        compare(DateUtils.ordinal(3), "3rd");
        compare(DateUtils.ordinal(4), "4th");
        compare(DateUtils.ordinal(21), "21st");
        compare(DateUtils.ordinal(22), "22nd");
        compare(DateUtils.ordinal(23), "23rd");
        compare(DateUtils.ordinal(31), "31st");
    }

    // The teens are the case a naive last-digit rule gets wrong.
    function test_ordinalTeens() {
        compare(DateUtils.ordinal(11), "11th");
        compare(DateUtils.ordinal(12), "12th");
        compare(DateUtils.ordinal(13), "13th");
    }

    // Locale-dependent, so only its shape is pinned: it must name the month and the year.
    function test_monthNameNamesMonthAndYear() {
        const name = DateUtils.monthName(new Date(2026, 7, 9));

        verify(name.length > 0);
        verify(name.indexOf("2026") !== -1, `expected a year in "${name}"`);
    }
}
