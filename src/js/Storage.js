.pragma library

function readJson(path) {
    try {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + path, false)
        xhr.send()
        if ((xhr.status === 200 || xhr.status === 0) && xhr.responseText && xhr.responseText.length > 0) {
            return JSON.parse(xhr.responseText)
        }
    } catch (e) {
        console.log("Storage: could not read", path, "-", e)
    }
    return null
}

function writeJson(path, value) {
    try {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", "file://" + path)
        xhr.send(JSON.stringify(value))
        return true
    } catch (e) {
        console.log("Storage: could not write", path, "-", e)
        return false
    }
}
