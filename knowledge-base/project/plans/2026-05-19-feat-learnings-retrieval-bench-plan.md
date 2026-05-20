---
title: One-shot Retrieval Diagnostic for learnings/ — Implementation Plan
date: 2026-05-19
issue: 4043
pr: 4045
branch: feat-learnings-retrieval-bench
spec: knowledge-base/project/specs/feat-learnings-retrieval-bench/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-19-learnings-retrieval-bench-brainstorm.md
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# Plan: One-shot Retrieval Diagnostic for `knowledge-base/project/learnings/`

## Overview

Ship `scripts/learning-retrieval-bench.sh` — a one-shot bash diagnostic that measures whether `/compound`-produced learnings are findable via the lookup mechanism agents use today (kb-search's two-tier grep strategy + bare `git grep`). For each of ~1117 files in `knowledge-base/project/learnings/` (excluding `archive/`), the script generates three query intensities (identity verbatim, light LLM paraphrase, heavy LLM paraphrase), executes both retrievers against each, and reports six corpus-wide R@5 values plus R@10/MRR/gap signals.

**Closure model:** the operator runs the bench on the feature branch BEFORE marking PR #4045 ready. The output learning + sibling JSON commit to the feature branch. PR body uses `Closes #4043`. Merge atomically closes the issue. No post-merge ceremony, no follow-up forgetting.

Pre-committed bucket thresholds (locked here BEFORE any number lands):
- **R@5(heavy, kbsearch) ≥ 0.7** → bucket `vindicate` — `Closes #4043`, no follow-up issue.
- **R@5(heavy, kbsearch) ∈ [0.4, 0.7)** → bucket `surface-rewrites` — `Closes #4043`, file follow-up for worst-N slug/frontmatter rewrites in the same PR.
- **R@5(heavy, kbsearch) < 0.4** → bucket `reopen-rag` — `Closes #4043`, file follow-up to reopen the 2026-04-07 RAG decision.

The bench prints the bucket name and the single verbatim `gh issue close 4043 --comment "…"` line; the operator runs it before marking PR ready. Follow-up `gh issue create` (for surface-rewrites / reopen-rag) is operator-authored — the bench prints the bucket name, not template text.

## Implementation Phases

### Phase 0: Preconditions (~5 s, no LLM)

- Verify `ANTHROPIC_API_KEY` non-empty; else exit 1 with "Set ANTHROPIC_API_KEY before running."
- Verify deps: `command -v {jq,curl,git,awk,sed,grep}`; missing → exit 1.
- Verify worktree (not bare): `git rev-parse --is-bare-repository` returns `false`; else exit 1.
- Count corpus: `find knowledge-base/project/learnings -type f -name "*.md" -not -path "*/archive/*" | wc -l` → `N`. Sanity: `100 ≤ N ≤ 5000`; else exit 1.
- `--corpus-count-override <N>` flag short-circuits the count (test-only; documented in `--help`).
- Compute cost separately for light + heavy passes:
  - `light_cost = N × $0.0010` (Haiku input ~150 tok + output ~80 tok)
  - `heavy_cost = N × $0.0015` (heavy outputs trend longer)
  - Print `light_cost + heavy_cost + 10% headroom`.
- If estimate > $5.00 → exit 1.
- Without `--confirm` → exit 0 informational.

### Phase 1: Corpus Indexing & Ground-Truth Extraction (~30 s)

Walk corpus → build per-file record via fallback chain:

1. YAML frontmatter `description:` (canonical awk: `/^---$/{c++; next} c==1` then grep `^description:` then `gsub(/^description:[[:space:]]*"?|"?$/,"")`)
2. Body under `## Problem` (sed range `/^## Problem$/,/^## /` minus boundary lines)
3. First paragraph after `# Title` (awk `/^# /` then `/^$/` terminator)
4. First 500 chars of body (final fallback)

Truncate ground-truth to 2000 chars (LLM prompt budget).

**`synced_to:` parsing (both shapes):**
- After locating `^synced_to:` line: if same line has non-whitespace after colon → scalar branch (gsub-strip).
- Else: consume following `^[[:space:]]+-[[:space:]]*` lines as a list until next top-level `^[a-z_]+:` key or blank line. Emit as JSON array.

Emit NDJSON to `/tmp/corpus.ndjson`: `{path, ground_truth, has_frontmatter, has_problem_section, synced_to: [...]}`.

Print extraction stats (used downstream in JSON output): `has_frontmatter_pct`, `has_problem_section_pct`, `fallback_distribution` (counts per chain step).

### Phase 2: Paraphrase Generation (~50 min sync, ~$2.68)

For each NDJSON line, two Anthropic curl calls (light + heavy) reusing `scripts/compound-promote.sh:124-200` pattern (`x-api-key`, `anthropic-version: 2023-06-01`, `claude-haiku-4-5-20251001`, max_tokens=512).

**Newline strip mandatory:** Phase 3 uses `grep -F --` which would search literally across newlines; LLM outputs occasionally contain `\n`. After parsing `.content[0].text`, strip with `tr -d '\n\r' | tr -s ' '` before writing to paraphrases NDJSON.

Per-call retry-once on HTTP non-2xx with 5s backoff; second failure → record `(API_ERROR)`, count in `api_stats.errors`, continue. Sequential by default (rate-limit safety).

### Phase 3: Dual-Retriever Lookup (~5 min)

For each (file × {identity, light, heavy} × {kbsearch, grep}) = 6 × 1117 = 6702 lookups.

**kb-search strategy emulator — bash replication of two-tier grep:**

```bash
kbsearch_rank() {
  local query="$1" source_path="$2" synced_paths="$3"
  # Tier 1: title matches in INDEX.md — extract markdown link target, not line number
  local tier1
  tier1=$(grep -in -F -- "$query" knowledge-base/INDEX.md \
    | head -20 \
    | sed -nE 's/.*\]\(([^)]+)\).*/\1/p')
  # Tier 2: content matches across knowledge-base/, excluding INDEX.md + archive/
  local tier2
  tier2=$(git grep -l -i -F -- "$query" -- 'knowledge-base/**/*.md' \
    ':!knowledge-base/INDEX.md' ':!**/archive/**' 2>/dev/null \
    | head -20)
  # Combined ordering: tier1 first (preserved order), then tier2 (excluding tier1 paths)
  # Source rank: min position across {source_path, synced_paths...} in combined list
  # null if no path appears in top-20 combined
  ...
}
```

**grep strategy:** `git grep -l -i -F -- "$query"` against `knowledge-base/project/learnings/**/*.md` excluding `**/archive/**`, head -20.

**Rank semantics (`synced_to` cross-filings = min-rank, NOT either-counts):** if source file appears at position P and any `synced_to[i]` appears at position Q < P, use Q. This biases R@5 upward vs. the strict "source-only" definition; documented inline in the output learning's Methodology section.

**Per-seed sub-corpus (folded-in fixture self-check):** the 7 hardcoded fixture-seed paths get their own per-row entry in the JSON output's `fixture_seeds` array, so the results table can show them alongside corpus-wide numbers without a separate self-check pass.

Hardcoded fixture seeds:
1. `knowledge-base/project/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`
2. `knowledge-base/project/learnings/2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`
3. `knowledge-base/project/learnings/2026-04-14-plan-prescribed-test-framework-not-available.md`
4. `knowledge-base/project/learnings/2026-03-21-kb-migration-verification-pitfalls.md`
5. `knowledge-base/project/learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`
6. `knowledge-base/project/learnings/2026-03-05-awk-scoping-yaml-frontmatter-shell.md`
7. `knowledge-base/project/learnings/2026-03-06-disambiguation-budget-compounds-with-domain-size.md`

### Phase 4: Metric Aggregation (~2 s)

Per row: `hit@5 = (rank != null && rank ≤ 5)`, `hit@10` same, `RR = rank != null ? 1/rank : 0`.

Aggregate corpus-wide for each (intensity × retriever) combo:
- 6 × R@5, 6 × R@10, 6 × MRR
- **Honesty gap:** `R@5(identity, kbsearch) − R@5(heavy, kbsearch)`
- **Skill ROI gap:** `R@5(heavy, kbsearch) − R@5(heavy, grep)`
- **Worst-N:** files with `R@5(heavy, kbsearch) = 0`, cap 20. Cause classification per entry: `missing-frontmatter` | `slug-mismatch` | `cross-category-dup` | `content-shape` | `unknown`.

Determine bucket from `R@5(heavy, kbsearch)` and the locked thresholds (Overview).

### Phase 5: Output Artifact Generation (~5 s)

Write two files atomically:

- **Learning:** `knowledge-base/project/learnings/$(date +%Y-%m-%d)-retrieval-diagnostic-findings.md`
  - Frontmatter: `category: workflow-patterns`, `tags: [retrieval, kb-search, compound, benchmark, diagnostic]`, `problem_type: workflow_diagnostic`
  - `## TL;DR` (one paragraph: bucket + headline R@5 + recommended action)
  - `## Methodology` (3-pass gradient, dual retriever, min-rank synced_to semantics, kb-search-strategy-not-skill framing)
  - `## Results` (corpus-wide 6×R@5 table + R@10/MRR + 7-row fixture-seed per-seed table + gap signals)
  - `## Worst-N Unfindable` (cause-classified list)
  - `## Recommended Action` (bucket name + verbatim `gh issue close 4043 --comment "…"`)

- **Sibling JSON:** `knowledge-base/project/learning-retrieval-metrics-$(date +%Y-%m-%d).json`
  ```json
  {
    "schema": 1,
    "generated_at": "<ISO8601 UTC>",
    "corpus_count": 1117,
    "model_id": "claude-haiku-4-5-20251001",
    "prompts": { "light": "...", "heavy": "..." },
    "extraction_stats": {
      "has_frontmatter_pct": 0.0,
      "has_problem_section_pct": 0.0,
      "fallback_distribution": { "description": 0, "problem_section": 0, "title_paragraph": 0, "first_500": 0 }
    },
    "api_stats": { "calls_made": 0, "retries": 0, "errors": 0 },
    "cost_estimate_usd": 0.0,
    "r5": {
      "identity_kbsearch": 0.0, "light_kbsearch": 0.0, "heavy_kbsearch": 0.0,
      "identity_grep": 0.0, "light_grep": 0.0, "heavy_grep": 0.0
    },
    "r10": { /* same shape */ },
    "mrr": { /* same shape */ },
    "gap_honesty": 0.0,
    "gap_skill_roi": 0.0,
    "fixture_seeds": [ { "path": "...", "rank_heavy_kbsearch": null, "rank_heavy_grep": null } ],
    "worst_n": [ { "path": "...", "rank_heavy_kbsearch": null, "cause": "missing-frontmatter" } ],
    "bucket": "vindicate|surface-rewrites|reopen-rag"
  }
  ```

The script prints the bucket name + verbatim `gh issue close 4043 --comment` to stdout for the operator to copy.

## Files to Create

| File | Note |
|---|---|
| `scripts/learning-retrieval-bench.sh` | Main script + `--self-test` mode (synthetic fixtures inline). |
| `knowledge-base/project/specs/feat-learnings-retrieval-bench/tasks.md` | Generated post-plan from this plan. |

**Run-time outputs (created by the bench on the feature branch BEFORE PR ready):**
- `knowledge-base/project/learnings/<date>-retrieval-diagnostic-findings.md`
- `knowledge-base/project/learning-retrieval-metrics-<date>.json`

## Files to Edit

- `knowledge-base/project/specs/feat-learnings-retrieval-bench/spec.md` — amend TR2 (Batch API → sync) once operator accepts the deviation.

## User-Brand Impact

**If this lands broken, the user experiences:** wasted ~50 min + $2.68 on a bench whose numbers don't reflect actual retrieval quality. Output learning could mislead a future RAG-reopen decision.

**If this leaks, the user's data is exposed via:** Anthropic API (same data flow as production `scripts/compound-promote.sh`; additive use, not a new vector). Learnings are operator workflow meta-reflections, not customer data.

**Brand-survival threshold:** **none**.

**threshold: none, reason:** This PR adds a one-shot bash diagnostic under `scripts/`; it does not touch `apps/*/server/`, schemas, migrations, auth flows, or user-facing UI. Run-time output lands under `knowledge-base/project/learnings/` (a sensitive path) but is operator-authored workflow content, not a runtime artifact emitted per request. The Anthropic data flow is pre-existing.

## Acceptance Criteria

All pre-merge (atomic closure via `Closes #4043`):

1. **AC1.** `scripts/learning-retrieval-bench.sh` exists, executable, passes `bash -n`. Invoking `bash scripts/learning-retrieval-bench.sh --self-test` exits 0 with PASS > 0 and FAIL = 0.
2. **AC2.** `--self-test` covers ≥7 cases via synthesized fixtures (`cq-test-fixtures-synthesized-only`): (a) full frontmatter + `## Problem`, (b) empty `description:` falls through to `## Problem`, (c) `## Problem` absent falls through to `# Title` paragraph, (d) all sections absent falls to first-500-chars, (e) `synced_to:` scalar form parsed, (f) `synced_to:` list form parsed, (g) mid-body `---` horizontal rule NOT misparsed as frontmatter boundary.
3. **AC3.** Cost-gate enforced: invoking without `--confirm` exits 0 with cost estimate printed. Invoking with `--confirm --corpus-count-override 5000` exits non-zero with "exceeds $5 ceiling" in stderr.
4. **AC4.** A full `--confirm` run completes on the feature branch and produces `knowledge-base/project/learnings/<date>-retrieval-diagnostic-findings.md` + `knowledge-base/project/learning-retrieval-metrics-<date>.json`, both committed to the PR.
5. **AC5.** Output JSON conforms to Phase 5 schema. `jq -e` asserts presence of: `schema == 1`, `generated_at`, `corpus_count`, `model_id`, `prompts.{light,heavy}`, `extraction_stats.{has_frontmatter_pct, has_problem_section_pct, fallback_distribution}`, `api_stats.{calls_made,retries,errors}`, `r5.{identity,light,heavy}_{kbsearch,grep}` (6 keys), `r10` and `mrr` same shape, `gap_honesty`, `gap_skill_roi`, `fixture_seeds` (array length 7), `worst_n`, `bucket in {vindicate,surface-rewrites,reopen-rag}`.
6. **AC6.** Output learning's `## Recommended Action` section names the bucket (one of `vindicate`/`surface-rewrites`/`reopen-rag`) AND includes the verbatim `gh issue close 4043 --comment "…"` line consistent with that bucket. Operator runs this line before marking PR ready, then `Closes #4043` in PR body atomically closes on merge.

## Sharp Edges

- **`grep -F --` shell-safety contract.** Phase 3 retrieval functions pass LLM-paraphrased queries to `grep -F -- "$query"`. Three layers of safety: (1) double-quoting `"$query"` prevents shell expansion (`$(...)`, backticks, glob) before grep sees the arg; (2) `-F` disables regex interpretation inside grep; (3) `--` end-of-options prevents flag-injection when the query starts with `-` (e.g., `-e`, `--help`). All three required; dropping any one introduces an exposure. Test case: pass a paraphrase containing `$(rm -rf ~)` and `-e foo` and confirm grep returns literal matches only.
- **Multi-line LLM paraphrases break `grep -F`.** Haiku sometimes returns paraphrases containing `\n`. Phase 2 strips `\n\r` via `tr -d '\n\r' | tr -s ' '` BEFORE writing to the paraphrases NDJSON. Without this strip, `grep -F` searches literally for the two-line string and returns 0 hits, silently inflating the unfindable count.
- **`synced_to:` min-rank semantics (NOT either-counts).** Phase 3 picks the BEST rank across `{source_path, synced_to[...]}`. This is more generous than spec TR5's literal "both filings count" reading — the bench reports the best findability across all filings, biasing R@5 upward. Documented in the output learning's Methodology section so a future reader doesn't conflate the two definitions.
- **kb-search tier-1 returns LINK TARGETS, not line numbers.** The two-tier-grep replication MUST extract markdown link targets via `sed -nE 's/.*\]\(([^)]+)\).*/\1/p'`. A literal `awk -F: '{print $1}'` over `grep -n` output would return INDEX.md line numbers, which are useless as rank participants — the comparison set is learning PATHS, not INDEX.md line numbers.
- **Rewriter–retriever vocabulary loop (CTO HIGH-severity).** The honesty gap `R@5(identity, kbsearch) − R@5(heavy, kbsearch)` is the load-bearing methodology signal. If the gap is < 0.05 the heavy paraphrase is too close to identity and the prompts need tightening before the corpus numbers can be treated as load-bearing. The 7-row fixture-seed sub-table is the secondary visual check — if all 7 score 0 or all 7 score 1, methodology is suspect even if the corpus gap looks healthy.
- **`git grep` outside the bare repo.** The bench MUST run inside a worktree (or main checkout). Phase 0 verifies `git rev-parse --is-bare-repository` returns `false`.
- **Bucket thresholds are locked BEFORE running.** The 0.7 / 0.4 thresholds are committed in this plan body BEFORE any number lands. Operator does NOT renegotiate them post-bench. If the operator wants different thresholds, they amend the plan in a separate commit ahead of running the bench — not after seeing the numbers.
- **Output learning filename uses run-day date.** `$(date +%Y-%m-%d)` at script run time, not plan-write date. Avoids the "Do not prescribe exact dated filenames" sharp-edge from PR #2226.
- **A plan whose `## User-Brand Impact` section is empty / TBD / TODO fails `deepen-plan` Phase 4.6.** Already filled above with threshold=none + scope-out bullet.

## Open Code-Review Overlap

73 open code-review issues queried. Path-overlap on planned files: **none** (script doesn't exist on main). Topical overlap:
- **#3321 (CODEOWNERS for `knowledge-base/project/learnings/`)** — different concern (access control). **Disposition: Acknowledge.** No coupling either direction.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Operations (COO) — carried forward from brainstorm. See `2026-05-19-learnings-retrieval-bench-brainstorm.md` `## Domain Assessments`. No new fan-out.

**Product/UX Gate:** NONE — script-only change, no user-facing UI.

## GDPR Gate

(a) and (c) triggers fire weakly: the bench sends learnings to Anthropic, but the same data flow already exists via `scripts/compound-promote.sh`. **Decision:** skip in-PR `/soleur:gdpr-gate` invocation. File follow-up at merge time: "Compliance audit of Anthropic API data flows: compound-promote.sh + learning-retrieval-bench.sh" (milestone Post-MVP / Later).

## IaC Gate

No infrastructure introduced (no SSH/systemd/Doppler/Terraform/cron/vendor/DNS/TLS/firewall/webhook). **Skip silently.**

## Test Strategy

- `--self-test` mode runs synthesized-fixture unit tests inline in the script. No separate `.test.sh` file.
- Fixtures built via `mktemp -d` inside the self-test function; env vars (`LEARNINGS_ROOT`, `INDEX_PATH`, `OUTPUT_DIR`) redirect script reads/writes; `CURL_BIN` overrideable for API mocking; `LIVE_API=1` opts in to live calls.
- Cost-gate test uses `--corpus-count-override 5000` to exercise the ceiling without writing 5000 files.

## Plan Deviation Candidates

1. **Sync API instead of Batch API.** Spec TR2 says Batch (50% off, 24h SLA). Plan ships sync — cost delta ~$0.84 one-time; complexity delta ~150 LoC saved on JSONL marshaling + polling. Operator confirms this deviation; if rejected, the script grows by ~150 LoC and the self-test grows Batch-API mock fixtures.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Sustained Anthropic 429s halt the run mid-stream | Low | Retry-once with 5s backoff; sustained → exit with clear count + resumability guidance (rerun on remaining files; LLM calls are independent) |
| Multi-line LLM paraphrase output breaks Phase 3 grep | Already mitigated | Phase 2 strip rule mandatory; tested in `--self-test` |
| `synced_to:` list-form silently drops cross-filings | Already mitigated | Phase 1 explicit branch; tested in `--self-test` (AC2-f) |
| `cq-test-fixtures-synthesized-only` violation | Caught at plan-review | Self-test fixtures all built via mktemp; no real-learning content |
| Run-time learning collides with operator's same-day learning name | Negligible | Date + `-retrieval-diagnostic-findings` is unique by topic |

NEVER CODE — this plan is the design contract. Implementation in `/soleur:work`.
