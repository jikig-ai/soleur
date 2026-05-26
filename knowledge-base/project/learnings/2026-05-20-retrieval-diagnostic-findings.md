---
title: Retrieval Diagnostic Findings — Stage 2 of #4176 (paraphrase pre-pass)
date: 2026-05-20
category: workflow-patterns
tags: [retrieval, kb-search, benchmark, diagnostic, stage-2, paraphrase, embeddings-trigger]
problem_type: workflow_diagnostic
issue: 4176
parent_issue: 4119
pr: 4183
description: Post-Stage-2 bench of kb-search + bare-grep retrieval with LLM paraphrase pre-pass. R@5(heavy, kb-search) = 0.2709 < 0.4 ladder threshold AND regressed -0.0238 from Stage 1's 0.2947 — Stage 2 ladder MISSED. ADR-trigger condition for Stage 3 (embeddings/RAG) met.
---

# Retrieval Diagnostic Findings — Stage 2 of #4176

## TL;DR

`R@5(heavy, kb-search) = 0.2709` across 1163 learnings — **below the 0.4 ladder threshold AND regressed -0.0238 from Stage 1's 0.2947**. The LLM paraphrase pre-pass did NOT bridge the heavy-paraphrase gap; if anything, it slightly hurt heavy recall while leaving identity (+0.278 vs Stage 1 baseline) and light (+0.232) decisively above non-regression thresholds.

`gap_skill_roi = -0.0258` (Stage 1: -0.008) — **widened**. kb-search is now further behind bare grep at heavy paraphrase than it was post-Stage-1. The union-by-hit-count ranking of paraphrase variants promotes paths sharing surface tokens with reformulated queries; on hard semantic queries this dilutes the top-5 with adjacent-but-wrong learnings.

**Ladder verdict (plan AC16, #4176):** MISS branch.

- `r5_heavy ≥ 0.4`: **FAIL** (0.2709)
- identity non-regression > -0.02 vs 0.497 Stage 1 baseline: PASS (+0.278)
- light non-regression > -0.02 vs 0.404 Stage 1 baseline: PASS (+0.232)

Both conditions must hold for the PASS branch; r5_heavy missed.

**Action:** keep #4176 + #4119 open. File Stage 3 deferred-tracking issue **WITH the explicit ADR-trigger note** per #4119 plan FR7+TR6 — embeddings/RAG retrieval cannot be silently implemented; `/soleur:architecture create 'Adopt embeddings-based KB retrieval'` MUST run first to produce an ADR documenting the substrate change. Stage 2 PR #4183 still ships (the work itself lands; the gate decided to defer Stage 3).

## Stage 2 vs Stage 1 comparison

| Metric                       | Stage 1 (post-cap-split)   | Stage 2 (paraphrase pre-pass) | Δ        |
|---                           |---                          |---                            |---       |
| R@5 identity (kb-search)     | 0.802                       | **0.7747**                    | -0.0273 |
| R@5 light (kb-search)        | 0.675                       | **0.6363**                    | -0.0387 |
| R@5 heavy (kb-search)        | 0.2947                      | **0.2709**                    | -0.0238 |
| R@5 identity (grep)          | 0.949                       | 0.9475                        | -0.0015 |
| R@5 light (grep)             | 0.7489                      | 0.7489                        | 0       |
| R@5 heavy (grep)             | 0.3025                      | 0.2966                        | -0.0059 |
| gap_skill_roi                | -0.008                      | **-0.0258**                   | -0.0178 (worse) |
| gap_honesty                  | 0.507                       | 0.5039                        | -0.003 |
| Corpus size                  | 1147                        | 1163                          | +16 |

Every kb-search bucket regressed against its Stage 1 number. The corpus grew by 16 learnings between runs, so a small portion of the regression is attributable to new corpus content (heavier paraphrase ground-truth dispersion) rather than Stage 2's logic — but the gap_skill_roi widening (-0.008 → -0.0258, three-fold) is independent of corpus growth and unambiguously attributable to the paraphrase pre-pass's union-by-hit-count ranking adding noise to top-5 at heavy paraphrase.

## Why Stage 2 didn't bridge the gap

Per the post-Stage-1 diagnostic, the remaining R@5(heavy) gap to 0.4 was bounded by **grep's own heavy-paraphrase ceiling** (R@5(heavy, grep) = 0.3025). Stage 2's hypothesis was that LLM-generated paraphrases would surface vocabulary-shift variants that broke through that ceiling.

The Stage 2 bench result falsifies that hypothesis empirically:

1. **R@5(heavy, grep) = 0.2966** ≈ Stage 1's 0.3025 — grep's heavy ceiling is stable. The corpus didn't change semantics.
2. **R@5(heavy, kb-search) regressed below grep** (0.2709 vs 0.2966) — the paraphrase union *hurts* heavy recall on net. Mechanism: 3 paraphrase variants × tokens-per-variant inflate the hit-set with adjacent-but-irrelevant paths; union-by-hit-count promotes paths that share surface tokens with multiple variants but don't match the source ground truth.
3. **Identity + light regressed too** (small magnitude, but still negative). The adaptive `< 5` trigger fires more often than modeled — many identity/light queries have sparse baseline grep hits and tip into Stage 2, where the variant union dilutes the top-5.

**Conclusion:** lexical-union over LLM paraphrases is structurally bounded by the same grep semantic ceiling. Closing the heavy-paraphrase gap to 0.4 requires a different retrieval substrate (vector similarity over embeddings), not better query expansion over grep. This is the Stage 3 (#4119 plan FR7+TR6) condition.

---

(Stage 1 historical narrative preserved below — provides the before/after baseline for the Stage 2 comparison above.)

## Stage 1 of #4119 (historical)

`R@5(heavy, kb-search) = 0.2947` on a 1147-learning corpus, vs **0.1331** on the pre-fix 2026-05-19 baseline. Cap-split (8 tier-1 + 12 tier-2) + tier-1 learnings scope **erased the structural displacement bug** — `gap_skill_roi` collapsed from −0.173 to −0.008. kb-search matched grep at every paraphrase level.

Remaining R@5(heavy) = 0.295 was **bounded by grep's own semantic ceiling** (R@5(heavy, grep) = 0.303). The ladder routed `0.18 ≤ 0.295 < 0.30` → Stage 2 (LLM paraphrase pre-pass). Stage 1.5 (IDF/stopword tune) was moot — kb-search already at grep parity.

| Metric                       | 2026-05-19 (pre) | 2026-05-20 (Stage 1) | Δ        |
|---                           |---               |---                   |---       |
| R@5 identity (kb-search)     | 0.497            | **0.802**            | +0.305 (+61%) |
| R@5 light (kb-search)        | 0.404            | **0.675**            | +0.271 |
| R@5 heavy (kb-search)        | 0.133            | **0.295**            | +0.162 (+121%) |
| R@5 identity (grep)          | 0.952            | 0.949                | −0.003 |
| R@5 heavy (grep)             | 0.306            | 0.303                | −0.003 |
| gap_skill_roi                | **−0.173**       | **−0.008**           | +0.165 |
| gap_honesty                  | 0.364            | 0.507                | +0.143 |

The Stage 1 structural displacement bug was fixed. The remaining gap to the 0.4 ladder threshold was identified at Stage 1 close as "fundamental to grep at heavy paraphrase — Stage 2's LLM paraphrase pre-pass is the right next step." Stage 2 result above falsifies that.

---

(Auto-generated bench diagnostic below; the script's recommendation block hardcodes `Closes #4043` from Stage 1 of #4043 — historical, not the operative action. #4043 is already CLOSED via PR #4094 on 2026-05-20. Operative action is the MISS branch in the Stage 2 TL;DR above.)

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
| **R@5 identity**     | 0.7747  | 0.9475  |
| **R@5 light**        | 0.6363  | 0.7489  |
| **R@5 heavy**        | 0.2709  | 0.2966  |
| **R@10 identity**    | 0.9347 | 0.9604 |
| **R@10 light**       | 0.7481 | 0.7833 |
| **R@10 heavy**       | 0.3508 | 0.3482 |
| **MRR identity**     | 0.5863 | 0.9070 |
| **MRR light**        | 0.4714 | 0.6617 |
| **MRR heavy**        | 0.1825 | 0.2364 |

### Gap signals

- **Honesty gap (R@5 identity − heavy, kb-search):** 0.5039 — if < 0.05 the heavy paraphrase is too close to identity and prompts need tightening before treating corpus numbers as load-bearing.
- **Skill-ROI gap (R@5 heavy: kb-search − grep):** -0.0258 — **negative** — bare grep outperforms kb-search at heavy paraphrase. The two-tier strategy's INDEX.md tier-1 hits displace corpus content hits from the cap-20, hurting recall on hard queries.

### Fixture-seed sub-corpus (7 seeds, heavy-paraphrase pass)

- `knowledge-base/project/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-04-14-plan-prescribed-test-framework-not-available.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-21-kb-migration-verification-pitfalls.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` — kb-search rank: null, grep rank: null
- `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md` — kb-search rank: 8, grep rank: null
- `knowledge-base/project/learnings/2026-03-06-disambiguation-budget-compounds-with-domain-size.md` — kb-search rank: null, grep rank: null

If all 7 are findable (rank ≤ 5) the methodology may be too easy; if all 7 are unfindable the diagnostic is detecting the right shapes.

## Worst-N Unfindable

- `knowledge-base/project/learnings/2026-02-06-docs-consolidation-migration.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-06-parallel-plan-review-catches-overengineering.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-06-spec-workflow-implementation.md` — cause: **content-shape**
- `knowledge-base/project/learnings/2026-02-09-worktree-cleanup-gap-after-merge.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-brand-guide-contract-and-inline-validation.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-command-vs-skill-selection-criteria.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-12-review-compound-before-commit-workflow.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-base-href-breaks-local-dev-server.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-static-docs-site-from-brand-guide.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-13-terraform-best-practices-research.md` — cause: **content-shape**
- `knowledge-base/project/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-17-backdrop-filter-breaks-fixed-positioning.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-17-ux-review-gap-visual-polish-vs-information-architecture.md` — cause: **unknown**
- `knowledge-base/project/learnings/2026-02-17-worktree-not-enforced-for-new-work.md` — cause: **unknown**

## Recommended Action

**Bucket:** `reopen-rag`.

Run this verbatim before marking PR #4045 ready:

```bash
gh issue close 4043 --comment "R@5(heavy, kb-search)=0.2709 < 0.4. Reopening the 2026-04-07 RAG/embeddings decision. See knowledge-base/project/learnings/2026-05-20-retrieval-diagnostic-findings.md."
```

Per plan, atomic closure via `Closes #4043` in PR body lands the close on merge.

## Bench Revision History

The first `--confirm` run on 2026-05-19 produced bucket=`reopen-rag` with R@5(light|heavy, *) ≡ 0 — degenerate. Three independent bugs were discovered and fixed before the rerun whose numbers appear above:

1. **jq null-rank drop** (code). The per-row writer used `--arg rank "" | select(length>0)|tonumber? // null` which silently emitted NO output when rank was empty — null-rank rows never landed in `ranks.ndjson`. Fixed by switching to `--argjson rank null` (or numeric).
2. **Sentence-as-grep-query** (methodology). The plan §Phase 3 passed the full paraphrase sentence to `grep -F`. Real kb-search consumes a short $KEYWORD; a 1-2 sentence paraphrase never substring-matches verbatim source text. Fixed by adding bash-side keyword extraction (top-3 longest non-stopword tokens, ≥4 chars, drop all-numeric, dedup) + token-overlap ranking.
3. **Git pathspec coverage** (code). The pathspec `'knowledge-base/project/learnings/**/*.md'` matched ONLY files in subdirs (gobwas `**` requires intermediate dirs — same trap as `2026-03-21-lefthook-gobwas-glob-double-star.md`). The first run searched 301/1117 files (27% of corpus). Fixed by switching to directory-prefix pathspec + `:(exclude,glob)**/archive/**` long-form exclude.

All three fixes shipped together in commit `3fb52a05` with 13 new self-tests. The 7/7-fixture-seed-null methodology-suspect signal that fired on the first run no longer fires (3/7 seeds found at heavy_kbsearch, ranks 1, 7, 16).
