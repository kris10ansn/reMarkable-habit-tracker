import QtQuick 2.15
import QtTest 1.2
import "../src/js/Pairing.js" as Pairing

TestCase {
    name: "Pairing"

    // --- request building ----------------------------------------------------------------------

    function test_buildCodeRequestCarriesTheDeviceName() {
        compare(Pairing.buildCodeRequest("reMarkable").deviceName, "reMarkable");
    }

    function test_buildPollRequestCarriesTheCode() {
        compare(Pairing.buildPollRequest("ABC234").code, "ABC234");
    }

    // --- parseCodeResponse ----------------------------------------------------------------------

    function test_parseCodeResponseAcceptsTheDocumentedShape() {
        const parsed = Pairing.parseCodeResponse({ code: "ABC234", expiresAt: 1750000300000, pollIntervalSeconds: 3 });

        compare(parsed.code, "ABC234");
        compare(parsed.expiresAt, 1750000300000);
        compare(parsed.pollIntervalSeconds, 3);
    }

    function test_parseCodeResponseRejectsAnythingElse() {
        [undefined, null, {}, { code: "" }, { code: "ABC234" }, { code: "ABC234", expiresAt: "soon" }, { code: "ABC234", expiresAt: 1, pollIntervalSeconds: "3" }, "ABC234"].forEach(body => {
            compare(Pairing.parseCodeResponse(body), null, `${JSON.stringify(body)} should be rejected`);
        });
    }

    // --- parsePollResponse ----------------------------------------------------------------------

    // The PairingStatus member-name spelling is load-bearing across three apps — it must compare
    // exactly, never lower- or upper-cased.
    function test_parsePollResponseAcceptsPending() {
        const parsed = Pairing.parsePollResponse({ status: "Pending", token: null });

        compare(parsed.status, "Pending");
        compare(parsed.token, null);
    }

    function test_parsePollResponseAcceptsApprovedWithAToken() {
        const parsed = Pairing.parsePollResponse({ status: "Approved", token: "a-bearer-token" });

        compare(parsed.status, "Approved");
        compare(parsed.token, "a-bearer-token");
    }

    function test_parsePollResponseAcceptsExpiredWithANullToken() {
        const parsed = Pairing.parsePollResponse({ status: "Expired", token: null });

        compare(parsed.status, "Expired");
        compare(parsed.token, null);
    }

    // Approved without a string token is not a shape the client can act on — a null token would
    // silently "connect" the device with nothing to send as Authorization.
    function test_parsePollResponseRejectsApprovedWithoutAToken() {
        compare(Pairing.parsePollResponse({ status: "Approved", token: null }), null);
        compare(Pairing.parsePollResponse({ status: "Approved" }), null);
    }

    function test_parsePollResponseRejectsAnUnknownStatus() {
        [undefined, null, {}, { status: "pending" }, { status: "approved", token: "x" }, { status: "Something" }, "Pending"].forEach(body => {
            compare(Pairing.parsePollResponse(body), null, `${JSON.stringify(body)} should be rejected`);
        });
    }

    // --- terminal-status predicates -------------------------------------------------------------

    // PairingStore branches on these rather than re-spelling "Approved"/"Expired" itself, so the
    // load-bearing spelling lives in Pairing.js alone. Case sensitivity is the whole point.

    function test_isApprovedMatchesOnlyTheExactSpelling() {
        verify(Pairing.isApproved("Approved"));
        ["approved", "APPROVED", "Pending", "Expired", "", undefined].forEach(status => {
            verify(!Pairing.isApproved(status), `${status} should not read as approved`);
        });
    }

    function test_isExpiredMatchesOnlyTheExactSpelling() {
        verify(Pairing.isExpired("Expired"));
        ["expired", "EXPIRED", "Pending", "Approved", "", undefined].forEach(status => {
            verify(!Pairing.isExpired(status), `${status} should not read as expired`);
        });
    }
}
