# CLAUDE.md

Guidance for Claude Code at the **monorepo root**. Per-app specifics live in each app's own
`CLAUDE.md` — read those before working inside an app.

## Maintaining this file

Keep it lean: this is the cross-cutting layer only. Anything specific to one app belongs in that
app's `CLAUDE.md`, not here. Prefer tightening existing sections over appending; remove obsolete
guidance.

## What this is

A **habit tracker** built as a pnpm monorepo: two clients over one shared habit domain, plus the
backend that owns the canonical records and reconciles them:

```
/
├── apps/
│   ├── backend/      ASP.NET Core (.NET 10) + EF Core + PostgreSQL. Canonical store + Sync.
│   ├── remarkable/   QML scene for the reMarkable 1 (XOVI + rm-appload). Built with make.
│   └── mobile/       expo (React Native, TypeScript) app. Built with pnpm/expo.
└── CONTEXT.md        shared habit glossary (Habit, Entry, X/O, polarity, …)
```

The shared habit vocabulary lives in the root [`CONTEXT.md`](./CONTEXT.md); each app adds its own
`CONTEXT.md` for terms only it uses. Use those terms in code, comments, and docs.

## Hard rule: the backend is the only cross-app contract

The two clients are **independent peers**, not references for each other. When working in one client,
do not read the other to decide its domain model, storage shape, sync behaviour, or naming. Both
have aligned their vocabulary to the backend's (`Positive`/`Negative`, `Success`/`Failure`,
`editedAt`, tombstones), but they got there **separately, from the backend** — and they still
persist it differently on purpose: reMarkable writes per-month JSON files behind QML stores and
keeps `"x"`/`"o"` outcomes it respells at the sync edge; mobile writes SQLite tables via Drizzle,
storing the backend's spellings verbatim. Converging vocabulary is not a licence to copy: neither
client is a spec.

That contract has a machine-readable form: `dotnet build` emits **`apps/backend/openapi.json`**, and
it is committed. Mobile generates its entire wire layer from it with kubb (`apps/mobile/src/api/`) —
so a DTO change must land with a rebuilt spec, or clients silently keep decoding the old shape.
reMarkable hand-writes its edge (`src/js/Sync.js`) and reads the same file as documentation.

**Unification, merge, and conflict resolution are the backend's job**, never a client's. When a
client question is about the shared model or the sync contract, the answer is in
[`apps/backend/CONTEXT.md`](./apps/backend/CONTEXT.md) (Outcome, Position, Sync, Edit-time,
Tombstone) and [`apps/backend/README.md`](./apps/backend/README.md) (`Entities/`, `Dtos/`,
`Controllers/`) — plus the root glossary above. Where a client and the backend disagree, the backend
wins. "The other client does it this way" is never a justification for a change.

## Hard rule: never SSH to the device

Under no circumstance may the agent run `ssh`, `scp`, `rsync`, `make deploy`, `make remove`, or any
other command that touches the reMarkable — including "read-only" probes like `ssh remarkable
journalctl …`. The user runs all device-side commands and pastes back the output. If a step needs
the device, describe what to run and wait. This applies even when a `make` target wraps the SSH.

## Per-app guidance

- **`apps/backend/`** — C# / ASP.NET Core + EF Core, the canonical store and the owner of Sync.
  Source of truth for the shared model and the sync contract.
  See [`apps/backend/CLAUDE.md`](./apps/backend/CLAUDE.md).
- **`apps/remarkable/`** — pure-QML, built by `make` (run from that dir). Qt 5.15 / e-ink display
  constraints, apploader loading quirks, never-SSH. See [`apps/remarkable/CLAUDE.md`](./apps/remarkable/CLAUDE.md).
- **`apps/mobile/`** — expo + TypeScript, SQLite (Drizzle) + TanStack Query.
  See [`apps/mobile/CLAUDE.md`](./apps/mobile/CLAUDE.md).

## Workspace commands

- `pnpm install` — install all workspace deps from the root. `.npmrc` sets `node-linker=hoisted`
  because Metro (expo's bundler) doesn't follow pnpm's symlinked `node_modules`.
- **Aggregates** (run in every app that defines the script): `pnpm format`, `pnpm lint`,
  `pnpm typecheck`.
- **Per-app delegators** (root scripts that call into one app):
    - `pnpm mobile:start` (also `mobile:android` / `mobile:ios`; there is deliberately no web
      target — never run the mobile app on web, see `apps/mobile/CLAUDE.md`).
      `pnpm mobile:build:android` runs an EAS cloud build; `mobile:build:android:local` builds on
      this machine instead (`--local`, needs the Android SDK + JDK). Both default to the
      `production` profile — append `--profile preview` (or `development`) to pick another.
      `pnpm mobile:db:generate`
      regenerates the Drizzle migrations after a schema edit; `pnpm mobile:api:generate` regenerates
      mobile's backend client from `apps/backend/openapi.json` (rebuild that first with
      `pnpm backend:build`).
    - `pnpm remarkable:build` (also `remarkable:test` / `remarkable:clean` / `remarkable:backup` /
      `remarkable:deploy` / `remarkable:remove` / `remarkable:find-hotspot-ip`, which shell out to
      `make` — `deploy`/`remove`/`backup`/`find-hotspot-ip` touch the device, so user-only).
      `remarkable:test` runs that app's Qt Quick Test suite; it needs `qmltestrunner-qt5` and is the
      only checker there that can fail. `remarkable:find-hotspot-ip` nmap-scans the current network
      for the tablet (identifying it by SSH host key) and repoints `~/.ssh/config` at it.
    - `pnpm backend:start` (also `backend:build` / `backend:watch` / `backend:test`), plus the
      database targets `backend:db:up` / `backend:db:down` / `backend:migrate` / `backend:db:clear`.
      `db:up` needs Docker; `migrate` applies the EF Core migrations.
- Anything not wired above: `pnpm --filter @habit-tracker/<app> run <script>`.

## Code style

Shared `.prettierrc.json` applies repo-wide to the JS/TS/QML/Markdown side (mobile overrides it with
its own `.prettierrc.json`); C# is formatted by `dotnet format` instead. Prefer verbose, descriptive
names in code and persisted/domain data; avoid single-letter or cryptic names except for very small
local indices. Language-specific rules live per app — QML/JS conventions in
`apps/remarkable/CLAUDE.md`, layering and migration rules in `apps/backend/CLAUDE.md`, NativeWind and
file-naming rules in `apps/mobile/CLAUDE.md`.
