import QtQuick 2.15
import QtTest 1.2
import "../src/js/SuspendStatus.js" as SuspendStatus

TestCase {
    name: "SuspendStatus"

    function test_pendingCountsDown() {
        compare(SuspendStatus.text("pending", 5), "Saving suspend image in 5s");
        compare(SuspendStatus.text("pending", 1), "Saving suspend image in 1s");
    }

    // At zero the countdown has run out and the save is starting, so it reads as in-progress
    // rather than "in 0s".
    function test_pendingAtZeroReadsAsInProgress() {
        compare(SuspendStatus.text("pending", 0), "Saving suspend image...");
    }

    function test_everyPhaseHasALabel() {
        const phases = ["saving", "saved", "backing-up", "backed-up", "restoring", "restored", "backup-failed", "restore-failed"];

        phases.forEach(phase => verify(SuspendStatus.text(phase, 0).length > 0, `no label for ${phase}`));
    }

    function test_unknownPhaseIsSilent() {
        compare(SuspendStatus.text("", 0), "");
        compare(SuspendStatus.text("nonsense", 0), "");
    }
}
