---
feature: feat-kb-search-paraphrase-pre-pass-4176
issue: 4176
date: 2026-05-20
status: ready-for-work
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-05-20-feat-kb-search-paraphrase-pre-pass-plan.md
spec: knowledge-base/project/specs/feat-kb-search-paraphrase-pre-pass-4176/spec.md
draft_pr: 4183
---

# Tasks: kb-search Stage 2 — LLM paraphrase pre-pass (#4176)

Three implementation phases + two post-merge operator-acked phases.

## Phase 0: Preconditions (narrative)

- [x] **0.1** `git branch --show-current` returns `feat-kb-search-paraphrase-pre-pass-4176`.
- [x] **0.2** Confirm warm corpus cache exists: `ls -la /tmp/kb-bench-2026-05-20/paraphrases.ndjson` shows 1147 entries.
- [x] **0.3** Spot-check bench script line numbers: `grep -nE 'kbsearch_rank|self_test_flooding_pathology|self_test\(|PROMPT_LIGHT|PROMPT_HEAVY' scripts/learning-retrieval-bench.sh`. Plan cites 320-321 / 494 / 637 (start of `self_test_flooding_pathology`, body ends ~671) / 673 (dispatcher) / 1187 (aggregation). Adjust later phase references if drift.
- [x] **0.4** Read `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` for sibling test-driver pattern.

## Phase 1: RED — synthesized self-test fixture (commit 1)

- [x] **1.1** Add `self_test_paraphrase_prepass()` function to `scripts/learning-retrieval-bench.sh` immediately before `self_test()` dispatcher (~line 671). `cq-test-fixtures-synthesized-only` comment per the existing precedent at the flooding-pathology fixture.
- [x] **1.2** Fixture creates synthesized learning at `<tmp>/knowledge-base/project/learnings/orm-target.md` with frontmatter `category: performance-issues, tags: [n+1]` and body `# ORM N+1 query under burst load\n\ndatabase connection pool exhaustion under burst load occurs when transaction allocation rate exceeds the configured maximum, producing TimeoutError on subsequent queries`.
- [x] **1.3** Test query: `"ORM saturating worker pool"` (zero lexical overlap with content).
- [x] **1.4** Assertion 1 (PASSES at this commit): baseline `kbsearch_rank` returns `rank=null` for the query against the target — negative control demonstrating the failure shape.
- [x] **1.5** Assertion 2 (FAILS at this commit by design): Stage 2 `kbsearch_rank` (union-of-paraphrases via `anthropic_paraphrase` with `PROMPT_QUERY_PARAPHRASE`) returns `rank ≤ 8`. Phase 2 makes this green.
- [x] **1.6** Invoke `self_test_paraphrase_prepass` from `self_test()` dispatcher.
- [x] **1.7** Verify `bash scripts/learning-retrieval-bench.sh --self-test` exits non-zero (assertion 2 fails). This is the RED state.
- [x] **1.8** Commit: `test(kb-search): add Stage 2 RED self-test fixture for paraphrase pre-pass (#4176)`.

## Phase 2: GREEN — atomic TR2 commit (commit 2)

Single atomic commit. All four files below land in ONE `git commit`.

### 2.A `scripts/learning-retrieval-bench.sh`

- [x] **2.A.1** Add `PROMPT_QUERY_PARAPHRASE` constant near line 322 (beside `PROMPT_LIGHT`/`PROMPT_HEAVY`). Prompt text per plan §Phase 2 File 1.
- [x] **2.A.2** Add `# stage-2-paraphrase-union-v1` comment line above the new logic block in `kbsearch_rank()` (TR2 lockstep token).
- [x] **2.A.3** Extend `kbsearch_rank()` (line 494) per plan §Phase 2 File 1: compute baseline two-tier rank; if combined tier-1+tier-2 unique-path count `< 5` AND `--no-paraphrase` NOT passed AND query does NOT match sensitive-query regex `((=|:)\s*[a-zA-Z0-9+/]{16,}|sk-[a-zA-Z0-9]{20,}|dsn=)` (case-insensitive), generate exactly 3 variants via `for i in 1 2 3; do anthropic_paraphrase "$PROMPT_QUERY_PARAPHRASE" "$query"; done`, dedupe variants by exact-string-match, run two-tier rank per variant, union by path, return min-rank-across-variants.
- [x] **2.A.4** Add `--no-paraphrase` bench-side flag parsing near line 84. Variant count is the **constant 3** (no flag).
- [x] **2.A.5** Extend Phase 4 metric aggregation (~line 1187) to emit `r5_identity`, `r5_light`, `r5_heavy` as top-level JSON keys. No per-variant rank attribution in this PR (deferred).

### 2.B `plugins/soleur/skills/kb-search/SKILL.md`

- [x] **2.B.1** Insert `### Phase 2.5: Paraphrase Pre-Pass` section between current Phase 2 (~line 66) and Phase 3 (~line 80). Lead with `<!-- stage-2-paraphrase-union-v1 -->` HTML comment (TR2 token).
- [x] **2.B.2** Section content per plan §Phase 2 File 2 (in order): trigger condition (`< 5` unique paths from Phase 3 + not `--no-paraphrase` + not sensitive); sensitive-query regex guard with refuse message; cache lookup via `kb-search-cache.sh lookup`; variant generation (agent-inline, 3 variants); cache write via `kb-search-cache.sh append`; union execution + rank by union-hit-count; existing cap-split (8+12); fallback policy (stderr-warn + baseline grep).
- [x] **2.B.3** Add `--no-paraphrase` to `## Arguments` `Accepted forms` (line ~16) — described as "sensitive-query manual override (skips Phase 2.5 entirely)."
- [x] **2.B.4** Add `--clear-cache` to `## Arguments` `Accepted forms`.
- [x] **2.B.5** Add `## Privacy & Cost` section above `## Execution` with the 4 bullets per plan §Phase 2 File 2 (including the exact sentence `Runtime paraphrase is inline; no countable spend. If Option B is ever adopted, caps land with it.` — AC8 grep target).
- [x] **2.B.6** Verify frontmatter `description:` field is UNCHANGED. Run `awk '/^description:/{gsub(/^description:[[:space:]]*"?|"?$/,""); print; exit}' plugins/soleur/skills/kb-search/SKILL.md | wc -w` returns `22`. Run cumulative `grep -h '^description:' plugins/soleur/skills/*/SKILL.md | wc -w` returns ≤ `1921` (Stage 1 baseline).

### 2.C NEW file `plugins/soleur/skills/kb-search/scripts/kb-search-cache.sh`

- [x] **2.C.1** Create with `set -euo pipefail`. Three subcommands: `lookup <query>`, `append <query> <v1> [v2] [v3]`, `clear`. AC5 spec verbatim:
  - `lookup`: `sha256sum` the query; `jq` over `.soleur/cache/kb-search/query-paraphrases.ndjson` (if exists) for the matching `sha256` row; parse `cached_at` ISO 8601 UTC `Z` via `date -u -d "$cached_at" +%s`; compare against `date -u +%s`; if `age > 1209600` → cache miss (echo empty, exit 0); else echo newline-separated variants + exit 0. `jq` parse error → cache miss.
  - `append`: create `.soleur/cache/kb-search/` (chmod 700) if absent; `date -u +%Y-%m-%dT%H:%M:%SZ` for `cached_at`; append one NDJSON row `{"sha256":"<hash>","query":"<q>","variants":["<v1>",...],"cached_at":"<iso8601-Z>"}`.
  - `clear`: `rm -f .soleur/cache/kb-search/query-paraphrases.ndjson`.
- [x] **2.C.2** Verification in this commit:
  - `bash plugins/soleur/skills/kb-search/scripts/kb-search-cache.sh lookup "foo"` echoes empty + exits 0.
  - `bash plugins/soleur/skills/kb-search/scripts/kb-search-cache.sh append "foo" "bar" "baz" "qux"` creates `.soleur/cache/kb-search/` + writes row.
  - `stat -c '%a' .soleur/cache/kb-search/` returns `700`.
  - Re-`lookup "foo"` echoes `bar\nbaz\nqux`.
  - `clear` removes the file.

### 2.D NEW file `plugins/soleur/test/kb-search-lockstep.test.sh`

- [x] **2.D.1** Create file with trimmed body (per plan §Phase 2 File 4 — 12 lines, no header essay). Greps both `plugins/soleur/skills/kb-search/SKILL.md` AND `scripts/learning-retrieval-bench.sh` for the literal `stage-2-paraphrase-union-v1`; exits 1 if either file lacks it; emits `kb-search-lockstep: ok` on success.
- [x] **2.D.2** `chmod +x plugins/soleur/test/kb-search-lockstep.test.sh`.
- [x] **2.D.3** Verify `bash plugins/soleur/test/kb-search-lockstep.test.sh` exits 0 (token in both files from steps 2.A.2 + 2.B.1).
- [x] **2.D.4** Confirm the file extension `.test.sh` matches the existing sibling discovery pattern: `ls plugins/soleur/test/*.test.sh | wc -l` returns ≥ 2.

### 2.E Final commit verification

- [x] **2.E.1** `bash scripts/learning-retrieval-bench.sh --self-test` passes both `self_test_flooding_pathology` (Stage 1) AND `self_test_paraphrase_prepass` (Stage 2). Assertion 2 from Phase 1 flips RED → GREEN.
- [x] **2.E.2** `bash plugins/soleur/test/kb-search-lockstep.test.sh` exits 0.
- [x] **2.E.3** `grep -Fq stage-2-paraphrase-union-v1 plugins/soleur/skills/kb-search/SKILL.md` AND `grep -Fq stage-2-paraphrase-union-v1 scripts/learning-retrieval-bench.sh` both succeed.
- [x] **2.E.4** Cache helper round-trip (`lookup`→`append`→`lookup`→`clear`) passes.
- [x] **2.E.5** `git status --short` lists all 4 file changes (1 modified bench, 1 modified SKILL.md, 2 new files).
- [x] **2.E.6** Atomic commit message per plan §Phase 2 — single `git commit` covering all 4 file changes.

## Phase 3: PR housekeeping (commit 3)

- [x] **3.1** Verify the `deferred-scope-out` GitHub label exists: `gh label list --limit 200 | grep -E "^deferred-scope-out\b"`. Substitute with `domain/engineering` + `chore` if missing (per learning `2026-05-06-plan-prescribed-labels-must-be-verified.md`).
- [x] **3.2** File 14-day actuals validation issue per AC13: `gh issue create --title "feat: kb-search Stage 2 — 14-day actuals validation (paraphrase invocation telemetry)" --body "<AC13 body>" --milestone "Post-MVP / Later" --label deferred-scope-out`.
- [x] **3.3** Edit draft PR #4183 body via `gh pr edit 4183 --body-file <path>`. Body MUST include:
  - The 7-item CLO disclosure (AC10).
  - The #4042 premise-correction note (AC11).
  - `Ref #4176` (NOT `Closes #4176` — AC12).
  - Link to the 14-day actuals validation follow-up issue from 3.2.
- [x] **3.4** No file changes in repo from this phase (PR body is GH-side). If any operator-facing doc updates surface during PR-body authoring (rare), bundle into a single `docs(kb-search): PR housekeeping (#4176)` commit.

## Phase 4 (post-merge, operator-acked): bench rerun

**This phase is NOT executed by `/work`. Operator runs it manually after merge.**

- [ ] **4.1** Read `knowledge-base/project/learnings/workflow-issues/2026-05-20-long-running-bench-verify-process-before-relaunch.md` — verify-before-relaunch discipline applies.
- [ ] **4.2** From the worktree (or main after merge), run: `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-2026-05-20/paraphrases.ndjson`. Wall clock ~30-90 min. Estimated cost ~$6-$13 cold (query-paraphrases) + sub-second warm (corpus paraphrases).
- [ ] **4.3** Commit and push results: `knowledge-base/project/learning-retrieval-metrics-<date>.json` + new `knowledge-base/project/learnings/<date>-retrieval-diagnostic-findings.md`.

## Phase 5 (post-merge, operator-acked): ladder triage

- [ ] **5.1** Read `r5_heavy`, `r5_identity`, `r5_light` from `learning-retrieval-metrics-<date>.json`.
- [ ] **5.2** Compute non-regression: `r5_identity_stage2 - 0.497 > -0.02` AND `r5_light_stage2 - 0.404 > -0.02` (Stage 1 baselines from `2026-05-20-retrieval-diagnostic-findings.md`).
- [ ] **5.3** If `r5_heavy ≥ 0.4` AND non-regression holds → PASS branch:
  - `gh issue close 4176 --comment "Stage 2 paraphrase pre-pass shipped via PR #4183. R@5(heavy) = <value>; identity/light non-regression confirmed."`
  - `gh issue close 4119 --comment "KB retrieval reopen closed via Stage 2 ship. R@5(heavy) = <value>."`
  - Merge PR via `/soleur:ship`.
- [ ] **5.4** Otherwise → MISS branch:
  - File Stage 3 deferred issue: `gh issue create --title "feat: kb-search Stage 3 — embeddings/RAG retrieval (ADR-trigger)" --body "<R@5 values + STAGE 3 REQUIRES /soleur:architecture create 'Adopt embeddings-based KB retrieval' PER STAGE 1 PLAN FR7+TR6 — DO NOT silently implement embeddings without the ADR>" --milestone "Post-MVP / Later" --label deferred-scope-out`.
  - Keep #4176 + #4119 open.
  - Merge PR via `/soleur:ship` regardless (the Stage 2 work itself ships; the gate decided to defer Stage 3).

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-20-feat-kb-search-paraphrase-pre-pass-plan.md`
- Spec: `knowledge-base/project/specs/feat-kb-search-paraphrase-pre-pass-4176/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-20-kb-search-paraphrase-pre-pass-brainstorm.md`
- Stage 1 archived brainstorm: `knowledge-base/project/brainstorms/archive/20260520-161017-2026-05-20-kb-retrieval-reopen-brainstorm.md`
- Stage 1 diagnostics: `knowledge-base/project/learnings/2026-05-20-retrieval-diagnostic-findings.md`
- Verify-before-relaunch: `knowledge-base/project/learnings/workflow-issues/2026-05-20-long-running-bench-verify-process-before-relaunch.md`
