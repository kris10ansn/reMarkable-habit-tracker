// Shared client-side URL handling for every wire edge that talks to the configured backend
// (sync, tablet pairing). Pure functions only — SyncStore and PairingStore own the I/O.

// A scheme-less host (e.g. "192.168.1.50:5000") is treated by Qt's XMLHttpRequest as a local
// file, which rejects POST with "Unsupported method used on a local file". Default to http:// so
// the request actually goes over the network.
function withDefaultScheme(url) {
    const trimmed = (url || "").trim();
    if (!trimmed || /^https?:\/\//i.test(trimmed)) {
        return trimmed;
    }

    return "http://" + trimmed;
}

function endpoint(url, path) {
    return url.replace(/\/+$/, "") + path;
}
