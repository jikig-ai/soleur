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

- `tests/scripts/test-tmp-purge.sh`: 47/47 — classification ladder, quarantine
  on both bases, restore (bare + named), drain incl. arrival-time dwell,
  lock contention, retain-floor escalation, foreign-ns veto, owner_root
  cycle bound, live-fd retain, nested-.git retain, symlinked-qroot refusal.
- `tests/scripts/test-scratch-session.sh`: 42/42 — allocator shape/fd/marker,
  nested no-op, inherited-root survive, marker symlink refusal, Reaper 3
  dead/live/fail-closed arms, foreign-ns veto, environ/mmap/unix-socket
  liveness, nested-.git retain, tmpfs delete vs disk quarantine, arrival-time
  drain dwell, sweep telemetry/contention/defer incl. whole-arm timebox.
- `scripts/tmpfs-guard.test.sh`: 60/60 — Reaper 2 behavior unchanged.
- Session-start sweep on real `/var/tmp` (67k entries): ~5s wall, `wt_scanned=5`,
  `retained=5`, zero false reaps; `ms=` field emitted.

## First real dry-run (2026-09-24, pre-merge)

`bash scripts/soleur-tmp-purge.sh` on the live host — 5m27s for 88k entries
(dominated by per-entry classification + `du` on the actionable subset; the
per-entry subprocess cost was the first bug found and fixed — bulk `du`,
fork-free classify via `TC_*` globals, `tc_build_inuse_map` single `/proc`
pass).

| class | n | bytes (KB) |
|---|---|---|
| prefix:rung2-archive.* | 14,089 | 748,280 |
| prefix:gdboot.* | 7,837 | 26,016 |
| prefix:infra-suites.* | 3,216 | 81,912 |
| prefix:kbcov-* | 1,544 | 18,528 |
| prefix:gdpr-gate-incidents-* | 383 | 3,064 |
| prefix:soleur-inc-* | 452 | 16 |
| prefix:cron-filing-fixture-* | 117 | 936 |
| prefix:harness-discovery-* | 493 | 5,224 |
| file:inngest-arm-* | 4,748 | 18,304 |
| file:inngest-ci-*.sh | 2,374 | 61,616 |
| file:pr-*-body.md | 11 | 76 |
| empty | 2,556 | 0 |
| worktree:registered | 3 | 900,652 |
| worktree:unverifiable | 1 | 2,052,408 |
| protected | 26,036 | (not sized) |
| standalone-clone | 5,354 | (not sized) |
| unattributable | 19,000 | (not sized) |

## Post-merge (to fill after controlled backlog purge)

- [ ] Entries actually quarantined by `--apply`, per class
- [ ] `--drain` recovered bytes after TTL
- [ ] Session-start `SOLEUR_TMP_SWEEP` lines over the first week (ms, reaped)
- [ ] Re-run baseline counts after purge + one week of operation
