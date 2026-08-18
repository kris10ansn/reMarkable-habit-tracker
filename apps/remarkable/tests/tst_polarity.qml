import QtQuick 2.15
import QtTest 1.2
import "../src/js/Polarity.js" as Polarity

TestCase {
    name: "Polarity"

    function test_spellsTheBackendEnum() {
        compare(Polarity.POSITIVE, "Positive");
        compare(Polarity.NEGATIVE, "Negative");
    }

    function test_isNegativeOnlyForTheNegativeSpelling() {
        verify(Polarity.isNegative(Polarity.NEGATIVE));
        verify(!Polarity.isNegative(Polarity.POSITIVE));

        // Not a case-insensitive or truthiness test: an unrecognised value reads as positive
        // rather than flipping the grid's implicit-X rendering on.
        verify(!Polarity.isNegative("negative"));
        verify(!Polarity.isNegative(""));
        verify(!Polarity.isNegative(undefined));
    }

    function test_toggledRoundTrips() {
        compare(Polarity.toggled(Polarity.POSITIVE), Polarity.NEGATIVE);
        compare(Polarity.toggled(Polarity.NEGATIVE), Polarity.POSITIVE);
        compare(Polarity.toggled(Polarity.toggled(Polarity.POSITIVE)), Polarity.POSITIVE);
    }
}
