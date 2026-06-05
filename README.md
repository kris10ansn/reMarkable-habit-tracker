# rmhello

A pure-QML daily-goal-tracker prototype for reMarkable 1, launched via apploader (XOVI `rm-appload`). Renders a landscape grid of goals × days-of-the-month with the current day highlighted. The package name is historical — it started as a hello-world.

## Layout

```
.
├── application.qrc   # qrc manifest — lists files to bundle into the .rcc
├── ui/Main.qml       # the app — root component with signal close + unloading()
├── manifest.json     # apploader manifest
├── icon.png          # launcher icon
├── Makefile          # build, deploy, remove, clean
└── build/            # rcc output + deploy staging (gitignored)
```

apploader expects QML packaged into a Qt **binary resource** (`resources.rcc`) — loose `.qml` files won't be found. The Makefile invokes `rcc-qt5 --binary` to produce `build/resources.rcc`, then deploys `resources.rcc + manifest.json + icon.png` to the device.

## Requirements (host)

- Qt 5's `rcc` (`rcc-qt5` on Arch/Manjaro). Override with `make RCC=<path>` if needed.
- `ssh remarkable` (override with `make REMARKABLE_HOST=<host>`).

## Build & deploy

```
make build      # produces build/resources.rcc + staged icon/manifest
make deploy     # rsyncs build/* to /home/root/xovi/exthome/appload/rmhello/
make remove     # uninstalls
make clean      # local cleanup
```

On the device, open apploader (hold middle button ~3s) — the rmhello tile should appear. Tap to launch; tap "Quit" (bottom-right) to close.

## Debugging

Tail xochitl's stderr while testing:

```
ssh remarkable journalctl -fu xochitl --no-pager
```

QML parse errors, `console.log()` output, and apploader load/unload messages all surface there.

## Notes

- `entry` in `manifest.json` is the path *inside* the rcc, e.g. `/ui/Main.qml`. It must start with `/` — apploader concatenates it onto `qrc:/<nonce>`.
- The root QML must declare `signal close` and `function unloading()` per apploader convention. Emit `close()` from your Quit handler to ask apploader to unload the frontend.
- Don't set hardcoded `width`/`height` on the root; use `anchors.fill: parent` so apploader's container sizes you.
