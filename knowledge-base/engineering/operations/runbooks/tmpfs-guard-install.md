# tmpfs-guard install runbook

`scripts/tmpfs-guard.sh` reaps oversized `.output` files, stale large scratch
entries on `/tmp` (Reaper 2), and orphaned `soleur-run.*`/`.soleur-owned` roots
on both `/tmp` and `/var/tmp` (Reaper 3, #7004). It needs a **trigger** to do
any of that — the script is inert until something runs it.

This runbook covers three trigger options. **All are optional and manual** —
host-level scheduling is an operator preference and is deliberately NOT
automated by the repo.

## Option 1 — systemd user timer (recommended on systemd hosts)

The repo ships `scripts/tmpfs-guard.service` and `scripts/tmpfs-guard.timer`.

```bash
mkdir -p ~/.config/systemd/user
ln -sf "$PWD/scripts/tmpfs-guard.service" ~/.config/systemd/user/
ln -sf "$PWD/scripts/tmpfs-guard.timer"  ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tmpfs-guard.timer
systemctl --user list-timers tmpfs-guard.timer   # verify
```

The shipped unit assumes the checkout is `~/soleur`. If it lives elsewhere:

```bash
systemctl --user edit tmpfs-guard.service
# [Service]
# WorkingDirectory=/path/to/soleur
# ExecStart=
# ExecStart=/path/to/soleur/scripts/tmpfs-guard.sh
```

**Headless hosts**: user timers stop when the last session ends unless linger
is enabled:

```bash
loginctl enable-linger "$USER"
```

## Option 2 — cron (where cron exists)

```cron
*/5 * * * * /path/to/soleur/scripts/tmpfs-guard.sh
```

Verify `crontab` is installed first — on Arch/systemd boxes it typically is
not, which is exactly how the original guard silently never ran.

## Option 3 — session-start fallback (always on)

`worktree-manager.sh cleanup-merged` runs `sweep_orphan_scratch_dirs` at every
session start, before the repo lock and the fetch gate. It covers the Reaper 3
surface (dead `soleur-run.*`/marker dirs + a bounded worktree batch) but NOT
Reaper 2's large-entry reap — the timer/cron remains the only trigger for that.

## Verification

- The guard writes a heartbeat to
  `~/.local/state/soleur/tmpfs-guard-last-run` on every completed run —
  `stat` its mtime to confirm the trigger fires.
- Alarms land in `~/.local/state/soleur/tmpfs-guard-alarms.log` (surfaced at
  SessionStart).
- All three consumers serialize on
  `~/.local/state/soleur/tmp-guard.lock` — a contended run skips loudly rather
  than queueing.

## Quarantine drain & restore

Every moved entry lands in `<base>/soleur-quarantine.<uid>/<class>/` and is
recorded in `~/.local/state/soleur/tmp-purge-ledger.log` (action, class,
origin, quarantine path — Reaper 3, the session sweep, and the operator purge
all write this one ledger, so `--restore` sees every move).

- **Drain** (delete quarantine entries past their class TTL — scratch 7d,
  worktrees 30d; dwell counts from quarantine *arrival*, not content age):
  `bash scripts/soleur-tmp-purge.sh --drain`
  The installed timer/service drains on every run; without a trigger the
  session-start sweep prints a "quarantine holds entries" note instead.
- **Restore** (undo a quarantine move before drain):
  `bash scripts/soleur-tmp-purge.sh --restore <basename>` or `--restore` (all).
- **Inspect**: `bash scripts/soleur-tmp-purge.sh --dry-run` reports class
  counts and bytes; `SOLEUR_PURGE_BASES="…"` scopes the scan.
