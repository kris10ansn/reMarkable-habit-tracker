// Wire edge for the tablet's device-code pairing flow — POST /api/pairing/code and
// POST /api/pairing/poll, both anonymous per openapi.json. Pure functions only; PairingStore
// does the I/O. Timestamps are epoch ms UTC, matching every other endpoint on this wire.

const PENDING = "Pending";
const APPROVED = "Approved";
const EXPIRED = "Expired";

function buildCodeRequest(deviceName) {
    return { deviceName: deviceName };
}

function buildPollRequest(code) {
    return { code: code };
}

// Null on anything that isn't the documented shape — refused rather than guessed at, mirroring
// Sync.js's own parse. The caller treats null as a malformed-response error.
function parseCodeResponse(body) {
    if (!body || typeof body !== "object") {
        return null;
    }
    if (typeof body.code !== "string" || !body.code) {
        return null;
    }
    if (typeof body.expiresAt !== "number") {
        return null;
    }
    if (typeof body.pollIntervalSeconds !== "number") {
        return null;
    }

    return {
        code: body.code,
        expiresAt: body.expiresAt,
        pollIntervalSeconds: body.pollIntervalSeconds,
    };
}

// The PairingStatus member-name spelling ("Pending"/"Approved"/"Expired") is load-bearing across
// three apps — never lower-cased or reworded here. A token is required on Approved, forbidden
// (well, tolerated as null) otherwise.
function parsePollResponse(body) {
    if (!body || typeof body !== "object") {
        return null;
    }
    if (![PENDING, APPROVED, EXPIRED].includes(body.status)) {
        return null;
    }
    if (body.status === APPROVED && typeof body.token !== "string") {
        return null;
    }

    return {
        status: body.status,
        token: typeof body.token === "string" ? body.token : null,
    };
}

// The two terminal statuses, asked rather than re-spelled: PairingStore branches on the outcome of
// a poll, and the member-name spelling stays in this file only.
function isApproved(status) {
    return status === APPROVED;
}

function isExpired(status) {
    return status === EXPIRED;
}
