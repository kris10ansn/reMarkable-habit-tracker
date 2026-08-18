# CLAUDE.md — mobile app

@AGENTS.md

The `apps/mobile/` client of the habit-tracker monorepo: Expo (SDK 56) + expo-router + TypeScript,
styled with NativeWind (Tailwind for React Native).

## Hard rule: never run the app on web

Never run `expo start --web` (or any command that serves the app to a browser) — the web target
was deliberately removed from `package.json` and `app.json`; do not add it back or bypass it with
`pnpm exec expo start --web`. This app is native-only: verify with `pnpm typecheck` / `pnpm lint`,
and leave running the app on a device or emulator to the user — describe what to check and wait
for their report.

## Hard rule: the backend is mobile's only reference

Mobile's contract partner is **`apps/backend/`**. Never read `apps/remarkable/` to decide mobile's
domain model, storage shape, sync behaviour, or naming — it is a **peer client, not a spec**. Both
clients now spell the domain the backend's way, but each arrived there from the backend
independently; reMarkable still persists differently (per-month JSON files behind QML stores, with
`"x"`/`"o"` outcomes respelled at its sync edge). That the two look similar is a _result_ of both
following the backend, never a reason to copy one into the other — take the answer from
`apps/backend/`, not from the client that already solved it.

Unification, merge, and conflict resolution are the **backend's** job — mobile submits its state and
accepts the authoritative result; it does not invent merge rules. When a question is about the
shared model or the sync contract, the answers are in
[`apps/backend/CONTEXT.md`](../backend/CONTEXT.md) (Outcome, Position, Sync, Edit-time, Tombstone)
and [`apps/backend/README.md`](../backend/README.md) (`Entities/`, `Dtos/SyncDtos.cs`,
`Controllers/SyncController.cs`). Where mobile and the backend disagree, the backend wins.

## What this is

A mobile habit tracker with four tabs — **Today** (log), **Month** (the grid), **Habits** (edit
roster), **Sync**. The Month grid is **transposed** for portrait (days as rows, habits as columns,
today highlighted) and **navigable to any month** (past editable, future view-only). Data
**persists in SQLite** (`expo-sqlite`) storing the backend's shape
(Outcome/Polarity/Position/`editedAt`/`deletedAt` tombstones, UUID ids), read through **TanStack
Query** hooks (`src/state/queries/`) over a thin repo (`src/db/repo/`). Tapping a `HabitMark` on
Today or Month cycles its state; the Habits tab renames, flips polarity, and drag-to-reorders (drag
a row by its handle — the generic `components/ui/SortableList` with an inline `HabitRow` in
`app/habits.tsx`). The Sync tab persists a **Server URL** setting (empty = standalone) and offers a
manual **Sync now**; the Month screen also background-syncs whichever month is being viewed
whenever a Server URL is set.

Sync itself is one round trip: `useSync` (`src/state/queries/sync.ts`) gathers local state — the
months with entries edited since `lastSyncedAt` plus the month currently in view — via
`src/db/repo/sync.ts` (`monthsToSync`, `gatherRequest`), POSTs it through the generated `sync()`
client, then overwrites local state with the backend's authoritative response (`applySynced`);
`syncStartedAt` guards rows edited while the request is in flight. Merge is entirely the backend's
call (last-write-wins on `editedAt`) — mobile never resolves conflicts itself.

## Domain

Shared vocabulary lives in the monorepo-root [`CONTEXT.md`](../../CONTEXT.md) (Habit, Entry, X/O,
polarity, Unmarked); the sync terms live in the [backend glossary](../backend/CONTEXT.md). The TS
model in `src/domain/` mirrors the **backend's** shape so mobile↔backend
sync is a near-identity map: `types.ts` holds flat `Habit`/`Entry` rows storing
`Outcome`/`Polarity`; `marks.ts` maps Outcome → the X/O display reading (`markView`) and the tap
cycle (`nextAction`, `isSuccess`) — components never re-derive the semantics. `dates.ts` owns the
`dateKey` (`YYYY-MM-DD`) / `monthKey` (`YYYY-MM`) formats plus month math; `entries.ts` is the
per-month cell lookup. The look-back **streak** query lives in `db/repo/streaks.ts` (`getStreaks`),
since it crosses month partitions.

## Layout

- `src/app/` — expo-router routes. `_layout.tsx` is the `Tabs` navigator (headerShown false), wraps
  the tree in `AppProviders`, mounts the `Toaster` (`sonner-native`), and imports `global.css` (the
  app-wide stylesheet entrypoint — keep this import). Routes: `index` (Today), `month`, `habits`,
  `sync`.
- `src/components/AppProviders.tsx` — the provider stack (TanStack Query client + `DatabaseGate`,
  which runs migrations before rendering children). Screens can assume a ready DB.
- `src/components/` — UI grouped by feature: `ui/` holds reusable primitives (`Card`, `Button`,
  `Pill`, `Icon`, `IconButton`, `StatCard`, `TextField`, `AppScreen`, `ScreenHeader`, `SortableList`);
  `today/`, `month/`, `habits/`, `sync/` hold screen-specific pieces; `HabitMark.tsx` is the shared
  state chip. `SortableList` is the generic drag-to-reorder list (equal-height rows, id-keyed
  `onReorder`, `SortableListHandle` as the grab affordance); the habits binding is an inline
  `HabitRow` in `app/habits.tsx` (there is no `SortableHabitList` component).
- `src/domain/` — model + logic, no UI (the tap cycle is `nextAction` in `marks.ts`).
- `src/db/` — SQLite via **Drizzle**: `schema.ts` (Drizzle table defs — the `enum` column mode makes
  results match the domain types with no mappers; three tables, `habits` / `entries` /
  singleton `settings`), `drizzle/` (drizzle-kit–generated migrations — regenerate with
  `pnpm db:generate` after editing the schema; committed, not ignored), `client.ts`
  (`useDatabase` — the typed Drizzle handle), `migrations.ts` (wraps the generated bundle), `repo/`
  (the only DB access — Drizzle query builder, split per entity into
  `habits.ts`/`entries.ts`/`streaks.ts`/`settings.ts`/`sync.ts` behind an `index.ts` barrel so
  `import * as repo` keeps working; reads return alive rows, writes stamp `editedAt` (the merge
  key — the backend's audit `UpdatedAt` is server-owned, never on the wire, and deliberately not
  mirrored here) and set `deletedAt` on soft-delete). Migrations run at startup via `useMigrations`
  in `AppProviders`' `DatabaseGate`. Build glue: `babel.config.js` inlines `.sql`,
  `metro.config.js` adds the `sql` sourceExt (both required by Drizzle's expo migrator).
- `src/state/queries/` — the data seam: TanStack Query hooks `useHabits`, `useMonthEntries`,
  `useStreaks`, `useSettings`, `useSync`, and the
  `useToggleEntry`/`useUpdateHabit`/`useReorderHabit`/`useUpdateSettings` mutations (optimistic +
  invalidating), split per entity into
  `habits.ts`/`entries.ts`/`streaks.ts`/`settings.ts`/`sync.ts` with the query keys in `keys.ts`;
  `index.ts` is the public surface — import from `@/state/queries`
  (`streaksKey` stays internal). Screens read through these, never SQLite directly. Habits carry a
  stable `id` — key lists on it, never on `name` (renames would remount) or the index (reorders
  would desync uncontrolled `TextInput`s).
- `src/api/` — the backend seam. `gen/` is **generated** by [kubb](https://kubb.dev) from
  `apps/backend/openapi.json` (config: `kubb.config.ts`) and committed, so a fresh clone typechecks
  without codegen: `gen/types/` (wire types — string-union enums that are the _same_ types as
  `domain/types.ts`), `gen/zod/` (schemas), `gen/clients/` (one async function per backend
  operation, e.g. `sync()`, each validating its response with the Zod schema before returning).
  `client.ts` is the **only** hand-written file here — the fetch transport, which takes `baseURL`
  per call (no module-level state to go stale against the editable Server URL setting) and throws
  `ApiError` (non-2xx, `body` carries the backend's `ProblemDetails`) or `NetworkError`.
- `src/theme/colors.ts` — raw palette for non-className APIs. `src/lib/` — `cn.ts` (classname joiner
  for conditional classes) and `useUpdateEffect.ts` (effect that skips the first run, used to
  re-seed local form state from a query without clobbering typing).
- `@/*` path alias → `src/*` (see `tsconfig.json`).
- NativeWind config lives at the app root: `tailwind.config.js` (content globs + `nativewind/preset`
    - the design tokens), `global.css` (Tailwind directives), `metro.config.js` (`withNativeWind`),
      `babel.config.js` (`jsxImportSource: 'nativewind'`), and `nativewind-env.d.ts` (types).

## Conventions

- **Styling is NativeWind only** — use `className` with Tailwind utilities; do not use
  `StyleSheet.create` or inline `style` objects. **Exception:** React Navigation options that take
  color/style values (the tab bar in `_layout.tsx`) and `placeholderTextColor` — pull those from
  `src/theme/colors.ts`. Color values have a single source in `src/theme/palette.js`, consumed by
  both `tailwind.config.js` (shaped into the color scale) and `colors.ts` (re-exported raw); radii
  like `rounded-card`/`rounded-field` are tokens in `tailwind.config.js`.
- **Reuse the primitives.** Build screens from `components/ui/*` (`Card`, `Button`, `AppScreen`, …)
  and compose feature pieces; don't re-style raw `View`s ad hoc. Use `cn()` for conditional classes.
- **Icons are Material icons** from `@expo/vector-icons`, wrapped by the `Icon` primitive
  (`components/ui/Icon.tsx`) — pass a Material `name` and a `text-*` class for the tint (it registers
  `cssInterop` so `className` drives color); `size` is a number. `IconButton` takes an `icon` name;
  the tab bar passes React Navigation's resolved `color`. Don't render raw text glyphs for icons.
- Third-party components (e.g. `SafeAreaView` from `react-native-safe-area-context`, `MaterialIcons`)
  don't accept `className` until registered with `cssInterop(Component, { className: 'style' })` —
  registered in `src/components/ui/AppScreen.tsx` and `src/components/ui/Icon.tsx`. Core RN components (`View`, `Text`, `ScrollView`, `TextInput`,
  …) work out of the box; `ScrollView` also takes `contentContainerClassName`.
- `babel-preset-expo` auto-configures the reanimated 4 babel plugin on SDK 56, so **never** add
  `react-native-reanimated/plugin` (or `react-native-worklets/plugin`) to `babel.config.js` — it
  duplicates the plugin and errors.
- **File names match the export's casing.** A file whose main export is capitalized (a React
  component, e.g. `AppScreen`, `HabitMark`) is `PascalCase.tsx`; a file exporting lowercase
  identifiers (`marks.ts`, `cn.ts`) stays camelCase/lowercase. **Exception:** `src/app/` routes keep
  expo-router's framework-dictated lowercase names (the filename is the URL route; `index`/`_layout`
  are special) even though they default-export a capitalized screen component.
- Local `.prettierrc.json` (4-space / double-quote, plus `prettier-plugin-organize-imports` and
  `prettier-plugin-tailwindcss` for class sorting) overrides the repo-root config.
- **Never hand-edit `src/api/gen/`** — every run of `pnpm api:generate` wipes and rewrites it
  (`output.clean`). The backend owns those shapes; to change one, change `apps/backend/Dtos/`,
  rebuild the spec (`pnpm backend:build`), then regenerate. Behaviour that isn't derivable from the
  spec belongs in `src/api/client.ts` or above the seam, never in a generated file.
- **Talk to the backend only through the generated clients**, and only for Sync. Mobile is
  local-first: screens read SQLite via `state/queries/*`, and the backend's Habits CRUD endpoints
  (`getHabits`, `createHabit`, …) exist in `gen/clients/` because the spec has them, not because
  mobile may call them — doing so would bypass local storage and put merge decisions in a client.
  There are deliberately no generated React Query hooks; see the note in `kubb.config.ts`.
- `pnpm typecheck` (tsc --noEmit) to check types; `pnpm start` to run the dev server;
  `pnpm api:generate` to regenerate the backend client after the spec changes.
