---
date: 2026-05-20
topic: kb-retrieval-reopen
issue: 4119
blocks: 4042
supersedes_decision_in: 2026-04-07-kb-retrieval-improvement-brainstorm.md
status: decided
---

# Reopen the 2026-04-07 KB retrieval decision

## What We're Building

A **staged, bench-gated fix to `kb-search`** that recovers retrieval recall to R@5(heavy) ≥ 0.4, starting with the cheapest mechanical fixes and escalating only on bench failure. The 2026-04-07 brainstorm pre-committed file-based retrieval + INDEX.md + frontmatter as the choice, and named the reopen trigger as "evidence that agents consistently fail to find content despite manifest and standardized frontmatter." The 2026-05-19 bench supplied that evidence. The reopen is not "abandon file-based retrieval"; it is "the current implementation is structurally broken — fix the bug before reaching for new infra."

## Why This Approach

The bench evidence is unusually precise, and it does **not** point at a fundamental semantic-search deficit. It points at a structural bug in the current implementation:

| | kb-search | bare grep |
|---|---|---|
| R@5 identity | **0.497** | 0.952 |
| R@5 light    | 0.404 | 0.747 |
| R@5 heavy    | 0.133 | 0.306 |
| `gap_skill_roi` | — | **−0.173** (kb-search worse than baseline) |

kb-search loses to bare grep **at identity** — before paraphrase enters the picture. That is impossible if the two-tier mechanism is working as intended. Repo research located the cause:

- `knowledge-base/INDEX.md` has **3461 entries** (entire KB) but the bench evaluates against only **1127 learnings**.
- Tier-1 grep on INDEX.md fills the cap-20 with non-learning titles before tier-2 corpus content matches are evaluated.
- Dominant prefix-noise in INDEX.md titles: `session state` ×497, `digest` ×65, `tasks: fix` ×110, `feat: add` ×24, `spec` ×22. Common keywords match hundreds of irrelevant titles instantly.
- `kb-search` has **zero programmatic consumers**. It is a Markdown prompt strategy interpreted by agents. Schema changes are zero-churn.
- No existing RAG/embeddings infrastructure (greenfield).

Cheapest fix that addresses the located mechanism wins. Embeddings as the *first* response would be reaching for a sledgehammer when a wrench fits. Staged, bench-gated escalation is the YAGNI-aligned path. The bench itself is the observability surface — `hr-observability-as-plan-quality-gate` is satisfied by the bench being rerunnable on demand (and the `--cache-paraphrases` flag already exists, so reruns are sub-second after the first one).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Strategy | **Staged: tune → paraphrase → RAG**, bench-gated at each step | Bench evidence isolates a structural bug, not a semantic deficit. Cheaper fixes first; escalate only on bench failure. |
| Stage 1 scope | **Mechanical structural fixes only** | (1) Split cap-20 into 8 tier-1 + 12 tier-2. (2) Scope tier-1 to a learnings-only sub-index, dropping the 2300+ non-learning titles. (3) Backfill frontmatter for the ~63% of learnings missing it. Defer IDF/stopword scoring tweaks to Stage 1.5. |
| Stage 1 gate | **R@5(heavy, kb-search) ≥ 0.4** | Threshold pre-committed in the bench's `bucket` field (`reopen-rag` if <0.4, `surface-rewrites` if 0.4–0.6, `vindicate` if ≥0.6). |
| Stage 1 pass → action | **Close #4119, unblock #4042** | If the mechanical fix recovers recall, the original 2026-04-07 file-based decision stands. |
| Stage 1 fail → action | **Stage 1.5 first** (IDF/stopword scoring), then Stage 2 (paraphrase pre-pass) | Don't escalate to a new failure surface (LLM pre-pass) without exhausting the scoring tuning that's free. |
| Stage 2 trigger | Stage 1 + 1.5 still miss the gate | LLM paraphrase pre-pass adds ongoing cost ($0.0003-0.001/query, +800-2000ms latency) and a new failure mode (rewrite hallucinations). Justify with bench data, not vibes. |
| Stage 3 trigger | Stages 1+1.5+2 still miss the gate | Embeddings is an ADR trigger — run `/soleur:architecture create 'Adopt embeddings-based KB retrieval'` before implementation. Greenfield infra, irreversible operator coupling, ongoing API cost. |
| Bench co-evolution | **SKILL.md and bench script change in lockstep, same PR** | `learning-retrieval-bench.sh:413-507` (`kbsearch_rank`) hardcodes the current two-tier order and `head -20` cap. Any change to the strategy must update the emulator in the same commit, or the bench measures the wrong thing. |
| New bench fixture | **Synthesized INDEX.md-flooding pathology fixture** (`cq-test-fixtures-synthesized-only`) | ≥30 noise-titled INDEX entries + 3 learning targets that the cap-20 displacement currently misses. Catch the regression in `--self-test`, not the $3 / 70min full run. |
| Frontmatter backfill | **Reuse 2026-03-05 `backfill-frontmatter.py` pattern** | Idempotent, PyYAML, category inference from slug. ~533 files. Run BEFORE the retriever change so frontmatter coverage isn't a confound in the bench. |
| What is NOT being built | Anything beyond Stage 1 in this PR | Stages 1.5/2/3 are explicit deferred-tracking issues. |

## Open Questions

- **Stage 1 PR boundary**: does the frontmatter backfill ship in the same PR as the retriever change, or sequentially with a bench rerun between? **Lean**: sequential — backfill first (bench rerun A), then retriever tune (bench rerun B). This lets us attribute the metric movement to each lever. If sequencing the runs proves too expensive, fold into one PR with the bench breakdown showing per-tier deltas.
- **Sub-index format for scoped tier-1**: a separate `knowledge-base/INDEX-learnings.md` file vs. a section anchor inside the existing `INDEX.md` vs. a runtime filter on path prefix in the strategy. The plan stage chooses — all three are equivalent for the bench.
- **Per-tier breakdown in bench JSON**: CTO recommends emitting per-tier rank breakdown so future regressions distinguish "tier-1 flooded" from "tier-2 missed". Adopt — minor schema bump.

## Acceptance Criteria

1. **Stage 1 land:** PR modifies `plugins/soleur/skills/kb-search/SKILL.md` Phase 3 to (a) split cap-20 (8+12), (b) scope tier-1 to a learnings sub-index, AND modifies `scripts/learning-retrieval-bench.sh` `kbsearch_rank` (lines 413-507) in lockstep.
2. **Frontmatter backfill committed:** ~533 missing-frontmatter learnings get YAML frontmatter via a reusable script (`scripts/backfill-frontmatter.py` or equivalent).
3. **Synthesized fixture:** New flooding-pathology fixture added to `learning-retrieval-bench.sh --self-test`.
4. **Bench rerun committed:** `bash scripts/learning-retrieval-bench.sh --confirm` rerun with results committed to `knowledge-base/project/learning-retrieval-metrics-<date>.json` and a new diagnostic-findings learning.
5. **Gate outcome documented:**
   - If R@5(heavy, kb-search) ≥ 0.4 → close #4119 and unblock #4042.
   - If R@5(heavy, kb-search) < 0.4 → keep #4119 open, file Stage 1.5 deferred-tracking issue (IDF/stopword tuning).
6. **Deferred-tracking issues filed** for Stages 1.5, 2, 3 with their respective trigger conditions.

## Domain Assessments

**Assessed:** Engineering (CTO). Single-domain (engineering-only), no Marketing/Operations/Product/Legal/Sales/Finance/Support implications.

### Engineering (CTO)

**Summary:** Recommends Stage 1 (mechanical structural fixes) first. Identifies the lockstep constraint between `kb-search/SKILL.md` and `learning-retrieval-bench.sh:413-507` — both must change in the same PR or the bench measures the wrong strategy. Confirms `hr-observability-as-plan-quality-gate` is satisfied by the bench being the observability surface (rerunnable on demand). Flags Stage 3 (embeddings) as an ADR trigger requiring `/soleur:architecture create` before implementation. No capability gaps — existing components cover the work.

## Capability Gaps

None. `scripts/backfill-frontmatter.py` precedent exists; `learning-retrieval-bench.sh --cache-paraphrases` already supports cheap reruns; `kb-search` SKILL.md is the only strategy doc to edit; no new agents/skills needed.

## Session Errors

None this session. The premise probe (verify bench numbers exist + reconcile corpus count) succeeded on first attempt because the 2026-05-19 brainstorm and findings file are present in the worktree's main snapshot.

## Related

- Issue: #4119
- Blocks: #4042 (learnings archive via R@K signal — archive logic is premised on a working retriever)
- Source bench: `scripts/learning-retrieval-bench.sh`
- Source evidence: `knowledge-base/project/learnings/2026-05-19-retrieval-diagnostic-findings.md`, `knowledge-base/project/learning-retrieval-metrics-2026-05-19.json`
- Original (now-reopened) decision: `knowledge-base/project/brainstorms/2026-04-07-kb-retrieval-improvement-brainstorm.md`
- Sibling learnings: `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`, `knowledge-base/project/learnings/2026-05-19-cache-llm-outputs-flag-for-rerunnable-benches.md`, `knowledge-base/project/learnings/2026-05-19-brainstorm-pre-committed-ladder-and-data-source-granularity-check.md`
