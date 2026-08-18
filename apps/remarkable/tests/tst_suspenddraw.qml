import QtQuick 2.15
import QtTest 1.2
import "../src/js/SuspendDraw.js" as SuspendDraw

// computeSignature is the dedup key for the suspend image: an e-ink redraw is expensive, so the
// canvas only repaints when this string changes. Too coarse and the image goes stale; too fine
// and the device redraws for nothing. The drawing itself is covered by `make suspend-writer-test`.
TestCase {
    name: "SuspendDraw"

    readonly property date today: new Date(2026, 7, 9)

    function habit(overrides) {
        return Object.assign(
            { name: "Read 20 pages", polarity: "Positive", isPrivate: false, entries: {} },
            overrides || {});
    }

    function test_signatureIsStableForTheSameInput() {
        const habits = [habit({ entries: { "2026-08-01": "x", "2026-08-03": "o" } })];

        compare(SuspendDraw.computeSignature(habits, today), SuspendDraw.computeSignature(habits, today));
    }

    function test_signatureChangesWithAnOutcome() {
        const before = SuspendDraw.computeSignature([habit({ entries: { "2026-08-01": "x" } })], today);
        const after = SuspendDraw.computeSignature([habit({ entries: { "2026-08-01": "o" } })], today);

        verify(before !== after);
    }

    function test_signatureChangesWhenADayIsCleared() {
        const marked = SuspendDraw.computeSignature([habit({ entries: { "2026-08-01": "x" } })], today);
        const cleared = SuspendDraw.computeSignature([habit({ entries: {} })], today);

        verify(marked !== cleared);
    }

    function test_signatureChangesWithNameAndPolarity() {
        const base = SuspendDraw.computeSignature([habit()], today);

        verify(base !== SuspendDraw.computeSignature([habit({ name: "Exercise" })], today));
        verify(base !== SuspendDraw.computeSignature([habit({ polarity: "Negative" })], today));
    }

    // The rendered grid runs to today, so rolling over midnight must invalidate the image even
    // when nothing else changed.
    function test_signatureChangesWithTheDay() {
        const habits = [habit({ entries: { "2026-08-01": "x" } })];

        verify(SuspendDraw.computeSignature(habits, today) !== SuspendDraw.computeSignature(habits, new Date(2026, 7, 10)));
        verify(SuspendDraw.computeSignature(habits, today) !== SuspendDraw.computeSignature(habits, new Date(2026, 8, 9)));
        verify(SuspendDraw.computeSignature(habits, today) !== SuspendDraw.computeSignature(habits, new Date(2027, 7, 9)));
    }

    function test_signatureExcludesPrivateHabits() {
        const visibleOnly = SuspendDraw.computeSignature([habit({ name: "Shown" })], today);
        const withPrivate = SuspendDraw.computeSignature([
            habit({ name: "Shown" }),
            habit({ name: "Hidden", isPrivate: true })
        ], today);

        compare(visibleOnly, withPrivate);
    }

    // Private habits are excluded, so editing one must not trigger a redraw of an image it is not in.
    function test_signatureIgnoresEditsToPrivateHabits() {
        const before = SuspendDraw.computeSignature([habit({ isPrivate: true, entries: {} })], today);
        const after = SuspendDraw.computeSignature([habit({ isPrivate: true, entries: { "2026-08-01": "x" } })], today);

        compare(before, after);
    }

    // Only days up to today are drawn, so a future mark is invisible and must not force a redraw.
    function test_signatureIgnoresFutureDays() {
        const before = SuspendDraw.computeSignature([habit({ entries: {} })], today);
        const after = SuspendDraw.computeSignature([habit({ entries: { "2026-08-20": "x" } })], today);

        compare(before, after);
    }

    function test_signatureDistinguishesHabitOrder() {
        const first = SuspendDraw.computeSignature([habit({ name: "A" }), habit({ name: "B" })], today);
        const second = SuspendDraw.computeSignature([habit({ name: "B" }), habit({ name: "A" })], today);

        verify(first !== second);
    }

    function test_signatureToleratesAHabitWithNoEntries() {
        const signature = SuspendDraw.computeSignature([habit({ entries: undefined })], today);

        verify(signature.length > 0);
    }
}
