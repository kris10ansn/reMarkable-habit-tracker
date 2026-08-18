# CLAUDE.md — backend

Guidance for Claude Code inside `apps/backend/`. See the monorepo-root
[`CLAUDE.md`](../../CLAUDE.md) for cross-app conventions.

## Maintaining this file

Keep it lean — cross-app rules belong at the root, the run/API reference in
[`README.md`](./README.md), and vocabulary in [`CONTEXT.md`](./CONTEXT.md). Prefer tightening
existing sections over appending; remove guidance that goes stale.

## What this is

ASP.NET Core (.NET 10) Web API over EF Core + PostgreSQL. It owns the **canonical** Habit/Entry
records and performs **Sync**. It does not mirror any client's on-device shape — it stores the same
data reframed for a relational API, and client-only presentation concerns (grid orientation, a
device's reveal setting for private habits) deliberately do not cross into it.

Layout, prerequisites, run commands, migrations, and the endpoint reference are in
[`README.md`](./README.md). The vocabulary this app adds — **User, Outcome, Position, Sync,
Edit-time, Tombstone** — is in [`CONTEXT.md`](./CONTEXT.md); the shared habit vocabulary is in the
[root glossary](../../CONTEXT.md).

## This app is the cross-app contract

Both clients (`apps/remarkable/`, `apps/mobile/`) are **peers of each other and consumers of this
API**. They are not references for one another, and neither is a spec for this backend.

Consequences when working here:

- **Merge lives here, not in a client.** A client submits its state and overwrites local with the
  authoritative result. Do not push conflict resolution, dedup, or reconciliation into a client.
- **A change to `Dtos/SyncDtos.cs` or `Dtos/HabitDtos.cs` is a contract change.** Both clients
  decode these shapes (`apps/remarkable/src/js/Sync.js`, and mobile's sync layer once built). Say so
  explicitly when you change one; don't treat it as an internal refactor.
- **A contract change is not finished until `openapi.json` is rebuilt.** `dotnet build` regenerates
  that committed file (see [`README.md`](./README.md)) and mobile's whole API layer is generated
  from it (`pnpm mobile:api:generate`). Leaving it stale ships clients the previous contract
  silently — nothing fails, they just decode the wrong shape.
- **Enums serialize as the member names verbatim** (`"Positive"`, `"Success"`) — a bare
  `JsonStringEnumConverter` with no naming policy. Both clients have since aligned their own storage
  to these spellings, so the casing is load-bearing in three places at once: **do not add a naming
  policy or rename a member casually.** Where a client still keeps its own vocabulary (reMarkable
  persists `"x"`/`"o"` outcomes and respells them in `src/js/Sync.js`), that translation is the
  client's to own — never accommodate it by changing the wire.
- When a client and this backend disagree about the model, **the backend is right** and the client
  gets fixed.

## Domain rules that are easy to break

- **Two clock domains.** Everything on the wire is the client's clock, in epoch ms UTC: `EditedAt`
  (the **Edit-time** merge key, the _only_ value a merge compares), `CreatedAt`, and `DeletedAt`.
  All three are stored verbatim — `StampTimestamps` only fills a `CreatedAt` nobody supplied, so a
  habit made offline keeps its real create-time (mobile anchors negative-habit streaks on it). The
  server's own clock shows up in exactly one field, the `UpdatedAt` audit stamp, which has no DTO
  and never reaches a client. Don't collapse the two domains, and don't reintroduce `updatedAt` as
  a wire name — that spelling belonged to the audit field.
- **A skewed clock is refused, not merged.** `SyncService.ClockSkewTolerance` (5 min) bounds how far
  ahead of the server an incoming edit-time may be; past it the whole request throws
  `ClockSkewException` and the controller returns 400. Keep it a whole-request refusal — merging the
  sound half would leave the client's state split across two syncs.
- **Deletes are tombstones.** A `DeletedAt` soft-delete so a deletion can win _or lose_ against a
  dated edit; a row that simply vanished would be resurrected by the next sync. Requests carry alive
  rows _and_ tombstones; responses carry the authoritative **alive** state only (a delete surfaces
  as absence).
- **The entry log is permissive.** Any `Outcome` may be stored against any habit — "negative habits
  only record Failure" is a client convention, not a rule to enforce here. Absence of an entry is
  the Unmarked state; a negative habit's implicit "stayed clean" is never a stored `Success`.
- **Sync ids are client-minted.** `HabitDto.Id` arrives from the client (random, so two offline
  clients never collide) and must be stored as-is — never re-mint one during a merge. The REST
  `POST /api/habits` path is different: `CreateHabitRequest` carries no id, so the server mints
  there.
- **Auth is deferred.** Every request acts as the seeded stub user; `Services/CurrentUser.cs` is the
  single seam to replace when authentication lands. Don't scatter user resolution elsewhere.
- **No habits are seeded** — a new user starts empty and a first Sync populates the store.

## Conventions

- **Layers:** `Controllers/` (HTTP + DTO mapping only) → `Services/` (app logic, talks to the
  `DbContext` directly; there is no repository layer) → `Entities/` (EF entities + domain enums).
  Keep logic out of controllers and cross the boundary through `Dtos/`. Responses project to a
  record; never serialize an EF entity, which would leak `UserId` and the navigation properties.
- **One DTO per concept, not one per endpoint.** `HabitDto` and `EntryDto` (in `Dtos/HabitDtos.cs`)
  are the canonical wire shapes, used by Sync _and_ the REST endpoints alike. They spell every
  client-owned field exactly as the clients store it, so decoding is an identity map — mobile
  asserts that at compile time in `apps/mobile/src/api/contract.ts`. Adding a second shape for the
  same concept is what puts mappers back in the clients; don't.
- **Migrations are the schema source of truth.** After editing an entity or `HabitTrackerDbContext`,
  add a migration (`dotnet ef migrations add <Name> --project src/HabitTracker.Api`) and commit it;
  never hand-edit the generated files or the model snapshot.
- **Descriptive names** in code and persisted/wire data (repo-wide rule) — `editedAt`, not `ts`.
- Checks: `pnpm test` (xUnit, EF in-memory — no database needed), `pnpm lint`
  (`dotnet format --verify-no-changes`), `pnpm format`. Run these from this directory, or from the
  root as `pnpm backend:test` / `backend:build`.
- Running the API and touching the database (`pnpm start`, `db:up`, `migrate`, `db:clear`) needs
  Docker and a local Postgres — leave those to the user unless asked, and note that `db:clear`
  **drops** the database.
