# Learning: Brainstorm carry-forward leader-set + issue-body PR-shape conditionality

## Problem

Two recurring brainstorm-mechanics patterns surfaced during the 2026-05-15 brainstorm for issue #3819 (API-budget operator preamble backport, child of merged PR #3809):

1. **Triad leader-spawn cost on small backport brainstorms.** `USER_BRAND_CRITICAL=true` from Phase 0.1 normally mandates the CPO + CLO + CTO triad spawn at Phase 0.5. For a small backport sitting under a recently-merged parent PR that already carries `brand_survival_threshold` + `## Domain Review (carry-forward)` sections, re-running 3 leaders in parallel is redundant — they would re-derive the same threshold and produce the same sign-off the parent carries verbatim.

2. **Issue-body PR-shape preferences treated as load-bearing.** Issue #3819's body argued for per-skill PRs ("Single PR per skill makes review easier than a bundled six-file diff"). The argument was sound *given* the unresolved design question (fenced `<decision_gate>` block vs. inline prose). Once the surface decision was locked at Phase 2, the bundled PR became cheaper to review than 6 sequential ones — the consistency of the shape *is* the review check, and 6 PRs would multiply CI/review overhead for no remaining cognitive-load win.

## Solution

### Pattern 1 — In-flight feature refresh

The brainstorm skill's Phase 0.5 already documents this exact branching: "In-flight feature refresh — carry-forward only (reuse plan's leader sign-offs verbatim; user-impact-reviewer at PR review remains the load-bearing gate) vs focused refresh." Operate as follows:

1. At Phase 0.5, before spawning leaders, check whether `feature_description` references a GitHub issue whose parent plan carries `brand_survival_threshold:` + `## Domain Review (carry-forward)` (detect via `grep -n "brand_survival_threshold\|## Domain Review\|## User-Brand Impact" <parent-plan>`).
2. If yes, present the operator with carry-forward vs. focused refresh via AskUserQuestion.
3. Carry-forward → write the parent's leader sign-offs into the new brainstorm's `## Domain Assessments` as a `### Carry-forward summary` subsection, naming the parent plan/PR.
4. The load-bearing enforcement layer remains the `user-impact-reviewer` agent at PR review time — that is the actual gate, not the leader spawn at Phase 0.5.

### Pattern 2 — Issue-body PR-shape preferences are conditional

When an issue body recommends "this should be N PRs" or "single PR per X is cleaner":

1. Identify the *premise* the recommendation rests on (typically: "the design question is still open" or "the changes are not structurally similar").
2. If the brainstorm resolves the premise (locks the surface, picks the pattern), re-evaluate the PR shape. A bundled PR may now win because reviewers gain *consistency-check value* from seeing all sites in one diff.
3. Surface the re-evaluation as an explicit AskUserQuestion at Phase 2, not as an implicit choice.

## Key Insight

**Both patterns share a meta-shape:** the issue body and the brainstorm protocol both encode defaults that were correct at the time of writing but are conditional on a downstream decision. The brainstorm's job is to surface the conditionality, not to inherit the default as if it were a fact.

For carry-forward: the protocol default ("spawn the triad when USER_BRAND_CRITICAL=true") is conditional on the absence of a prior sign-off; the In-flight feature refresh branch already encodes this.

For issue-body PR shape: the recommendation is conditional on the surface decision; once locked, re-derive.

## Tags

- category: brainstorm-mechanics
- module: plugins/soleur/skills/brainstorm
- related-issues: #3819, #3809
- related-plans: knowledge-base/project/plans/2026-05-15-feat-goal-primitive-operator-escape-hatch-plan.md

## Session Errors

Session error inventory: none detected.
