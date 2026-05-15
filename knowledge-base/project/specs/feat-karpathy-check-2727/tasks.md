---
title: karpathy-check — tasks
date: 2026-05-15
issue: 2727
branch: feat-karpathy-check-2727
plan: knowledge-base/project/plans/2026-05-15-feat-karpathy-check-extend-simplicity-reviewer-plan.md
lane: single-domain
status: tasks-ready
---

# Tasks — karpathy-check

## Phase 1 — Edit code-simplicity-reviewer agent body

- [ ] 1.1 Record pre-edit description-word baseline: `shopt -s globstar; grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` (~2666).
- [ ] 1.2 Extend bullet `4. Challenge Abstractions` with two new sub-bullets (unstated invariants; magic numbers / implicit callsite contracts).
- [ ] 1.3 Insert new bullet `7. Verify Stated Goals Against Diff` after bullet `6. Optimize for Readability`. Match canonical format `N. **Name**:`. Include sub-bullets (a) read AC sources, (b) map criteria to diff, (c) flag unmet, (d) flag out-of-scope, (e) fallback string `_N/A — no diff in scope._`.
- [ ] 1.4 Append `### Hidden Assumptions` after `### YAGNI Violations`, before `### Final Assessment`. Include `If no findings, render _None._` instruction.
- [ ] 1.5 Append `### Goal Verification` after `### Hidden Assumptions`. Include `If no findings, render _None._` instruction.

## Phase 2 — Extend prior-art learning

- [ ] 2.1 Insert `## Audit Direction (pre-merge check)` in `knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` between `## When This Note Becomes Load-Bearing` and `## Related`.
- [ ] 2.2 Cross-link brainstorm, spec, plan, audit-vs-guidance learning, issue #2727.

## Phase 3 — Verify (AC greps)

- [ ] 3.1 AC1: `grep -cE '^7\. \*\*Verify Stated Goals Against Diff\*\*' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` → `1`
- [ ] 3.2 AC1: `grep -cE '^### (Hidden Assumptions|Goal Verification)$' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` → `2`
- [ ] 3.3 AC2: `grep -c 'N/A — no diff in scope' plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md` → `1`
- [ ] 3.4 AC3: `grep -c '^## Audit Direction' knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md` → `1`
- [ ] 3.5 AC4: description-word count equals Phase 1.1 baseline.

## Phase 4 — Commit, push, ready PR

- [ ] 4.1 Stage only the two edited files: `git add plugins/soleur/agents/engineering/review/code-simplicity-reviewer.md knowledge-base/project/learnings/best-practices/2026-05-03-karpathy-claude-md-prior-art.md`
- [ ] 4.2 Commit with `feat: extend code-simplicity-reviewer with Hidden Assumptions and Goal Verification (#2727)`. Body: `Closes #2727`, `## Changelog` section, semver:patch intent.
- [ ] 4.3 Push to origin.
- [ ] 4.4 Update PR #3784 body with manual-verification block listing all Phase 3 grep commands and expected outputs (AC5).
- [ ] 4.5 Apply `semver:patch` label.
- [ ] 4.6 Mark PR #3784 ready for review.

## Phase 5 — Post-merge (automated)

- [ ] 5.1 `gh issue view 2727 --json state` → `CLOSED` (auto-closed by `Closes #2727`). No operator action.
