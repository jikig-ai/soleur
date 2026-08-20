---
title: "Tasks — orphan process reaper (#7537)"
branch: feat-one-shot-7537-orphan-process-reaper
issue: 7537
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-20-feat-orphan-process-reaper-deleted-cwd-conjunction-plan.md
---

# Tasks — orphan process reaper

Derived from the plan after the five-reviewer panel. Phase order is load-bearing: the mutation matrix is
written before the detector, because a matrix derived from finished code tests the code that exists rather than
the property.

## Phase 1 — the failing suite (RED)

- [ ] 1.1 Create `scripts/orphan-process-reaper.test.sh` with the `scripts/tmpfs-guard.test.sh` harness shape:
      `set -euo pipefail`, `pass()`/`fail()` that never move `cases`, `cases` incremented at each call site,
      fixtures under the suite's own `mktemp -d`.
- [ ] 1.2 Build the fixture builders. **A dangling symlink does NOT produce `nlink==0`** — `stat` fails, which
      G-fail counts as `unreadable`, so a naive fixture makes every positive arm pass for the wrong reason.
      Anchor-positive arms must point at a real unlinked inode: either a live process with a genuinely unlinked
      cwd, or a synthesized link to `/proc/<pid>/fd/N` held open on an unlinked file (measured `%h` = 0).
      Negative/structural arms may use live targets. Add the control arm that asserts a dangling-symlink
      fixture classifies `unreadable`, not as an anchor (AC30b).
- [ ] 1.3 Write the positive arms: the single orphan (AC1) and the three-process wrapper/child shape (AC2).
- [ ] 1.4 Write the negative arms: tmpfs-guard cron shape (AC3), `exe` (AC4), the `… (deleted)` directory
      (AC5), foreign mount namespace (AC6), the seven fail-toward-alive cases (AC7), age floor both
      directions (AC8), the empty-starttime fail-open (AC9), anchorless (AC10), self-exclusion at anchor and
      member scope (AC11), structural refusal (AC12), cardinality cap (AC13), wedged `git commit` (AC14).
- [ ] 1.5 Write the must-PASS non-canonical fixtures from the Guard Contract.
- [ ] 1.6 Add the accounting-conservation check and the absolute assertion floor, written as
      `if [[ "$cases" -lt <N> ]]` so `guard-vacuity-floor.test.sh` recognises the shape (AC31).
- [ ] 1.7 Confirm the suite FAILS — the script does not exist yet.

## Phase 2 — the detector

- [ ] 2.1 Create `scripts/orphan-process-reaper.sh`. Header states it reaps **processes** and is unrelated to
      `apps/web-platform/infra/orphan-reaper.sh`.
- [ ] 2.2 Declare seams, named `ORPHAN_PROC_ROOT` (never bare `PROC_ROOT`), plus `ORPHAN_REAPER_DRY_RUN`,
      `ORPHAN_REAPER_MIN_AGE_S`, `ORPHAN_REAPER_MAX_SET`, `ORPHAN_REAPER_SELF_PID`, the signal sink.
- [ ] 2.3 Set `TC_PROC_ROOT` and `TC_SELF_PID` from those seams **before** sourcing
      `scripts/lib/test-contention.sh`; add the `declare -F` assertion for `_tc_self_and_ancestors`,
      `_tc_pgrp`, `_tc_starttime_ticks` (AC26).
- [ ] 2.4 Implement `_orphan_is_unlinked <pid> <link>` via `stat -Lc '%h'` — exactly one site.
- [ ] 2.5 Implement `_orphan_classify` as the single chokepoint: G1 own-uid, G2 cwd unlinked, G3 fd/255
      unlinked, G4 self/ancestor/pgid, G5 mount namespace, G6 age floor, G-fail default.
- [ ] 2.6 Implement the walk with `[[ -d "$d" ]] || continue` and the `fd/255` pre-filter (AC25).
- [ ] 2.7 Explicit non-zero handling at every `readlink`/`stat` capture; validate every borrowed value against
      `^[0-9]+$` (AC24, AC9).
- [ ] 2.8 Phase 1 goes GREEN.

## Phase 3 — reap set, verbs, evidence

- [ ] 3.1 Reap-set expansion by shared unlinked cwd inode, with G2/G4/G5/G6 restated per member.
- [ ] 3.2 Scanner-inside-the-doomed-inode structural refusal → `valid=0` (AC12).
- [ ] 3.3 Cardinality cap → refuse whole set, count `refused_cap` (AC13).
- [ ] 3.4 `report` and `reap`; exit codes `0`/`1` only (AC16).
- [ ] 3.5 `reap`: children before anchor; re-verify gates, starttime and `st_nlink` at the signal site;
      `TERM` only, one pid at a time, no group, no escalation (AC17, AC18).
- [ ] 3.6 `ORPHAN_PROC_ROOT != /proc` refusal on `reap` unless a signal sink is injected (AC19).
- [ ] 3.7 journald record written before every signal; failed write refuses the reap (AC20).
- [ ] 3.8 Own non-blocking `flock`, exit 0 on contention; never `tc_acquire` (AC28).
- [ ] 3.9 Counter line with all fields; path sanitization via `tr -c '[:print:]'` (AC22, AC23).
- [ ] 3.10 Fail-safe dry-run parsing (AC21).

## Phase 4 — the mutation battery

- [ ] 4.1 Create `scripts/orphan-process-reaper-mutation.test.sh`.
- [ ] 4.2 Implement rows M1–M26; each copies the detector, applies ONE edit, runs the behavioural suite
      against the mutant, asserts it FAILS.
- [ ] 4.3 Each row first asserts the mutant DIFFERS from the original; a no-op edit is reported vacuous and
      fails the battery.
- [ ] 4.4 No mutation applied inside a command substitution (AC29).
- [ ] 4.5 Implement harness rows H1–H4, including H4 (procfs seam leak).
- [ ] 4.6 Confirm each row actually reddens.

## Phase 5 — registration and wiring

- [ ] 5.1 Measure the battery's wall-clock and record it (AC35).
- [ ] 5.2 Two `run_suite` lines in `scripts/test-all.sh` with neighbour-idiom comments (AC33).
- [ ] 5.3 Preamble invocation: `timeout 10 bash scripts/orphan-process-reaper.sh report || true`, verb pinned
      to `report`, banner emitted every run (AC34).
- [ ] 5.4 Comment-only note in `plugins/soleur/scripts/lib/proc.sh` + reciprocal in the reaper; no undefined
      ordinal cited (AC37).
- [ ] 5.5 Confirm `scripts/lint-orphan-test-suites.sh` and `scripts/guard-vacuity-floor.test.sh` pass
      (AC32, AC33).
- [ ] 5.6 Confirm `scripts/tmpfs-guard.sh` is unmodified and its suite passes (AC36).

## Phase 6 — end-to-end and the ADR

- [ ] 6.1 Implement the incident-trace arm (AC40): worktree removal → anchor → report with set + reap command
      → explicit reap → child before anchor → journald record per signal.
- [ ] 6.2 Live-procfs sanity: `report` exits 0, `valid=1`, `scanned > 0` (AC38).
- [ ] 6.3 Write the ADR. Re-derive the ordinal against freshly-fetched `origin/*` refs immediately before
      merge and sweep every artifact naming it in the same edit (AC39).
