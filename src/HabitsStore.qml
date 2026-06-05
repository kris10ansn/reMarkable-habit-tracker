import QtQuick 2.15
import "js/habits.js" as DefaultHabits

QtObject {
    id: store

    property string filePath: "/home/root/xovi/exthome/appload/habit-tracker/habits.json"
    property var habits: []

    Component.onCompleted: load()

    function load() {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file://" + filePath, false);
            xhr.send();
            if ((xhr.status === 200 || xhr.status === 0) && xhr.responseText && xhr.responseText.length > 0) {
                var data = JSON.parse(xhr.responseText);
                if (Array.isArray(data)) {
                    habits = data;
                    return;
                }
            }
        } catch (e) {
            console.log("HabitsStore: could not read", filePath, "-", e);
        }
        habits = DefaultHabits.habits.slice();
        save();
    }

    function save() {
        try {
            var xhr = new XMLHttpRequest();
            xhr.open("PUT", "file://" + filePath);
            xhr.send(JSON.stringify(habits));
        } catch (e) {
            console.log("HabitsStore: could not write", filePath, "-", e);
        }
    }

    function add(name, negative) {
        var trimmed = (name || "").replace(/^\s+|\s+$/g, "");
        if (!trimmed) return;
        habits = habits.concat([{ name: trimmed, negative: !!negative, entries: {} }]);
        save();
    }

    function move(fromIndex, toIndex) {
        if (fromIndex < 0 || fromIndex >= habits.length) return;
        if (toIndex < 0 || toIndex >= habits.length) return;
        if (fromIndex === toIndex) return;
        var copy = habits.slice();
        var item = copy.splice(fromIndex, 1)[0];
        copy.splice(toIndex, 0, item);
        habits = copy;
        save();
    }

    function remove(index) {
        if (index < 0 || index >= habits.length) return;
        var copy = habits.slice();
        copy.splice(index, 1);
        habits = copy;
        save();
    }

    function setNegative(index, negative) {
        if (index < 0 || index >= habits.length) return;
        var copy = habits.slice();
        copy[index] = { name: copy[index].name, negative: !!negative, entries: copy[index].entries };
        habits = copy;
        save();
    }

    function setName(index, name) {
        if (index < 0 || index >= habits.length) return;
        var trimmed = (name || "").replace(/^\s+|\s+$/g, "");
        if (!trimmed) return;
        var copy = habits.slice();
        copy[index] = { name: trimmed, negative: copy[index].negative, entries: copy[index].entries };
        habits = copy;
        save();
    }

    function toggleEntry(index, dateKey) {
        if (index < 0 || index >= habits.length) return;
        var copy = habits.slice();
        var h = copy[index];
        var entries = {};
        for (var k in h.entries) entries[k] = h.entries[k];
        var current = entries[dateKey] || "";
        var next;
        if (h.negative) {
            // negative cycle: empty(displayed X) -> o -> empty
            next = current === "o" ? "" : "o";
        } else {
            // positive cycle: empty -> x -> o -> empty
            next = current === "" ? "x" : current === "x" ? "o" : "";
        }
        if (next) entries[dateKey] = next;
        else delete entries[dateKey];
        copy[index] = { name: h.name, negative: h.negative, entries: entries };
        habits = copy;
        save();
    }
}
