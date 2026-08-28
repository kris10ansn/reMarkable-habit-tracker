import QtQuick 2.15
import "js/Pairing.js" as Pairing
import "js/ServerUrl.js" as ServerUrl

// TV-style device-code pairing (AUTH_PLAN.md decision 6): request a short code, poll for the
// phone's approval while the settings page is visible, hand the token to SettingsStore once
// approved. Nothing here persists — the code is worthless once its 5-minute window closes, and
// a live token belongs to SettingsStore instead. Every field is ephemeral UI state, unlike the
// JsonStore-backed stores.
QtObject {
    id: pairingStore

    // Wired by Main.
    property var settingsStore: null

    // Gates the poll timer. Main binds this to the settings page's visibility — polling behind a
    // hidden page would waste battery and, worse, wake the e-ink panel for a screen no one sees.
    property bool active: false

    // "" (idle) | "requesting" (code request in flight) | "waiting" (code shown, polling) |
    // "expired" | "error".
    property string status: ""
    property string code: ""
    property double expiresAt: 0
    property int pollIntervalSeconds: 3
    property string errorMessage: ""

    readonly property bool isConnected: !!(pairingStore.settingsStore && pairingStore.settingsStore.token)
    readonly property bool isBusy: pairingStore.status === "requesting" || pairingStore.status === "waiting"

    // A request already on the wire is never doubled up — a slow network must not pile up polls.
    property bool _awaitingResponse: false

    // Tracks the in-flight XHR so a timeout or cancel() can abort() it, and so a callback that
    // still fires afterward (Qt's XMLHttpRequest can call onreadystatechange even post-abort) is
    // recognised as stale by identity — status alone isn't enough, since a fresh
    // requestCode()/poll started right after would already have put status back to
    // "requesting"/"waiting" for the new request.
    property var _activeXhr: null

    // Qt's XMLHttpRequest has no built-in timeout, so a stalled connection (dropped Wi-Fi, a
    // half-open hop through the Cloudflare tunnel) would otherwise wedge _awaitingResponse for
    // the life of the app. Shorter than SyncStore's 15s: these requests carry a few bytes each
    // way, not a month of habit rows, and this store polls every ~3s against a 5-minute code
    // window, so a lodged request should clear out of the way quickly rather than eating several
    // poll ticks.
    property Timer _timeoutTimer: Timer {
        interval: 10000
        repeat: false
        onTriggered: pairingStore._onRequestTimedOut()
    }

    // Test seam: lets a test hand _post a stand-in that never reaches DONE, to reach the timeout
    // path without a live server. Production code never overrides this.
    property var _createXhr: function () {
        return new XMLHttpRequest();
    }

    onActiveChanged: {
        if (pairingStore.active) {
            pairingStore._resume();
        } else {
            pairingStore._pollTimer.stop();
        }
    }

    property Timer _pollTimer: Timer {
        interval: pairingStore.pollIntervalSeconds * 1000
        repeat: true
        onTriggered: pairingStore._poll()
    }

    function requestCode() {
        if (pairingStore.isConnected || pairingStore.isBusy) {
            return;
        }
        const url = pairingStore._serverUrl();
        if (!url) {
            return;
        }

        pairingStore.status = "requesting";
        pairingStore.errorMessage = "";
        pairingStore._post(url, "/api/pairing/code", Pairing.buildCodeRequest("reMarkable"), pairingStore._onCodeResponse);
    }

    // Drops the in-progress code/poll without touching the token — used when the user navigates
    // away mid-flow via anything other than an explicit disconnect.
    function cancel() {
        pairingStore._pollTimer.stop();
        pairingStore._timeoutTimer.stop();
        pairingStore._abandonActiveRequest();
        pairingStore.status = "";
        pairingStore.code = "";
        pairingStore.expiresAt = 0;
        pairingStore.errorMessage = "";
    }

    // Signs this device out locally only. The session row this token names survives server-side
    // until revoked from the phone's linked-devices list — dropping it here cannot reach the
    // server (there is no account UI on this device, by design).
    function disconnect() {
        pairingStore.cancel();
        if (pairingStore.settingsStore) {
            pairingStore.settingsStore.clearToken();
        }
    }

    // Called whenever the settings page becomes visible again. A code already in hand keeps
    // polling — the phone may have approved it while the page was hidden — unless it ran out
    // while we weren't looking, in which case it's reported expired without spending a request.
    function _resume() {
        if (pairingStore.status !== "waiting") {
            return;
        }
        if (Date.now() >= pairingStore.expiresAt) {
            pairingStore._pollTimer.stop();
            pairingStore.status = "expired";
            return;
        }

        pairingStore._pollTimer.restart();
    }

    function _poll() {
        if (Date.now() >= pairingStore.expiresAt) {
            pairingStore._pollTimer.stop();
            pairingStore.status = "expired";
            return;
        }

        const url = pairingStore._serverUrl();
        if (!url) {
            return;
        }
        pairingStore._post(url, "/api/pairing/poll", Pairing.buildPollRequest(pairingStore.code), pairingStore._onPollResponse);
    }

    // Ignores a response that arrives once the request that made sense of it no longer applies
    // (cancelled, already connected, or disconnected mid-flight) — a stray "requesting" reply
    // must never clobber state a later action already moved past.
    function _onCodeResponse(xhr) {
        if (pairingStore.status !== "requesting") {
            return;
        }
        if (xhr.status !== 200) {
            pairingStore._fail(xhr);
            return;
        }

        const parsed = Pairing.parseCodeResponse(pairingStore._parse(xhr.responseText));
        if (!parsed) {
            pairingStore.status = "error";
            pairingStore.errorMessage = "Malformed server response";
            return;
        }

        pairingStore.code = parsed.code;
        pairingStore.expiresAt = parsed.expiresAt;
        // Assigned before status flips to "waiting": the Timer's interval binding reads this
        // property, so it must already hold the server's value by the time restart() below (or a
        // later _resume()) fires the first tick.
        pairingStore.pollIntervalSeconds = parsed.pollIntervalSeconds;
        pairingStore.status = "waiting";

        if (pairingStore.active) {
            pairingStore._pollTimer.restart();
        }
    }

    // The PairingStatus spelling ("Pending"/"Approved"/"Expired") is load-bearing across three
    // apps — compared verbatim, never lower-cased. Guarded on still being "waiting" so a second
    // Approved (which the server never actually sends — a poll after approval answers Expired
    // with a null token) or any other stray late reply cannot re-store a token or resurrect a
    // stopped poll.
    function _onPollResponse(xhr) {
        if (pairingStore.status !== "waiting") {
            return;
        }
        if (xhr.status !== 200) {
            pairingStore._fail(xhr);
            return;
        }

        const parsed = Pairing.parsePollResponse(pairingStore._parse(xhr.responseText));
        if (!parsed) {
            pairingStore._pollTimer.stop();
            pairingStore.status = "error";
            pairingStore.errorMessage = "Malformed server response";
            return;
        }

        if (parsed.status === "Approved") {
            pairingStore._pollTimer.stop();
            if (pairingStore.settingsStore) {
                pairingStore.settingsStore.setToken(parsed.token);
            }
            pairingStore.status = "";
            pairingStore.code = "";
            pairingStore.expiresAt = 0;
            return;
        }

        if (parsed.status === "Expired") {
            pairingStore._pollTimer.stop();
            pairingStore.status = "expired";
            return;
        }

        // Pending: nothing observable changed, so nothing repaints this tick.
    }

    function _fail(xhr) {
        pairingStore._pollTimer.stop();
        if (xhr.status === 429) {
            pairingStore.status = "error";
            pairingStore.errorMessage = "Too many attempts — wait a moment and try again.";
            return;
        }
        if (xhr.status === 0) {
            pairingStore.status = "error";
            pairingStore.errorMessage = "Couldn’t reach the server";
            return;
        }

        pairingStore.status = "error";
        pairingStore.errorMessage = "Server returned " + xhr.status;
    }

    function _post(url, path, body, onDone) {
        if (pairingStore._awaitingResponse) {
            return;
        }
        pairingStore._awaitingResponse = true;

        const xhr = pairingStore._createXhr();
        pairingStore._activeXhr = xhr;
        xhr.onreadystatechange = function () {
            if (pairingStore._activeXhr !== xhr) {
                return;
            }
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }

            pairingStore._activeXhr = null;
            pairingStore._awaitingResponse = false;
            pairingStore._timeoutTimer.stop();
            onDone(xhr);
        };

        xhr.open("POST", ServerUrl.endpoint(url, path));
        xhr.setRequestHeader("Content-Type", "application/json");
        pairingStore._timeoutTimer.restart();
        xhr.send(JSON.stringify(body));
    }

    // Shared by cancel() and a timeout: releases the in-flight guard and aborts the XHR so a
    // callback that still fires afterward can't act on state the store has since moved past.
    // abort() alone doesn't guarantee that — the identity check in _post's onreadystatechange is
    // what actually stops it.
    function _abandonActiveRequest() {
        const xhr = pairingStore._activeXhr;
        pairingStore._activeXhr = null;
        pairingStore._awaitingResponse = false;
        if (xhr) {
            xhr.abort();
        }
    }

    // A poll timing out isn't fatal — the code can still be valid, and the next tick just tries
    // again. The initial code request has nothing to retry, so that one surfaces as an error the
    // user can act on instead of leaving the spinner running.
    function _onRequestTimedOut() {
        pairingStore._abandonActiveRequest();

        if (pairingStore.status === "requesting") {
            pairingStore.status = "error";
            pairingStore.errorMessage = "Couldn’t reach the server";
        }
    }

    function _serverUrl() {
        if (!pairingStore.settingsStore) {
            return "";
        }

        return ServerUrl.withDefaultScheme(pairingStore.settingsStore.serverUrl);
    }

    function _parse(text) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }
}
