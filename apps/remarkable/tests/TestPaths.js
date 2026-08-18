// Absolute filesystem paths inside tests/tmp/, the scratch dir `make test` wipes and recreates
// before every run. Storage.js speaks plain paths (it prefixes file:// itself), so the resolved
// URL is stripped back down to one.
//
// Every test that touches a file must pick a name unique across the whole suite: qmltestrunner
// runs all tst_*.qml in one process against one tmp dir. Prefix with the test file's subject.

function tmpDir() {
    return Qt.resolvedUrl("tmp")
        .toString()
        .replace(/^file:\/\//, "");
}

function tmpPath(name) {
    return `${tmpDir()}/${name}`;
}
