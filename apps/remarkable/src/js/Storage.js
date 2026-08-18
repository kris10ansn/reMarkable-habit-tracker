const MISSING = "missing";
const CORRUPT = "corrupt";

const ok = (status) => status === 200 || status === 0;

// A local-file write reports nothing useful about whether it worked: Qt answers status 0 whether
// the bytes landed or the directory does not exist, and it answers asynchronously. So the only
// proof a write succeeded is reading the file back once the request completes.
//
// Every write therefore takes an `onDone(error)` — null on success, a message otherwise. It cannot
// be a return value or a throw: this used to throw from the request's own callback, which throws
// into the event loop where no caller can catch it, so a missing data/ dir reported a clean save
// and the app carried on believing it had persisted (see JsonStore).
const reportWrite = (onDone, error) => {
    if (error) {
        console.warn(error);
    }
    if (typeof onDone === "function") {
        onDone(error);
    }
};

// The raw text of a file, or null if it could not be read. Kept separate from readFile because a
// write verifies against the exact body it sent, which may legitimately be a MISSING-like string.
const rawText = (path) => {
    try {
        const xhr = new XMLHttpRequest();

        xhr.open("GET", `file://${path}`, false);
        xhr.send();

        return ok(xhr.status) ? xhr.responseText : null;
    } catch (e) {
        console.warn("Storage: could not read", path, "-", e);
        return null;
    }
};

function writeFile(path, body, onDone) {
    const xhr = new XMLHttpRequest();

    xhr.onreadystatechange = () => {
        if (xhr.readyState !== xhr.DONE) return;

        const landed = rawText(path) === body;
        reportWrite(
            onDone,
            landed ? null : `Storage: write failed for ${path}`,
        );
    };

    try {
        xhr.open("PUT", `file://${path}`);
        xhr.send(body);
    } catch (error) {
        reportWrite(onDone, `Storage: write failed for ${path} - ${error}`);
    }
}

function readFile(path) {
    const text = rawText(path);

    return text ? text : MISSING;
}

function readJson(path) {
    const body = readFile(path);
    if (body === MISSING) return MISSING;

    try {
        return JSON.parse(body);
    } catch (e) {
        console.warn("Storage: corrupt JSON at", path, "-", e);
        return CORRUPT;
    }
}

// Throws rather than reporting through onDone: a value that stringifies to nothing is a caller
// bug, not a storage failure, and it must be caught before it truncates the file.
function writeJson(path, value, onDone) {
    const body = JSON.stringify(value);

    if (typeof body !== "string" || body === "") {
        throw new Error(`Storage: refusing to write empty body for ${path}`);
    }

    writeFile(path, body, onDone);
}

function isMissing(result) {
    return result === MISSING;
}
function isCorrupt(result) {
    return result === CORRUPT;
}

function readBinary(path) {
    try {
        const xhr = new XMLHttpRequest();

        xhr.open("GET", `file://${path}`, false);
        xhr.responseType = "arraybuffer";
        xhr.send();

        // An unreadable file answers with a zero-length buffer rather than nothing, so length is
        // the real test — otherwise a missing suspend image copies as an empty one.
        const empty = !xhr.response || xhr.response.byteLength === 0;

        return ok(xhr.status) && !empty ? xhr.response : null;
    } catch (e) {
        console.warn("Storage: could not read binary", path, "-", e);
        return null;
    }
}

// Verified by size rather than by content: the failure mode is nothing being written at all, and
// comparing a megabyte of suspend image byte by byte on the device is not worth the certainty.
function writeBinary(path, buffer, onDone) {
    const xhr = new XMLHttpRequest();
    const expected = buffer ? buffer.byteLength : 0;

    xhr.onreadystatechange = () => {
        if (xhr.readyState !== xhr.DONE) return;

        const written = readBinary(path);
        const landed = !!written && written.byteLength === expected;
        reportWrite(
            onDone,
            landed ? null : `Storage: binary write failed for ${path}`,
        );
    };

    try {
        xhr.open("PUT", `file://${path}`);
        xhr.send(buffer);
    } catch (error) {
        reportWrite(
            onDone,
            `Storage: binary write failed for ${path} - ${error}`,
        );
    }
}
