# reMarkable habit tracker

A small habit tracker for the **reMarkable 1** e-ink tablet. It draws a landscape grid: one row per habit, one column per day of the current month, with today's column highlighted. No syncing, no accounts, no backend — just a QML scene rendered on the device.

Tap a box to cycle its state. **Positive habits** cycle empty → X → O → empty (X = done, O = explicitly not done). **Negative habits** start with X (treated as the default "didn't slip up") and toggle to O when you mark a slip. For negative habits, future days are rendered muted. The habit list and all marks are persisted to a JSON file on the device.

## What it looks like

```
June 2026
30 days · today is day 5

Read 20 pages           ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ …
Exercise                ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ …
Meditate                ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ …
No screens after 22:00  ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ …
Journal                 ▢ ▢ ▢ ▢ ▣ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ ▢ …

                                            [ Edit ]  [ Quit ]
```

## How it runs (and why the stack looks the way it does)

The reMarkable 1 ships with **xochitl**, the stock UI. There's no official way to launch third-party apps. This project depends on a community stack that bolts an app menu onto xochitl:

- **XOVI** — a function-hooking framework that loads extensions into xochitl.
- **rm-appload** (`asivery/rm-appload`) — an XOVI extension. It overlays a launcher on xochitl (hold the middle button ~3 seconds to open it) and runs each app's frontend inside xochitl's own Qt process. The frontend runtime it exposes is **QML** (Qt 5.15 — what the rM1 firmware ships).

So the "app" is a QML scene that apploader loads into xochitl. No separate process, no Wayland/X, no framebuffer driver — Qt's existing render path on the device does the drawing.

apploader doesn't read loose `.qml` files at runtime — it expects them packaged into a **Qt binary resource** (`.rcc`). The build step here just runs Qt 5's `rcc --binary` over `application.qrc` to produce one. Deploy = `scp` three files (`resources.rcc`, `manifest.json`, `icon.png`) into apploader's app directory on the device.

### Stack at a glance

| Layer       | What                                                          |
| ----------- | ------------------------------------------------------------- |
| Hardware    | reMarkable 1 (e-ink, ARM, Linux-based firmware)               |
| Stock UI    | xochitl (Qt 5.15 process)                                     |
| Hooking     | XOVI                                                          |
| App runtime | rm-appload (XOVI extension, QML frontend host)                |
| This app    | `Main.qml` + a `Theme` singleton, small components, JS data   |
| Build       | `rcc-qt5 --binary` → `resources.rcc`                          |
| Deploy      | `scp` to `/home/root/xovi/exthome/appload/habit-tracker/`     |

## Repo layout

```
.
├── application.qrc      # lists files to bundle into the .rcc
├── src/
│   ├── Main.qml         # entry; root declares signal close + unloading()
│   ├── Theme.qml        # singleton with sizes, fonts, colors
│   ├── qmldir           # registers Theme as a singleton
│   ├── components/      # reusable QML pieces (AppButton, HabitRow, …)
│   │   └── qmldir
│   └── js/              # plain JS modules (habits list, date helpers)
├── manifest.json        # apploader manifest (id, display name, entry path inside the rcc)
├── icon.png             # launcher icon shown in apploader
├── Makefile             # build / deploy / remove / clean
└── build/               # rcc output + deploy staging (gitignored)
```

## Prerequisites

On your **host machine** (Linux/macOS):

- **Qt 5's `rcc`.**
  - Arch/Manjaro: `pacman -S qt5-base` (binary is `rcc-qt5`)
  - Debian/Ubuntu: `apt install qtbase5-dev-tools` (binary is `/usr/lib/qt5/bin/rcc`)
  - macOS: `brew install qt@5`

  Override with `make RCC=<path>` if it isn't on `$PATH` as `rcc-qt5`. Qt 6's `rcc` works for `--binary` too, but the device runtime is Qt 5.15 — stay on 5 to avoid surprises.
- **SSH access to the device** as `ssh remarkable` (i.e. an entry in `~/.ssh/config`). Override the host with `make REMARKABLE_HOST=<host>`.

On the **device** you need an installed XOVI + rm-appload setup. See [`asivery/rm-appload`](https://github.com/asivery/rm-appload) for installation — that's the prerequisite that makes this app loadable at all.

## Build & deploy

```sh
make build      # produces build/resources.rcc + staged icon/manifest
make deploy     # scps build/* to /home/root/xovi/exthome/appload/habit-tracker/
make remove     # uninstalls from the device
make clean      # nukes local build/
```

On the device, hold the middle button ~3 seconds to open apploader. The "reMarkable habit tracker" tile should appear; tap to launch, tap **Quit** (bottom-right) to close.

## Customizing the habits

Tap **Edit** (bottom-right, next to **Quit**) to enter edit mode. Each row gains `↑`/`↓` buttons to reorder it, a `×` to delete it, a `−` toggle to mark the habit as negative (tracks slips rather than wins), and the habit name becomes editable. An input row appears at the bottom of the habit list — type a name and tap **+** (or press Enter) to add. Tap **Done** to leave edit mode.

The list is persisted to `habits.json` next to the app on the device (`/home/root/xovi/exthome/appload/habit-tracker/habits.json`). On first launch the file is seeded from the defaults in `src/js/habits.js`. To wipe back to defaults, delete that file on the device and relaunch.

## Debugging

apploader runs inside xochitl, so QML parse errors and `console.log()` output go to xochitl's stderr → systemd journal on the device. Tail it while testing:

```sh
ssh remarkable journalctl -fu xochitl --no-pager
```

apploader prefixes its messages with `[AppLoad]:` / `[QTFB]:`. `[QTFB]: Unregistered framebuffer controller ID: -1` is harmless for QML-only apps.

## Gotchas worth knowing before editing

These have already cost real debug cycles:

1. **QML files must live inside the `.rcc`.** Loose `.qml` on the device won't be found. Add new files to `<qresource>` in `application.qrc` and rebuild.
2. **`entry` in `manifest.json` must start with `/`.** apploader concatenates the entry onto `qrc:/<nonce>` with no separator; without the leading slash you get `qrc:/NONCEMain.qml` and "No such file."
3. **Root QML conventions.** The root component must declare `signal close` and `function unloading() { ... }`. Emit `close()` from your Quit handler — `Qt.quit()` is a no-op (Qt's process is xochitl, you don't own it).
4. **No hardcoded root size.** apploader sizes the container; use `anchors.fill: parent` on the root. Hardcoded `width: 1404; height: 1872` is silently ignored.
5. **The grid is rendered rotated 90°.** The screen is portrait, but the layout reads better landscape — `src/Main.qml` has a centered `Item { rotation: 90 }` wrapper that swaps `width`/`height` and anchors the layout into it.

## A note on naming

The repo lives under `~/src/rust/` — that's historical. Earlier attempts at a reMarkable app were Rust (`remarkable-app/`, `remarkable-helloworld-2/`); this iteration is QML-only, and the prototype started life as a hello-world before turning into a habit tracker.
