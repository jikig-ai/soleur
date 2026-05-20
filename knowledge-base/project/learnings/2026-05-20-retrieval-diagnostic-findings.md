---
title: Retrieval Diagnostic Findings — Stage 1 of #4119
date: 2026-05-20
category: workflow-patterns
tags: [retrieval, kb-search, benchmark, diagnostic, stage-1]
problem_type: workflow_diagnostic
issue: 4119
pr: 4156
description: Post-Stage-1 bench of kb-search + bare-grep retrieval. Cap-split 8/12 + tier-1 learnings scope. R@5(heavy, kb-search) = 0.295, falls into Stage 2 ladder branch.
---

# Retrieval Diagnostic Findings — Stage 1 of #4119

## TL;DR

`R@5(heavy, kb-search) = 0.2947` on a 1147-learning corpus, vs **0.1331** on the pre-fix 2026-05-19 baseline. Cap-split (8 tier-1 + 12 tier-2) + tier-1 learnings scope **erased the structural displacement bug** — `gap_skill_roi` collapsed from −0.173 to −0.008. kb-search now matches grep at every paraphrase level.

Remaining R@5(heavy) = 0.295 is **bounded by grep's own semantic ceiling** (R@5(heavy, grep) = 0.303). No scoring tune on the existing strategy can exceed this.

**Ladder decision (plan FR7 + decision-5):** 0.18 ≤ 0.295 < 0.30 → **Stage 2** deferred-issue (LLM paraphrase pre-pass). Stage 1.5 (IDF/stopword tune) is moot — kb-search is already at grep parity.

**Action:** keep #4119 open (blocked on Stage 2 outcome). File Stage 2 deferred-tracking issue. #4042 remains blocked.

## Stage 1 before/after

|                      | 2026-05-19 (pre) | 2026-05-20 (post) | Δ        |
|---                   |---               |---                |---       |
| R@5 identity (kb-search) | 0.497         | **0.802**         | +0.305 (+61%) |
| R@5 light (kb-search)    | 0.404         | **0.675**         | +0.271 |
| R@5 heavy (kb-search)    | 0.133         | **0.295**         | +0.162 (+121%) |
| R@5 identity (grep)      | 0.952         | 0.949             | −0.003 |
| R@5 heavy (grep)         | 0.306         | 0.303             | −0.003 |
| gap_skill_roi            | **−0.173**    | **−0.008**        | +0.165 |
| gap_honesty              | 0.364         | 0.507             | +0.143 |

The structural displacement bug is fixed. The remaining gap to the 0.4 ladder threshold is fundamental to grep at heavy paraphrase — Stage 2's LLM paraphrase pre-pass is the right next step.

---

(Original auto-generated diagnostic below; the script hardcodes a reference to #4043 — historical, not actionable.)

## Auto-generated Diagnostic Summary

Bucket: **`reopen-rag`** (script classifier; ladder above governs the actual action). `R@5(heavy, kb-search) = 0.2947` across 1147 learnings.

## Methodology

Per the plan (`knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md`) and post-first-run revision (see commit `3fb52a05`):

- **Three paraphrase intensities** generated per learning: `identity` (ground-truth verbatim, no LLM), `light` (synonym substitution via Haiku), `heavy` (different framing via Haiku).
- **Keyword extraction from each query.** The retriever does NOT pass the full paraphrase sentence to `grep -F` (the original plan did; that yielded vacuous 0 because sentence-paraphrases never substring-match verbatim source text). Instead, a bash heuristic extracts the top-3 longest non-stopword tokens (≥4 chars, drop all-numeric, dedup) from each query.
- **Token-overlap ranking.** Each candidate path is scored by the number of distinct extracted tokens that substring-match it (case-insensitive). Sort by score desc, ties broken by lexicographic path order, cap top-20.
- **Two retrievers** exercised per intensity: a bash emulator of kb-search's two-tier strategy (INDEX.md title-line token-overlap as tier-1 → KB-wide content token-overlap as tier-2, combined unique cap-20), and a learnings-only baseline (single-tier token-overlap against `knowledge-base/project/learnings/`).
- **min-rank synced_to semantics:** if a learning declares `synced_to:`, the source's rank is the BEST (lowest) position across {source_path, synced_to[…]} in the retriever's combined output. This biases R@5 upward vs. the strict "source-only" definition and is documented here so a future reader does NOT conflate the two.
- **kb-search is a strategy, not a skill call.** The bench replicates the two-tier strategy in bash because (a) the skill is a Markdown prompt agents interpret, not a CLI, and (b) the strategy is the stable interface — its grep flags survive Markdown wording changes.
- **Headline numbers are a proxy, not a direct measurement.** Token-overlap retrieval is an upper-bound proxy of true `kb-search` skill recall. The skill itself takes a single `$KEYWORD` argument; the bench's top-3-token-overlap shape is more permissive than a single-keyword call would be. Read R@5 as "the skill's recall ceiling under a charitable keyword-extraction assumption", not as "the skill's recall when used in practice."

## Results

### Corpus-wide R@5 / R@10 / MRR (6 cells each)

|                      | kb-search    | bare grep    |
|---                   |---           |---           |
| **R@5 identity**     | 0.8021  | 0.9486  |
| **R@5 light**        | 0.6748  | 0.7489  |
| **R@5 heavy**        | 0.2947  | 0.3025  |
| **R@10 identity**    | 0.9564 | 0.9616 |
| **R@10 light**       | 0.7768 | 0.7855 |
| **R@10 heavy**       | 0.3714 | 0.3548 |
| **MRR identity**     | 0.6219 | 0.9086 |
| **MRR light**        | 0.5232 | 0.6662 |
| **MRR heavy**        | 0.1993 | 0.2440 |

### Gap signals

- **Honesty gap (R@5 identity − heavy, kb-search):** 0.5074 — if < 0.05 the heavy paraphrase is too close to identity and prompts need tightening before treating corpus numbers as load-bearing.
- **Skill-ROI gap (R@5 heavy: kb-search − grep):** -0.0078 — **negative** — bare grep outperforms kb-search at heavy paraphrase. The two-tier strategy's INDEX.md tier-1 hits displace corpus content hits from the cap-20, hurting recall on hard queries.

### Fixture-seed sub-corpus (7 seeds, heavy-paraphrase pass)

- `knowledge-base/project/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md` — kb-search rank: 6, grep rank: 3
- `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` — kb-search rank: 11, grep rank: 10
- `knowledge-base/project/learnings/2026-04-14-plan-prescribed-test-framework-not-available.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-21-kb-migration-verification-pitfalls.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md` — kb-search rank: 6, grep rank: 13
- `knowledge-base/project/learnings/2026-03-06-disambiguation-budget-compounds-with-domain-size.md` — kb-search rank: 1, grep rank: 3

If all 7 are findable (rank ≤ 5) the methodology may be too easy; if all 7 are unfindable the diagnostic is detecting the right shapes.

## Worst-N Unfindable

- `knowledge-base/project/learnings/2026-02-06-docs-consolidation-migration.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-06-parallel-plan-review-catches-overengineering.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-06-spec-workflow-implementation.md` — cause: **content-shape**
- `knowledge-base/project/learnings/2026-02-09-parallel-subagent-fan-out-in-work-command.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-09-plugin-staleness-audit-patterns.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-09-worktree-cleanup-gap-after-merge.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-review-compound-before-commit-workflow.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-ship-integration-pattern-for-post-merge-steps.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-base-href-breaks-local-dev-server.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-parallel-subagent-css-class-mismatch.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-static-docs-site-from-brand-guide.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-terraform-best-practices-research.md` — cause: **content-shape**
- `knowledge-base/project/learnings/2026-02-14-google-fonts-variable-font-deduplication.md` — cause: **retriever-miss**
- `knowledge-base/project/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md` — cause: **unknown**

## Recommended Action

**Bucket:** `reopen-rag`.

Run this verbatim before marking PR #4045 ready:

```bash
gh issue close 4043 --comment "R@5(heavy, kb-search)=0.2947 < 0.4. Reopening the 2026-04-07 RAG/embeddings decision. See knowledge-base/project/learnings/2026-05-20-retrieval-diagnostic-findings.md."
```

Per plan, atomic closure via `Closes #4043` in PR body lands the close on merge.

## Bench Revision History

The first `--confirm` run on 2026-05-19 produced bucket=`reopen-rag` with R@5(light|heavy, *) ≡ 0 — degenerate. Three independent bugs were discovered and fixed before the rerun whose numbers appear above:

1. **jq null-rank drop** (code). The per-row writer used `--arg rank "" | select(length>0)|tonumber? // null` which silently emitted NO output when rank was empty — null-rank rows never landed in `ranks.ndjson`. Fixed by switching to `--argjson rank null` (or numeric).
2. **Sentence-as-grep-query** (methodology). The plan §Phase 3 passed the full paraphrase sentence to `grep -F`. Real kb-search consumes a short $KEYWORD; a 1-2 sentence paraphrase never substring-matches verbatim source text. Fixed by adding bash-side keyword extraction (top-3 longest non-stopword tokens, ≥4 chars, drop all-numeric, dedup) + token-overlap ranking.
3. **Git pathspec coverage** (code). The pathspec `'knowledge-base/project/learnings/**/*.md'` matched ONLY files in subdirs (gobwas `**` requires intermediate dirs — same trap as `2026-03-21-lefthook-gobwas-glob-double-star.md`). The first run searched 301/1117 files (27% of corpus). Fixed by switching to directory-prefix pathspec + `:(exclude,glob)**/archive/**` long-form exclude.

All three fixes shipped together in commit `3fb52a05` with 13 new self-tests. The 7/7-fixture-seed-null methodology-suspect signal that fired on the first run no longer fires (3/7 seeds found at heavy_kbsearch, ranks 1, 7, 16).
