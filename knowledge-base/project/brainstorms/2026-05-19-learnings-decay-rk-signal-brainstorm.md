---
title: Pre-committed Action Ladder for Learnings Archive (Conditional on Bench Output)
date: 2026-05-19
status: decided
participants: founder, CTO
issue: 4042
sibling_issue: 4043
sibling_pr: 4045
lane: single-domain
brand_survival_threshold: none
---

# Pre-committed Action Ladder for Learnings Archive

## What We're Building

**Not a script yet.** A pre-committed response curve, captured in `spec.md`, that describes what the operator will do once `scripts/learning-retrieval-bench.sh` (merged in PR #4045) has been run against the corpus for the first time.

The bench's `worst_n` array (files where `R@5(heavy, kbsearch) = 0`, cap 20) is the candidate pool. The response curve branches on `worst_n.length` and on per-candidate `cause` classification. No `scripts/learning-archive-candidates.sh` is built unless the data warrants it.

This mirrors the sibling brainstorm's pre-committed action ladder pattern (#4043 / PR #4045): commit the response BEFORE the number lands, so the number doesn't get rationalized after.

## Why This Approach

### The premise reframe (from issue body to what we're building)

| Issue #4042 proposed | What we're building | Why |
|---|---|---|
| Read `rule-metrics.json` for per-learning rule-fire hit counts | Use `worst_n` from `scripts/learning-retrieval-bench.sh` output | `rule-metrics.json` tracks AGENTS.md rule fires, NOT per-learning hits. Per-learning telemetry stream does not exist and would be heavy to instrument. #4043 explicitly notes this gap in its body. |
| Monthly scheduled cron in `.github/workflows/` | Conditional one-shot, contingent on bench output | Same logic as sibling: 1 operator, ~841 files, no drift evidence. The recurring framing assumes signal that hasn't shipped. |
| Auto-emit draft PR with `git mv` moves | Markdown report (if needed) → operator authors archive PR themselves | CTO: bench is calibrated for diagnostic, not for `git mv` gating. Inverting design intent on a one-shot snapshot is Type-I-error machinery. |
| Filter: zero hits + zero `[[link]]` + age > 60d | Filter: bench `cause` ∈ {content-shape, cross-category-dup, unknown} + grep-rank check + opt-out frontmatter | `missing-frontmatter` and `slug-mismatch` causes route to sibling's `surface-rewrites` bucket (rewrite, not archive). Inbound `[[link]]` count is a weak signal in this corpus (wiki-link convention not established in AGENTS.md). |

### What changed our framing

1. **Mis-premised data source.** Pre-worktree probe found `knowledge-base/project/rule-metrics.json` exists (78 AGENTS.md rules tracked) but `rules[].id` are rule IDs like `cm-challenge-reasoning-instead-of`, not learning file paths. Per-learning fire counts are not collected by `scripts/rule-metrics-aggregate.sh`. The issue's stated mechanism cannot work as written.
2. **Sibling work shipped today.** PR #4045 merged `scripts/learning-retrieval-bench.sh` — a one-shot diagnostic producing per-corpus R@5/R@10/MRR + a `worst_n` array (cap 20) with `cause` classification. This IS the missing measurement apparatus, and it's the natural input for any decay heuristic.
3. **Sibling rule-side issue #3683** waits until 2026-07-04 for an 8-week telemetry window. Today is 2026-05-19. The rule-side sibling is *more rigorous* than the original #4042 framing — on a corpus 100× smaller. Archive-by-one-snapshot would be less rigorous than rule-retirement.
4. **CTO HIGH-severity risk** on the original framing: paraphrase-to-source recall is a coarse "should we invest in RAG" diagnostic; repurposing it as a per-file `git mv` gate inverts design intent. One snapshot, no trend, no second observation.

### Why not defer entirely (close as superseded)

Considered. The CPO-style "close as superseded" framing (rejected option C) would have been right IF the bench's `surface-rewrites` bucket fully absorbed the archive use case. It doesn't: a learning whose content has gone genuinely stale (workflow refactored, rule promoted to AGENTS.core.md) is not a slug/frontmatter rewrite candidate — it's an archive candidate. Pre-committing the conditional response now is cheap and prevents the operator from negotiating ad-hoc when the bench output lands.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Shape | Pre-committed action ladder in `spec.md`, no script yet | Sibling reshape pattern; YAGNI applied; no recurring infra |
| Input data | `scripts/learning-retrieval-bench.sh` output JSON (`worst_n` array + `extraction_stats`) | Already merged via PR #4045; no per-learning telemetry stream to instrument |
| Trigger | Operator runs bench once (`bash scripts/learning-retrieval-bench.sh --confirm`), then evaluates ladder against output | One-shot, not recurring; matches #4043 closure model |
| Ladder branch A: `worst_n.length ≤ 5` | Operator triages inline in a single PR (no script) | Eyeballable in <30 min; tooling overhead > value at this scale |
| Ladder branch B: `worst_n.length ∈ [6, 20]` | Build `scripts/learning-archive-candidates.sh` that enriches `worst_n` with grep-rank + age + inbound-link count + frontmatter `archive_ok` opt-out; emits markdown report | Per-file CTO check needed; report (not `git mv` PR) preserves human triage |
| Ladder branch C: `worst_n.length = 20` (cap hit, likely undercount) | Extend bench to remove cap or report total `R@5=0` count separately; return for re-evaluation | Bench cap is a measurement artifact; archiving on a truncated list is biased |
| Cause filter | Archive ONLY if `cause` ∈ {`content-shape`, `cross-category-dup`, `unknown`}. `missing-frontmatter` / `slug-mismatch` route to sibling's `surface-rewrites` bucket. | Bench already classifies; respect its distinction between findable-after-rewrite vs. genuinely-stale |
| Grep-rank gate | A candidate is dropped from the archive list if `git grep -l "<title-slug-keywords>" knowledge-base/project/learnings/` returns its own path at position 1 of ≤3 results | CTO: `R@5(kb-search) − R@5(grep)` is skill ROI signal. High grep recall = findable today via dominant mechanism = NOT a stale-archive candidate. |
| Opt-out | Frontmatter `archive: never` (boolean shape, default absent = eligible) excludes from candidate pool | Founder/CTO override for tacit-but-load-bearing learnings without grep matches |
| Output format (branch B) | Markdown report at `knowledge-base/project/learnings-archive-candidates-<date>.md` (transient, gitignored) | NOT a `git mv` PR. Operator reads, decides per file, authors their own archive PR. Reversibility via git history is fallback, not license. |
| Closure | Branch A or B completion = `Closes #4042` in operator-authored archive PR. Branch C completion = follow-up issue on bench extension, leave #4042 open referencing it. | Atomic closure; no post-merge ceremony |

### Lane

Lane override: none. Inferred=single-domain (Engineering), chosen=single-domain (Engineering). The CTO assessment was load-bearing; no other domain leader would have surfaced different load-bearing risks (no compliance, no user-facing surface, no commercial scope).

## Open Questions

- **Threshold for branch A (≤5).** Picked by analogy to "eyeballable in <30 min." If the bench's `worst_n` returns 7 in branch B, building a script feels like overkill; maybe the boundary should be ≤8. Defer to operator at branch-execution time.
- **Branch C "cap likely hit" detection.** The bench has cap 20 on `worst_n`. If `worst_n.length == 20`, that's either exactly 20 R@5=0 files OR 20+ that got truncated. The bench's `extraction_stats` doesn't currently report total R@5=0 count separately. Branch C may need a bench AC amendment (small extension: emit `r5_zero_count` alongside `worst_n`).
- **`archive: never` frontmatter adoption.** Today, no learnings have this. It exists in the spec as a forward-compatible opt-out; adoption happens only when a candidate is flagged that the operator wants to exempt going forward. Not a backfill cost.
- **Interaction with `synced_to:` cross-filed learnings.** Bench uses min-rank semantics across `synced_to[]`. If file A is cross-filed at B and the bench surfaces A in `worst_n` but B in the surface-rewrites bucket, the archive logic should defer to the rewrites side (rewrite the more findable filing, archive the less findable one only if both score zero). Defer to operator triage in branch A; document for branch B script.
- **Re-evaluation cadence.** When (if ever) does this brainstorm re-fire? Tentative re-evaluation criterion: at 2026-08-19 (3 months out), if the bench has been re-run and `worst_n.length` has grown to > 20, re-open this brainstorm to decide whether the cap is the binding constraint.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Reframe sound but the four-filter conjunction (R@K + age + link-count + opt-out) misses three load-bearing risks: (1) R@5 from a single one-shot bench is too thin — one snapshot, no trend, paraphrase-to-source recall is a coarse diagnostic threshold not a per-file gate; (2) rewriter-bounded ceiling means operator-natural-language queries (proper nouns, error strings, jargon) score low R@5 while being highly load-bearing; (3) inbound `[[link]]` count is a weak signal — wiki-link convention is not established in this corpus, long tail has zero inbound links regardless of value. Recommendations: emit a candidate list with per-file rationale (NOT `git mv` PR), add grep-recall as a fifth filter (skill ROI signal `R@5(kb-search) − R@5(grep)`), require per-file human sign-off before any archival. Capability gap: bench `worst_n` JSON does not include grep-rank, age, or inbound-link counts; either compute in archive script or extend bench AC. Sibling #3683 precedent (8w telemetry window post-2026-07-04) argues against acting on a single snapshot from a bench whose output file does not yet exist.

## Capability Gaps

- **Per-candidate enrichment fields not in bench JSON.** Evidence: `knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md` AC5 lists JSON schema as `r5/r10/mrr/gap_honesty/gap_skill_roi/worst_n/extraction_stats/...`; `worst_n[]` entries are `{path, rank_heavy_kbsearch, cause}` only. No `grep_rank_heavy`, no `file_age_days`, no `inbound_link_count`. Belongs to Engineering (CTO). Needed if ladder branch B fires (`worst_n.length ∈ [6, 20]`): the archive script must compute these signals independently (cheap: `git log --diff-filter=A --format=%ci`, `git grep -l "[[:wikilink:]:title]"`, `git grep -c <title-slug-words>`) OR the bench gets a small AC amendment.

## Productize Candidate

None. The proposed work is itself conditional and one-shot; it is not a recurring pattern that would benefit from a Soleur skill.

## Bench Run Results (2026-05-19)

The retrieval bench (`scripts/learning-retrieval-bench.sh`) ran for the first time on 2026-05-19 against 1127 learnings. Cost: $3.10. Wall time: ~50 min.

### Headline numbers

| | kb-search | bare grep |
|---|---|---|
| R@5 identity | 0.497 | 0.952 |
| R@5 light    | 0.404 | 0.747 |
| **R@5 heavy** | **0.133** | **0.306** |
| MRR heavy    | 0.091 | 0.239 |

**Gap signals:**

- `gap_honesty = 0.3638` (identity − heavy, kb-search) — well above the 0.05 methodology floor; the heavy-paraphrase numbers are honest.
- `gap_skill_roi = −0.1730` (heavy: kb-search − grep) — **NEGATIVE**. Bare grep outperforms kb-search on hard queries. The two-tier strategy's INDEX.md tier-1 hits displace corpus content hits from the cap-20.

### Sibling bench bucket

Bucket fired: **`reopen-rag`** (per the sibling brainstorm's pre-committed ladder, `R@5(heavy, kb-search) < 0.4` triggers RAG reopen). Follow-up filed: **#4119** — "reopen 2026-04-07 KB retrieval decision."

### This brainstorm's ladder

**Branch C fires:** `worst_n.length = 20` (cap hit). But the spec's literal Branch C action ("extend bench with `r5_zero_count`") is no longer the load-bearing next step. The bench's `gap_skill_roi = −0.173` shows the retriever itself is broken, which means `worst_n` cannot distinguish stale content from broken retrieval — the entire archive-by-R@K mechanism is premised on a working retriever.

Spec FR4 and AC4 updated to reflect: #4042 blocks on #4119's outcome (a working retriever + R@5(heavy, kb-search) ≥ 0.4 on a re-run bench).

### Worst-N cause distribution (truncated at 20)

- `unknown`: 17
- `content-shape`: 2
- `retriever-miss`: 1 (NEW cause, not in spec's original 5-cause enum — the bench added it after the first run's bug-fix cycle, see findings file's Bench Revision History)
- `missing-frontmatter`: 0
- `slug-mismatch`: 0
- `cross-category-dup`: 0

The all-`unknown`-dominant distribution is itself evidence the cause-classifier is unable to attribute most retrieval failures to the spec's named buckets — likely because the broken-retriever floor masks per-file causes. Re-classification after #4119 ships will produce a more useful distribution.

### Methodology validation

All 7 fixture seeds (pre-known retrieval-failure shapes named in the bench plan) returned null rank in both retrievers — the diagnostic is detecting the right shapes. The first bench run had three bugs (jq null-rank drop, sentence-as-grep-query, gobwas glob coverage) caught and fixed before the run whose numbers appear above.

### What we are NOT doing now (despite the data)

- NOT archiving any learning from `worst_n`. The retriever is broken; the candidate list is noise plus signal, indistinguishable.
- NOT building `scripts/learning-archive-candidates.sh`. Same reason — the input substrate is unsound.
- NOT closing #4042. It remains open with a pointer to #4119; re-enter the ladder after #4119 ships.

Pre-committing the ladder before the bench was the right call — without it, the operator would have negotiated with the data. The ladder said "if Branch C fires, do not archive"; the bench fired Branch C; we are not archiving.
