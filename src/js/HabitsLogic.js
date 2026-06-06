.pragma library

function trim(s) {
    return (s || "").replace(/^\s+|\s+$/g, "")
}

function addHabit(habits, name, negative) {
    var trimmed = trim(name)
    if (!trimmed) return null
    return habits.concat([{ name: trimmed, negative: !!negative, entries: {} }])
}

function moveHabit(habits, from, to) {
    if (from < 0 || from >= habits.length) return null
    if (to < 0 || to >= habits.length) return null
    if (from === to) return null
    var copy = habits.slice()
    var item = copy.splice(from, 1)[0]
    copy.splice(to, 0, item)
    return copy
}

function removeHabit(habits, index) {
    if (index < 0 || index >= habits.length) return null
    var copy = habits.slice()
    copy.splice(index, 1)
    return copy
}

function setNegative(habits, index, negative) {
    if (index < 0 || index >= habits.length) return null
    var copy = habits.slice()
    var h = copy[index]
    copy[index] = { name: h.name, negative: !!negative, entries: h.entries }
    return copy
}

function setName(habits, index, name) {
    if (index < 0 || index >= habits.length) return null
    var trimmed = trim(name)
    if (!trimmed) return null
    var copy = habits.slice()
    var h = copy[index]
    copy[index] = { name: trimmed, negative: h.negative, entries: h.entries }
    return copy
}

// positive: empty -> x -> o -> empty
// negative: empty(displayed X) -> o -> empty
function nextEntryValue(current, negative) {
    if (negative) return current === "o" ? "" : "o"
    return current === "" ? "x" : current === "x" ? "o" : ""
}

function toggleEntry(habits, index, dateKey) {
    if (index < 0 || index >= habits.length) return null
    var copy = habits.slice()
    var h = copy[index]
    var entries = {}
    for (var k in h.entries) entries[k] = h.entries[k]
    var next = nextEntryValue(entries[dateKey] || "", h.negative)
    if (next) entries[dateKey] = next
    else delete entries[dateKey]
    copy[index] = { name: h.name, negative: h.negative, entries: entries }
    return copy
}
