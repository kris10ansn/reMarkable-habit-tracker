#!/usr/bin/env bash
# Smoke test for tools/suspend-writer, the second consumer of src/js.
#
# The tool hosts SuspendDraw.js and its .import chain outside QML, so a storage-shape change or a
# new .import breaks it without breaking `make build` or `make lint` — it has drifted silently once
# already. This catches that from committed fixtures.
#
# No golden-image comparison: font rendering is not portable between machines. Instead the render
# is checked against an empty-roster baseline drawn on this same machine, which proves the habits
# reached the renderer, and against itself, which proves the render is deterministic.

set -euo pipefail

cd "$(dirname "$0")"

WRITER=../tools/suspend-writer/build/suspend-writer
FIXTURES=fixtures
TMP=tmp
TODAY=2026-08-09

if [ ! -x "$WRITER" ]; then
    echo "suspend-writer not built at $WRITER — run 'make suspend-writer-host'" >&2
    exit 1
fi

mkdir -p "$TMP"
failures=0

pass() { echo "PASS   : suspend-writer::$1"; }

fail() {
    echo "FAIL!  : suspend-writer::$1 $2" >&2
    failures=$((failures + 1))
}

# Renders and reports the tool's exit status without tripping `set -e`.
render() {
    local out=$1
    shift
    "$WRITER" --today "$TODAY" --out "$TMP/$out" "$@" >"$TMP/$out.log" 2>&1 && echo 0 || echo $?
}

expect_exit() {
    local test_name=$1 expected=$2 actual=$3
    if [ "$actual" = "$expected" ]; then
        pass "$test_name"
    else
        fail "$test_name" "expected exit $expected, got $actual"
    fi
}

# --- a valid roster and month render ------------------------------------------------------------

status=$(render valid.png --roster "$FIXTURES/roster.json" --month "$FIXTURES/2026-08.json")
expect_exit "rendersValidData" 0 "$status"

if [ ! -s "$TMP/valid.png" ]; then
    fail "writesANonEmptyPng" "no output at $TMP/valid.png"
elif [ "$(head -c 4 "$TMP/valid.png" | od -An -tx1 | tr -d ' \n')" != "89504e47" ]; then
    fail "writesANonEmptyPng" "output is not a PNG"
else
    pass "writesANonEmptyPng"
fi

# --- the habits actually reached the renderer -----------------------------------------------------

printf '{"habits":[]}' >"$TMP/empty-roster.json"
status=$(render baseline.png --roster "$TMP/empty-roster.json")
expect_exit "rendersAnEmptyRoster" 0 "$status"

if cmp -s "$TMP/valid.png" "$TMP/baseline.png"; then
    fail "drawsTheHabits" "the render is identical to an empty roster — the grid did not draw"
else
    pass "drawsTheHabits"
fi

# --- the same inputs draw the same image ------------------------------------------------------------

status=$(render repeat.png --roster "$FIXTURES/roster.json" --month "$FIXTURES/2026-08.json")
expect_exit "repeatsTheRender" 0 "$status"

if cmp -s "$TMP/valid.png" "$TMP/repeat.png"; then
    pass "rendersDeterministically"
else
    fail "rendersDeterministically" "the same inputs produced two different images"
fi

# --- pre-migration data is refused, not drawn wrong -------------------------------------------------

# The app refuses a file it cannot read rather than folding it in as empty (ADR 0006); the tool
# exits 2 rather than drawing a blank grid that reads as "no marks yet".
status=$(render stale-roster.png --roster "$FIXTURES/roster-pre-migration.json")
expect_exit "refusesAPreMigrationRoster" 2 "$status"

status=$(render stale-month.png --roster "$FIXTURES/roster.json" --month "$FIXTURES/2026-08-pre-migration.json")
expect_exit "refusesAPreMigrationMonth" 2 "$status"

# --- a roster still spelling hideFromSleep is refused, not drawn wrong -------------------------------

# An old-spelling roster has no `isPrivate` key; rendering it as `isPrivate: false` would put a
# private habit on the lock screen, so this must exit 2 the same as the other pre-migration shapes.
status=$(render stale-private.png --roster "$FIXTURES/roster-hide-from-sleep.json")
expect_exit "refusesARosterStillSpellingHideFromSleep" 2 "$status"

# --- report ------------------------------------------------------------------------------------------

if [ "$failures" -ne 0 ]; then
    echo "Totals: $failures failed" >&2
    exit 1
fi

echo "Totals: 9 passed, 0 failed"
