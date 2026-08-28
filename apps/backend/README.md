# Backend — Habit Tracker API

ASP.NET Core (.NET 10) Web API over EF Core + PostgreSQL. Owns the canonical Habit/Entry records and
performs Sync — it is the one place the clients' state is reconciled. It does **not** mirror the
clients' on-device shape; it stores the same data reframed for a relational API. See the vocabulary
in [`CONTEXT.md`](./CONTEXT.md) and the agent guidance in [`CLAUDE.md`](./CLAUDE.md).

## Layout

```
src/HabitTracker.Api/        single Web API project, folder layers:
  Controllers/               HTTP endpoints, DTOs in / out
  Services/                  app logic (talks to DbContext directly)
  Entities/                  EF entities + domain enums (Polarity, Outcome, PairingStatus)
  Authentication/            bearer-token auth handler, claim names, OpenAPI security scheme
  Data/                      DbContext, model config, seed, timestamp stamping
  Dtos/                      request/response records
  Migrations/                EF Core migrations (schema source of truth)
tests/HabitTracker.Api.Tests/  xUnit tests (EF in-memory)
docker-compose.yml             local PostgreSQL
```

Every endpoint requires an `Authorization: Bearer <token>` session token by default, except signup,
login, and the tablet-facing pairing endpoints (`POST /api/pairing/code`, `POST /api/pairing/poll`),
which are anonymous by necessity. `Services/CurrentUser.cs` is the single seam the authenticated
user is resolved into — see [`CLAUDE.md`](./CLAUDE.md). Tokens are opaque, 256-bit, non-expiring,
and revocation-based (see `Services/SessionService.cs`); there is no JWT and no ASP.NET Identity.

## Prerequisites

- .NET 10 SDK
- Docker (for PostgreSQL)

## Run it

From this directory (or use the root `pnpm backend:*` delegators):

```bash
pnpm db:up        # start PostgreSQL in Docker
pnpm migrate      # apply EF migrations to the database
pnpm start        # run the API (http://localhost:5137)
```

`src/HabitTracker.Api/HabitTracker.Api.http` has ready-to-run requests for the Habits endpoints. In
Development, the OpenAPI document is served at `/openapi/v1.json`.

Production deployment (GCP e2-micro + Cloudflare Tunnel) is documented in [`DEPLOY.md`](./DEPLOY.md).

### The OpenAPI document

`pnpm build` (`dotnet build`) also writes the document to [`openapi.json`](./openapi.json) in this
directory — that is the `Microsoft.Extensions.ApiDescription.Server` package plus the
`OpenApiDocumentsDirectory` / `OpenApiGenerateDocumentsOptions` properties in
`HabitTracker.Api.csproj`. The file is **committed**, so a client can generate its API layer with
neither a running server nor a database: mobile runs [kubb](https://kubb.dev) over this exact file
(`apps/mobile/kubb.config.ts`) to produce `apps/mobile/src/api/gen/`.

Rebuild and commit it in the same change as any edit to `Dtos/` or a controller signature. A stale
`openapi.json` hands every client the old contract without any error to notice.

## Develop

```bash
pnpm build        # compile
pnpm test         # run tests (no database needed — EF in-memory)
pnpm format       # dotnet format
pnpm lint         # dotnet format --verify-no-changes
```

### Migrations

The EF tool is a repo-local tool (`.config/dotnet-tools.json`); run `dotnet tool restore` once, then:

```bash
dotnet ef migrations add <Name> --project src/HabitTracker.Api
pnpm migrate      # = dotnet ef database update
```

> **`AddAuthentication` is destructive, on purpose.** It deletes the stub user that
> `InitialCreate` seeded — and `Habit.UserId` cascades, as does `Entry.HabitId` — so applying it to
> a database that predates auth drops **every habit and entry** in it. That is intended: those rows
> belong to an identity that no longer exists, and there is no honest way to guess which real
> account should inherit them. Take a `pg_dump` first if a pre-auth deployment holds anything worth
> keeping; a client that still has its local copy will repopulate the store on its first Sync after
> signing in.

## API

`/api/habits` — list / get / create / update / delete habits for the current user.
Enums serialize as strings (`"Positive"`, `"Success"`). Delete is a **soft-delete** (tombstone), so a
removed habit stops appearing but can still lose/win a sync merge.

`/api/sync` (POST) — one round-trip offline-first sync. The client submits its roster +
the month(s) it holds — alive rows and `deleted` tombstones, each carrying an `editedAt` (epoch
milliseconds UTC); the server merges per row **last-write-wins** by that edit-time and returns the
authoritative **alive** state to overwrite local with. Edit-time is stored verbatim as the merge
key, distinct from the server-stamped `UpdatedAt` audit field, which never reaches a client.
`Entry` `(HabitId, Date)`-keyed with `Outcome {Success, Failure}` is now exposed through sync. See
`HabitTracker.Api.http` for a sample.

A request whose newest `editedAt` runs more than five minutes ahead of the server clock is rejected
with `400` and merges nothing: an edit-time from a badly wrong clock would out-rank every later edit
until wall-clock caught up. Smaller drift merges normally and is logged as a warning.

### Auth

`/api/auth/signup` (POST, anonymous) — email + password + device name (+ invite code, required
once the `Users` table is non-empty). Returns the new user and a bearer token — signup logs you in.
The first user ever created needs no invite and becomes an admin.

`/api/auth/login` (POST, anonymous) — email + password + device name → user + bearer token. A
wrong email and a wrong password both answer the same generic `401`, so a caller can't enumerate
registered emails.

`/api/auth/logout` (POST) — deletes the calling session (the one the request authenticated with).

`/api/sessions` (GET) — the calling user's sessions, i.e. its linked devices. `DELETE
/api/sessions/{id}` — revokes one of the caller's own sessions; `404` for anyone else's.

`/api/invites` (POST, admin only) — mints a 7-day single-use invite code, returned once.

`/api/pairing` — the reMarkable's device-code pairing flow: `POST /code` (anonymous) issues a
6-character code the tablet displays and polls with `POST /poll` (anonymous) every few seconds. The
phone looks the code up with `GET /{code}` (authenticated) to see the requesting device's name, then
`POST /approve` (authenticated) to bind it to its account. The tablet's next poll after approval
returns a bearer token — the only time that token exists on the wire for this flow — and the code is
deleted in that same request, so a second poll on the same code reports it expired.

Every endpoint above except the four marked anonymous requires `Authorization: Bearer <token>`; a
missing or unknown token gets `401`. See [`CLAUDE.md`](./CLAUDE.md) for the auth layer's shape.
