.import "Storage.js" as Storage

// Storage reports a write only once it has landed, so both of these answer through a callback
// rather than a return value. Reporting the copy synchronously is what let a failed suspend-image
// backup read as a success — and enabling the feature on that answer overwrites the stock image
// with no way back (ADR 0001).

function copyFile(srcPath, dstPath, onDone) {
    const buffer = Storage.readBinary(srcPath);
    if (buffer === null) {
        console.warn("SuspendRender: could not read", srcPath);
        onDone(false);
        return;
    }

    Storage.writeBinary(dstPath, buffer, (error) => {
        if (error) {
            console.warn("SuspendRender: could not write", dstPath);
        }
        onDone(!error);
    });
}

function readSignature(path) {
    const sig = Storage.readJson(path);
    return typeof sig === "string" ? sig : "";
}

function writeSignature(path, signature, onDone) {
    const report = (succeeded) => {
        if (typeof onDone === "function") {
            onDone(succeeded);
        }
    };

    try {
        Storage.writeJson(path, signature, (error) => report(!error));
    } catch (e) {
        console.warn("SuspendRender: could not write signature", path, "-", e);
        report(false);
    }
}
