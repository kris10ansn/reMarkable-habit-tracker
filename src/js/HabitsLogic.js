const trim = (s) => (s || "").trim();

const inBounds = (arr, i) => i >= 0 && i < arr.length;

const replaceAt = (arr, i, value) => [
    ...arr.slice(0, i),
    value,
    ...arr.slice(i + 1),
];

const updateAt = (arr, i, updates) =>
    replaceAt(arr, i, Object.assign({}, arr[i], updates));

const withEntry = (entries, key, value) => {
    const copy = Object.assign({}, entries);
    if (value) copy[key] = value;
    else delete copy[key];
    return copy;
};

// positive: empty -> x -> o -> empty
// negative: empty(displayed X) -> o -> empty
const nextEntryValue = (current, negative) => {
    if (negative) return current === "o" ? "" : "o";
    if (current === "") return "x";
    if (current === "x") return "o";
    return "";
};

function addHabit(habits, name, negative) {
    const trimmed = trim(name);
    if (!trimmed) return null;
    return [...habits, { name: trimmed, negative: !!negative, entries: {} }];
}

function moveHabit(habits, from, to) {
    if (!inBounds(habits, from) || !inBounds(habits, to) || from === to)
        return null;
    const copy = habits.slice();
    const [item] = copy.splice(from, 1);
    copy.splice(to, 0, item);
    return copy;
}

function removeHabit(habits, index) {
    if (!inBounds(habits, index)) return null;
    return [...habits.slice(0, index), ...habits.slice(index + 1)];
}

function setNegative(habits, index, negative) {
    if (!inBounds(habits, index)) return null;
    return updateAt(habits, index, { negative: !!negative });
}

function setName(habits, index, name) {
    const trimmed = trim(name);
    if (!inBounds(habits, index) || !trimmed) return null;
    return updateAt(habits, index, { name: trimmed });
}

function toggleEntry(habits, index, dateKey) {
    if (!inBounds(habits, index)) return null;
    const habit = habits[index];
    const next = nextEntryValue(habit.entries[dateKey] || "", habit.negative);
    return updateAt(habits, index, {
        entries: withEntry(habit.entries, dateKey, next),
    });
}
