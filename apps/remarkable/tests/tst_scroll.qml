import QtQuick 2.15
import QtTest 1.2
import "../src/js/Scroll.js" as Scroll

TestCase {
    name: "Scroll"

    function test_clampScrollHoldsBothEnds() {
        compare(Scroll.clampScroll(-50, 400), 0);
        compare(Scroll.clampScroll(900, 400), 400);
        compare(Scroll.clampScroll(120, 400), 120);
    }

    function test_clampScrollCollapsesWhenNothingToScroll() {
        compare(Scroll.clampScroll(120, 0), 0);
    }

    function test_scrollByBoxesMovesWholeSteps() {
        compare(Scroll.scrollByBoxes(0, 3, 50, 1000), 150);
        compare(Scroll.scrollByBoxes(300, -2, 50, 1000), 200);
    }

    function test_scrollByBoxesClampsAtTheEdges() {
        compare(Scroll.scrollByBoxes(20, -5, 50, 1000), 0);
        compare(Scroll.scrollByBoxes(980, 5, 50, 1000), 1000);
    }

    function test_centerOnDayPutsTheBoxMidViewport() {
        // Day 11 starts at 10 * 50 = 500; centring it in a 300-wide viewport means
        // 500 - 150 + 20 = 370.
        compare(Scroll.centerOnDay(11, 300, 40, 10, 1000), 370);
    }

    function test_centerOnDayClampsAtBothEnds() {
        compare(Scroll.centerOnDay(1, 300, 40, 10, 1000), 0);
        compare(Scroll.centerOnDay(31, 300, 40, 10, 200), 200);
    }
}
