# Habit Tracker — mobile

> Part of the **habit-tracker** monorepo — this is the `apps/mobile/` client. Its contract partner is
> the backend in [`apps/backend/`](../backend/), which owns the canonical records and Sync;
> `apps/remarkable/` is an independent peer client, not a reference. Shared habit vocabulary is in
> the [root `CONTEXT.md`](../../CONTEXT.md), the sync terms in the
> [backend glossary](../backend/CONTEXT.md).

The mobile client of the habit tracker: an [Expo](https://expo.dev) (SDK 56) app built with
expo-router and TypeScript, styled with [NativeWind](https://www.nativewind.dev) (Tailwind for
React Native).

It renders the Habit × Entry model in the backend's shape over a mobile-native, tabbed UI:

- **Today** — the primary daily surface: one card per habit with today's mark and its streak.
- **Month** — the whole grid at review scale, **transposed** for portrait: days are rows (vertical
  scroll), habits are columns, today's row highlighted.
- **Habits** — manage the roster: rename, reorder, set polarity.
- **Sync** — point the app at a backend, or stay standalone with an empty Server URL.

## Status

**Persistent, editable, and synced.** Habits and entries live in on-device SQLite (`expo-sqlite` +
Drizzle) read through TanStack Query, so marking a day, renaming a habit, flipping its polarity,
reordering the roster, and adding or deleting habits all persist across restarts. The Sync screen
stores a **Server URL** (blank = standalone) and offers a manual **Sync now**; the Month screen also
background-syncs whichever month is being viewed. A fresh install starts empty and fills in from its
first sync. The backend at [`apps/backend/`](../backend/) owns the merge (last-write-wins on
`editedAt`) — this client submits its state and accepts the result rather than resolving conflicts
itself.

## Run it

Install workspace deps once from the monorepo root (`pnpm install`), then from the root:

```sh
pnpm mobile:start      # start the expo dev server
pnpm mobile:android    # open on an Android emulator/device
pnpm mobile:ios        # open on an iOS simulator/device
```

Or run scripts directly from this directory with `pnpm start` / `pnpm android` / `pnpm ios`.
There is deliberately no web target. The dev server prints options to open the app in a development build, a simulator, or
[Expo Go](https://expo.dev/go).

Checks:

```sh
pnpm typecheck    # tsc --noEmit
pnpm lint         # expo lint (config in eslint.config.js)
```

## Layout

```
src/
├── app/          expo-router routes (file-based). _layout.tsx is the Tabs navigator
│                 (imports global.css); index=Today, month, habits, sync.
├── components/   UI, grouped by feature — ui/ (primitives: Card, Button, Pill,
│                 AppScreen, SortableList, …), today/, month/, habits/, sync/,
│                 plus HabitMark.tsx and AppProviders.tsx (query client + DatabaseGate).
├── db/           SQLite via Drizzle — schema.ts, drizzle/ (generated migrations),
│                 client.ts, migrations.ts, repo/ (the only DB access, incl. sync.ts).
├── state/        queries/ — TanStack Query hooks + mutations, incl. sync.ts; the seam
│                 screens read through. Screens never touch SQLite directly.
├── domain/       model + logic, no UI (types.ts, dates.ts, entries.ts, roster.ts, marks.ts).
├── theme/        palette.js — single source of color values; colors.ts re-exports
│                 it raw for non-className APIs (the tab bar).
└── lib/          cn.ts — classname joiner; useUpdateEffect.ts.
```

- `@/*` is a path alias for `src/*` (see `tsconfig.json`).
- The domain types mirror the **backend's** shape — `Outcome`/`Polarity`/`Position`, `YYYY-MM-DD`
  date keys, UUID ids — so mobile↔backend sync is a near-identity map. X/O is a _display_ reading,
  not storage: the mapping lives in `domain/marks.ts` (`markView`) so components stay presentational.
- Edit the schema, then run `pnpm db:generate` to regenerate the Drizzle migrations (they're
  committed, not ignored).

## Styling

NativeWind only: style with `className` and Tailwind utilities, not `StyleSheet.create` or inline
`style`. Color values have a single source in `src/theme/palette.js`, consumed by both
`tailwind.config.js` (shaped into the color scale) and `src/theme/colors.ts` (re-exported raw for the
few React Navigation APIs that take color values rather than classes); radii are tokens in
`tailwind.config.js`. Config lives at the app root (`tailwind.config.js`, `global.css`, `metro.config.js`,
`babel.config.js`, `nativewind-env.d.ts`). Third-party components need
`cssInterop(Component, { className: 'style' })` before they accept `className` (registered in
`src/components/ui/AppScreen.tsx` for `SafeAreaView` and `src/components/ui/Icon.tsx` for
`MaterialIcons`); core RN components work out of the box.
