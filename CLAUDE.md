# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Maintaining this file

Update CLAUDE.md as you learn the user's preferences for code style, workflow, or project conventions that should persist across sessions. Keep it lean: max 200 lines, every line must earn its place. Prefer tightening or replacing existing sections over appending new ones, and remove guidance that becomes obsolete.

## What this is

A pure-QML **habit tracker** for **reMarkable 1**, launched via **apploader** — specifically the XOVI extension `asivery/rm-appload`. apploader's frontend runtime is QML, loaded inside xochitl's process. No backend. Renders a landscape grid of habits × days-of-the-current-month with the current day highlighted.

## Hard rule: never SSH to the device

Under no circumstance may the agent run `ssh`, `scp`, `rsync`, `make deploy`, `make remove`, or any other command that touches the reMarkable. That includes "read-only" probes like `ssh remarkable journalctl …` or `ssh remarkable ls …`. The user runs all device-side commands and pastes back the output. If a step requires device interaction, describe what to run and wait — do not execute it.

This applies even when a `make` target wraps the SSH (e.g. `make deploy`, `make remove`) — those are user-only.

## Commands

- `make build` — compiles `application.qrc` → `build/resources.rcc` via `rcc-qt5`, stages `manifest.json` + `icon.png` alongside it.
- `make deploy` — builds, then `scp`s `build/*` to `/home/root/xovi/exthome/appload/habit-tracker/` on the device.
- `make remove` — uninstalls from the device.
- `make clean` — removes local `build/`.

Overrides: `make REMARKABLE_HOST=<host>` (default `remarkable`), `make RCC=<path>` (default `rcc-qt5`; rM1 is Qt 5.15, so Qt 5's rcc is required).

There are no tests or linters.

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

## Adding new QML files

Append to `<qresource>` in `application.qrc` **and** register the type in the directory's `qmldir`. The `entry` field stays pointing at the root component.

## QML import namespaces

`Main.qml` does `import "." as App` and `import "components" as App`, so both `Theme` (in `src/`) and components (in `src/components/`) are reached via the `App.` prefix. **Files inside `src/components/` use `import ".." as App` — that prefix points at `src/`, NOT at `src/components/`.** From a component file, reference sibling components bare (`AppButton`, not `App.AppButton`); use `App.Theme` for the singleton. Getting this wrong fails at load with `Type App.X unavailable / No such file or directory` pointing at `src/X.qml`.

## Keep README.md current

When functionality changes (new features, removed features, changed UX, new commands), update `README.md` in the same change. The README is the user-facing description of what the app does and how to use it — it must not drift from the actual behavior.

## Device-side details

- App lives at `/home/root/xovi/exthome/appload/habit-tracker/` after deploy.
- Open apploader on the device by holding the middle button ~3 seconds.
- The repo lives under `~/src/rust/` but is not a Rust project — naming is historical (prior attempts under `remarkable-app/` and `remarkable-helloworld-2/` were Rust). App code lives under `src/`: `Main.qml` + `Theme.qml` singleton at the top, reusable QML in `src/components/`, plain JS in `src/js/`. Each QML directory has a `qmldir`.

## Maintaining this file

As Claude learns your code style, QML patterns, and working preferences, update this document to capture non-obvious patterns or rules. Keep it lean (under 200 lines) — focus on:

- Gotchas that have burned cycles
- Style or architecture choices specific to this project
- Constraints that affect design decisions
- Anything that would surprise a future reader

This stays checked in; future sessions will read it and adjust approach accordingly.
