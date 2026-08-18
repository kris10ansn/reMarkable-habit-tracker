#!/usr/bin/env node
// Migrate a copy of the device's data/ dir from the device-local "hide from suspend image"
// flag to the synced "private" flag. `hideFromSleep` only ever meant "leave this habit off the
// suspend image"; the new `isPrivate` means "keep this off the suspend image AND the main grid,
// on every device, unless the reveal setting is on" — so it is backend-owned and syncs like
// name/polarity/position. This renames the roster field so a habit already hidden from suspend
// starts out private rather than reverting to public.
//
// Input — a copy of data/ off the device, e.g. from `make backup`:
//   roster.json    { habits: [{ id, name, polarity, hideFromSleep, createdAt, editedAt, deletedAt }] }
//   YYYY-MM.json   { month, entries: [{ habitId, date, outcome, editedAt, deletedAt }] }
//   sync.json      { lastSyncedAt }
//
// Output — a fresh dir to rsync back over the device's data/ (see the README's
// "Upgrading across a storage-format change"): roster.json with each habit row's `hideFromSleep`
// renamed to `isPrivate` (kept at the old key's position); a row with no `hideFromSleep` at all
// gets `isPrivate: false` — lenient, since that only means "never explicitly hidden". Every other
// file (month files, sync.json, anything else present) is copied byte-for-byte — `isPrivate` is a
// roster-only field. `settings.json` needs no migration: `showPrivateHabits` is additive with a
// safe default, so the existing loader already handles a file that predates it.
//
// The app carries no migration code and refuses to write to a file it cannot read (ADR 0006), so
// this runs off-device, once, with the app closed and before the new build is deployed — and the
// suspend-writer binary must be rebuilt and redeployed too, since it reads the same roster shape.
// Delete this script once the device has been migrated.
//
// Usage:
//   node scripts/migrate-is-private.mjs <input-dir> <output-dir> [--force]

import {
    copyFileSync,
    existsSync,
    mkdirSync,
    readdirSync,
    readFileSync,
    statSync,
    unlinkSync,
    writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";

const [, , inputArg, outputArg, ...flags] = process.argv;

if (!inputArg || !outputArg) {
    usage("Missing required input or output path.");
}

const options = parseFlags(flags);
const inputDir = resolve(inputArg);
const outputDir = resolve(outputArg);

if (!existsSync(inputDir) || !statSync(inputDir).isDirectory()) {
    die(`Input is not a directory: ${inputDir}`);
}

if (inputDir === outputDir) {
    die(
        "Input and output must be different paths. Write to a fresh directory, inspect it, then push it to the device.",
    );
}

if (existsSync(outputDir) && !options.force) {
    die(
        `Output already exists: ${outputDir}. Pass --force to overwrite the generated files there.`,
    );
}

const source = readSource(inputDir);
const migrated = migrate(source);

write(inputDir, outputDir, migrated);
verify(outputDir, source, migrated);
report(migrated, outputDir);

function parseFlags(args) {
    const parsed = { force: false };

    args.forEach((flag) => {
        if (flag !== "--force") {
            usage(`Unknown option: ${flag}`);
        }
        parsed.force = true;
    });

    return parsed;
}

// --- read ------------------------------------------------------------------

function readSource(dir) {
    const rosterPath = join(dir, "roster.json");
    if (!existsSync(rosterPath)) {
        die(`Missing roster.json in ${dir}.`);
    }

    const roster = readJson(rosterPath);
    if (!roster || !Array.isArray(roster.habits)) {
        die(`Expected ${rosterPath} to contain { "habits": [...] }.`);
    }

    // Already-migrated input is turned away rather than re-read leniently, matching
    // migrate-edited-at.mjs's temperament: silently no-op-ing a second run would hide a real
    // problem (e.g. running the wrong script against already-current data).
    if (roster.habits.some((habit) => habit && habit.isPrivate !== undefined)) {
        die(
            `${rosterPath} already carries isPrivate — this data has been migrated. Nothing to do.`,
        );
    }

    return {
        roster,
        rosterPath,
        passthrough: passthroughFiles(dir),
    };
}

// Everything but roster.json is carried across untouched, so pushing the output back with
// `rsync --delete` cannot drop a file it simply did not know about — month files and sync.json
// among them.
function passthroughFiles(dir) {
    return readdirSync(dir).filter((name) => name !== "roster.json");
}

// --- migrate -----------------------------------------------------------------

function migrate(source) {
    const habits = source.roster.habits.map((habit) => renamed(habit));

    return { roster: { habits }, passthrough: source.passthrough };
}

// The rename, key order preserved: `hideFromSleep` out, `isPrivate` in its place, every other
// field untouched. A row that never had `hideFromSleep` (it was never explicitly hidden) becomes
// `isPrivate: false` rather than being refused — unlike a missing edit-time, a missing "was this
// ever hidden" flag has an unambiguous, safe default.
function renamed(habit) {
    if (!Object.prototype.hasOwnProperty.call(habit, "hideFromSleep")) {
        return Object.assign({}, habit, { isPrivate: false });
    }

    return Object.keys(habit).reduce((out, key) => {
        if (key === "hideFromSleep") {
            out.isPrivate = !!habit.hideFromSleep;
            return out;
        }

        out[key] = habit[key];
        return out;
    }, {});
}

// --- write and verify ----------------------------------------------------------

function write(sourceDir, dir, migrated) {
    mkdirSync(dir, { recursive: true });
    clearGeneratedFiles(dir);

    writeJson(join(dir, "roster.json"), migrated.roster);

    migrated.passthrough.forEach((name) =>
        copyFileSync(join(sourceDir, name), join(dir, name)),
    );
}

// Read the output back rather than trusting the in-memory rows: a serialization bug that drops a
// row or leaves the old key behind must not be reported as a clean migration. Compares against
// `source` (pre-rename) rather than `migrated`, since the migrated rows no longer carry
// `hideFromSleep` to compare against.
function verify(dir, source, migrated) {
    const inputHabits = source.roster.habits;
    const outputHabits = readJson(join(dir, "roster.json")).habits;

    if (outputHabits.length !== migrated.roster.habits.length) {
        die(
            `Verification failed: ${join(dir, "roster.json")} holds ${outputHabits.length} habit row(s), expected ${migrated.roster.habits.length}.`,
        );
    }

    outputHabits.forEach((habit, index) => {
        if (Object.prototype.hasOwnProperty.call(habit, "hideFromSleep")) {
            die(
                `Verification failed: habit ${habit.id} still holds hideFromSleep.`,
            );
        }

        if (typeof habit.isPrivate !== "boolean") {
            die(
                `Verification failed: habit ${habit.id} has a non-boolean isPrivate: ${JSON.stringify(habit.isPrivate)}.`,
            );
        }

        const expected = !!inputHabits[index].hideFromSleep;
        if (habit.isPrivate !== expected) {
            die(
                `Verification failed: habit ${habit.id} isPrivate=${habit.isPrivate}, expected ${expected}.`,
            );
        }
    });
}

function report(migrated, dir) {
    console.log(
        `roster.json  ${migrated.roster.habits.length} habit row(s) renamed`,
    );

    migrated.passthrough.forEach((name) =>
        console.log(`${name}  copied unchanged`),
    );

    console.log(`\nWrote ${migrated.passthrough.length + 1} file(s) to ${dir}`);
}

// --- helpers -------------------------------------------------------------------

function clearGeneratedFiles(dir) {
    if (existsSync(join(dir, "roster.json"))) {
        unlinkSync(join(dir, "roster.json"));
    }
}

function readJson(path) {
    try {
        return JSON.parse(readFileSync(path, "utf8"));
    } catch (error) {
        die(`Could not read JSON from ${path}: ${error.message}`);
    }
}

function writeJson(path, value) {
    writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
}

function usage(message) {
    console.error(`${message}\n`);
    console.error(
        "Usage: node scripts/migrate-is-private.mjs <input-dir> <output-dir> [--force]",
    );
    process.exit(1);
}

function die(message) {
    console.error(message);
    process.exit(1);
}
