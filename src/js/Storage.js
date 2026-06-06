function readJson(path) {
    try {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", `file://${path}`, false);
        xhr.send();
        const ok = (xhr.status === 200 || xhr.status === 0) && xhr.responseText;
        return ok ? JSON.parse(xhr.responseText) : null;
    } catch (e) {
        console.log("Storage: could not read", path, "-", e);
        return null;
    }
}

function writeJson(path, value) {
    try {
        const xhr = new XMLHttpRequest();
        xhr.open("PUT", `file://${path}`);
        xhr.send(JSON.stringify(value));
        return true;
    } catch (e) {
        console.log("Storage: could not write", path, "-", e);
        return false;
    }
}
