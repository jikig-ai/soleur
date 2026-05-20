---
title: KB retrieval reopen — Stage 1 (cap-split + tier-1 learnings scope + frontmatter backfill)
status: draft
owner: engineering
issue: 4119
blocks: 4042
spec: knowledge-base/project/specs/feat-kb-retrieval-reopen-4119/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-20-kb-retrieval-reopen-brainstorm.md
created: 2026-05-20
lane: single-domain
brand_survival_threshold: none
---

# Plan: KB Retrieval Reopen — Stage 1

**Issue:** #4119  
**Blocks:** #4042  
**Branch:** `feat-kb-retrieval-reopen-4119` (worktree already created)  
**Draft PR:** #4156  
**Brainstorm:** [2026-05-20-kb-retrieval-reopen-brainstorm.md](../brainstorms/2026-05-20-kb-retrieval-reopen-brainstorm.md)  
**Spec:** [feat-kb-retrieval-reopen-4119/spec.md](../specs/feat-kb-retrieval-reopen-4119/spec.md)

## Context

Bench evidence (2026-05-19, PR #4045) showed `kb-search` performs **worse than bare grep** at every paraphrase level (gap_skill_roi = −0.173), even at identity (0.497 vs 0.952). Repo research located the mechanism:

- `knowledge-base/INDEX.md` indexes **3461 entries** (full KB) but the retrieval task targets ~1152 learnings.
- `kbsearch_rank` (`scripts/learning-retrieval-bench.sh:492-507`) concatenates tier-1 (INDEX.md grep) before tier-2 (corpus grep) and caps at 20. Tier-1 noise titles (`session state` ×497, `tasks: fix` ×110, `digest` ×65) flood the cap before tier-2 content matches are evaluated.
- ~28% of learnings (324/1152, **not** the 533 figure from brainstorm — denominator corrected per current corpus) have no YAML frontmatter.
- `kb-search` has zero programmatic consumers. SKILL.md is a Markdown strategy interpreted by agents.

Stage 1 fixes the structural displacement with three mechanical changes, gated by bench rerun. Stages 1.5/2/3 escalate only on Stage 1 gate miss.

## Approach (high-level)

| Lever | Where | Effect on R@5 | Cost |
|---|---|---|---|
| Cap split (8 tier-1 + 12 tier-2) | SKILL.md Phase 3 + `kbsearch_rank` | Direct: reserves tier-2 floor | Trivial code |
| Scope tier-1 to /learnings/ | SKILL.md Phase 3 + `kbsearch_rank` (filter INDEX.md output) | Direct: removes 2300+ non-learning title competitors | Trivial code |
| Frontmatter backfill | `scripts/backfill-frontmatter.py` re-run | **None** on R@5 (bench uses `extract_keywords → grep`, ignores facets) | Mechanical |
| Synthesized self-test fixture | `learning-retrieval-bench.sh --self-test` | Regression catch only | Bash fixture |
| Bench `kbsearch_rank` lockstep update | `learning-retrieval-bench.sh:492-507` | Required co-evolution | Trivial code |

The fix is small. The discipline is large.

## Critical Design Decisions (gap-closures from SpecFlow)

### D1: Confidence-bounded ladder (closes SpecFlow gap 1)

The spec's FR7 ladder has overlapping bands (`<0.3` and `no improvement vs. 0.1331 baseline ±0.02`). Replace with non-overlapping bands and a borderline-rerun rule:

| Post-fix R@5(heavy, kb-search) | Action |
|---|---|
| ≥ 0.42 | **Pass** — gate cleared with ≥0.02 margin. Close #4119, comment on #4042 to unblock. |
| 0.38 – 0.42 | **Borderline** — re-run bench once (cache-hit, free). If average of two runs ≥ 0.40 → pass; else fall through. |
| 0.30 – 0.38 | Open Stage 1.5 deferred issue (IDF/stopword scoring). |
| 0.18 – 0.30 | Open Stage 2 deferred issue (LLM paraphrase pre-pass). Cumulative-baseline + noise envelope; 0.18 = 0.1331 + 0.05 envelope. |
| < 0.18 | Open Stage 3 deferred issue (embeddings/RAG, ADR-trigger). |

The 0.05 noise envelope above the original 0.1331 baseline lets the bench's own paraphrase-generation non-determinism (first-fill Haiku call) absorb up to one ladder-step of variance.

### D2: Lockstep ↔ regression-proof via frozen `legacy_kbsearch_rank` (closes SpecFlow gaps 2+3)

TR2 (lockstep PR) and FR5 (fixture must FAIL pre-fix, PASS post-fix) structurally conflict if both ship in one commit. Resolution: introduce a **frozen copy** of the pre-fix implementation as `legacy_kbsearch_rank()` in the self-test section of `learning-retrieval-bench.sh` (NOT in the production path). The new flooding-pathology fixture asserts both:

- `legacy_kbsearch_rank("...", target)` returns rank > 8 (FAIL semantics on old impl)
- `kbsearch_rank("...", target)` returns rank ≤ 8 (PASS semantics on new impl)

`legacy_kbsearch_rank` lives in the self-test block only, marked `# DO NOT REMOVE: regression-fail anchor. Delete after Stage 1.5 or 6 weeks.` This satisfies both rules with no dead production code.

### D3: Backfill separated, attribution-explicit (closes SpecFlow gap 4)

- Backfill ships as its own commit, labelled `chore(learnings): backfill frontmatter via scripts/backfill-frontmatter.py`.
- Plan explicitly states: **the backfill does not move R@5(heavy)** because `extract_keywords → token-overlap grep` does not consult frontmatter. The backfill improves `worst_n` `cause` classification accuracy only.
- TR4's "single commit clearly labelled 'frontmatter-only'" supersedes any "two-commit bench rerun" interpretation. One backfill commit. One lockstep-fix commit. One bench-rerun-output commit.

### D4: Pre-change baseline rerun on current corpus (closes SpecFlow gaps 5+7)

- Phase 0 of implementation runs `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases <path>` on the current 1152-doc corpus to establish a fresh baseline. Cost: ~$3 / 70min for paraphrase generation.
- Phase 6 reruns with the same `--cache-paraphrases <path>` — cache-hit makes it near-free.
- Both metric JSONs committed; ladder compares post-fix to **fresh** baseline (not 0.1331).
- Drift acknowledged: spec's 0.1331 number was measured on 1127 docs; current corpus is 1152 (+2.2%). The gate's hard threshold (≥0.42 for pass) is drift-immune; ladder lower branches reference the fresh Phase 0 baseline.

### D5: Synced-paths semantics explicitly preserved (closes SpecFlow gap 6)

Add to acceptance: `kbsearch_rank`'s `synced_paths_json` arg and `rank_paths_min_rank` (line 467) behavior remain unchanged. Verify via the existing self-test at lines 919-934 (`min-rank synced_to: best position across both filings`) which continues to pass without modification after the Stage 1 fix.

### D6: Tier-1 learnings scope via runtime filter, not new file (chosen during plan)

Three options were open in brainstorm: separate `INDEX-learnings.md`, section anchor in `INDEX.md`, or runtime filter. **Choose runtime filter**: smallest blast radius (zero generator changes), reversible (revert SKILL.md + `kbsearch_rank` only), and the existing `rank_indexmd_by_token_overlap` already returns paths prefixed `knowledge-base/` so an `awk '/\/learnings\//'` post-filter is one line.

## Implementation Phases

### Phase 0: Pre-change baseline bench rerun (operator)

**Goal:** establish a fresh baseline on the current 1152-doc corpus and warm the paraphrase cache for Phase 6.

```bash
mkdir -p /tmp/kb-bench-cache
doppler run -p soleur -c prd_scheduled -- \
  bash scripts/learning-retrieval-bench.sh --confirm \
    --cache-paraphrases /tmp/kb-bench-cache/paraphrases-2026-05-20.ndjson
```

**Expected duration:** ~70min, ~$3.07 (per `learning-retrieval-bench.sh` cost-gate).

**Outputs (commit immediately):**
- `knowledge-base/project/learning-retrieval-metrics-2026-05-20-pre.json`
- `knowledge-base/project/learnings/2026-05-20-retrieval-pre-baseline.md`

Commit: `chore(bench): pre-change baseline on 1152-doc corpus (R@5(heavy)=<value>)`.

### Phase 1: Frontmatter backfill (mechanical, no R@5 impact)

```bash
# Idempotent re-run; safe if already up-to-date.
doppler run -p soleur -c dev -- python3 scripts/backfill-frontmatter.py
```

**Expected modifications:** ~324 files gain YAML frontmatter under `knowledge-base/project/learnings/{**/,}*.md`. Stats output (`processed/created/augmented/skipped/errors`) goes in commit body.

**Pre-commit sanity:**
```bash
find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -c '^---'
# Expect: 1152 (or current total)
```

**Commit:** `chore(learnings): backfill frontmatter on ~324 files (PyYAML, idempotent)`. Body includes the script's stats line and notes that backfill does NOT affect bench retrieval scoring.

### Phase 2: Lockstep SKILL.md + bench `kbsearch_rank` update + synthesized fixture

Single commit. Three coordinated edits:

**2a. `plugins/soleur/skills/kb-search/SKILL.md` (Phase 3 section):**

Replace the existing tier-1/tier-2 prose with explicit per-tier caps and learnings-scoped tier-1:

```text
- Keyword-only (no facets):
  1. Tier 1: grep `knowledge-base/INDEX.md` for the keyword, restrict matches to lines whose
     link target contains `/learnings/`, take the top 8.
  2. Tier 2: grep `knowledge-base/project/learnings/**/*.md` content for the keyword,
     take the top 12. Exclude `archive/`.
- Combined output: tier-1 results first, then tier-2 (dedup paths). Maximum 20 total
  (8 + 12); each tier has its own cap.
```

**2b. `scripts/learning-retrieval-bench.sh` `kbsearch_rank` (lines 492-507):**

Update body to match SKILL.md change:

```bash
kbsearch_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  if [[ -z "$query" ]]; then echo ""; return; fi
  local tokens tier1 tier2 combined
  tokens=$(extract_keywords "$query" 3)
  if [[ -z "$tokens" ]]; then echo ""; return; fi
  # Tier 1: INDEX.md hits scoped to /learnings/ paths; cap 8.
  tier1=$(rank_indexmd_by_token_overlap "$tokens" | awk '/\/learnings\//' | head -8)
  # Tier 2: corpus grep restricted to learnings-only; cap 12.
  tier2=$(rank_paths_by_token_overlap_corpus "$tokens" learnings-only | head -12)
  combined=$(
    {
      printf '%s\n' "$tier1"
      printf '%s\n' "$tier2"
    } | awk 'NF && !seen[$0]++'
  )
  rank_paths_min_rank "$combined" "$source_path" "$synced_paths_json"
}
```

Note: `head -20` removed from `combined` since each tier already capped. `synced_paths_json` arg path through `rank_paths_min_rank` unchanged.

**2c. `scripts/learning-retrieval-bench.sh` self-test additions (after line 934):**

Add `legacy_kbsearch_rank` (frozen copy of pre-fix impl) and a flooding-pathology fixture:

```bash
# Frozen pre-fix impl. DO NOT REMOVE: regression-fail anchor.
# Delete after Stage 1.5 lands or six weeks from 2026-05-20.
legacy_kbsearch_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  local tokens tier1 tier2 combined
  tokens=$(extract_keywords "$query" 3)
  if [[ -z "$tokens" ]]; then echo ""; return; fi
  tier1=$(rank_indexmd_by_token_overlap "$tokens")
  tier2=$(rank_paths_by_token_overlap_corpus "$tokens" kb-wide)
  combined=$({ printf '%s\n' "$tier1"; printf '%s\n' "$tier2"; } \
    | awk 'NF && !seen[$0]++' | head -20)
  rank_paths_min_rank "$combined" "$source_path" "$synced_paths_json"
}

# Synthesized flooding-pathology fixture (cq-test-fixtures-synthesized-only).
# 30 noise-titled session-state entries displace the target learning under
# legacy_kbsearch_rank but the fix recovers it.
self_test_flooding_pathology() {
  local KB_ROOT="$TMP_ROOT/kb-flood"
  mkdir -p "$KB_ROOT/knowledge-base/project/learnings" \
           "$KB_ROOT/knowledge-base/project/sessions"
  # Target learning containing the keyword "schema drift".
  st_write "$KB_ROOT/knowledge-base/project/learnings/target.md" \
    '---' 'category: migrations' '---' '# Schema Drift Reasoning' \
    'discussing schema drift across pinned migrations.'
  # Decoy: 30 sessions-state files with "schema drift" in title only, displacing tier-1.
  for i in $(seq 1 30); do
    st_write "$KB_ROOT/knowledge-base/project/sessions/session-state-${i}.md" \
      '# Session State Schema Drift Notes' "Session $i unrelated content."
  done
  (cd "$KB_ROOT" && git init -q && git add -A \
    && git -c user.email=t@t -c user.name=t commit -q -m fixture)
  # INDEX.md lists all 31 entries; 30 are non-learning, 1 is learning.
  {
    echo '# Knowledge Base Index'; echo
    echo '- [Schema Drift Reasoning](project/learnings/target.md)'
    for i in $(seq 1 30); do
      echo "- [Session State Schema Drift Notes ${i}](project/sessions/session-state-${i}.md)"
    done
  } > "$KB_ROOT/knowledge-base/INDEX.md"
  (cd "$KB_ROOT" && git add -A \
    && git -c user.email=t@t -c user.name=t commit -q --amend --no-edit)
  local prev_repo="$REPO_ROOT" prev_idx="$INDEX_PATH"
  REPO_ROOT="$KB_ROOT"; INDEX_PATH="$KB_ROOT/knowledge-base/INDEX.md"
  # Legacy MUST place target below cap-20 (or returning ""): pathology demo.
  local rk_legacy rk_new
  rk_legacy=$(legacy_kbsearch_rank "schema drift" \
    "knowledge-base/project/learnings/target.md" "[]")
  rk_new=$(kbsearch_rank "schema drift" \
    "knowledge-base/project/learnings/target.md" "[]")
  if [[ -z "$rk_legacy" || "$rk_legacy" -gt 8 ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
    echo "  PASS: legacy_kbsearch_rank demonstrates flood-displacement (rank=${rk_legacy:-null})"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
    echo "  FAIL: legacy_kbsearch_rank did not displace target (rank=$rk_legacy); fixture too weak"
  fi
  if [[ -n "$rk_new" && "$rk_new" -le 8 ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
    echo "  PASS: kbsearch_rank recovers target (rank=$rk_new)"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
    echo "  FAIL: kbsearch_rank failed to recover target (rank=$rk_new)"
  fi
  REPO_ROOT="$prev_repo"; INDEX_PATH="$prev_idx"
}
# Invoke from self_test() main body (one new line near line 936).
self_test_flooding_pathology
```

**Commit:** `feat(kb-search): cap-split 8/12 + tier-1 learnings scope (lockstep SKILL.md + bench + fixture)`. Body cites SpecFlow gaps D1-D6 and links the brainstorm.

### Phase 3: Self-test gate (CI)

```bash
bash scripts/learning-retrieval-bench.sh --self-test
```

Must pass all assertions including the new `self_test_flooding_pathology` invocation (legacy fails, new passes). This is the CI gate per spec TR3 — PR cannot mark ready unless this passes.

### Phase 4: Generator audit (no change expected)

`scripts/generate-kb-index.sh` is **not** edited; the runtime filter approach (D6) leaves INDEX.md format untouched. Verify by diffing:

```bash
bash scripts/generate-kb-index.sh
git diff knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt
# Diff should reflect ONLY the frontmatter backfill from Phase 1 (new tags/categories),
# NOT structural changes to INDEX.md.
```

If unexpected diff appears, halt and investigate.

### Phase 5: Plugin loader budget check

Per `plugins/soleur/AGENTS.md` "Token Budget Check" — SKILL.md description size:

```bash
bun test plugins/soleur/test/components.test.ts
```

SKILL.md edits are in the body, not the `description:` frontmatter, so cumulative description size is unaffected. Test must pass.

### Phase 6: Post-change bench rerun (cache-hit, free)

```bash
bash scripts/learning-retrieval-bench.sh --confirm \
  --cache-paraphrases /tmp/kb-bench-cache/paraphrases-2026-05-20.ndjson
```

**Expected duration:** ~minutes (no LLM spend; cache hit). Outputs:

- `knowledge-base/project/learning-retrieval-metrics-2026-05-20-post.json`
- `knowledge-base/project/learnings/2026-05-20-retrieval-stage1-findings.md`

Commit: `chore(bench): post-Stage-1 metrics (R@5(heavy)=<value>; cache-hit)`.

### Phase 7: Gate decision + ladder action (automated)

The gate decision must be `jq`-driven, not eyeballed (per `hr-no-dashboard-eyeball-pull-data-yourself`):

```bash
POST_R5H=$(jq '.r5.heavy_kbsearch' knowledge-base/project/learning-retrieval-metrics-2026-05-20-post.json)
PRE_R5H=$(jq '.r5.heavy_kbsearch' knowledge-base/project/learning-retrieval-metrics-2026-05-20-pre.json)
echo "Pre:  $PRE_R5H"
echo "Post: $POST_R5H"
# Apply D1 ladder.
```

Action per D1 ladder table. If pass: close #4119, comment on #4042 with the post-fix metric and bench JSON link. If fail: file the appropriate Stage 1.5/2/3 deferred-tracking issue with milestone `Post-MVP / Later`, trigger condition, and bench-rerun gate (per `wg-when-deferring-a-capability-create-a` and `hr-autonomous-loop-skill-api-budget-disclosure` for Stage 2/3 budget disclosure).

### Phase 8: Ship via `/soleur:ship`

Standard ship flow. The PR will already contain three commits (backfill, lockstep fix, bench output). Optional Phase 5.5 gates: `cmo-content-gate` does NOT apply (no marketing surfaces), `gdpr-gate` does NOT apply (no regulated data), `deploy_pipeline_fix` does NOT apply (no infra).

## Acceptance Criteria

Maps to spec AC1-AC8 with SpecFlow gap-closures:

- **AC-P1.** Pre-change baseline metric JSON committed (`learning-retrieval-metrics-2026-05-20-pre.json`) on current 1152-doc corpus before any retriever change. (closes SpecFlow gap 5+7)
- **AC-P2.** Frontmatter backfill commit reduces missing-frontmatter learnings count from current `find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---'` baseline to 0 (modulo intentional exclusions documented inline). (corrects spec AC4 denominator)
- **AC-P3.** `plugins/soleur/skills/kb-search/SKILL.md` Phase 3 documents tier-1 cap=8 + `/learnings/` scope and tier-2 cap=12 + `learnings/`-only scope.
- **AC-P4.** `scripts/learning-retrieval-bench.sh` `kbsearch_rank` (lines 492-507) updated in lockstep with SKILL.md; same commit. (spec TR2)
- **AC-P5.** `legacy_kbsearch_rank` exists ONLY in self-test section with deletion-date comment (six weeks or post-Stage 1.5).
- **AC-P6.** Synthesized flooding-pathology fixture asserts (a) `legacy_kbsearch_rank` returns rank > 8 or null for target query, (b) `kbsearch_rank` returns rank ≤ 8.
- **AC-P7.** `bash scripts/learning-retrieval-bench.sh --self-test` passes including the new fixture and all existing tests (esp. lines 919-934 `synced_to` test, preserving D5).
- **AC-P8.** Post-change bench rerun committed (`learning-retrieval-metrics-2026-05-20-post.json`) and findings learning file.
- **AC-P9.** Gate decision documented in PR body with `jq`-extracted numbers and ladder branch outcome (per D1).
- **AC-P10.** If pass → #4119 closed + #4042 unblock comment. If fail → exactly one Stage 1.5/2/3 deferred issue filed with milestone `Post-MVP / Later`.
- **AC-P11.** PR `## Changelog` section + `semver:patch` label.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Backfill script's category inference produces a wrong category for some files | Medium | Low (cosmetic; backfill is irrelevant for R@5) | Commit backfill as standalone reviewable commit; spot-check 5 random files in PR body |
| Pre-change paraphrase generation hits rate-limits or errors mid-run | Low | Medium (delays Stage 1; cost wasted) | `--cache-paraphrases` persists partial NDJSON; rerun resumes. Run during off-peak. |
| `legacy_kbsearch_rank` fixture proves "too weak" — legacy doesn't displace target | Low | Medium (regression-catch invalid) | Synthesize 30+ decoys (sized to overflow cap-20 with margin); validate by running self-test on a stash-out of Phase 2b before committing. |
| `awk '/\/learnings\//'` filter accidentally matches non-learning paths containing the substring | Very low | Low | Anchored substring `/learnings/` is unique to the target tree. Verify with `grep '/learnings/' knowledge-base/INDEX.md | grep -v '^- \[' \| wc -l` = 0 (no non-link occurrences). |
| Post-fix R@5(heavy) lands in the 0.38-0.42 borderline | Possible | Low | D1 ladder explicitly handles via second cache-hit rerun (free). |
| Bench paraphrase non-determinism on first-fill produces a baseline that won't be reproducible later | Medium | Low | NDJSON cache file IS the reproducibility artifact; preserve at a stable path (`/tmp/kb-bench-cache/`) and consider committing if size <2MB. |
| Stage 1 passes the gate but Stage 1.5/2/3 needs trigger later | High (future) | Low | Pre-committed ladder + deferred-issue procedure already in spec FR8. |
| `legacy_kbsearch_rank` left in the codebase indefinitely | Medium | Low | Comment includes hard deletion date (six weeks); add a calendar reminder in PR description. |

## Test Strategy

- **Existing self-test coverage (preserved):** lines 832-958 of `learning-retrieval-bench.sh` — token extraction, synonym-substitution, pure-stopword, synced_to min-rank, bug-1 null-rank, cost-gate. All must continue to pass.
- **New regression test:** `self_test_flooding_pathology` (Phase 2c). Two assertions: legacy fails, new passes. Sized to exceed cap-20 with margin.
- **Generator non-regression:** Phase 4 diff check confirms `generate-kb-index.sh` output unaffected.
- **Plugin loader budget:** Phase 5 `bun test`.
- **Bench self-test in CI:** must be added to `.github/workflows/ci.yml` if not already wired (verify in Phase 3).

## Domain Review

**Domains relevant:** Engineering (carried forward from brainstorm 2026-05-20).

### Engineering

**Status:** reviewed (brainstorm carry-forward; CTO assessment completed 2026-05-20)  
**Assessment:** Stage 1 mechanical structural fixes recommended over Stages 2/3 due to bench evidence locating the displacement bug rather than a semantic-search deficit. Lockstep SKILL.md ↔ `learning-retrieval-bench.sh:413-507` requirement called out. Observability satisfied by bench-as-surface (rerunnable on demand). Stage 3 flagged as ADR-trigger. No new capability gaps. See brainstorm `## Domain Assessments` for full text.

**Decision:** reviewed (no new domain implications surfaced during planning).

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Embeddings/RAG first | Sledgehammer for a screwdriver problem. Bench evidence isolates a structural bug, not a semantic deficit. ADR-required. Deferred to Stage 3 ladder branch. |
| Drop tier-1 entirely (kb-search = bare grep) | Loses the title-hit signal which still has value when the index entry is precise. Spec's two-tier philosophy survives if we just stop letting it flood. |
| 5+15 cap split (more tier-2) | Maybe better; deferred for empirical A/B once per-tier breakdown in bench output exists (TR4-equivalent in spec). 8+12 is the conservative first cut. |
| Separate `INDEX-learnings.md` file | Larger blast radius: changes `generate-kb-index.sh`. Runtime filter (D6) is one shell idiom and reversible by SKILL.md revert alone. |
| Single-commit bundle (backfill + fix together) | Loses attribution. Spec explicitly says backfill doesn't enter the bench retrieval path; bundling muddies the change log. |
| Pre-change rerun skipped (trust 2026-05-19 baseline) | Corpus drifted +2.2% in 15 days. Cheap to refresh via cache; rigor wins. |
| Add `--legacy-rank` runtime flag to production | Adds maintenance surface. Frozen `legacy_kbsearch_rank` in self-test only is one-shot dead-code with a deletion date. |

## Open Questions (Resolved during plan)

| Brainstorm question | Resolution |
|---|---|
| Backfill in same PR as retriever change? | **Same PR, two commits** (D3). |
| Sub-index format? | **Runtime filter** in SKILL.md + `kbsearch_rank` (D6). |
| Per-tier rank breakdown in bench JSON? | Deferred to Stage 1.5 if needed; cap-split achieves the same diagnostic isolation without schema bump. |

## Out of Scope

- Stages 1.5 (IDF/stopword scoring), 2 (LLM paraphrase pre-pass), 3 (embeddings/RAG) — see ladder in D1.
- INDEX.md schema changes (Phase 4 verifies non-regression).
- New `kb-search` consumers; the skill remains prompt-only.
- Per-tier rank breakdown in bench JSON (deferred).
- Bench script paraphrase-pipeline refactor.

## Filename + Branch + PR Wire-up

- Plan file: `knowledge-base/project/plans/2026-05-20-feat-kb-retrieval-reopen-stage1-plan.md`
- Tasks file: `knowledge-base/project/specs/feat-kb-retrieval-reopen-4119/tasks.md`
- Branch: `feat-kb-retrieval-reopen-4119` (created)
- Draft PR: #4156

## Cross-References

- Spec: [feat-kb-retrieval-reopen-4119/spec.md](../specs/feat-kb-retrieval-reopen-4119/spec.md)
- Brainstorm: [2026-05-20-kb-retrieval-reopen-brainstorm.md](../brainstorms/2026-05-20-kb-retrieval-reopen-brainstorm.md)
- Sibling: #4042 (blocked by this), #4045 (bench PR, merged), #4119 (this issue)
- Hard rules touched: `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`, `hr-autonomous-loop-skill-api-budget-disclosure` (Stage 2/3 only), `wg-when-deferring-a-capability-create-a`, `cq-test-fixtures-synthesized-only`
