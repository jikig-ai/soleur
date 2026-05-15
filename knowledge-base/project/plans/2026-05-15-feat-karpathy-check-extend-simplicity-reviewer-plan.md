---
title: karpathy-check — extend code-simplicity-reviewer
date: 2026-05-15
issue: 2727
parent_issue: 2718
branch: feat-karpathy-check-2727
pr: 3784
lane: single-domain
brand_survival_threshold: none
semver: patch
status: plan-ready
---

# Plan — karpathy-check (extend code-simplicity-reviewer)

## Overview

Extend the existing `code-simplicity-reviewer` agent body with one new review-process bullet ("Verify Stated Goals Against Diff") and two new output-format sections (`### Hidden Assumptions`, `### Goal Verification`). Fold the Hidden Assumptions audit sub-bullets into the existing process bullet #4 (Challenge Abstractions). Extend the 2026-05-03 prior-art learning with an Audit Direction section.

The agent is invoked from at least five surfaces today — `/soleur:review` section 4 (line 380-382), the CONCUR-gate at SKILL.md:502-524, `/soleur:plan-review`'s 3-agent panel, `/soleur:work` final validation, and opportunistic spawns in `atdd-developer` + `compound`. Several of these invocations do NOT pass a diff. The new bullet's instruction text MUST include an explicit fallback string (`_N/A — no diff in scope._`) for off-diff contexts.

## User-Brand Impact

**If this lands broken, the user experiences:** review-friction-only noise — extra empty sections in `code-simplicity-reviewer` output, or low-signal hallucinated content when invoked without a diff.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — internal review tooling, no production path.

**Brand-survival threshold:** none.

## Files to Edit

1. `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md`
2. `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md`

## Files to Create

None.

## Edits

### code-simplicity-reviewer.md

- Extend existing bullet `4. Challenge Abstractions` with two sub-bullets: "Surface unstated invariants the diff silently relies on" and "Flag magic numbers and implicit callsite contracts without inline justification."
- Insert new bullet `7. Verify Stated Goals Against Diff` after bullet `6. Optimize for Readability`. Match the format of existing bullets (`N. **Name**:` followed by sub-bullets — see line 11 `1. **Analyze Every Line**:` as the canonical shape). Sub-bullets MUST include: (a) read acceptance criteria from the PR body, linked issue body, and any linked `knowledge-base/project/specs/.../spec.md`; (b) map each criterion to evidence in the diff; (c) flag unmet criteria; (d) flag added behavior not in the criteria as out-of-scope; (e) **fallback**: "If invoked without a diff in scope (CONCUR-gate, plan-review, atdd, compound), render `### Hidden Assumptions` and `### Goal Verification` as `_N/A — no diff in scope._` and continue."
- Insert `### Hidden Assumptions` after `### YAGNI Violations`, before `### Final Assessment`. Bullet structure mirrors `### YAGNI Violations`: item / why it matters / suggested fix. Section MUST end with: "If no findings, render `_None._`"
- Insert `### Goal Verification` after `### Hidden Assumptions`, before `### Final Assessment`. Bullet structure: criterion (sourced from PR body / linked issue / linked spec) / verdict (met / unmet / out-of-scope) / evidence (file:line). Section MUST end with: "If no findings, render `_None._`"

### 2026-05-03-karpathy-claude-md-prior-art.md

- Insert `## Audit Direction (pre-merge check)` between `## When This Note Becomes Load-Bearing` and `## Related`. Section names the extended `code-simplicity-reviewer` as the implementation surface; cross-links the 2026-05-15 brainstorm + spec + plan + audit-vs-guidance learning + issue #2727; notes the audit-direction was added 2026-05-15 and completes the decision space.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `grep -cE '^7\. \*\*Verify Stated Goals Against Diff\*\*' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` returns `1`. Bullet format MUST match existing bullets exactly: `N. **Name**:` (asterisks outside the name, colon outside the asterisks).
- [ ] AC2: `grep -cE '^### (Hidden Assumptions|Goal Verification)$' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` returns `2`.
- [ ] AC3: `grep -c 'N/A — no diff in scope' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` returns `1` (the fallback instruction text is present in bullet 7).
- [ ] AC4: `grep -c '^## Audit Direction' knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` returns `1`.
- [ ] AC5: `shopt -s globstar; grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` returns the same value as the pre-edit baseline (frontmatter `description:` unchanged).
- [ ] AC6: PR body includes the AC1–AC5 grep commands and their expected output in a manual-verification section. PR body also includes `Closes #2727` and a `## Changelog` section noting `semver:patch`.

### Post-merge

- [ ] AC7: `gh issue view 2727 --json state` reports `CLOSED` (auto-closed by `Closes #2727`).

## Non-Goals

- This plan does NOT add Karpathy-derived rules to any `AGENTS.*.md` sidecar. The current always-loaded payload (`B_ALWAYS = 23,196 bytes`) already exceeds the critical threshold (22,000 bytes); future PRs citing this plan as precedent for AGENTS.md additions MUST independently justify against the budget per `cq-agents-md-tier-gate`.
- No changes to `plugins/soleur/skills/review/SKILL.md`. The agent is already routed by section 4, CONCUR-gate, `plan-review`, `work`, `atdd-developer`, and `compound` — extending the agent body propagates to every surface.
- No new skill, slash command, agent file, or script. No new test framework.
- No rename of `code-simplicity-reviewer` (would orphan five invocation surfaces).

## Risks

1. **Off-diff invocation output quality.** The agent is invoked without a diff in ≥3 surfaces (`/soleur:plan-review`, CONCUR-gate, `atdd-developer`). Mitigated by the explicit fallback string in bullet 7 (AC3) and the per-section `_None._` fallback (AC2's sections include the empty-case rendering instruction).

## Cross-domain note (Operations)

`/soleur:plan-review`'s consolidated output (3-agent panel) will now include two extra sections per `code-simplicity-reviewer` reply. Attention-cost per plan review is bounded by the `_N/A — no diff in scope._` fallback (no diff → no per-finding bullets). No action required; surface only.

## Open Code-Review Overlap

None. Both target files queried via `gh issue list --label code-review --state open` + `jq` containment check; no open issues reference either path.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm Phase 0.5).

### Engineering

**Status:** reviewed (carry-forward + 5-agent plan-review panel)
**Assessment:** Single-file content edit. Agent body extension propagates to all invocation surfaces uniformly. Frontmatter / filename / `description:` unchanged. Five-agent panel converged on cutting ceremony and encoding the off-diff fallback explicitly.

## References

- Issue: #2727 (parent #2718). PR: #3784 (draft).
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-15-karpathy-check-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-karpathy-check-2727/spec.md`
- Companion learning (guidance direction): `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md`
- Companion learning (audit-vs-guidance reframe): `knowledge-base/project/learnings/2026-05-15-brainstorm-audit-vs-guidance-direction-reframe.md`
- Target agent: `plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md`
- Invocation surfaces (verified via grep):
  - `plugins/soleur/skills/review/SKILL.md` line 380-382 (section 4, every review)
  - `plugins/soleur/skills/review/SKILL.md` line 502-524 (CONCUR-gate for scope-out filings)
  - `plugins/soleur/skills/plan-review/SKILL.md` line 8 (3-agent panel, every plan review)
  - `plugins/soleur/skills/work/SKILL.md` line 525, 533 (final validation, optional)
  - `plugins/soleur/skills/atdd-developer/SKILL.md` line 39 + `plugins/soleur/skills/compound/SKILL.md` line 136, 504, 558 (opportunistic)
- Source pattern (MIT): `alirezarezvani/claude-skills/commands/karpathy-check.md`
