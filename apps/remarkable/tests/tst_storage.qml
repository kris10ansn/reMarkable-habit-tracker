import QtQuick 2.15
import QtTest 1.2
import "../src/js/Storage.js" as Storage
import "TestPaths.js" as TestPaths

// Storage speaks three answers, not two: a value, MISSING, or CORRUPT. Keeping MISSING and
// CORRUPT apart is what lets HabitsStore seed defaults on a first run but refuse a damaged file
// (ADR 0006) — collapsing them would overwrite real data.
TestCase {
    name: "Storage"

    function path(name) {
        return TestPaths.tmpPath(`storage-${name}`);
    }

    // Writes are async PUTs, so a readback has to wait for the file to land.
    function writtenJson(target) {
        tryVerify(() => !Storage.isMissing(Storage.readJson(target)), 2000, `nothing written to ${target}`);

        return Storage.readJson(target);
    }

    function test_jsonRoundTrip() {
        const target = path("round-trip.json");
        const value = { month: "2026-08", entries: [{ habitId: "a", date: "2026-08-01", outcome: "x" }] };

        Storage.writeJson(target, value);

        const back = writtenJson(target);
        compare(back.month, "2026-08");
        compare(back.entries.length, 1);
        compare(back.entries[0].outcome, "x");
    }

    function test_readingAnAbsentFileIsMissing() {
        const result = Storage.readJson(path("does-not-exist.json"));

        verify(Storage.isMissing(result));
        verify(!Storage.isCorrupt(result));
    }

    function test_readingUnparseableJsonIsCorrupt() {
        const target = path("corrupt.json");
        Storage.writeFile(target, "{ this is not json");

        tryVerify(() => Storage.isCorrupt(Storage.readJson(target)), 2000);
        verify(!Storage.isMissing(Storage.readJson(target)));
    }

    // An empty file is indistinguishable from an absent one here, and that is the safe reading:
    // a truncated write must not be mistaken for damaged data the app then refuses forever.
    function test_readingAnEmptyFileIsMissing() {
        const target = path("empty.json");
        Storage.writeFile(target, "");

        wait(200);
        verify(Storage.isMissing(Storage.readJson(target)));
    }

    // --- write reporting ----------------------------------------------------------------------

    // A local-file write answers status 0 whether or not it landed, so success is established by
    // reading the file back. Nothing else can tell the two apart.
    function test_writeReportsSuccessOnceTheBytesLand() {
        const target = path("reports-ok.json");
        const errors = [];

        Storage.writeJson(target, { a: 1 }, error => errors.push(error));

        tryVerify(() => errors.length === 1, 2000, "the write never reported");
        compare(errors[0], null);
        compare(Storage.readJson(target).a, 1);
    }

    // The regression that mattered: this used to throw from the request's own callback, which
    // throws into the event loop where no caller can catch it — so a write into a missing
    // directory reported a clean save.
    function test_writeReportsFailureForAMissingDirectory() {
        const errors = [];

        Storage.writeJson(`${TestPaths.tmpDir()}/no-such-dir/x.json`, { a: 1 }, error => errors.push(error));

        tryVerify(() => errors.length === 1, 2000, "the failed write never reported");
        verify(errors[0], "a failed write must report an error");
        verify(errors[0].indexOf("no-such-dir") !== -1, `the message should name the file: ${errors[0]}`);
    }

    function test_binaryWriteReportsFailureForAMissingDirectory() {
        const source = path("binary-source.bin");
        Storage.writeFile(source, "some bytes");
        tryVerify(() => Storage.readBinary(source) !== null, 2000);

        const errors = [];
        Storage.writeBinary(`${TestPaths.tmpDir()}/no-such-dir/y.bin`, Storage.readBinary(source), error => errors.push(error));

        tryVerify(() => errors.length === 1, 2000, "the failed binary write never reported");
        verify(errors[0], "a failed binary write must report an error");
    }

    function test_binaryRoundTripReportsSuccess() {
        const source = path("binary-round-trip-src.bin");
        const target = path("binary-round-trip-dst.bin");
        Storage.writeFile(source, "0123456789");
        tryVerify(() => Storage.readBinary(source) !== null, 2000);

        const errors = [];
        Storage.writeBinary(target, Storage.readBinary(source), error => errors.push(error));

        tryVerify(() => errors.length === 1, 2000);
        compare(errors[0], null);
        compare(Storage.readBinary(target).byteLength, 10);
    }

    // An unreadable file answers with a zero-length buffer rather than nothing, so length is the
    // real test — otherwise a missing suspend image copies as an empty one.
    function test_readBinaryTreatsAnAbsentFileAsNothing() {
        compare(Storage.readBinary(path("no-such-binary.bin")), null);
    }

    // writeJson refuses a value that stringifies to nothing, so a serialize hook that returns
    // undefined truncates the file instead of silently emptying it. JsonStore turns the throw
    // into its saveFailed signal.
    function test_writeJsonRefusesAnEmptyBody() {
        let threw = false;
        try {
            Storage.writeJson(path("never-written.json"), undefined);
        } catch (error) {
            threw = true;
        }

        verify(threw);
        verify(Storage.isMissing(Storage.readJson(path("never-written.json"))));
    }

    function test_sentinelsAreDistinctFromOrdinaryValues() {
        verify(Storage.isMissing(Storage.MISSING));
        verify(Storage.isCorrupt(Storage.CORRUPT));
        verify(!Storage.isMissing(Storage.CORRUPT));
        verify(!Storage.isCorrupt(Storage.MISSING));

        [null, undefined, 0, "", {}, []].forEach(value => {
            verify(!Storage.isMissing(value));
            verify(!Storage.isCorrupt(value));
        });
    }

    function test_readFileReturnsRawText() {
        const target = path("raw.txt");
        Storage.writeFile(target, "hello");

        tryVerify(() => Storage.readFile(target) === "hello", 2000);
    }

    function test_overwritingReplacesTheWholeFile() {
        const target = path("overwrite.json");

        Storage.writeJson(target, { a: 1, b: 2, c: 3 });
        tryVerify(() => !Storage.isMissing(Storage.readJson(target)), 2000);

        Storage.writeJson(target, { a: 9 });
        tryVerify(() => Storage.readJson(target).b === undefined, 2000);
        compare(Storage.readJson(target).a, 9);
    }
}
