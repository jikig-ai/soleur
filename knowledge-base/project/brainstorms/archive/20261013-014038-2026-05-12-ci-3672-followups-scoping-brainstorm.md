---
title: CI #3672 follow-ups scoping (bundle vs split)
date: 2026-05-12
status: complete
related_issues: [3692]
deferred_issues: [3693, 3694]
related_pr: 3709
parent_pr: 3672
parent_issue: 3680
lane: single-domain
brand_survival_threshold: none
---

# CI #3672 follow-ups scoping

## What We're Building

A scoping decision (not new code) over three open follow-up issues from the merged test-job restructure (PR #3672, merged 2026-05-12):

- **#3692** — Bun version probe for FPE-class re-evaluation (standalone measurement; `.bun-version` bump to test if FPE SIGFPE still fires on the latest 1.3.x patch)
- **#3693** — Suite-internal split of `apps/web-platform/test/` into sub-directories so `scripts/test-all.sh` can bin-pack future shard matrices more aggressively
- **#3694** — Apply the synthetic-aggregator shard pattern to the `e2e` job (~111s → ~65s)

## Why This Approach

**[Updated 2026-05-12 — plan-time pivot]:** Original decision was to bundle #3692 + #3693 and defer #3694. Plan-skill discovery revealed the webplat split is materially larger than the brainstorm anticipated (**355 top-level files in `apps/web-platform/test/`**, only ~28 in existing subdirs — a 200+ file refactor, not a "small companion commit"). Parent plan `2026-05-12-feat-ci-test-job-speedup-plan.md` had **explicitly deferred** #3693 to a conditional trigger ("test-webplat shard >100s sustained post-merge") that has zero data yet (parent #3672 merged today). Preemptively shipping a 200+ file refactor without the data the parent plan said should drive the decision is over-engineering.

Final decision: **probe only (#3692 alone) in PR #3709**. Both #3693 and #3694 remain open and gated on their own triggers.

The original framing in the feature description ("shared CI surface, possible ordering dependencies, aggregator wiring cleaner in one diff") did not survive inspection:

- Files touched are disjoint: `.bun-version` (probe), `apps/web-platform/test/` + `scripts/test-all.sh` (split), `.github/workflows/*` (e2e shard).
- #3693's issue body explicitly drops the bun-FPE dependency: `apps/web-platform` runs **Vitest (tinypool/threads), not Bun** — the spawn-count class does not apply.
- #3694 has a **time-based gate** the issue author wrote: "Re-evaluation trigger: ≥1 week post-merge with no regressions." Parent #3672 merged 2026-05-12 19:44 UTC. The gate cannot be met today.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope of this PR | **[Updated 2026-05-12]** Probe-only (#3692) | Plan-time discovery: 355 top-level webplat test files; parent plan deferred #3693 to a data-driven trigger; preempting it is over-engineering. Bundle calculus changed once the real scope was known. |
| #3693 disposition | **[Updated 2026-05-12]** Defer; restore parent plan's conditional trigger | Re-open with plan-time discovery note. Re-evaluate when `test-webplat` shard wall-clock data exists post-#3672 (matrix shard timings are emitted via `TEST_TIMING_LOG`). |
| #3694 disposition | Defer to own PR | Honors explicit ≥1-week post-#3672 stability gate (issue body). |
| Probe result handling | If FPE no longer fires on 1.3.14: keep `.bun-version` at 1.3.14, record finding in learnings, unlock `--max-pool-size` discussion for future work. If FPE still fires: revert `.bun-version` to 1.3.11 in the same commit and record the failing patch. | Probe is a measurement, not a unilateral version bump commitment. |
| Probe target version | **[Updated 2026-05-13]** Retargeted 1.3.13 → 1.3.14 after `npm view bun@latest version` returned 1.3.14 at work-skill execution time (precondition drift between plan-write and execution). | Phase 1 step 2 of the plan covers this drift path; retarget shipped as commit `7dd3950a`. |
| Regression-signal protection | Single-commit PR; full CI before merge | Addresses user-impact concern from Phase 0.1 (regression masked, slow feedback). Probe-only scope has the smallest possible blast radius. |

## Open Questions

- **Probe revert protocol:** **[Resolved 2026-05-12 — plan Phase 4b].** Plan defined the revert protocol (amend `.bun-version` back to 1.3.11 in the same commit, record failing patch in learnings, file next-probe issue). Did not fire on this probe (1.3.14 was clean).
- **Webplat sub-directory shape:** **[Deferred → #3693].** Plan-time discovery surfaced 355 top-level files in `apps/web-platform/test/`. Decision deferred to the next pickup of #3693; the three scoping options (minimal / cluster / full refactor) are captured in the table below.
- **#3694 re-evaluation timer:** **[Deferred → #3694].** Earliest re-evaluation 2026-05-19 per #3694's "≥1 week post-#3672 stability" gate; tracking via the issue comment on #3694.

## Approaches Considered

- **A — Keep separate, sequence by gate:** **[Updated 2026-05-12] CHOSEN.** Probe (#3692) ships now in PR #3709; #3693 + #3694 remain open under their own triggers.
- **B — Bundle #3692 + #3693, defer #3694:** Initially chosen, then dropped after plan-time discovery of 355 top-level files in `apps/web-platform/test/` and parent plan's data-driven deferral of #3693.
- **C — Bundle all three:** Rejected. Directly violates #3694's "≥1 week post-merge" gate.
- **D — Park all three:** Rejected. #3692 is fast and informative now; no reason to wait.

### Webplat split scoping options (now deferred under #3693)

Captured for the next time #3693 is picked up:

| Option | Files moved | Test-all.sh edits | Value |
|---|---|---|---|
| Minimal split (test-all.sh only) | 0 | 2-3 run_suite lines using vitest path filters (existing subdirs + top-level catch-all) | Finer labels, modest bin-pack value |
| Cluster split | ~100 (kb-*, ws-*, agent-runner-*, cc-*, soleur-go-runner-*) | Per-cluster run_suite | Real cohesion win; moderate diff |
| Full refactor | 250+ across ~10-15 new subdirs | Per-subdir run_suite | Closes #3693 fully; high review surface |

## Domain Assessments

**Assessed:** Engineering (lane=single-domain; other domains not relevant — pure CI infra with no UX, marketing, legal, sales, finance, support, ops surface).

### Engineering

**Summary:** Bundle scope is acceptable since files are disjoint and two-commit revert surgery is preserved. Probe-with-permanent-change is a mild rollback anti-pattern but bounded here because the webplat split has no informational dependency on the probe result (Vitest, not Bun). #3694 deferral is mandatory — its 1-week gate is unmet.

## User-Brand Impact

Not user-brand-critical. CI test infra is internal; the user's Phase 0.1 selection ("regression masked" + "slow feedback") is mitigated by:

- Each commit runs full CI before merge.
- Two-commit split keeps revert targets surgical.
- #3694's deferral (which was the highest blast-radius option) honors its own gate.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-12-chore-ci-bun-probe-plan.md. Branch: feat-ci-followups-scoping. Worktree: .worktrees/feat-ci-followups-scoping/. Issue: #3692. PR: #3709. Probe-only scope (single commit): bump .bun-version 1.3.11 → 1.3.14, observe CI for FPE-class regression on bun-test surfaces, revert + record on failure or keep + record on success. #3693 deferred to its parent-plan trigger (test-webplat shard >100s sustained). #3694 deferred to ≥2026-05-19.
```
