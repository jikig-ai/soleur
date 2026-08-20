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

- [x] 1.1 Create `scripts/orphan-process-reaper.test.sh` with the `scripts/tmpfs-guard.test.sh` harness shape:
      `set -euo pipefail`, `pass()`/`fail()` that never move `cases`, `cases` incremented at each call site,
      fixtures under the suite's own `mktemp -d`.
- [x] 1.2 Build the fixture builders. **A dangling symlink does NOT produce `nlink==0`** — `stat` fails, which
      G-fail counts as `unreadable`, so a naive fixture makes every positive arm pass for the wrong reason.
      Anchor-positive arms must point at a real unlinked inode: either a live process with a genuinely unlinked
      cwd, or a synthesized link to `/proc/<pid>/fd/N` held open on an unlinked file (measured `%h` = 0).
      Negative/structural arms may use live targets. Add the control arm that asserts a dangling-symlink
      fixture classifies `unreadable`, not as an anchor (AC30b).
- [x] 1.3 Write the positive arms: the single orphan (AC1) and the three-process wrapper/child shape (AC2).
- [x] 1.4 Write the negative arms: tmpfs-guard cron shape (AC3), `exe` (AC4), the `… (deleted)` directory
      (AC5), foreign mount namespace (AC6), the seven fail-toward-alive cases (AC7), age floor both
      directions (AC8), the empty-starttime fail-open (AC9), anchorless (AC10), self-exclusion at anchor and
      member scope (AC11), structural refusal (AC12), cardinality cap (AC13), wedged `git commit` (AC14).
- [x] 1.5 Write the must-PASS non-canonical fixtures from the Guard Contract.
- [x] 1.6 Add the accounting-conservation check and the absolute assertion floor, written as
      `if [[ "$cases" -lt <N> ]]` so `guard-vacuity-floor.test.sh` recognises the shape (AC31).
- [x] 1.7 Confirm the suite FAILS — the script does not exist yet.

## Phase 2 — the detector

- [x] 2.1 Create `scripts/orphan-process-reaper.sh`. Header states it reaps **processes** and is unrelated to
      `apps/web-platform/infra/orphan-reaper.sh`.
- [x] 2.2 Declare seams, named `ORPHAN_PROC_ROOT` (never bare `PROC_ROOT`), plus `ORPHAN_REAPER_DRY_RUN`,
      `ORPHAN_REAPER_MIN_AGE_S`, `ORPHAN_REAPER_MAX_SET`, `ORPHAN_REAPER_SELF_PID`, the signal sink.
- [x] 2.3 Set `TC_PROC_ROOT` and `TC_SELF_PID` from those seams **before** sourcing
      `scripts/lib/test-contention.sh`; add the `declare -F` assertion for `_tc_self_and_ancestors`,
      `_tc_pgrp`, `_tc_starttime_ticks` (AC26).
- [x] 2.4 Implement `_orphan_is_unlinked <pid> <link>` via `stat -Lc '%h'` — exactly one site.
- [x] 2.5 Implement `_orphan_classify` as the single chokepoint: G1 own-uid (`stat -Lc '%u'` — the `-L` is
      load-bearing), G2 cwd unlinked, G3 fd/255 unlinked **AND** absolute path ending `' (deleted)'` **AND**
      regular file (a memfd has `nlink 0`), G4 self/ancestor/pgid, G5 mount namespace, G6 age floor against
      `"$ORPHAN_PROC_ROOT"/uptime`, G7 pid namespace, G-fail default.
- [x] 2.5b Refuse to run as root (`EUID` 0). Check procfs by identity (`stat -fc '%T' == proc`), not by name.
      Validate the seam non-empty/absolute/directory before assigning `TC_PROC_ROOT`/`TC_SELF_PID`.
- [x] 2.6 Implement the walk with `[[ -d "$d" && ! -L "$d" ]] || continue` and the `fd/255` pre-filter,
      counting pre-filter misses as `prefiltered_no_fd255` separately from `unreadable_denied` /
      `unreadable_gone` (AC25, M35).
- [x] 2.7 Explicit non-zero handling at every `readlink`/`stat` capture; validate every borrowed value against
      `^[0-9]+$` (AC24, AC9).
- [x] 2.8 Phase 1 goes GREEN.

## Phase 3 — reap set, verbs, evidence

- [x] 3.1 Reap-set expansion by shared cwd **`dev:inode`** (`stat -Lc '%d:%i'`, never bare `%i`), with every
      gate restated per member — G4 on members is the suicide-bug fix.
- [x] 3.2 Scanner-inside-the-doomed-inode structural refusal → `valid=0` (AC12).
- [x] 3.3 Cardinality cap → refuse whole set, count `refused_cap` (AC13).
- [x] 3.4 `report` and `reap`; exit codes `0`/`1` only (AC16).
- [x] 3.5 `reap`: children before anchor; re-verify gates, starttime and `st_nlink` at the signal site; pid
      form `^[1-9][0-9]*$` with pid 1 refused; `kill -TERM -- "$pid"` quoted; no group, no escalation.
- [x] 3.6 `ORPHAN_PROC_ROOT != /proc` refusal on `reap` unless a signal sink is injected (AC19).
- [x] 3.7 journald mirror of the summary line on EVERY invocation of BOTH verbs (the layer-7 durability
      obligation), plus the authorizing record before every signal with verdict-first / cmdline-last field
      order; probe the channel at startup and report `evidence=ok|down`; a failed write refuses the reap.
- [x] 3.8 Own non-blocking `flock`, exit 0 on contention; never `tc_acquire` (AC28).
- [x] 3.9 Counter line with all fields; path sanitization via `tr -c '[:print:]'` (AC22, AC23).
- [x] 3.10 Fail-safe dry-run parsing (AC21).

## Phase 4 — the mutation battery

- [x] 4.1 Create `scripts/orphan-process-reaper-mutation.test.sh`.
- [x] 4.2 Implement rows M1–M36; each copies the detector, applies ONE edit, runs the behavioural suite
      against the mutant, asserts it FAILS. Run the unmutated control FIRST and abort the battery if it is
      not GREEN. Assert edit PLACEMENT (line inside the target function, exactly one line changed), not just
      that the file differs.
- [x] 4.3 Each row first asserts the mutant DIFFERS from the original; a no-op edit is reported vacuous and
      fails the battery.
- [x] 4.4 No mutation applied inside a command substitution (AC29).
- [x] 4.5 Implement harness rows H1, H1b (`fail()` increments `pass_n`), H2, H3, H4 (procfs seam leak), H5
      (forced `exit 0`), plus the assertion-helper positive control that calls `pass()` and `fail()` once each
      and verifies both counters moved.
- [x] 4.7 Record the failing-arm-label set per mutant and assert pairwise non-identical and non-subset — this
      is what makes "the rows span distinct axes" a check rather than prose.
- [x] 4.6 Confirm each row actually reddens.

## Phase 5 — registration and wiring

- [x] 5.1 Measure the battery's wall-clock and record it (AC35).
- [x] 5.2 Two `run_suite` lines in `scripts/test-all.sh` with neighbour-idiom comments (AC33).
- [x] 5.3 Preamble invocation: `timeout 10 bash scripts/orphan-process-reaper.sh report || true`, verb pinned
      to `report`, banner emitted every run; caller captures rc and prints `ORPHAN_SCAN valid=0 reason=rc<N>`
      itself on non-zero/124; caller passes `ORPHAN_REAPER_EXCLUDE_PGID`; skip under `CI` with one line.
- [x] 5.4 Comment-only note in `plugins/soleur/scripts/lib/proc.sh` + reciprocal in the reaper; no undefined
      ordinal cited (AC37).
- [x] 5.5 Confirm `scripts/lint-orphan-test-suites.sh` and `scripts/guard-vacuity-floor.test.sh` pass
      (AC32, AC33).
- [x] 5.6 Confirm `scripts/tmpfs-guard.sh` is unmodified and its suite passes (AC36).

## Phase 6 — end-to-end and the ADR

- [x] 6.1 Implement the incident-trace arm (AC40): worktree removal → anchor → report with set + reap command
      → explicit reap → child before anchor → journald record per signal.
- [x] 6.2 Live-procfs sanity: `report` exits 0, `valid=1`, `scanned > 0` (AC38).
- [x] 6.3 Write the ADR. Re-derive the ordinal against freshly-fetched `origin/*` refs immediately before
      merge and sweep every artifact naming it in the same edit (AC39).

## Deviations from the plan, recorded rather than silently absorbed

- **2.5 / G1 placement.** The plan puts the own-uid gate inside
  `_orphan_classify` as `stat -Lc '%u'`. Measured against a real `/proc`, that
  gate counted **zero**: a foreign process's `/proc/<pid>/fd` is mode 500, so
  the `fd/255` pre-filter rejects it first and the gate was unreachable in
  production — a guard that could not fire, which is the class this whole change
  exists to avoid. Ownership now sits ONCE in the walk, ahead of the pre-filter,
  as a fork-free `[[ -O ]]` so it can run for every pid on a ~600-pid hot path.
  Live proof from a real runner launch: `skipped_foreign_uid=371` of
  `scanned=577`, where the plan's placement measured 0.

- **M16 / M27 / M36 are not mutation rows.** The battery refuses multi-line
  edits by construction, and these three cannot be expressed as one:
  - M27 (evidence written after the signal) is a source-ORDER property; it is
    asserted directly against `signal_one`'s span instead.
  - M36 (caller stops emitting on a non-zero rc) lives in `scripts/test-all.sh`,
    not in the detector the battery mutates; it is asserted against the
    preamble's source.
  - M16 (reap set derives its own predicate) collapses onto M1 in this
    implementation — both make an anchorless fixture flag — so it is not carried
    as a second spelling of one axis.

- **AC30 subset clause.** The plan asks for pairwise non-identical AND
  non-subset failing-arm sets. IDENTICAL is enforced and fails the battery — it
  is the duplicate-detection the criterion exists for, and it caught M7≈M17.
  Proper SUBSET is reported, not failed: across 36 rows spanning catastrophic
  and narrow mutations, a narrow row legitimately reddens fewer arms than a
  broad one, and requiring non-subset would force either fewer rows or
  artificially broadened fixtures.

- **AC35 budget.** Measured 75-90s wall-clock for 36 rows at `-P6`, inside the
  120s ceiling. Rows are independent (own copy, own temp dir, own fixtures) and
  a row's verdict is its suite's exit status, which concurrency does not change;
  wall-clock is affected, and that is why the degree is stated with the number.
  Serial cost is ~36 x 10.5s.
