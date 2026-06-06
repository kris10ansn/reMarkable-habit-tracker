import QtQuick 2.15
import "js/Storage.js" as Storage
import "js/HabitsLogic.js" as Logic
import "js/habits.js" as DefaultHabits

QtObject {
    id: store

    property string filePath: "/home/root/xovi/exthome/appload/habit-tracker/habits.json"
    property var habits: []

    signal saved()

    Component.onCompleted: load()

    function load() {
        const data = Storage.readJson(filePath)
        if (Array.isArray(data)) {
            habits = data
            return
        }

        habits = DefaultHabits.habits.slice()

        if (Storage.isCorrupt(data)) {
            console.warn("HabitsStore: refusing to overwrite corrupt file at", filePath, "- using defaults in memory only")
            return
        }
        save()
    }

    function save() {
        Storage.writeJson(filePath, habits)
        saved()
    }

    function _apply(next) {
        if (next === null) return
        habits = next
        save()
    }

    function add(name, negative)         { _apply(Logic.addHabit(habits, name, negative)) }
    function move(from, to)              { _apply(Logic.moveHabit(habits, from, to)) }
    function remove(index)               { _apply(Logic.removeHabit(habits, index)) }
    function setNegative(index, negative){ _apply(Logic.setNegative(habits, index, negative)) }
    function setName(index, name)        { _apply(Logic.setName(habits, index, name)) }
    function toggleEntry(index, dateKey) { _apply(Logic.toggleEntry(habits, index, dateKey)) }
}
