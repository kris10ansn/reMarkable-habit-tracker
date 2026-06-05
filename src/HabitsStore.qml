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
        habits = habits.concat([{ name: trimmed, negative: !!negative }]);
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
        copy[index] = { name: copy[index].name, negative: !!negative };
        habits = copy;
        save();
    }
}
