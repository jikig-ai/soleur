---
title: Tasks — One-shot Retrieval Diagnostic for learnings/
issue: 4043
pr: 4045
branch: feat-learnings-retrieval-bench
plan: knowledge-base/project/plans/2026-05-19-feat-learnings-retrieval-bench-plan.md
spec: knowledge-base/project/specs/feat-learnings-retrieval-bench/spec.md
lane: cross-domain
---

# Tasks: One-shot Retrieval Diagnostic

## Phase 1: Script Skeleton + Phase 0 Preconditions

- [x] 1.1 Create `scripts/learning-retrieval-bench.sh` with shebang, `set -euo pipefail`, header comment citing the plan + spec + brainstorm paths and the sibling `scripts/compound-promote.sh` LLM-curl precedent.
- [x] 1.2 Implement arg parsing: `--confirm`, `--self-test`, `--corpus-count-override <N>`, `--help`. Without `--confirm` and not `--self-test`: print cost estimate and exit 0 (informational).
- [x] 1.3 Implement Phase 0 preconditions:
  - [x] 1.3.1 `ANTHROPIC_API_KEY` non-empty check (fail-fast with actionable error).
  - [x] 1.3.2 `command -v {jq,curl,git,awk,sed,grep}` check.
  - [x] 1.3.3 `git rev-parse --is-bare-repository` returns `false` check.
  - [x] 1.3.4 Corpus count via `find ... | wc -l` with `100 ≤ N ≤ 5000` sanity (respect `--corpus-count-override`).
  - [x] 1.3.5 Split cost computation (light + heavy at distinct rates) + 10% headroom; exit if > $5.00.

## Phase 2: Corpus Indexing + Ground-Truth Extraction

- [x] 2.1 Implement YAML frontmatter parser using canonical `/^---$/{c++; next} c==1` block detection.
- [x] 2.2 Implement scalar-value extraction with canonical `gsub` strip pattern (precedent: `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34`).
- [x] 2.3 Implement `synced_to:` two-branch parser:
  - [x] 2.3.1 Scalar branch: same-line non-whitespace after colon → gsub-strip.
  - [x] 2.3.2 List branch: consume `^[[:space:]]+-[[:space:]]*` lines until next top-level key or blank.
- [x] 2.4 Implement `## Problem` section extractor (sed range minus boundaries).
- [x] 2.5 Implement `# Title` first-paragraph extractor.
- [x] 2.6 Implement fallback-chain orchestrator (description → problem → title-para → first-500).
- [x] 2.7 Walk corpus and emit NDJSON to `/tmp/corpus.ndjson` with `{path, ground_truth, has_frontmatter, has_problem_section, synced_to: [...]}`.
- [x] 2.8 Compute and stash extraction stats: `has_frontmatter_pct`, `has_problem_section_pct`, `fallback_distribution`.

## Phase 3: Paraphrase Generation

- [x] 3.1 Build light + heavy paraphrase prompts as named bash variables.
- [x] 3.2 Implement Anthropic curl call using `compound-promote.sh:124-200` pattern (`x-api-key`, `anthropic-version: 2023-06-01`, model `claude-haiku-4-5-20251001`, max_tokens 512).
- [x] 3.3 Parse `.content[0].text` from response; handle `stop_reason == max_tokens` warning.
- [x] 3.4 **Strip newlines from paraphrase output** via `tr -d '\n\r' | tr -s ' '` BEFORE writing to NDJSON.
- [x] 3.5 Implement per-call retry-once with 5s backoff on HTTP non-2xx; second failure → record `(API_ERROR)`, count in `api_stats.errors`, continue.
- [x] 3.6 Sequential per-file iteration; progress print every 50 files.
- [x] 3.7 Emit paraphrases to `/tmp/paraphrases.ndjson` with `{path, identity, light, heavy}`.

## Phase 4: Dual-Retriever Lookup

- [x] 4.1 Implement `kbsearch_rank()` two-tier emulator:
  - [x] 4.1.1 Tier 1: `grep -in -F -- "$query" knowledge-base/INDEX.md | head -20 | sed -nE 's/.*\]\(([^)]+)\).*/\1/p'` (extract link target, NOT line number).
  - [x] 4.1.2 Tier 2: `git grep -l -i -F -- "$query" -- 'knowledge-base/**/*.md' ':!knowledge-base/INDEX.md' ':!**/archive/**' | head -20`.
  - [x] 4.1.3 Combined ordering: tier1 first preserving order, then tier2 dedupe-excluding tier1.
- [x] 4.2 Implement `grep_rank()` learnings-only emulator with same `-F --` safety.
- [x] 4.3 Implement min-rank semantics for `synced_to`: source rank = min across `{source_path, synced_to[...]}` in retriever result list.
- [x] 4.4 Hardcode the 7 fixture-seed paths as a bash array; produce per-seed rank rows for the output.
- [x] 4.5 Iterate file × {identity, light, heavy} × {kbsearch, grep} = 6 lookups per file; emit `/tmp/ranks.ndjson` with `{path, intensity, retriever, rank}`.

## Phase 5: Metric Aggregation

- [x] 5.1 Per-row compute: `hit@5`, `hit@10`, `reciprocal_rank`.
- [x] 5.2 Corpus-wide aggregate via `jq`: 6 × R@5, 6 × R@10, 6 × MRR.
- [x] 5.3 Compute `gap_honesty = r5.identity_kbsearch - r5.heavy_kbsearch` and `gap_skill_roi = r5.heavy_kbsearch - r5.heavy_grep`.
- [x] 5.4 Build worst-N list (max 20) where `rank_heavy_kbsearch IS null`; classify cause per entry: `missing-frontmatter` | `slug-mismatch` | `cross-category-dup` | `content-shape` | `unknown`.
- [x] 5.5 Determine bucket from `r5.heavy_kbsearch` and locked thresholds: `≥0.7 → vindicate`, `[0.4, 0.7) → surface-rewrites`, `<0.4 → reopen-rag`.

## Phase 6: Output Artifact Generation

- [x] 6.1 Build sibling JSON with the full schema (see plan §Phase 5 schema block).
- [x] 6.2 Write JSON to `knowledge-base/project/learning-retrieval-metrics-$(date +%Y-%m-%d).json` atomically.
- [x] 6.3 Render output learning markdown with TL;DR, Methodology (3-pass framing + min-rank synced_to + kb-search-strategy-not-skill), Results (corpus 6-row + fixture 7-row), Worst-N, Recommended Action (bucket + verbatim `gh issue close 4043 --comment "…"`).
- [x] 6.4 Write learning to `knowledge-base/project/learnings/$(date +%Y-%m-%d)-retrieval-diagnostic-findings.md` atomically.
- [x] 6.5 Print bucket name + `gh issue close 4043` line to stdout for operator.

## Phase 7: `--self-test` Mode (Inline Tests)

- [x] 7.1 Implement `self_test()` function gated on `--self-test` flag.
- [x] 7.2 Test case (a): fixture with full frontmatter + `## Problem` → ground-truth = problem body.
- [x] 7.3 Test case (b): empty `description:` → falls through to `## Problem`.
- [x] 7.4 Test case (c): missing `## Problem` → falls through to `# Title` paragraph.
- [x] 7.5 Test case (d): all extraction sections absent → first-500-chars used.
- [x] 7.6 Test case (e): `synced_to: <path>` scalar form parsed as 1-element array.
- [x] 7.7 Test case (f): `synced_to:\n  - <a>\n  - <b>` list form parsed as 2-element array.
- [x] 7.8 Test case (g): mid-body `---` horizontal rule NOT misparsed as frontmatter close.
- [x] 7.9 Cost-gate test: `--corpus-count-override 5000 --confirm` exits non-zero with "exceeds $5 ceiling" in stderr.
- [x] 7.10 `grep -F --` shell-safety test: query containing `$(rm -rf ~)` and `-e foo` greps literally; no shell expansion observed.
- [x] 7.11 Newline-strip test: simulated multi-line paraphrase becomes single line before grep.
- [x] 7.12 All fixtures via `mktemp -d` + synthesized content (per `cq-test-fixtures-synthesized-only`); env vars `LEARNINGS_ROOT`/`INDEX_PATH`/`OUTPUT_DIR`/`CURL_BIN` redirect script behavior.
- [x] 7.13 PASS/FAIL/TOTAL counters; exit non-zero if any FAIL.

## Phase 8: Pre-merge Bench Run + PR Closure

- [ ] 8.1 Operator: ensure `ANTHROPIC_API_KEY` is in env.
- [ ] 8.2 Operator: `bash scripts/learning-retrieval-bench.sh` (no `--confirm`) → verify cost estimate prints.
- [ ] 8.3 Operator: `bash scripts/learning-retrieval-bench.sh --confirm` → ~50 min wall clock, ~$2.68 spend.
- [ ] 8.4 Verify run produced both output files; jq-validate the JSON schema per AC5.
- [ ] 8.5 Read the output learning; verify bucket recommendation aligns with `r5.heavy_kbsearch` and locked thresholds.
- [ ] 8.6 Commit both output files: `git add knowledge-base/project/learnings/*-retrieval-diagnostic-findings.md knowledge-base/project/learning-retrieval-metrics-*.json && git commit -m "docs: retrieval diagnostic findings for #4043"`.
- [ ] 8.7 If bucket = `surface-rewrites` or `reopen-rag`: operator authors the appropriate `gh issue create` follow-up (the bench prints the bucket name, not template text — issue title/body is operator judgment).
- [ ] 8.8 Update PR body to include `Closes #4043` + paste the output learning's TL;DR.
- [ ] 8.9 Run `gh pr ready 4045` → trigger CI → auto-merge per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

## Phase 9: Spec Amendment (one-shot)

- [ ] 9.1 If the operator accepted the sync-vs-Batch plan deviation: amend spec.md TR2 to reflect "sync API, one-shot, ~$2.68 actual cost (vs ~$1.34 Batch theoretical)" and commit alongside the bench artifacts.
