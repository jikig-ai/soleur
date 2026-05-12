---
title: CI #3672 follow-ups scoping (bundle vs split)
date: 2026-05-12
status: complete
related_issues: [3692, 3693, 3694]
related_pr: 3709
parent_pr: 3672
parent_issue: 3680
lane: single-domain
brand_survival_threshold: internal-only
---

# CI #3672 follow-ups scoping

## What We're Building

A scoping decision (not new code) over three open follow-up issues from the merged test-job restructure (PR #3672, merged 2026-05-12):

- **#3692** — Bun version probe for FPE-class re-evaluation (standalone measurement; `.bun-version` bump to test if FPE SIGFPE still fires in 1.3.11, then revert)
- **#3693** — Suite-internal split of `apps/web-platform/test/` into sub-directories so `scripts/test-all.sh` can bin-pack future shard matrices more aggressively
- **#3694** — Apply the synthetic-aggregator shard pattern to the `e2e` job (~111s → ~65s)

## Why This Approach

User chose to bundle **#3692 + #3693** into one PR and defer **#3694** to its own PR.

The original framing in the feature description ("shared CI surface, possible ordering dependencies, aggregator wiring cleaner in one diff") did not survive inspection:

- Files touched are disjoint: `.bun-version` (probe), `apps/web-platform/test/` + `scripts/test-all.sh` (split), `.github/workflows/*` (e2e shard).
- #3693's issue body explicitly drops the bun-FPE dependency: `apps/web-platform` runs **Vitest (tinypool/threads), not Bun** — the spawn-count class does not apply.
- #3694 has a **time-based gate** the issue author wrote: "Re-evaluation trigger: ≥1 week post-merge with no regressions." Parent #3672 merged 2026-05-12 19:44 UTC. The gate cannot be met today.

So the bundle is a workflow ergonomics choice (one review cycle instead of two), not a structural coupling. Two-commit split inside one PR preserves revert surgery.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope of this PR | Bundle #3692 + #3693 | One review cycle; files disjoint; revert surgery preserved via two commits |
| #3694 disposition | Defer to own PR | Honors explicit ≥1-week post-#3672 stability gate (issue body) |
| Commit shape inside bundle | Two commits: (1) bun probe + result note, (2) webplat split | Independent revertability — if probe fails, webplat split still ships |
| Probe result handling | If FPE no longer fires: keep `.bun-version` bump, record finding in learnings, unlock `--max-pool-size` discussion for future work. If FPE still fires: revert `.bun-version` and record finding | Probe is a measurement, not a unilateral version bump commitment |
| #3693 trigger threshold | Apply regardless of post-#3672 timing | User chose to ship preemptively rather than wait for empirical >100s observation. Tradeoff accepted; minor over-engineering risk noted |
| Regression-signal protection | Each commit isolated; CI runs both before merge | Addresses user-impact concern from Phase 0.1 (regression masked, slow feedback) |

## Open Questions

- **Probe revert protocol:** If `bun test plugins/soleur/` (~25 .test.ts) or `bun test test/` (~3 named) re-triggers FPE on 1.3.11, do we leave `.bun-version` at 1.3.5 or fall back to a stable patch between 1.3.5 and 1.3.11? Plan skill should make this decision based on Bun's changelog scan.
- **Webplat sub-directory shape:** Issue #3693 suggests `auth/`, `kb/`, `sandbox/` as example sub-dirs. Actual sub-suite boundaries should reflect cohesion in the current 20 `.test.ts` files (`accept-terms`, `agent-env`, `bash-sandbox`, `byok`, `callback`, `csp`, `kb-*`, `middleware`, `sandbox*`, `security-headers`, `share-*`, `shared-*`, `tc-version`). Plan-time decision.
- **#3694 re-evaluation timer:** Track via a calendar entry / scheduled check rather than waiting for ad-hoc memory.

## Approaches Considered

- **A — Keep separate, sequence by gate:** Three PRs, each gated on its own trigger. Lowest blast radius. *Rejected:* user prefers single review cycle for #3692+#3693.
- **B — Bundle #3692 + #3693, defer #3694:** **CHOSEN.** Probe + webplat split together; e2e shard deferred to honor its 1-week stability gate.
- **C — Bundle all three:** Rejected. Directly violates #3694's "≥1 week post-merge" gate. Maximum blast radius; rollback profile mixes probe + two permanent changes.
- **D — Park all three:** Rejected. #3692 is fast and informative now; no reason to wait.

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
/soleur:plan #3692 #3693 — Bundle bun probe + webplat test/ split. Brainstorm: knowledge-base/project/brainstorms/2026-05-12-ci-3672-followups-scoping-brainstorm.md. Spec: knowledge-base/project/specs/feat-ci-followups-scoping/spec.md. Branch: feat-ci-followups-scoping. Worktree: .worktrees/feat-ci-followups-scoping/. PR: #3709. Plan two commits: (1) .bun-version bump + bun-test probe with revert protocol, (2) apps/web-platform/test/ sub-directory split + scripts/test-all.sh per-sub-dir run_suite lines. #3694 deferred until ≥2026-05-19 post-#3672 stability check.
```
