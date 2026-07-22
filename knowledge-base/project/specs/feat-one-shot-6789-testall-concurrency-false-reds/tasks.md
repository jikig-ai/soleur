---
title: "Tasks — parallel-worktree test-all.sh contention (#6789)"
date: 2026-07-22
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-22-fix-testall-worktree-contention-plan.md
issue: 6789
---

# Tasks — fix parallel-worktree `test-all.sh` contention (#6789)

Derived from [the plan](../../plans/2026-07-22-fix-testall-worktree-contention-plan.md). Read the plan's `## Hypotheses` and `## Research Insights` before starting — several obvious-looking implementations are explicitly ruled out there with measurements.

## Phase 0 — Preconditions

- [ ] 0.1 Re-measure the baseline on the current machine; the plan's numbers were taken 2026-07-22 and will drift: `df -h /tmp`, `ls /tmp | wc -l`, `du -sh /tmp/* | sort -rh | head`, `ls -d "${XDG_RUNTIME_DIR:-/tmp}"/skill-security-scan-* | wc -l`.
- [ ] 0.2 Confirm `flock` is present (`command -v flock`) and read `.claude/hooks/lib/session-state.sh` — specifically `_session_state_root`, `_acquire_lock_impl`, `acquire_lock`, `release_lock`, `with_lock`.
- [ ] 0.3 Confirm the `run_suite` registration convention in `scripts/test-all.sh` (suites are enumerated by hand; `scripts/*.test.sh` is NOT auto-globbed).

## Phase 1 — Instrumentation (must ship ahead of every fix below)

**Ordering is load-bearing.** Commit Phase 1 without any cleanup or locking change. See the plan's Sharp Edges on probe-first ordering.

- [ ] 1.1 Add a contention preamble to `scripts/test-all.sh`, before the first `run_suite`: `/tmp` + `$XDG_RUNTIME_DIR` headroom; sibling `test-all.sh` processes resolved to worktrees via `/proc/<pid>/cwd`; `nproc`, loadavg, `MemAvailable`, swap free.
- [ ] 1.2 Add an epilogue recording whole-run `/tmp` entry-count and byte delta; append a per-suite delta to the **existing** `TEST_TIMING_LOG` channel (extend the record — do not invent a second mechanism). This per-suite delta is the probe for hypothesis H4.
- [ ] 1.3 Emit a clearly-marked banner naming **which** condition fired (low headroom / sibling detected). Fail loud and attributable; never silent.
- [ ] 1.4 Verify: `bash scripts/test-all.sh scripts 2>&1 | head -20` shows the preamble before the first `--- <suite> ---` line. (AC1)

## Phase 2 — Recover and bound the headroom

Priority follows measured bytes, not entry count.

- [ ] 2a.1 Extend `scripts/tmpfs-guard.sh` beyond `.output`-only to reap stale, large, own-uid `/tmp` scratch entries. Gate on **age AND size AND ownership** — never one dimension (R3).
- [ ] 2a.2 Preserve the guard's existing `fuser` active-handle respect and usage-percentage escalation; do not duplicate or contradict `cleanup_claude_tmp` in `worktree-manager.sh`, which owns the running-session boundary.
- [ ] 2b.1 Bound the `meta_dir` leak in `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` by **age-reaping older siblings at startup**. **Do NOT add an `EXIT` trap** — `.scan-meta.json` is deliberately persisted for the GDPR Art. 32 override mechanism (R1). The artifact the current process just wrote must always survive.
- [ ] 2b.2 Verify `run-scan.sh` still prints `.scan-meta.json written to: <path>` and the file exists **after** exit. (AC8)
- [ ] 2c.1 Use the Phase 1.2 per-suite delta to identify the escape path for the measured +2 `skill-scan-*` artifacts per run before changing the trap at `run-scan.sh:95`. Do not guess the mechanism.
- [ ] 2d.1 Re-run `python3 scripts/lint-trap-tempfile-ownership.py --census` and lower `scripts/lint-trap-tempfile-ownership.highwater` to match. Do **not** attempt to pay off the ~100 accepted files (ADR-129 documents why that switches the gate off). (AC7)

## Phase 3 — Advisory, self-announcing queue

- [ ] 3.1 Source `.claude/hooks/lib/session-state.sh` from `scripts/test-all.sh` and call `acquire_lock` **internally**. Reuse the primitive; write no new lock and modify nothing shared.
- [ ] 3.2 On timeout, **proceed with a banner — never abort.** This is the load-bearing safety property.
- [ ] 3.3 Source the `waiting on <worktree> (pid N, running Xs)` announcement from the Phase 1 sibling scan, not from the lock file (the primitive writes no holder metadata). Refresh during the wait.
- [ ] 3.4 Size the timeout to a full suite duration, not `with_lock`'s 30 s default.
- [ ] 3.5 Skip acquisition when `CI` is set.
- [ ] 3.6 Do **not** implement stale-holder detection — `flock` auto-releases on holder death (measured). Assert the property instead.
- [ ] 3.7 Write the lock `.test.sh` covering the 7 Test Scenarios in the plan, **including the positive control** that the probe command is valid against a free lock. Mutation-test every arm.
- [ ] 3.8 Register the new suite with an explicit `run_suite` line and confirm `bash scripts/lint-orphan-test-suites.sh` passes. (AC10)

## Phase 4 — Correct the recorded attribution

- [ ] 4.1 Rewrite the sibling-worktree contention paragraph in `plugins/soleur/skills/work/SKILL.md` (the "Sibling-worktree contention produces a FALSE RED" block). Drop both refuted causes; name the real mechanism; point at the Phase 1 banner and Phase 3 queue instead of the `ps` ritual.
- [ ] 4.2 Keep the paragraph's correct halves: confirm-three-ways before accepting "flake"; never delete another session's `/tmp` artifacts.
- [ ] 4.3 Verify by asserting the **presence** of the corrected mechanism sentence — not by an absence-grep for the old tokens, which the corrected prose legitimately still mentions while explaining the refutation. (AC6)
- [ ] 4.4 Write the learning: *a documented cause is a claim with an author and a date, not a fact.* Directory + topic only — pick the date at write time; do not reuse this plan's date.

## Phase 5 — ADR

- [ ] 5.1 `git fetch origin main` first, then derive the next free ordinal from `origin/main` (provisional; `/ship` re-verifies). ADR-133 was free at plan time.
- [ ] 5.2 Author the ADR. Record both refuted hypotheses (H1 semgrep-unreachable, H2 PID-scoped-since-birth) with their discriminators in `## Alternatives Considered`. (AC11)
- [ ] 5.3 If renumbered, sweep the whole feature artifact set in the same edit: `grep -rn 'ADR-133' knowledge-base/project/{plans,specs}/` — plan, tasks, and any AC naming the ordinal.

## Phase 6 — Exit gate

- [ ] 6.1 Full-suite run from the worktree root: `cd <worktree> && bash scripts/test-all.sh`. Capture `rc=$?` and grep the log for the summary line — a backgrounded runner can report exit 0 with a real failure.
- [ ] 6.2 Confirm the suite count matches pre-change (no suite dropped or double-registered). (AC9)
- [ ] 6.3 Re-measure `/tmp` headroom and confirm the recovery is real, not inferred.
