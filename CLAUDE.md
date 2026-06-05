# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A pure-QML hello-world app for **reMarkable 1**, launched via **apploader** — specifically the XOVI extension `asivery/rm-appload`. apploader's frontend runtime is QML, loaded inside xochitl's process. No backend.

## Hard rule: never SSH to the device

Under no circumstance may the agent run `ssh`, `scp`, `rsync`, `make deploy`, `make remove`, or any other command that touches the reMarkable. That includes "read-only" probes like `ssh remarkable journalctl …` or `ssh remarkable ls …`. The user runs all device-side commands and pastes back the output. If a step requires device interaction, describe what to run and wait — do not execute it.

This applies even when a `make` target wraps the SSH (e.g. `make deploy`, `make remove`) — those are user-only.

## Commands

- `make build` — compiles `application.qrc` → `build/resources.rcc` via `rcc-qt5`, stages `manifest.json` + `icon.png` alongside it.
- `make deploy` — builds, then `scp`s `build/*` to `/home/root/xovi/exthome/appload/rmhello/` on the device.
- `make remove` — uninstalls from the device.
- `make clean` — removes local `build/`.

Overrides: `make REMARKABLE_HOST=<host>` (default `remarkable`), `make RCC=<path>` (default `rcc-qt5`; rM1 is Qt 5.15, so Qt 5's rcc is required).

There are no tests or linters.

## How apploader loads the app — the non-obvious bits

These are easy to miss and have already cost debug cycles:

1. **QML is not deployed loose.** apploader loads QML from a Qt **binary resource** (`resources.rcc`), not from `.qml` files on disk. `application.qrc` lists files to bundle; `rcc --binary` produces the `.rcc`; only the `.rcc` (plus `manifest.json` + `icon.png`) gets deployed.
2. **`entry` in `manifest.json` must start with `/`.** apploader builds the load URL as `qrc:/<random-nonce><entry>` (raw concatenation, no separator added). Without the leading slash you get `qrc:/NONCEMain.qml` and "No such file." Path is *inside* the rcc.
3. **Root QML conventions.** The root component must declare `signal close` and `function unloading() { ... }`. Emit `close()` from your "Quit" handler to ask apploader to unload the frontend — `Qt.quit()` is a no-op (Qt's process is xochitl).
4. **No hardcoded root size.** apploader sizes the container; use `anchors.fill: parent` on the root and anchor children to it. Hardcoded `width: 1404; height: 1872` will be silently ignored.

## Debugging

apploader runs inside xochitl, so QML errors and `console.log` go to xochitl's stderr → systemd journal on the device:

```
ssh remarkable journalctl -fu xochitl --no-pager
```

Tail this in another terminal while launching the app. apploader prefixes its own messages with `[AppLoad]:` and `[QTFB]:`. `[QTFB]: Unregistered framebuffer controller ID: -1` is harmless for QML-only apps (no qtfb requested).

## Adding new QML files

Append to `<qresource>` in `application.qrc`, then `make deploy`. The `entry` field stays pointing at the root component.

## Device-side details

- App lives at `/home/root/xovi/exthome/appload/rmhello/` after deploy.
- Open apploader on the device by holding the middle button ~3 seconds.
- The repo lives under `~/src/rust/` but is not a Rust project — naming is historical (prior attempts under `remarkable-app/` and `remarkable-helloworld-2/` were Rust; this is now a single `Main.qml`).
