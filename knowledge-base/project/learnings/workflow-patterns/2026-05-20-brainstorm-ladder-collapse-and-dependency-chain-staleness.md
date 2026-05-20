---
date: 2026-05-20
category: workflow-patterns
tags: [brainstorm, premise-validation, ladder-collapse, dependency-chains, domain-leaders]
applies_to: brainstorm Phase 1.0.5 / Phase 0.5 leader spawn
related_issues: [4119, 4176, 4042, 4094, 4156]
---

# Brainstorm: ladder-collapse detection + dependency-chain staleness + leader numeric-claim cross-check

## Problem

The kb-search Stage 2 brainstorm (#4176) surfaced three premise-validation gaps that the existing brainstorm Phase 1.0.5 prose covers in general terms but doesn't catch sharply enough:

1. **Published ladders can mechanically collapse mid-execution.** The parent issue #4119 enumerated a 4-bucket ladder at design time: `≥0.4 → close`, `0.3–0.4 → Stage 1.5 (IDF/stopword)`, `<0.3 → Stage 2 (paraphrase)`, `no movement → Stage 3 (RAG)`. Stage 1 (PR #4156) landed and produced `R@5(heavy) = 0.2947` with `gap_skill_roi = −0.008` (kb-search at grep parity). The bucket says "Stage 1.5" — but `gap_skill_roi ≈ 0` means kb-search already performs at grep's ceiling; no scoring tweak (IDF, stopwords) can exceed grep's own semantic ceiling. The Stage 1.5 bucket-action is **mechanically moot** regardless of which bucket the number lands in. A brainstorm that just looks up "0.2947 → Stage 2" would have proceeded correctly by accident; one that landed in the 0.3–0.4 bucket would have proposed Stage 1.5 work that cannot move the metric.

2. **Dependency chains can ship via independent paths and become stale.** The user input cited "comment on #4042 to unblock" as a Stage 2 success-path action. Parent #4119 body literally states `Blocks: #4042`. But `gh issue view 4042 --json state,closedByPullRequestsReferences` showed `state=CLOSED` (2026-05-20 via PR #4094) — the learnings-decay archive shipped its own way through the pre-committed ladder Branch B/C, breaking the published "Stage N unblocks Stage M+1" chain. The brainstorm's existing premise probe checks closed-blocker artifacts when the issue body literally says "does not yet exist" — but does NOT systematically verify the state of issues that the user's *workflow action list* references as "unblock" / "comment on close" / "depends on close".

3. **Domain leaders speculate on numerically-verifiable ceilings; research measures them.** CTO assessment said "kb-search description budget headroom should not be a concern; verify before adding description text." Repo-research-analyst measured cumulative 1847/1800 (**−47 words headroom**) via `grep -h 'description:' plugins/soleur/skills/*/SKILL.md | wc -w`. The leader speculated reasonably from the strategic-reasoning vantage; the research measurement contradicted it. Without cross-check, the leader's claim could have anchored the plan author on a false ceiling.

## Solution

Three small additions to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.0.5 and Phase 0.5:

### Pattern 1 — Re-derive ladder-bucket actions from post-implementation evidence

When the feature description cites a published N-bucket ladder from a parent issue AND a prior Stage already landed AND the current bucket's named action depends on the *strategy* not having reached parity with its baseline (e.g., "Stage 1.5 IDF/stopword tune" requires the keyword-grep strategy to NOT be at grep's own ceiling), re-verify that the bucket-action is mechanically meaningful by reading the post-Stage-N diagnostic numbers (e.g., `gap_skill_roi`, gap-to-baseline). The bucket lookup is necessary but not sufficient — a mechanically-moot bucket action proceeds correctly only by accident.

**Cost:** 30-second read of the post-Stage-N diagnostic learning file. **Benefit:** brainstorm proposes a meaningful Stage N+1, not a Stage 1.5 that the metric cannot move.

### Pattern 2 — Verify dependency-chain target states at Phase 1.0.5

The existing Phase 1.0.5 premise probe catches `"does not yet exist"`, `"deferred from #N"`, `"blocked by #N"` literals in the feature description body. Extend the probe to ALSO catch:

- `"comment on #N to unblock"`
- `"closes #N when this lands"`
- `"unblocks #N"`
- `"depends on #N closing"`

For each cited target, run `gh issue view <N> --json state,closedByPullRequestsReferences`. If the target is already CLOSED via an independent PR (the closing PR's number does NOT match the current brainstorm's feature scope), the dependency chain has been satisfied through an independent path and the cited action is moot. Record in the brainstorm doc's `## Session Errors` so PR body authors don't add stale "comment on #N" actions.

**Cost:** one `gh issue view` per target cited (typically 0-2 per brainstorm). **Benefit:** PR bodies don't carry stale dependency claims that confuse future readers about which path actually shipped the unblocking work.

### Pattern 3 — Cross-check domain-leader numeric claims against research measurement

When a domain leader's assessment cites a *numerically-verifiable ceiling* — word counts, file counts, byte budgets, headroom percentages, descriptor counts — and the research-analyst output also touches the same number, the research wins. Leader claims of this shape should be flagged for cross-check at the synthesis step (Phase 2 approach selection), not anchored as authoritative. Distinct from the existing pattern of cross-checking leader infra/substrate claims (`grep main for the symbol`); this targets *quantitative* ceiling claims specifically.

**Cost:** during synthesis, scan leader summaries for numbers + scan research summaries for the same numbers; resolve the contradiction explicitly. **Benefit:** plan author doesn't anchor on a strategic-vantage speculation when a literal measurement is available.

## Key Insight

Premise-validation isn't a single gate at Phase 1.0.5 — it's a *layered* gate where each subsequent phase has a chance to catch a different premise-drift shape. Phase 1.0.5 catches "this thing doesn't exist / was deferred / is blocked" claims in the feature description. Phase 1.1 catches "this approach hook" / "this flag/symbol exists" claims. Phase 0.5 leaders catch domain-shape blind spots. But **none of those layers catch "ladder-bucket-action is mechanically moot" or "dependency chain shipped via an independent path"** — those require explicit, narrow probes added at Phase 1.0.5.

The shape is: **a published artifact (ladder, dependency claim, capability ceiling) frozen at design-time can become physically wrong by Stage N execution**. The artifact looks authoritative because it's *cited*, but the evidence the artifact was built on has since moved. Verify the *current state of the evidence*, not the *state described by the artifact*.

## Session Errors

1. **Initial `cd .worktrees/...` failed** with "No such file" because shell `cd` state doesn't persist across Bash tool invocations. Recovery: absolute paths.
   **Prevention:** prefer absolute paths for cross-invocation work in worktrees; the Bash tool documents this but it's easy to forget when chaining a `cd` after a worktree-creation command.

2. **Premise drift caught at Phase 1.0.5** (closure of #4042 via #4094 broke the "unblock #4042" published dependency chain). Recovery: surfaced in brainstorm doc + spec acceptance criteria item 9.
   **Prevention:** Pattern 2 above — extend Phase 1.0.5 probe to verify dependency-chain target states whenever feature description cites "unblock #N" / "comment on #N to close" / "closes #N when this lands".

3. **CTO/research contradiction on description-budget headroom** (leader said "not a concern"; research measured −47 words). Recovery: re-anchored to "no description-line growth at plan time" in the brainstorm and spec.
   **Prevention:** Pattern 3 above — flag domain-leader numeric ceiling claims for cross-check against research measurement at synthesis.

## Tags

- category: workflow-patterns
- module: brainstorm-skill
- related: [[2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd]], [[2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders]], [[2026-05-19-brainstorm-pre-committed-ladder-and-data-source-granularity-check]], [[2026-05-12-brainstorm-defer-decision-issue-body-rule-drift-and-oauth-only-bundling-scope-bound]]
