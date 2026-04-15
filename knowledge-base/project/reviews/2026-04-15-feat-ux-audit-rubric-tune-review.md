---
branch: feat-ux-audit-rubric-tune
date: 2026-04-15
agents: [git-history-analyzer, pattern-recognition-specialist, security-sentinel, code-quality-analyst]
related_issues: [2378, 2341, 2342]
---

# Code Review: feat-ux-audit-rubric-tune

4 agents ran in parallel (non-code classification: yaml + markdown + workflow only). No P1 blockers. Summary of P2/P3 findings and how each was handled.

## P1 — None

## P2 — Addressed in this commit

- **Terminology: "global cap" was ambiguous in Step 6** (code-quality). The sentence "per-route cap runs before the global cap" could be mis-read as referring to `CAP_OPEN_ISSUES` (the actual global cap from Step 2). Changed to "runs before `CAP_PER_RUN`" and added a parenthetical clarifying that `CAP_OPEN_ISSUES` is a separate check.
- **Threshold ambiguity: 240 vs 280 in real-estate rubric** (code-quality). The strengthened category mentioned both "280px example" and "≥ 240px flagging threshold" in the same paragraph, which could confuse. Re-worded into a "Minimum severity floor" clause that explicitly states 240px is the threshold while 280px is the illustrative example for the category.

## P2 — Deferred with justification

- **Audit-specific policy embedded in shared ux-design-lead rubric** (pattern-recognition-specialist, echoed by git-history-analyzer). The `### 5-category rubric` section sits under `## UX Audit (Screenshots)`, so the scoping is bounded — other invocations (`.pen` design, HTML audits) read their own sections. Moving the severity floor from the rubric into the audit skill's delegation prompt would reduce coupling but is a larger refactor. The bounded scoping holds; if a future MISS shows the bleed, we refactor then. **Why now:** This is the ONE tune allowed per plan #2341 Phase 3. Shipping the scoped fix preserves the plan's budget; a refactor would be a separate PR.

- **Monitor dedup insight** (code-quality). The learning documents that Monitor-tool polling filters should dedup identical consecutive outputs. Per rule `wg-every-session-error-must-produce-either`, this deserves a durable skill edit rather than living only in a learning file. **Why now:** The rule `hr-never-use-sleep-2-seconds-in-foreground` already prescribes Monitor for polling; adding a dedup sub-rule is a narrow doc change that touches AGENTS.md. Tracking as a follow-up rather than expanding this PR's scope.

## P3 — Acknowledged, not addressed

- `workflow_dispatch: {}` vs `workflow_dispatch:` — cosmetic YAML style, no functional difference. Current form is valid.

## Strategic finding (git-history-analyzer)

Two learnings in one day on the `soleur:ux-audit` skill (the first on scope-cutting/review-hardening, this one on calibration MISS path) suggests rubric calibration itself is the unstable surface. Recommendation: if a third calibration attempt misses, build the deferred golden-set test gate (#2352) before tuning the rubric further. Tuning without a deterministic test loop means every calibration run is a one-shot subjective judgment.

## Security

`security-sentinel` found no issues. Hardcoded `UX_AUDIT_DRY_RUN: 'true'` has no interpolation risk, no dangling `inputs.dry_run` references remain, route reorder introduces no new paths, agent rubric wording contains no secret patterns or injection vectors.
