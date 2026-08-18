# reMarkable habit tracker

> Part of the **habit-tracker** monorepo — this is the `apps/remarkable/` client. Run the
> `make` commands below from this directory. The sibling expo client lives in `apps/mobile/`.

A small habit tracker for the **reMarkable 1** e-ink tablet. The reMarkable has no app ecosystem and no official way to run third-party software, but a community modding stack ([XOVI](https://github.com/asivery/xovi) + [rm-appload](https://github.com/asivery/rm-appload)) lets you load custom QML scenes inside the stock UI process. This is one such scene — a calendar grid of habits × days of the month (with arrows to step back and forth through months), persisted to disk, with a twist: it can overwrite the tablet's **suspend image** (the full-screen image shown while the device sleeps) with today's grid, so the habits are the first thing you see when you wake the device. That overwrite is opt-in — you turn it on in **Settings**.

No accounts, no telemetry. It runs fully standalone and offline by default — just a QML scene drawn by the same Qt process that already runs the device's UI. Optionally, point it at a self-hosted server (Settings → **Sync server**) to sync your habits across devices; leave it blank and nothing ever leaves the tablet.

## What it looks like

```
‹  June 2026  ›
   30 days · today is the 5th

                         1  2  3  4  [5] 6  7  8  9  10 …
Read 20 pages           ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ …
Exercise                ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ …
Meditate                ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ …
No screens after 22:00  ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ …
Journal                 ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ …

[ Edit ]                            [ Settings ] [ Quit ]
```

## Features

- **Calendar grid layout.** One row per habit, one column per day of the month, today's column highlighted in inverted ink. Horizontal `‹` / `›` buttons scroll a week at a time when the month doesn't fit; the view opens centered on today. Vertical `↑` / `↓` buttons scroll a page of habits at a time when the list is taller than the screen; the day-of-month header stays fixed while the rows scroll. The grid builds asynchronously on launch — until it's ready a `Loading…` placeholder fills its place and the `‹` / `›` buttons stay disabled.
- **Month navigation.** `‹` / `›` arrows either side of the month header step back and forth through months — unbounded in both directions, so you can review any past month or peek ahead. Any month is fully editable: tap cells to backfill a month you never tracked (its file is written lazily, only once you mark something). Only the current month highlights today and feeds the suspend image; other months show no highlight. A **Today** button appears in the header while you're off the current month and jumps straight back. Switching months shows the same `Loading…` screen as first open while the grid rebuilds; the month arrows stay live so you can keep hopping.
- **Two habit modes.**
    - _Positive_ habits cycle empty → X → O → empty. X = done, O = explicitly not done.
    - _Negative_ habits invert it: every day is implicitly X ("didn't slip up today"), tap to flip to O when you do slip. Future days render muted and the name carries a `(−)` suffix.
- **Private habits.** Per-habit `P` toggles, always available in edit mode, mark a habit private. A private habit never appears on the suspend image, and it also drops out of the main grid — including edit mode — unless **Show private habits** is on in Settings. The private flag syncs across devices like a rename or reorder; the "show private habits on this device" setting stays local and never syncs.
- **Suspend-image overlay (opt-in).** Off by default; enable it on the **Settings** page. While on, the latest habit grid is the suspend image, always excluding private habits. Enabling backs up the original `suspended.png` first; disabling restores it.
- **Settings.** A small settings page (button next to **Quit**) with the suspend-image-writing `On` / `Off` toggle, a **Show private habits** `On` / `Off` toggle, and a **Sync server** address field. Changes are staged and applied on **Done**, which returns to the grid and runs the backup/restore — its progress shows in the grid's status line. **Back** discards staged changes (with a confirmation if you've changed anything).
- **Optional offline-first sync.** Leave the **Sync server** blank and the app is fully local. Enter a server address and it syncs your roster and the month you're viewing with that server — on open, whenever you navigate to a month, a few seconds after edits, and via a **Sync now** button. Conflicts resolve last-write-wins per habit and per day; deletes propagate as tombstones. It's offline-tolerant: when the server is unreachable you keep working and a quiet status line (below the suspend status) counts the debounce down ("Syncing in 3s" → "Syncing…"), tracks the request as it runs ("Connecting…" → "Receiving…"), and then shows the outcome ("Synced to server" / "Sync failed: offline"). The endpoint is unauthenticated, so run it on a trusted network (home LAN / Tailscale / VPN), not the open internet.
- **In-app editing.** Reorder, rename, delete, toggle positive/negative, toggle private, add new habits — all from the device. No editing JSON by SSH.
- **Local persistence.** Habit data lives under a `data/` folder on the device: `roster.json` (the habit list + config) plus one `YYYY-MM.json` per month (that month's entries, one row per marked day); `sync.json` holds sync bookkeeping. App preferences stay in `settings.json`. A single tap rewrites only the current month, not all of history. Saves fail loudly — if `data/` is missing, a dialog says so rather than dropping your entries silently. The app reads exactly one storage format and refuses anything else: a file it can't read is never treated as empty, so nothing gets overwritten by the next tap. Format changes are handled by a script you run on your computer, not by the app (see [Upgrading across a storage-format change](#upgrading-across-a-storage-format-change)).

## Install

You need a **reMarkable 1** (this targets Qt 5.15 specifically — it doesn't run on rM2). Because the device doesn't let you sideload apps natively, install the community stack first:

1. **XOVI** — a function-hooking framework for xochitl. See [`asivery/xovi`](https://github.com/asivery/xovi).
2. **rm-appload** — an XOVI extension that adds an app launcher. See [`asivery/rm-appload`](https://github.com/asivery/rm-appload).

Then build and deploy this app:

```sh
make build      # produces build/resources.rcc + staged icon/manifest
make deploy     # scps build/* to /home/root/xovi/exthome/appload/habit-tracker/
```

(`make deploy` needs `ssh remarkable` to resolve to the tablet — set it up in `~/.ssh/config`, or use `make REMARKABLE_HOST=<host> deploy`. If the tablet's address moves — a phone hotspot re-leases every session — `make find-hotspot-ip` locates it and updates the config; see [below](#finding-the-tablet-after-its-address-changes).)

On the tablet, hold the middle button for ~3 seconds to open apploader, then tap the **reMarkable habit tracker** tile.

## Daily use

- **Tap a cell** to cycle its state.
- **`‹` / `›` beside the month title** move to the previous / next month; **Today** (appears once you're off the current month) jumps back. Editing works in any month, so you can backfill a month you missed.
- **Edit** (bottom-left) enters edit mode. Each row gains `↑` / `↓` (reorder), `×` (delete with confirmation), `−` (toggle polarity), `P` (toggle private — always available), and the name becomes a text input. An empty row at the bottom of the list takes a new habit name; tap `+` or press Enter to add. With **Show private habits** off, a private row disappears from the list entirely (including here in edit mode) — reveal it first if you need to reorder or edit it, since reordering past a hidden row moves it without visibly moving anything.
- **Done** leaves edit mode.
- **Settings** (bottom-right, left of Quit) opens the settings page. Toggle suspend-image writing `On` / `Off`, toggle **Show private habits** `On` / `Off`, and/or type a **Sync server** address (e.g. `http://192.168.1.50:5137`; blank = offline). **Done** applies and returns to the grid — enabling suspend writing backs up your current suspend image and starts drawing the grid there; disabling restores the backup; a non-blank server triggers a sync. **Sync now** forces an immediate sync. **Back** returns without applying.
- **Quit** (bottom-right) unloads the app and restores the normal xochitl UI.

State is saved under `/home/root/xovi/exthome/appload/habit-tracker/data/` — `roster.json` plus a `YYYY-MM.json` per month. First launch seeds the roster from the defaults in `src/js/habits.js`. The `data/` folder must exist (the deploy creates it); if it's missing, saves surface a visible error instead of failing silently. To reset, delete the files and relaunch.

A habit is stored as `{ id, name, polarity, isPrivate, createdAt, editedAt, deletedAt }` and a month as `{ "month": "2026-07", "entries": [ { habitId, date, outcome, editedAt, deletedAt }, … ] }` — the same row shape the sync server speaks, so the only thing translated on the way out is the X/O mark, which the server calls `Success` / `Failure`. Files written in an older shape are refused, not converted: see [Upgrading across a storage-format change](#upgrading-across-a-storage-format-change).

## How it's built

The reMarkable 1 runs **xochitl**, the stock UI, which is itself a Qt 5.15 application. The community modding stack hooks into it:

- **XOVI** loads native extensions into xochitl.
- **rm-appload** is one such extension: it overlays a launcher on top of xochitl and runs each "app" as a QML scene inside xochitl's own Qt process. The frontend runtime it exposes is plain QML — no Wayland, no X, no framebuffer driver, no separate process.

This app is the QML scene. It's packaged as a Qt binary resource (`.rcc`) plus a small manifest and icon; deploy is `scp` of three files into apploader's directory on the device.

| Layer       | What                                                                 |
| ----------- | -------------------------------------------------------------------- |
| Hardware    | reMarkable 1 (e-ink, ARM, Linux-based firmware)                      |
| Stock UI    | xochitl (Qt 5.15 process)                                            |
| Hooking     | XOVI                                                                 |
| App runtime | rm-appload (XOVI extension, QML frontend host)                       |
| This app    | `Main.qml` + a `Theme` singleton, small components, plain JS helpers |
| Build       | `rcc-qt5 --binary` → `resources.rcc`                                 |
| Deploy      | `scp` to `/home/root/xovi/exthome/appload/habit-tracker/`            |

### Interesting bits

**Suspend-image rendering.** xochitl displays `/usr/share/remarkable/suspended.png` while the device sleeps. The app draws today's grid to a hidden Qt `Canvas`, exports it to PNG, and overwrites that file — but only while the opt-in feature is on. Enabling it (Settings → Done) backs the original up to `suspended.png.bak` first; disabling restores the backup. (Uninstalling does not restore it — toggle the feature off first, or copy `suspended.png.bak` back manually.) The result: glance at a sleeping tablet and the habits are right there.

**Cheap re-renders.** Saving a 1404×1872 PNG for every trivial edit is wasteful, so renders are _debounced_ (a 3-second timer restarts after each change while editing) and _deduplicated_ via a content signature persisted alongside the PNG — if nothing visible changed, nothing is written. A small status line on the grid ("Saving suspend image in 3s…" → "Suspend image saved", and the backup/restore phases) makes the pipeline visible. On quit, the latest state is flushed synchronously so the suspend image never lags a tap behind.

**Pure QML + plain JS.** State lives in JSON-backed QML stores sharing a `JsonStore.qml` base for the load/debounced-save plumbing. `HabitsStore.qml` is a facade that splits persistence across two files — a `roster.json` (identity + config, plus tombstones for deleted habits) and a per-month file holding that month's entries as flat `(habitId, date)` rows — so a single toggle rewrites only the current month, not all history, and corruption is isolated to one month. The rows match the backend's shape exactly while the month partitioning keeps launch and per-tap cost bounded to one month, which matters on a 1 GHz device. Components forward signals upward; only the store mutates state. Updates are immutable (array spread, `Object.assign`) — the V4 engine handles re-bindings from there. Optional sync is a separate `SyncStore.qml` (the network engine + a `sync.json` sidecar) over a pure-JS `Sync.js` translation layer; the merge itself runs server-side, so the client just sends its state and accepts the authoritative result.

**Platform constraints shape the code.**

- _ES2016 / Qt 5.15 V4 engine._ No `async`/`await`, no optional chaining, no object spread. The codebase targets ES2016 deliberately and the project's `CLAUDE.md` captures the rule for future contributors (human or AI).
- _Grayscale e-ink, 16 levels._ Color renders as washed-out mid-grays; white is invisible against the paper-white background. The UI is strict black-on-white with weight, borders, and inversion as the only emphasis tools.
- _Portrait display, landscape layout._ `Main.qml` wraps the scene in an `Item { rotation: 90 }` with `width` and `height` swapped, so the rest of the QML reads as a normal landscape layout.

## Building from source

You need Qt 5's `rcc` (Qt 6's works too for `--binary`, but the device runtime is Qt 5.15 — stay on 5 to avoid surprises):

- Arch/Manjaro: `pacman -S qt5-base` (binary is `rcc-qt5`)
- Debian/Ubuntu: `apt install qtbase5-dev-tools`
- macOS: `brew install qt@5`

Override the binary with `make RCC=<path>` if it isn't on `$PATH` as `rcc-qt5`.

```sh
make build      # produces build/resources.rcc + staged icon/manifest
make test       # runs the test suite (see below)
make deploy     # scps build/* to the device
make remove     # uninstalls from the device
make backup     # pulls the device's data/ into a timestamped .backup/ dir
make find-hotspot-ip  # relocates the tablet on the current network (see below)
make clean      # nukes local build/
```

### Tests

```sh
make test                  # Qt Quick Test over tests/tst_*.qml
make suspend-writer-test   # smoke-tests the off-device renderer against tests/fixtures/
```

`make test` needs `qmltestrunner-qt5` (Arch/Manjaro: `pacman -S qt5-declarative`; Debian/Ubuntu:
`apt install qtdeclarative5-dev-tools`), and runs headless against the sources in `src/` — no build
step first. It covers the plain-JS modules (the sync wire format, the outcome cycles, the date and
scroll helpers, the suspend-image signature) and the QML stores (debounced saving, the refusal of
unreadable files, month navigation, and the sync engine's terminal paths). Override the runner with
`make QMLTESTRUNNER=<path>`.

`make suspend-writer-test` additionally needs a host C++ toolchain and Qt 5 dev headers, since it
builds `tools/suspend-writer` first.

### Finding the tablet after its address changes

A phone hotspot hands out a new lease every session, so the `remarkable-hotspot` entry in
`~/.ssh/config` goes stale. `make find-hotspot-ip` scans the network you are on, identifies the
tablet by its **SSH host key** — the key survives lease changes, so a fingerprint already in
`known_hosts` under one of your `remarkable` hosts is proof rather than a guess — and rewrites that
entry's `Hostname`, keeping the old file as `~/.ssh/config.bak`.

```sh
make find-hotspot-ip                             # repoint the remarkable-hotspot entry
make find-hotspot-ip HOTSPOT_HOST=remarkable     # repoint a different ssh-config host
pnpm remarkable:find-hotspot-ip                  # same, from the monorepo root
tools/find-remarkable-hotspot-ip.sh <ssh-host>   # same, without make
```

Requires `nmap`, and runs it under `sudo` (so expect a password prompt): host discovery needs root
to use ARP, and an unprivileged `nmap -sn` degrades to a TCP connect sweep that never sees the
tablet, which answers on no port but SSH. It only ever acts on an unambiguous match: no match, or
more than one, and it prints what it saw and changes nothing. Two matches means `known_hosts` still
vouches for an address that has since changed hands — clear that entry with `ssh-keygen -R <addr>`.
The first connection on a new address files the key under it too, so the next hotspot is recognised
without any state of its own.

## Upgrading across a storage-format change

The app only ever reads one storage format — it carries no migration code, by design
([ADR 0006](docs/adr/0006-external-one-shot-migrations.md)). When a release changes the format, it
ships a one-shot script in `scripts/` that you run on your computer against a backup of the device's
data.

**Close the app on the device first** and leave it closed until the last step. An old build on new
data is as broken as a new build on old data, and a running app flushes its in-memory state on quit —
straight over whatever you just pushed.

```sh
make backup                                    # pulls data/ into .backup/<timestamp>/
node scripts/<the-migration-script>.mjs .backup/<timestamp> /tmp/migrated
```

The script writes to a fresh directory and never touches the device or your backup. It prints what it
did — habits in/out, entries per month in/out, anything it dropped — and re-reads its own output to
confirm the counts before reporting success. Check those numbers look like your data, then push it
back and deploy:

```sh
rsync -avz /tmp/migrated/ remarkable:/home/root/xovi/exthome/appload/habit-tracker/data/
make deploy
```

Then reopen the app. If you get the order wrong, nothing is lost: the new build refuses files it
can't read, blocks saves and sync, and tells you which file is the problem — fix it and reopen.

**Current migration: private habits.** The habit-private-flag change (ADR 0008) ships
`scripts/migrate-is-private.mjs`, which renames each roster row's `hideFromSleep` to `isPrivate` and
leaves the month files untouched — run it as `<the-migration-script>.mjs` above. This migration also
**requires rebuilding and redeploying `tools/suspend-writer`** (`make suspend-writer-device` then
`make suspend-writer-deploy`) before you reopen the app: an un-rebuilt suspend-writer binary reads the
migrated roster's absent `hideFromSleep` as false and would draw private habits on the lock screen. Do
this before the final `make deploy` above, not after.

## Repo layout

```
.
├── application.qrc      # files bundled into the .rcc
├── manifest.json        # apploader manifest (id, display name, entry path)
├── icon.png             # launcher icon
├── Makefile             # build / deploy / remove / clean
├── src/
│   ├── Main.qml         # entry; root declares signal close + unloading()
│   ├── Theme.qml        # singleton: sizes, fonts, colors
│   ├── JsonStore.qml    # base: deferred load + debounced save for the stores
│   ├── HabitsStore.qml  # facade: roster + per-month entry files, sole source of mutation
│   ├── SettingsStore.qml# JSON-backed app settings (suspend-image on/off, sync server URL)
│   ├── SyncStore.qml    # offline-first sync engine + sidecar (last-synced time)
│   ├── components/      # reusable QML pieces (AppButton, HabitsGrid, SuspendCanvas, SettingsPage, …)
│   └── js/              # plain JS modules (date helpers, scroll math, suspend-image draw, sync translation)
├── scripts/             # one-shot storage migrations, run on your computer (see ADR 0006)
├── docs/adr/            # the decisions behind the storage layout, suspend image and migrations
└── build/               # rcc output + deploy staging (gitignored)
```

## Development notes

apploader runs inside xochitl, so QML parse errors and `console.log()` output land in xochitl's stderr → systemd journal:

```sh
ssh remarkable journalctl -fu xochitl --no-pager
```

apploader prefixes its messages with `[AppLoad]:` / `[QTFB]:`. `[QTFB]: Unregistered framebuffer controller ID: -1` is harmless for QML-only apps.

### Platform gotchas worth knowing before editing

1. **QML files must live inside the `.rcc`.** Loose `.qml` files on the device aren't found. Add new files to `<qresource>` in `application.qrc` (and to the relevant `qmldir`) and rebuild.
2. **`entry` in `manifest.json` must start with `/`.** apploader concatenates the entry onto `qrc:/<nonce>` with no separator; without the leading slash you get `qrc:/NONCEMain.qml` and "No such file."
3. **Root QML conventions.** The root must declare `signal close` and `function unloading() { ... }`. Emit `close()` from the Quit handler — `Qt.quit()` is a no-op (the Qt process is xochitl, you don't own it).
4. **No hardcoded root size.** apploader sizes the container; use `anchors.fill: parent`. Hardcoded `width: 1404; height: 1872` is silently ignored.
