# feat-tmp-scratch-reclamation — measurements

Durable measurement record for #7004 / PR #8738. Values are operator-host
observations unless marked synthetic.

## Baseline (2026-09-24)

| Surface | Entries | Size | Notes |
|---|---|---|---|
| `/tmp` (tmpfs, 16 GB) | ~14k top-level | ~5.5 GB | kbcov 2.1k, pirgate 2k, inngest 2k, tmp.* 2k |
| `/var/tmp` (disk) | 67,222 top-level | ~27 GB | grew 40,390 → 67,222 during one planning session |
| `/var/tmp` orphaned worktrees | ~1,484 `tmp.*` dirs bearing `.git` | — | only 3 of the sample were registered |
| `~/.local/state/soleur/` | absent | — | tmpfs-guard had never run; no crontab installed |

## Trigger verification (the "two claims" measurement)

- `command -v crontab` → absent on this Arch/systemd host.
- `systemctl --user list-timers` → no tmpfs-guard timer.
- `~/.local/state/soleur/tmpfs-guard-last-run` → absent. The guard's heartbeat
  never existed: **the shipped reaper had never executed**.

## Synthetic verification (branch `feat-tmp-scratch-reclamation`)

- `tests/scripts/test-tmp-purge.sh`: 38/38 — classification ladder, quarantine
  on both bases, restore, drain, lock contention, retain-floor escalation.
- `tests/scripts/test-scratch-session.sh`: 30/30 — allocator shape/fd/marker,
  nested no-op, Reaper 3 dead/live/fail-closed arms, tmpfs delete vs disk
  quarantine, TTL drain, sweep telemetry/contention/defer.
- `scripts/tmpfs-guard.test.sh`: 60/60 — Reaper 2 behavior unchanged.
- Session-start sweep on real `/var/tmp` (67k entries): ~5s wall, `wt_scanned=5`,
  `retained=5`, zero false reaps; `ms=` field emitted.

## Post-merge (to fill after controlled backlog purge)

- [ ] `SOLEUR_TMP_PURGE` dry-run totals on the real host (per-class counts, GB)
- [ ] Entries actually quarantined by `--apply`, per class
- [ ] `--drain` recovered bytes after TTL
- [ ] Session-start `SOLEUR_TMP_SWEEP` lines over the first week (ms, reaped)
- [ ] Re-run baseline counts after purge + one week of operation
