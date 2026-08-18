# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Maintaining this file

Update CLAUDE.md as you learn the user's preferences for code style, workflow, or project conventions that should persist across sessions. Keep it lean: max 200 lines, every line must earn its place. Prefer tightening or replacing existing sections over appending new ones, and remove guidance that becomes obsolete.

## What this is

A pure-QML **habit tracker** for **reMarkable 1**, launched via **apploader** — specifically the XOVI extension `asivery/rm-appload`. apploader's frontend runtime is QML, loaded inside xochitl's process. The shipped app is QML + plain JS with no native component; the one C++ thing in the tree, `tools/suspend-writer/`, is a dev tool that hosts the app's own JS modules outside QML and is never part of a build or deploy. Renders a landscape grid of habits × days-of-the-current-month with the current day highlighted.

This is the `apps/remarkable/` app in the habit-tracker monorepo (pnpm workspaces). It runs fully standalone by default and _optionally_ syncs to the monorepo's backend (`apps/backend/`, ASP.NET Core + EF Core + PostgreSQL) when the user sets a Server URL. See the monorepo-root `CLAUDE.md` for cross-app conventions.

**The sibling expo client (`apps/mobile/`) is a peer, not a reference.** Never read it to decide this app's storage shape, domain model, or sync behaviour. Both clients now spell the domain the backend's way, but each aligned to the backend independently, and they still persist differently: this app writes per-month JSON files behind QML stores and keeps `"x"`/`"o"` outcomes it respells at the sync edge, while mobile writes SQLite tables storing the backend's spellings verbatim. Their resemblance is a _result_ of both following the backend, not a reason to copy — neither is a spec for the other. Merge and conflict resolution belong to the backend: this client sends its state and accepts the authoritative result (see `src/js/Sync.js`). Where a client and the backend disagree, the backend wins.

**Domain docs.** Three glossaries: this app's `CONTEXT.md` (device-only terms — suspend image, Private / Show private habits, settings, edit mode, Server URL), the monorepo-root [`../../CONTEXT.md`](../../CONTEXT.md) (the shared Habit / Entry / X-O / polarity vocabulary every client speaks), and the [backend glossary](../backend/CONTEXT.md) (Outcome, Position, Private, Sync, Edit-time, Tombstone — the sync contract). This app's `docs/adr/` records seven deliberate decisions you must not silently undo — `0001` opt-in suspend-image writing (amended by `0008`), `0002` month-partitioned storage, `0004` viewing other months, `0005` backend-shaped entry rows (which amends `0002`), `0006` external one-shot migrations (which supersedes `0005`'s read-tolerance), `0007` the `editedAt` timestamp name (which supersedes `0005`'s naming), `0008` private habits (a synced flag replacing device-local suspend visibility; supersedes `0005`/`0007`'s device-local-field consequence). Every ADR number cited in code resolves to a file here — if you add a citation, add the ADR. Read the glossaries before changing domain behaviour, and keep them current when it changes.

## Hard rule: no in-app data migrations

The app speaks exactly **one** on-disk shape. Never add read-time tolerance for an old format, a
conversion-on-load, or a version-bump branch — not even "just for one release". When a storage format
changes, ship a one-shot Node script in `scripts/` that the user runs off-device against a `make
backup` copy, and delete it once their device is migrated (git history keeps it).

What makes that safe is refusal, not tolerance: a file the app can't read is never folded in as
empty. `JsonStore.isUnwritable` blocks writes to it, `HabitsStore.hasUnreadableData` blocks sync, and
a modal names the file. A forgotten migration costs a dialog, never data. See
[`docs/adr/0006-external-one-shot-migrations.md`](docs/adr/0006-external-one-shot-migrations.md).

## Hard rule: never SSH to the device

Under no circumstance may the agent run `ssh`, `scp`, `rsync`, `make deploy`, `make remove`, or any other command that touches the reMarkable. That includes "read-only" probes like `ssh remarkable journalctl …` or `ssh remarkable ls …`. The user runs all device-side commands and pastes back the output. If a step requires device interaction, describe what to run and wait — do not execute it.

This applies even when a `make` target wraps the SSH. The full user-only set is `make deploy`, `make remove`, **`make backup`** (rsyncs the device's `data/` back into `.backup/<timestamp>/`), **`make suspend-writer-deploy`** and **`make find-hotspot-ip`** (nmap-scans the network and reads the device's SSH host key) — plus the `pnpm remarkable:deploy` / `remarkable:remove` / `remarkable:backup` / `remarkable:find-hotspot-ip` delegators (the suspend-writer targets have no delegator; they are `make`-only). Assume any target not listed as local below touches the device.

## Commands

Local (agent-runnable):

- `make build` — stages `src/` into `build/src/` (see the `.pragma library` injection below), then compiles `application.qrc` → `build/resources.rcc` via `rcc-qt5` and stages `manifest.json` + `icon.png` alongside it.
- `make lint` — runs `qmllint-qt5` over every `src/**/*.qml`. Best-effort to a fault: the recipe is `command -v … && $(QMLLINT) … || echo "not installed; skipping"`, so **a missing linter _and_ a failing lint both print the skip notice and exit 0**. `make lint` can never fail the build — read its output, don't trust its exit code.
- `make test` — Qt Quick Test over `tests/tst_*.qml`, headless on host Qt 5.15 (the device's Qt), against live `src/`. Covers the JS modules and the stores. **Unlike `lint`, this target fails properly** — never give it the `|| echo skipping` treatment. See the testing section below.
- `make suspend-writer-test` — builds the host suspend-writer and smoke-tests it against `tests/fixtures/`. Separate from `make test` because it needs a C++ build.
- `make clean` — removes local `build/`.
- `make suspend-writer-host` / `suspend-writer-clean` — host build of the off-device renderer against host Qt5, for previewing a render as a PNG; no device or SDK needed (see below).

Device-touching (**user-only**, never run these): `make deploy`, `make remove`, `make backup`, `make suspend-writer-device` (needs the SDK), `make suspend-writer-deploy`, `make find-hotspot-ip` (`tools/find-remarkable-hotspot-ip.sh` — nmap-scans the network and reads the device's SSH host key to relocate it after a hotspot lease change, then rewrites `~/.ssh/config`).

Overrides: `make REMARKABLE_HOST=<host>` (default `remarkable`), `make HOTSPOT_HOST=<host>` (default `remarkable-hotspot`, the alias `find-hotspot-ip` repoints), `make RCC=<path>` (default `rcc-qt5`; rM1 is Qt 5.15, so Qt 5's rcc is required), `make QMLLINT=<path>`, `make QML_IMPORT_PATH=<dir>` (default `/usr/lib/qt/qml`, passed to the linter as `-I`).

`make test` and `make lint` are the checkers. Only `make test` can fail the build.

## Tests

`make test` runs **Qt Quick Test** (`qmltestrunner-qt5`) over `tests/tst_*.qml` — one runner for both
the plain-JS modules and the QML stores, because it resolves the `.import` chains natively and runs
the same V4 engine as the device. Tests import live `src/` (the `.pragma library` injection is a
build-step concern), so there is nothing to build first. New behaviour in `src/js/` or a store lands
with a test.

- **Layout.** `tests/tst_<subject>.qml` per module or store, plus two shared helpers: `Fixtures.js`
  (`fakeModel` — the duck-typed `{count, get(i)}` stand-in `HabitsModel.js` actually consumes, and
  the row builders) and `TestPaths.js` (paths under `tests/tmp/`). Test code follows the same style
  rules as the app: ES2016, verbose names, comments only for the non-obvious _why_.
- **Writes are async.** `Storage.writeFile` issues an async `PUT`, so a readback must wait —
  `tryVerify` on the **exact expected body**, not merely that the file exists. Waiting on existence
  lets a store load the previous test's file; that bug cost a debug cycle already.
- **Stores are built per test**, via a `Component` + `createObject(testCase, {...})`, so each one
  loads against a path the test chose and the deferred `Qt.callLater(reload)` does not first fire
  against the device path. `tryVerify(() => store.isLoaded)` after creating.
- **XHR cannot `mkdir`** (the same limitation that makes the deploy create `data/`), so the
  `HabitsStore` scratch dirs come from the `make test` recipe: `tests/tmp/habits` is shared —
  each test takes its own _month_ and rewrites `roster.json` — and `tests/tmp/habits-seed` is left
  empty for the first-run seeding test. A `cleanup()` marks the outgoing store's files unwritable so
  a late debounce cannot write into the next test.
- **What is pinned** is the behaviour the ADRs exist to protect: refuse-don't-fold and
  never-overwrite-a-refused-file (0006), `loadMonth` flushing to the old file _before_ re-pointing
  and the stale-`requestMonthKey` discard (0004), the alive-only model with tombstones (0002/0005),
  and the `x`/`o` ↔ `Success`/`Failure` respelling (0005). Sync's terminal paths are reached by
  calling `_handleDone` with a plain `{status, responseText}` stand-in — no server needed.
- **Not covered:** the QML views (`Main.qml` instantiates the stores against device paths), the real
  XHR-over-HTTP round trip (`_send` has no injection seam), and `SuspendDraw.draw` — that one is
  covered by `make suspend-writer-test` instead.

## suspend-writer: a second consumer of the JS renderer — tell the user when you break it

`tools/suspend-writer/` is a standalone C++ tool that draws the suspend image **off-device**: it
hosts `src/js/SuspendDraw.js` and its `.import` chain in a `QJSEngine` behind a QPainter-backed
Canvas2D shim, so the same renderer runs without a QML runtime. It has its own
[README](tools/suspend-writer/README.md) and its own build scripts (host = Qt5 no SDK; device =
ARM/Qt6, needs the SDK unpacked at `tools/suspend-writer/sdk/`). `suspend-writer-deploy` copies the
`SW_JS_MODULES` list to the device _loose_, next to the ARM binary, because the app itself only
ships those modules inside `resources.rcc`.

So **`src/js` has a consumer outside the app.** Two kinds of change break it, and **neither fails `make build` or `make lint`**:

- **A storage-shape change** (roster rows, month entry rows). `main.cpp` joins the month's entry rows onto the roster by habit id before handing them to `HabitsModel.toSuspendHabits` — that join is the only copy of the on-disk shape outside `src/`, and it also guards the shape, so stale data exits 2 instead of drawing a wrong grid. Keep the projection _in the JS modules_: reimplementing any of it in `main.cpp` is what let the tool silently drift out of date once already.
- **A new `.import`** in `SuspendDraw.js`, `HabitsModel.js`, `Entries.js` or `Polarity.js`. Each module is loaded explicitly in `main.cpp` with its export list and deployed via `SW_JS_MODULES` in the Makefile; a missing one is a runtime `ReferenceError`, not a build error.

**Call this out in your summary whenever a change touches either** — the tool is built and deployed separately, so it stays broken on the device until the user rebuilds it. Verify with `make suspend-writer-test`, which builds the host binary and runs `tests/suspend-writer-smoke.sh` against `tests/fixtures/`: a valid roster+month renders (and differs from an empty-roster baseline, proving the grid drew), the render is deterministic, and pre-migration data exits 2 rather than drawing a blank grid. There is no golden image — font rendering is not portable between machines — so for a change meant to leave the output alone, also render against migrated `.backup/` data and diff it against a pre-change render.

## How apploader loads the app — the non-obvious bits

These are easy to miss and have already cost debug cycles:

1. **QML is not deployed loose.** apploader loads QML from a Qt **binary resource** (`resources.rcc`), not from `.qml` files on disk. `application.qrc` lists files to bundle; `rcc --binary` produces the `.rcc`; only the `.rcc` (plus `manifest.json` + `icon.png`) gets deployed.
2. **`entry` in `manifest.json` must start with `/`.** apploader builds the load URL as `qrc:/<random-nonce><entry>` (raw concatenation, no separator added). Without the leading slash you get `qrc:/NONCEMain.qml` and "No such file." Path is _inside_ the rcc.
3. **Root QML conventions.** The root component must declare `signal close` and `function unloading() { ... }`. Emit `close()` from your "Quit" handler to ask apploader to unload the frontend — `Qt.quit()` is a no-op (Qt's process is xochitl).
4. **No hardcoded root size.** apploader sizes the container; use `anchors.fill: parent` on the root and anchor children to it. Hardcoded `width: 1404; height: 1872` will be silently ignored.

## Display constraints (grayscale e-ink)

The rM1 screen is 16-level grayscale e-ink. Color is not just stylistic — it determines whether content is visible at all:

- **Never use white or near-white** (`"white"`, `"#fff"`, very light grays) for foreground content (text, icons, borders). It vanishes against the paper-white background. Default background is white; default foreground is black.
- **Avoid colored fills/strokes** (red, blue, green, etc.). They render as a mid-gray that washes out and loses contrast. Use black, dark gray, or leave unfilled.
- For emphasis, prefer weight/size/borders/inversion (black-on-white vs white-on-black blocks) over color.
- When inverting (light text on dark fill), the fill must be dark enough — black or near-black — for the light text to read.

## Debugging

apploader runs inside xochitl, so QML errors and `console.log` go to xochitl's stderr → systemd journal on the device:

```
ssh remarkable journalctl -fu xochitl --no-pager
```

Tail this in another terminal while launching the app. apploader prefixes its own messages with `[AppLoad]:` and `[QTFB]:`. `[QTFB]: Unregistered framebuffer controller ID: -1` is harmless for QML-only apps (no qtfb requested).

## Adding new QML and JS files

Append to `<qresource>` in `application.qrc` **and** register the type in the directory's `qmldir`. The `entry` field stays pointing at the root component. `make build` fails on a file listed in the `.qrc` that doesn't exist, but silently omits an existing file you forgot to list — it then fails at load on the device.

For `src/js/*.js`: **never write `.pragma library` into the source.** The `inject-pragma` build step prepends it to every JS file when staging `build/src/`, so sources omit it and stay parseable by prettier and the editor. `.import "Other.js" as Other` _does_ belong in the source (JS→JS deps can't use QML imports once the pragma makes the file a shared library); prettier can't parse those files, which is why a few already fail `--check`.

## QML import namespaces

`Main.qml` does `import "." as App` and `import "components" as App`, so both `Theme` (in `src/`) and components (in `src/components/`) are reached via the `App.` prefix. **Files inside `src/components/` use `import ".." as App` — that prefix points at `src/`, NOT at `src/components/`.** From a component file, reference sibling components bare (`AppButton`, not `App.AppButton`); use `App.Theme` for the singleton. Getting this wrong fails at load with `Type App.X unavailable / No such file or directory` pointing at `src/X.qml`.

## Stores and navigation

- **Persisted state uses `JsonStore.qml`.** That base owns the deferred initial load, the 200 ms debounced save, the `saved`/`saveFailed` signals, and `flushPendingSave`. A store sets `filePath` and assigns two function-property hooks: `serialize` (→ the value to write) and `applyLoaded(data)` (← fold a just-read value, handling the `Storage` MISSING sentinel and rejecting anything it can't read). Don't re-implement file I/O or the save timer per store. `SettingsStore` extends it directly; `HabitsStore` instead **composes two `JsonStore` children behind a facade** — a roster store (`data/roster.json`: alive habits as id + name + polarity + private flag + createdAt + editedAt, followed by their tombstones) and a month store (`data/YYYY-MM.json`: the viewed month's entries as flat `{ habitId, date, outcome, editedAt, deletedAt }` rows — the wire format's month payload but for `outcome`, which `Sync.js` maps to the backend's `Success`/`Failure`). The ListModel is the single in-memory source of truth and each child serializes a _projection_ of it (`HabitsModel.toRoster` / `toMonthEntryRows`); config edits schedule the roster save, entry toggles the month save. Load is parallel, folded by id once both resolve. **Three invariants:** the model holds _alive_ habits only (a delete moves the row to `habitTombstones`, so index-based APIs never drift from what the grid renders); each habit's entry rows live indexed by date on its own model row (`entriesByDate`) because that is the only per-habit reactive vehicle QML gives us (the binding-count measurement is in ADR 0005); and a file that isn't the shape this version writes is _refused_ rather than read as empty (`_reject` sets `JsonStore.isUnwritable`, which blocks saves to it), because folding it in as empty would let the next toggle overwrite real data. See [`docs/adr/0002-month-partitioned-habit-storage.md`](docs/adr/0002-month-partitioned-habit-storage.md), [`docs/adr/0005-backend-shaped-entry-rows.md`](docs/adr/0005-backend-shaped-entry-rows.md) and [`docs/adr/0006-external-one-shot-migrations.md`](docs/adr/0006-external-one-shot-migrations.md). These `src/` stores resolve as `App.<Name>` without a `src/qmldir` entry (file-based resolution).
- **Saves are loud, never silent — and a write only reports once it has landed.** A local-file write tells you nothing by itself: Qt answers status 0 whether the bytes were written or the directory doesn't exist, and it answers _asynchronously_. So `Storage.writeFile` / `writeJson` / `writeBinary` each take an `onDone(error)` and establish success by **reading the file back** at DONE. Never report a write from its own `onreadystatechange` by throwing — that throws into the event loop where no caller can catch it, which is exactly how a missing `data/` dir used to report a clean save. `JsonStore._doSave` routes `onDone` into `saved` / `saveFailed`, so `saved` means on disk; `HabitsStore` exposes the failure as `saveError` and `Main` shows a dismissable modal, and the session keeps running in memory. `writeJson` still _throws_ for a value that stringifies to nothing — that's a caller bug, not a storage failure. The `data/` dir must exist (QML/XHR can't `mkdir`; the deploy creates it).
- **Anything gated on a write succeeding must wait for the callback.** `SuspendRender.copyFile` and `SuspendCanvas.backup`/`restore` answer through `onDone(ok)`, and `Main.applySuspendSetting` only turns the setting on inside that callback: enabling suspend-image writing on a backup that silently failed overwrites a stock image nothing can restore (ADR 0001).
- **Full-screen views switch via `landscape.currentView`** (`"grid"` | `"settings"`) in `Main.qml` — each view is an `Item` gated by `visible`. No StackView/router; add a view as a sibling `Item` plus a `currentView` value. Pages forward signals up to `Main`, which owns the stores and orchestrates side effects (e.g. suspend-image backup/restore on the settings commit).
- **Month navigation re-points the one model; "now" stays pinned.** The header `‹`/`›` move `landscape.viewYear`/`viewMonth` (distinct from the real `today`); `HabitsStore.loadMonth` **flushes the pending month save to the old file _before_ re-pointing** `_month.filePath` and re-reading — reversing that order writes an edit into the wrong month. `monthKey`, and thus the month file path and `SyncStore.monthKey`, derive from the viewed month. Two invariants must not regress (see [`docs/adr/0004-view-other-months.md`](docs/adr/0004-view-other-months.md)): **suspend renders only when `landscape.isCurrentMonth`** (every trigger in `Main` is guarded, and a debounced render is cancelled via `suspendCanvas.cancelPending()` on leaving the current month), and **sync discards a response whose captured `requestMonthKey` no longer matches** the viewed month. A switch tears the grid Loader down first (`beginLoadMonth` drops `_month.isLoaded`) so the `Loading…` screen paints that frame, then **defers the blocking read** (`Qt.callLater(landscape._loadViewedMonth)`, mirroring the deferred first-open read) before the Loader async-rebuilds — doing the read synchronously on the tap delays the loading screen until it finishes (ADR 0004). The deferred step also runs `syncNow`/suspend after `isLoaded` is restored, so their gates pass. The month arrows gate on the sticky `habitsStore.hasLoadedOnce` (first load ever), the scroll buttons on `landscape.loading` (per-rebuild), so month-hopping stays live and coalesces (`Qt.callLater` dedups to the final on-screen month). The today-highlight and future-day muting are two separate grid signals — `highlightDay` (0 = none) and `lastNonFutureDay` — because a past month has no highlight but no future days either. Navigation is unbounded and empty months write no file until a box is toggled (the month `applyLoaded` folds empty entries without seeding+saving), so the app still never enumerates `data/`.

## Code style

- **Container components forward signals; they don't reach into stores.** Components expose signals up to the page that owns the store, which wires them to store methods. Keeps components reusable and dependencies one-way.
- **Extract on duplication, not speculation.** Collapse near-identical blocks into a component or shared JS helper. Before writing a new helper, grep for one with the same shape — duplication crosses file types (JS↔QML) and consumer boundaries (store↔component).
- **Target ES2016 / Qt 5.15 V4 engine.** Use `let`/`const` (never `var`), arrow functions, template literals, destructuring, array spread (`[...arr]`), default params, `Array.prototype.includes`, native `String.prototype.trim()`. NOT available: `async`/`await`, object spread (`{...obj}` — use `Object.assign({}, a, b)`), optional chaining (`?.`), nullish coalescing (`??`).
- **Functional style.** Prefer pure functions, immutable updates (spread / `Object.assign` / `slice` over in-place mutation), `.map`/`.filter`/`.reduce` over imperative loops, `const` arrows for small helpers. In `.pragma library` files, top-level exports use `function` declarations; internal helpers use `const` arrows.
- **Verbose naming.** Prefer descriptive names for variables, properties, persisted JSON fields, and wire/domain shapes. Avoid single-letter or cryptic names except for tiny local indices; storage objects must use names like `outcome` and `editedAt`, not shorthand.
- **Flat code, max 2 levels of nesting.** No `if` / `try` / loop nested 3+ deep. Use early returns, guard clauses, extracted helpers, or logical operators (`||`, `&&`, ternaries) to flatten. If a block would reach 3 levels, extract a function.
- **In QML bindings, prefer expressions over imperative blocks.** A `property` or signal handler that's just an `if`-ladder returning values should collapse to a single expression — a small extracted `readonly property` carrying the condition, or a ternary where one reads cleanly.
- **Avoid ternaries unless they're the more elegant option.** A single, short ternary that reads at a glance is fine; reach for guard clauses / early returns instead when the condition is nested, chained, or the branches are non-trivial. Never stack ternaries. In plain `function` bodies prefer early returns over a returned ternary.
- **Blank lines within functions separate logical phases.** Add a blank line after guard clauses / early returns, between setup and computation, or before a return statement. Groups related statements visually.
- **Make the code speak for itself; comment sparingly.** Default to no comments — prefer descriptive names, extracted helpers, and clear structure over prose that explains the code. Only add a comment when the WHY is non-obvious (hidden constraint, subtle invariant, workaround for a specific bug, surprising behavior). Never explain WHAT — well-named identifiers do that. If a comment feels necessary to explain WHAT code does, rename or restructure instead. If removing the comment wouldn't confuse a future reader, don't write it.
- **Self-update on style refactor.** When a refactor revises a code-style preference here (banning a pattern, adopting a new helper convention, moving the JS target), update this section in the same change so future sessions inherit the rule.

## Keep README.md current

When functionality changes (new features, removed features, changed UX, new commands), update `README.md` in the same change. The README is the user-facing description of what the app does and how to use it — it must not drift from the actual behavior.

## Device-side details

- App lives at `/home/root/xovi/exthome/appload/habit-tracker/` after deploy.
- Open apploader on the device by holding the middle button ~3 seconds.
- This app lives at `apps/remarkable/` in the monorepo; its directory name (and the repo's `~/src/...` path) is historical and not a Rust project despite prior Rust attempts. App code lives under `src/`: `Main.qml` + `Theme.qml` singleton at the top, reusable QML in `src/components/`, plain JS in `src/js/`. Each QML directory has a `qmldir`. Run all `make` commands from `apps/remarkable/` (paths in the Makefile and `application.qrc` are app-relative).
