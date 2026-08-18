# 1. Suspend-image writing is opt-in, with backup on enable and restore on disable

Status: accepted

Amended by [ADR 0008](0008-private-habits.md): the per-habit control this ADR describes as hidden
while the setting is off is now the always-visible Private toggle.

## Context

The app overwrites the device suspend image (`/usr/share/remarkable/suspended.png`) with
the habit grid. Originally this was always on: the original image was backed up to
`suspended.png.bak` on first launch (gated by a `.backup-done` marker file so startup didn't
read a screen-sized PNG), and there was no way to turn the overwrite off or get the stock
image back from inside the app.

Two problems: the feature was forced on every install, and disabling/recovering required SSH.

## Decision

Suspend-image writing is an **opt-in setting** (`settings.json`, `suspendImageEnabled`),
exposed on a Settings page. Default **off**.

- The setting, not a marker file, is the source of truth. The `.backup-done` marker and the
  launch-time `ensureBackup` are removed.
- **Backup is tied to the enable transition, not to launch.** Enabling backs up the current
  `suspended.png` → `.bak`, then writes the grid. If the backup fails, the enable is aborted
  (setting not persisted, grid not written) so we never clobber an unrecoverable original.
- **Disabling restores** `.bak` → `suspended.png` and invalidates the persisted render
  signature (otherwise the dedup check would skip the re-render on a later enable).
- All automatic render/save triggers are gated on `suspendImageEnabled`. While off, the
  per-habit `Z` (suspend visibility) controls are hidden.

  > Superseded by [ADR 0008](0008-private-habits.md): suspend visibility became the synced
  > Private flag, and its edit-mode toggle is no longer gated on this setting — it is always
  > visible.

## Consequences

- Fresh installs write nothing to the suspend image and take no backup until the user opts in
  — the headline overlay is now a choice, not a default.
- Backup/restore run only on deliberate user actions, so there is no per-launch cost and no
  marker file to maintain.
- Recovery of the stock image is in-app (toggle off) rather than SSH-only. Uninstalling still
  does not restore it; toggle off first or copy `suspended.png.bak` back manually.
