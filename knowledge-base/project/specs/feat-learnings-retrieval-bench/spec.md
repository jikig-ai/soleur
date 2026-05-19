---
title: One-shot Retrieval Diagnostic for learnings/
status: draft
owner: engineering
issue: 4043
brainstorm: knowledge-base/project/brainstorms/2026-05-19-learnings-retrieval-bench-brainstorm.md
created: 2026-05-19
lane: cross-domain
brand_survival_threshold: none
---

# Spec: One-shot Retrieval Diagnostic for `knowledge-base/project/learnings/`

**Issue:** #4043
**Branch:** feat-learnings-retrieval-bench
**Brainstorm:** [2026-05-19-learnings-retrieval-bench-brainstorm.md](../../brainstorms/2026-05-19-learnings-retrieval-bench-brainstorm.md)

## Problem Statement

The 2026-04-07 KB retrieval brainstorm decided file-based retrieval (manifest + `kb-search` + standardized frontmatter) is correct AT CURRENT SCALE, and named the trigger for reconsidering RAG/embeddings as *"evidence that agents consistently fail to find relevant content despite having a manifest and standardized frontmatter."* No such evidence has ever been gathered. The learnings corpus has grown to 841 files; `/compound` keeps producing learnings; nobody knows whether the right learning gets found when a relevant situation re-occurs.

#4043 proposed a monthly cron benchmark. This spec reshapes it as a **one-shot diagnostic**: run once, write findings as a single learning, close #4043. Brainstorm rationale: at 841 files and one operator, the monthly-drift assumption isn't supported. A one-shot produces the missing evidence the prior brainstorm asked for, with three pre-committed outcome paths (close issue / file slug-rewrite follow-up / reopen RAG decision).

## Goals

- **G1.** Produce a single number per corpus-wide metric (R@5, R@10, MRR) computed via three paraphrase passes (identity / light / heavy) against both `kb-search` and bare grep.
- **G2.** Surface the worst-N learnings (R@5 = 0) as a concrete list with proposed cause classification (missing frontmatter, slug mismatch, cross-category dup, content shape).
- **G3.** Execute one of three pre-committed actions based on corpus-wide R@5 (see TR4).
- **G4.** Self-validate methodology against 7 named fixture seeds from learnings-research (slug mismatches, frontmatter holes, cross-category dupes) before reporting numbers.
- **G5.** Cost ceiling: **$5 total** for the one-shot diagnostic.

## Non-Goals

- **NG1.** Ongoing infrastructure (no `.github/workflows/` file, no cron, no recurring schedule).
- **NG2.** Mutating the existing `rule-metrics.json` schema. Output goes to a learning + an optional sibling JSON beside it.
- **NG3.** Improving any retrieval. This is measurement only. Slug rewrites or kb-search changes are out of scope; they would happen in follow-up PRs gated by the bucket action.
- **NG4.** Backfilling frontmatter on the 533 files missing it. Fallback extraction rules handle them.
- **NG5.** Embedding-based retrieval, vector DB, RAG. Excluded per 2026-04-07 brand and product constraints unless this diagnostic produces R@5 < 0.4 evidence.

## Functional Requirements

### FR1: Per-file evaluation across paraphrase intensity gradient

For each learning in `knowledge-base/project/learnings/*.md` (and `**/*.md` subdirs, excluding `archive/`):

1. Extract a "ground-truth problem statement" via this fallback chain:
   - YAML frontmatter `description:` field if present, else
   - Body content under `## Problem` section if present, else
   - First paragraph after `# Title`, else
   - First 500 chars of body.
2. Generate **three** query prompts:
   - **Identity:** the ground-truth problem statement verbatim. No LLM call.
   - **Light paraphrase:** synonym substitution. LLM call with paraphrase-light prompt.
   - **Heavy paraphrase:** problem reformulation in different framing. LLM call with paraphrase-heavy prompt.

### FR2: Dual lookup execution

For each of the three query prompts above, execute **both** lookup mechanisms and capture the ranked list of file paths returned:

- **`kb-search`:** invoke the skill (or its underlying grep two-tier strategy) with the query prompt as `$KEYWORD`. Parse markdown output ordering. Source file's rank = position in combined "Title Matches" + "Content Matches" output, or `null` if not in top-20.
- **`grep`:** `git grep -l -i <query-tokens> knowledge-base/project/learnings/` with naive top-K rank by file path order (lexicographic). Source file's rank = position in result list, or `null` if absent.

### FR3: Per-file metric computation

For each (file, paraphrase-intensity, lookup-mechanism) triple, compute:
- **Hit at K:** 1 if source file rank ≤ K, else 0 (for K=5, K=10).
- **Reciprocal rank:** `1/rank` if hit, else 0.

Aggregate corpus-wide:
- **R@5** = mean Hit@5 across all files
- **R@10** = mean Hit@10
- **MRR** = mean reciprocal rank

Report **six** corpus-wide R@5 values: {identity, light, heavy} × {kb-search, grep}. The headline number is **R@5(heavy, kb-search)**. The honesty signal is **R@5(identity, kb-search) − R@5(heavy, kb-search)** (the rewriter-loop gap). The skill ROI signal is **R@5(heavy, kb-search) − R@5(heavy, grep)**.

### FR4: Fixture-seed self-check

Before reporting corpus-wide numbers, validate against the 7 fixture seeds named in the brainstorm's learnings-research section. For each, classify the expected outcome (findable / unfindable) and confirm the bench produces a sensible result. If all 7 are "findable" at R@5, methodology is suspect; if all 7 are "unfindable," the diagnostic is detecting the right shapes. Report this self-check as a preamble in the output learning.

### FR5: Worst-N unfindable list

Surface the N learnings with R@5(heavy, kb-search) = 0 (max 20 entries). For each, classify the likely cause: `missing-frontmatter` (533/841 baseline), `slug-mismatch`, `cross-category-dup`, `content-shape` (no `## Problem`, 67/841 baseline), or `unknown`. This list IS the actionable output.

### FR6: Output as a single learning + sibling JSON

Write findings to **`knowledge-base/project/learnings/2026-05-19-retrieval-diagnostic-findings.md`** with the structure:
- Frontmatter (category: `workflow-patterns`, tags: `retrieval, kb-search, compound, benchmark`)
- `## TL;DR` (one paragraph: bucket result + recommended next action)
- `## Methodology` (3-pass gradient, dual lookup, fixture-seed self-check)
- `## Results` (table of 6 R@5 values, R@10, MRR, gap signals)
- `## Worst-N Unfindable` (FR5 list with causes)
- `## Action Taken` (which bucket, what gets filed)

Also emit a sibling raw-numbers JSON at `knowledge-base/project/learning-retrieval-metrics-2026-05-19.json` (date-stamped to make it explicit this is a one-shot snapshot, not a recurring metrics file).

## Technical Requirements

### TR1: Script location and language

Implement as `scripts/learning-retrieval-bench.sh` (bash). Reuse the curl+jq Anthropic-API call pattern from `scripts/compound-promote.sh` lines 124-200 (NDJSON tempfile + `jq -s` slurp pattern, ADR-021 forbids claude-code-action here). Sibling to `scripts/rule-metrics-aggregate.sh`.

### TR2: Model + cost ceiling

Use Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) via direct Anthropic API, leveraging the Batch API for 50% discount (24h SLA acceptable for one-shot). Cost target: ≤ $5 (841 files × 2 LLM calls per file (light + heavy; identity is free) × ~$0.001 × 0.5 = ~$0.84; budget includes retries).

### TR3: Frontmatter / content extraction fallbacks

Per learnings-research: 533/841 learnings lack YAML frontmatter, 67/841 lack `## Problem`. Extraction must follow the fallback chain in FR1. Use the awk frontmatter-parsing pattern from `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` (`/^---$/{c++; next} c==1`) to avoid `---` horizontal-rule false-matches inside body content.

### TR4: Pre-committed bucket actions

Branch on corpus-wide **R@5(heavy, kb-search)**:

- **R@5 ≥ 0.7:** Close #4043 with comment linking the output learning. No further action. Result: brand and product framing of 2026-04-07 vindicated.
- **R@5 ∈ [0.4, 0.7):** Close #4043. File ONE follow-up issue: "Slug/frontmatter rewrite sweep on worst-N learnings (R@5 = 0)" — milestone Post-MVP / Later. List the worst-N as acceptance-criteria checklist.
- **R@5 < 0.4:** Close #4043. File ONE follow-up issue: "Reopen 2026-04-07 RAG/embeddings decision — retrieval evidence triggers reconsideration." Milestone: same as the trigger threshold demands (whatever phase the brainstorm picks).

The action is pre-committed in this spec; the operator does NOT negotiate the response after seeing the numbers. (CPO vanity-metric mitigation.)

### TR5: `synced_to:` frontmatter handling

If a learning's frontmatter contains `synced_to: <path>`, treat BOTH paths as "correct hits" when the source-file rank is computed. Cross-filed learnings already exist (research surfaced `2026-03-06-disambiguation-budget-compounds-with-domain-size.md`); both filings count.

### TR6: kb-search cap awareness

`kb-search` returns max 20 results in two tiers (Title Matches, Content Matches). Bench parses the combined ordering. Rank = position in concatenated list. Ties within a tier (same title-match-strength) broken by file path order.

### TR7: Cost gate

Print estimated cost (file count × 2 LLM calls × Haiku rate × 0.5 Batch discount) and require explicit `--confirm` flag to proceed. Halt if estimate exceeds $5.
