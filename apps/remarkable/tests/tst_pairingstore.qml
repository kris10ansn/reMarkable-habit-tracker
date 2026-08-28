import QtQuick 2.15
import QtTest 1.2
import "../src" as App

// PairingStore's decisions, without a server: _onCodeResponse/_onPollResponse take an
// { status, responseText } stand-in rather than a live XHR, exactly like SyncStore's
// _handleDone (see tst_syncstore.qml) — requestCode()/the poll Timer are what would actually
// touch the network, so tests exercise their early-return guards only and drive the response
// handlers directly for everything past that.
TestCase {
    id: testCase
    name: "PairingStore"

    property var store: null

    Component {
        id: pairingStoreComponent

        App.PairingStore {}
    }

    function cleanup() {
        if (!store) {
            return;
        }

        store._pollTimer.stop();
        store.destroy();
        store = null;
    }

    function fakeSettingsStore(overrides) {
        return Object.assign({
            serverUrl: "http://example.test",
            token: "",
            setToken: function (value) {
                this.token = value;
            },
            clearToken: function () {
                this.token = "";
            }
        }, overrides || {});
    }

    function makeStore(settingsOverrides) {
        store = pairingStoreComponent.createObject(testCase, {
            settingsStore: fakeSettingsStore(settingsOverrides)
        });

        return store;
    }

    function done(status, body) {
        return { status: status, responseText: typeof body === "string" ? body : JSON.stringify(body) };
    }

    // A stand-in for XMLHttpRequest that never reaches DONE on its own, so a test can reach the
    // _timeoutTimer path without a live server. respond() lets a test simulate the abandoned
    // request finally answering, late.
    function fakeHangingXhr() {
        return {
            readyState: 0,
            status: 0,
            responseText: "",
            onreadystatechange: null,
            abortCalls: 0,
            open: function () {},
            setRequestHeader: function () {},
            send: function () {},
            abort: function () {
                this.abortCalls++;
            },
            respond: function (status, body) {
                this.readyState = XMLHttpRequest.DONE;
                this.status = status;
                this.responseText = typeof body === "string" ? body : JSON.stringify(body);
                if (this.onreadystatechange) {
                    this.onreadystatechange();
                }
            }
        };
    }

    // --- requestCode guards (never reach the network) --------------------------------------------

    function test_requestCodeIsANoOpWithoutAServerUrl() {
        makeStore({ serverUrl: "" });

        store.requestCode();

        compare(store.status, "");
    }

    function test_requestCodeIsANoOpWhenAlreadyConnected() {
        makeStore({ token: "an-existing-token" });

        store.requestCode();

        compare(store.status, "");
    }

    function test_requestCodeIsANoOpWhileBusy() {
        makeStore();
        store.status = "waiting";

        store.requestCode();

        compare(store.status, "waiting");
    }

    // --- _onCodeResponse -----------------------------------------------------------------------

    function test_onCodeResponseStoresTheCodeAndStartsWaiting() {
        makeStore();
        store.active = true;
        store.status = "requesting";

        store._onCodeResponse(done(200, { code: "ABC234", expiresAt: 1750000300000, pollIntervalSeconds: 3 }));

        compare(store.status, "waiting");
        compare(store.code, "ABC234");
        compare(store.expiresAt, 1750000300000);
        compare(store.pollIntervalSeconds, 3);
        verify(store._pollTimer.running, "polling should start immediately while the page is visible");
    }

    function test_onCodeResponseWhileInactiveStoresTheCodeButDoesNotPoll() {
        makeStore();
        store.active = false;
        store.status = "requesting";

        store._onCodeResponse(done(200, { code: "ABC234", expiresAt: 1750000300000, pollIntervalSeconds: 3 }));

        compare(store.status, "waiting");
        verify(!store._pollTimer.running, "a hidden settings page must not be polled");
    }

    function test_onCodeResponseIgnoresAStrayReply() {
        makeStore();
        store.status = "";

        store._onCodeResponse(done(200, { code: "ABC234", expiresAt: 1750000300000, pollIntervalSeconds: 3 }));

        compare(store.status, "", "a response for a request nothing is waiting on changes nothing");
        compare(store.code, "");
    }

    function test_onCodeResponseSurfacesAMalformedBody() {
        makeStore();
        store.status = "requesting";

        store._onCodeResponse(done(200, "<html>not json</html>"));

        compare(store.status, "error");
        compare(store.errorMessage, "Malformed server response");
    }

    function test_onCodeResponseSurfacesARateLimit() {
        makeStore();
        store.status = "requesting";

        store._onCodeResponse(done(429, ""));

        compare(store.status, "error");
        compare(store.errorMessage, "Too many attempts — wait a moment and try again.");
    }

    // --- _onPollResponse -------------------------------------------------------------------------

    // The "at minimum" cases from the phase brief: Pending -> Approved stores the token, Expired
    // doesn't, and a second Approved can't happen.
    function test_pendingLeavesTheStatusWaiting() {
        makeStore();
        store.status = "waiting";
        store.code = "ABC234";

        store._onPollResponse(done(200, { status: "Pending", token: null }));

        compare(store.status, "waiting");
        compare(store.settingsStore.token, "");
    }

    function test_approvedStoresTheTokenAndStopsPolling() {
        makeStore();
        store.status = "waiting";
        store.code = "ABC234";
        store._pollTimer.start();

        store._onPollResponse(done(200, { status: "Approved", token: "a-bearer-token" }));

        compare(store.settingsStore.token, "a-bearer-token");
        compare(store.status, "");
        compare(store.code, "");
        verify(!store._pollTimer.running);
    }

    function test_expiredDoesNotStoreATokenAndStopsPolling() {
        makeStore();
        store.status = "waiting";
        store.code = "ABC234";
        store._pollTimer.start();

        store._onPollResponse(done(200, { status: "Expired", token: null }));

        compare(store.status, "expired");
        compare(store.settingsStore.token, "");
        verify(!store._pollTimer.running);
    }

    // Once approval has already been processed, status has moved off "waiting" — a late/duplicate
    // reply (the server is not supposed to send a second Approved, but nothing here trusts that)
    // must not re-store a token or resurrect a stopped poll.
    function test_aStrayPollResponseAfterApprovalIsIgnored() {
        makeStore();
        store.status = "waiting";
        store.code = "ABC234";
        store._onPollResponse(done(200, { status: "Approved", token: "first-token" }));
        compare(store.settingsStore.token, "first-token");

        store._onPollResponse(done(200, { status: "Approved", token: "second-token" }));

        compare(store.settingsStore.token, "first-token", "a stray reply must not overwrite the stored token");
    }

    function test_pollResponseSurfacesARateLimit() {
        makeStore();
        store.status = "waiting";
        store.code = "ABC234";

        store._onPollResponse(done(429, ""));

        compare(store.status, "error");
        compare(store.errorMessage, "Too many attempts — wait a moment and try again.");
        compare(store.settingsStore.token, "");
    }

    function test_pollResponseSurfacesOffline() {
        makeStore();
        store.status = "waiting";
        store.code = "ABC234";

        store._onPollResponse(done(0, ""));

        compare(store.status, "error");
        compare(store.errorMessage, "Couldn’t reach the server");
    }

    // --- resuming after the settings page reappears -----------------------------------------------

    function test_resumeRestartsPollingWhileTheCodeIsStillValid() {
        makeStore();
        store.status = "waiting";
        store.expiresAt = Date.now() + 60000;

        store.active = true;

        verify(store._pollTimer.running);
        compare(store.status, "waiting");
    }

    function test_resumeReportsExpiredWithoutPollingWhenTheCodeRanOutWhileHidden() {
        makeStore();
        store.status = "waiting";
        store.expiresAt = Date.now() - 1000;

        store.active = true;

        compare(store.status, "expired");
        verify(!store._pollTimer.running);
    }

    function test_hidingThePageStopsPolling() {
        makeStore();
        store.status = "waiting";
        store.expiresAt = Date.now() + 60000;
        store.active = true;
        verify(store._pollTimer.running);

        store.active = false;

        verify(!store._pollTimer.running);
    }

    function test_activatingWithNoCodeInFlightDoesNothing() {
        makeStore();

        store.active = true;

        compare(store.status, "");
        verify(!store._pollTimer.running);
    }

    // --- disconnect / cancel ---------------------------------------------------------------------

    function test_disconnectClearsTheTokenAndAnyInFlightCode() {
        makeStore({ token: "a-bearer-token" });
        store.status = "waiting";
        store.code = "ABC234";
        store._pollTimer.start();

        store.disconnect();

        compare(store.settingsStore.token, "");
        compare(store.status, "");
        compare(store.code, "");
        verify(!store._pollTimer.running);
    }

    function test_cancelClearsInFlightStateButNotTheToken() {
        makeStore({ token: "a-bearer-token" });
        store.status = "waiting";
        store.code = "ABC234";
        store._pollTimer.start();

        store.cancel();

        compare(store.status, "");
        compare(store.code, "");
        verify(!store._pollTimer.running);
        compare(store.settingsStore.token, "a-bearer-token", "cancel must not sign the device out");
    }

    // --- request timeout / abandonment -----------------------------------------------------------

    function test_aTimedOutCodeRequestReleasesTheFlagAndBecomesAnErrorTheUserCanRetryFrom() {
        makeStore();
        let issuedCount = 0;
        store._createXhr = function () {
            issuedCount++;
            return fakeHangingXhr();
        };

        store.requestCode();
        compare(issuedCount, 1);
        compare(store.status, "requesting");

        store._onRequestTimedOut();

        compare(store.status, "error", "the initial code request has nothing to retry, so it surfaces as an error");
        compare(store.errorMessage, "Couldn’t reach the server");
        verify(!store._awaitingResponse, "the in-flight guard must release once the request is abandoned");

        store.requestCode();

        compare(issuedCount, 2, "a fresh requestCode() must actually issue a request, not silently return");
    }

    function test_aTimedOutPollIsNotFatalAndTheNextTickRetries() {
        makeStore();
        store.active = true;
        store.status = "waiting";
        store.code = "ABC234";
        store.expiresAt = Date.now() + 60000;
        let xhrs = [];
        store._createXhr = function () {
            const xhr = fakeHangingXhr();
            xhrs.push(xhr);
            return xhr;
        };
        store._pollTimer.restart();

        store._poll();
        compare(xhrs.length, 1);

        store._onRequestTimedOut();

        compare(store.status, "waiting", "the code may still be valid, so a poll timeout is not surfaced as an error");
        verify(!store._awaitingResponse);
        verify(store._pollTimer.running, "a poll timeout must not stop the timer — the next tick tries again");

        store._poll();

        compare(xhrs.length, 2, "the next tick issues a fresh poll rather than staying wedged behind the old one");
    }

    function test_cancelDuringAnInFlightRequestAllowsAnImmediateRetry() {
        makeStore();
        let xhrs = [];
        store._createXhr = function () {
            const xhr = fakeHangingXhr();
            xhrs.push(xhr);
            return xhr;
        };

        store.requestCode();
        compare(xhrs.length, 1);

        store.cancel();

        compare(xhrs[0].abortCalls, 1, "cancel must abort the abandoned request, not just forget about it");
        verify(!store._awaitingResponse, "cancel must release the in-flight guard too");
        compare(store.status, "");

        store.requestCode();

        compare(xhrs.length, 2, "a fresh request right after cancel() must not be swallowed by a stuck flag");
    }

    // The status-based guards in _onCodeResponse/_onPollResponse only protect a late reply while
    // status has moved off "requesting"/"waiting" — they do nothing once a fresh request has put
    // it back. This is the case _post's XHR-identity check exists for.
    function test_aLateReplyFromAnAbandonedCodeRequestCannotClobberAFreshOne() {
        makeStore();
        let xhrs = [];
        store._createXhr = function () {
            const xhr = fakeHangingXhr();
            xhrs.push(xhr);
            return xhr;
        };

        store.requestCode();
        store.cancel();
        store.requestCode();
        compare(xhrs.length, 2, "the second requestCode() must issue its own request");
        compare(store.status, "requesting");

        // The first (abandoned) request finally answers, after a second one is already in flight.
        xhrs[0].respond(200, { code: "OLD000", expiresAt: Date.now() + 300000, pollIntervalSeconds: 3 });

        compare(store.code, "", "a stray reply from the abandoned request must not overwrite the fresh one's state");
        compare(store.status, "requesting", "the fresh request must still be the one considered in flight");
    }

    function test_aLateReplyFromATimedOutPollCannotStoreATokenOrStopThePollTimer() {
        makeStore();
        store.active = true;
        store.status = "waiting";
        store.code = "ABC234";
        store.expiresAt = Date.now() + 60000;
        let xhrs = [];
        store._createXhr = function () {
            const xhr = fakeHangingXhr();
            xhrs.push(xhr);
            return xhr;
        };
        store._pollTimer.restart();

        store._poll();
        store._onRequestTimedOut();
        store._poll();
        compare(xhrs.length, 2, "a second poll should now be in flight");

        // The first (timed-out) poll finally answers.
        xhrs[0].respond(200, { status: "Approved", token: "stale-token" });

        compare(store.settingsStore.token, "", "a stray reply from a timed-out poll must not sign the device in");
        compare(store.status, "waiting", "the fresh poll is still the one considered in flight");
        verify(store._pollTimer.running, "a stray reply must not resurrect or otherwise disturb a still-running poll");
    }

    // --- isConnected / isBusy --------------------------------------------------------------------

    // isConnected is a binding over settingsStore.token; reassigning settingsStore (as Main does
    // whenever the real store's identity could change) is what a QML binding actually reacts to,
    // so the fake below stands in as a whole new object rather than a mutated one.
    function test_isConnectedReflectsTheSettingsStoreToken() {
        makeStore({ token: "" });
        verify(!store.isConnected);

        store.settingsStore = fakeSettingsStore({ token: "a-bearer-token" });
        verify(store.isConnected);
    }

    function test_isBusyCoversRequestingAndWaiting() {
        makeStore();

        ["requesting", "waiting"].forEach(phase => {
            store.status = phase;
            verify(store.isBusy, `${phase} should count as busy`);
        });

        ["", "expired", "error"].forEach(phase => {
            store.status = phase;
            verify(!store.isBusy, `${phase} should not count as busy`);
        });
    }
}
