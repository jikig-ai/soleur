---
title: Review panel scales to the declared risk tier; fix commits get targeted seats
status: active
date: 2026-10-01
issue: 9399
related: [9339, 9412]
related_adrs: [ADR-127, ADR-053, ADR-084]
tags: [review, one-shot, plan, panel-scaling, cost]
brand_survival_threshold: none
---

# ADR-267: Review panel scales to the declared risk tier; fix commits get targeted seats

## Context

The review skill ran a fixed 11+ seat panel on every diff regardless of blast radius. PR #9339 — a small disk-leak fix — incurred the full panel, then multiple fix rounds each re-incurring broad review, totalling ~8 CI cycles. Two structural gaps compounded the cost: (a) the `brand_survival_threshold` declared at plan time never reached the review phase, so review had no signal to scale by; (b) post-panel fix commits — measured as the least-audited surface in the pipeline — had no re-review contract at all, so they got either zero review or an ad-hoc full re-panel.

## Decision

1. **One tier enum, no new vocabulary.** Review resolves the plan's `brand_survival_threshold` enum (`none` / `single-user incident` / `aggregate pattern`; `undeclared` is a parse state, never emitted) in order: PR body → linked plan → `undeclared`. The resolution is fail-closed: a `SENSITIVE_PATH_RE` diff that is `undeclared` — or `none` without an explicit `reason:` scope-out — clamps to `single-user incident`, and sensitive diffs always carry `security-sentinel` (mirrors preflight Check 6). Review never spawns fewer seats than declared; an over-declared tier is reported as `tierMismatch`, not silently down-tiered.
2. **Panel scaling** (`references/risk-tier-and-fix-rounds.md` is the normative table; `review.workflow.js` implements `resolveTier`/`scaleAlwaysOn`; `plugins/soleur/test/review-tier-parity.test.ts` pins all three copies): at `none`, the three broad always-on seats {data-integrity, agent-native, performance} are trigger-gated on their path-map surfaces; the floor seats never shed. `single-user incident` adds `user-impact-reviewer`; `aggregate pattern` adds it plus `SKEPTICS=3` and the mandatory design-validity pass.
3. **One map, two consumers.** `skills/review/scripts/fix-round-seats.sh` is the single committed path→seat map: it defines both the `none`-tier trigger predicates AND the seat set for a post-panel fix round ({reporting seats} ∪ {path-mapped seats} ∪ {conditional seats}; `code-quality-analyst` floor on unmatched source; `--finding-seats` registry-validated). Targeted rounds are report-only, capped at two before escalating to the full panel, and end with exactly one verification pass; `soleur:one-shot` Step 5 invokes `soleur:review <PR> --fix-round` after resolver commits.
4. **Reporting.** Reviews announce `Tier: <v> (source: …)` and record seats spawned vs tier; `emit-review-trailer.sh --risk-tier` emits `Reviewed-Risk-Tier:` with NO consumer (the ADR-127 argument — the field is recorded because retrofitting a key already in main's history is the expensive part). A fix-round trailer attests `Reviewed-Coverage: full` over the fix range only. Findings are deduped across seats into a canonical-defect ledger before any fix dispatch.
5. **Plan-side.** `plan-issue-templates.md` gains a `**Threshold decision (challengeable):**` line making the threshold explicit and disputable; challenges route to the ADR-084 `decision-challenges.md` channel.

## Consequences

- `none`-tier code diffs spawn a smaller panel; cheap classes (lockfile-only, non-code) are unchanged.
- Fix commits now get deterministic re-review instead of none-or-everything; the two-round cap prevents a targeted-review treadmill.
- `resolve-pr-parallel` wiring is deferred (follow-up #9412); the trailer field has no consumer by design.
- Three copies of the contract (reference table, workflow gating, shell map) are pinned by `review-tier-parity.test.ts`; a fourth `SENSITIVE_PATH_RE`/`GDPR_PATH_RE` literal lives in `fix-round-seats.sh` and is byte-pinned to the canonical sources.
