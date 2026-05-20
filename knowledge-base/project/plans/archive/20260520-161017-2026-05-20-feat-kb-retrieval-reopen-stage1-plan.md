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

**Issue:** #4119 · **Blocks:** #4042 · **Branch:** `feat-kb-retrieval-reopen-4119` · **Draft PR:** #4156

## Context

Bench evidence (2026-05-19, PR #4045): `kb-search` performs **worse than bare grep** at every paraphrase level (`gap_skill_roi = −0.173`), even at identity (0.497 vs 0.952). Root cause located: `kbsearch_rank` (`scripts/learning-retrieval-bench.sh:492-507`) concatenates tier-1 (full INDEX.md grep, 3461 entries) before tier-2 (kb-wide corpus grep) and caps at 20. Noise titles flood the cap. ~324 of 1152 learnings have no frontmatter — orthogonal hygiene.

The fix is three file edits behind a bench rerun. Spec FR1-FR8 covers the contract.

## Decisions (incremental over spec)

1. **Tier-1 scope via runtime filter**, not a new index file. One anchored `awk` substring filter on `rank_indexmd_by_token_overlap` output. Reversible by reverting SKILL.md + `kbsearch_rank` only.
2. **No frozen `legacy_kbsearch_rank`.** Git records the prior implementation. The new fixture asserts post-fix behavior; pre-fix failure is demonstrated by `git stash && --self-test` during development and captured in PR body.
3. **No pre-change baseline rerun.** Spec FR7 gate (`R@5(heavy) ≥ 0.4`) is absolute, drift-immune. One post-fix rerun suffices.
4. **Backfill is hygiene, not a R@5 lever.** Bench uses `extract_keywords → grep`; ignores facets. Ship as its own commit for reviewability; do not attribute any R@5 movement to it.
5. **SpecFlow overlap between FR7 branches** (`<0.3` vs `no improvement vs. 0.1331 ±0.02`) resolved by: if R@5(heavy) lands inside both, file Stage 2 (the lower stage) — one follow-up, not two. Corpus drift since 2026-05-19 (1127 → 1152, +2.2%) is below the ±0.02 envelope and ignored.

## Implementation

### Phase 1 — Frontmatter backfill (separate commit)

```bash
MISSING_FM_PRE=$(find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---')
echo "$MISSING_FM_PRE missing-frontmatter learnings before backfill"   # expect ~324
doppler run -p soleur -c dev -- python3 scripts/backfill-frontmatter.py
MISSING_FM_POST=$(find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---')
echo "$MISSING_FM_POST after"   # expect 0
```

Spot-check 5 random newly-backfilled files for inferred-category sanity. Commit: `chore(learnings): backfill frontmatter via scripts/backfill-frontmatter.py`. Body records both counts and notes "does not move R@5; hygiene only."

### Phase 2 — Lockstep SKILL.md + bench + fixture (single commit)

**2a. `plugins/soleur/skills/kb-search/SKILL.md` Phase 3 (keyword-only branch).** Replace existing tier-1/tier-2 prose with:

```text
- Keyword-only (no facets):
  1. Tier 1 (cap 8): grep `knowledge-base/INDEX.md` for the keyword, then restrict to
     lines whose link target is rooted under `knowledge-base/project/learnings/`.
  2. Tier 2 (cap 12): grep `knowledge-base/project/learnings/**/*.md` content for the
     keyword. Exclude `archive/`.
- Output tier-1 first, then tier-2, deduped by path. Maximum 20 total; each tier
  self-caps.
```

**2b. `scripts/learning-retrieval-bench.sh:492-507` (`kbsearch_rank`).** Replace with:

```bash
kbsearch_rank() {
  local query="$1" source_path="$2" synced_paths_json="$3"
  if [[ -z "$query" ]]; then echo ""; return; fi
  local tokens tier1 tier2 combined
  tokens=$(extract_keywords "$query" 3)
  if [[ -z "$tokens" ]]; then echo ""; return; fi
  # Tier 1: INDEX.md hits scoped to /learnings/ (anchored: leading `^` OR `/` prefix to
  # avoid future false matches on paths like `sessions/learnings-retrospective/`).
  tier1=$(rank_indexmd_by_token_overlap "$tokens" \
    | awk '$0 ~ "(^|/)knowledge-base/project/learnings/"' \
    | head -8)
  # Tier 2: corpus grep restricted to learnings/ only.
  tier2=$(rank_paths_by_token_overlap_corpus "$tokens" learnings-only | head -12)
  # Total bounded by tier caps (8+12); no outer head -20 needed.
  combined=$({ printf '%s\n' "$tier1"; printf '%s\n' "$tier2"; } | awk 'NF && !seen[$0]++')
  rank_paths_min_rank "$combined" "$source_path" "$synced_paths_json"
}
```

The `synced_paths_json` arg path through `rank_paths_min_rank` is unchanged.

**2c. New self-test function in `scripts/learning-retrieval-bench.sh` (alongside existing `self_test`):**

```bash
self_test_flooding_pathology() {
  local KB_ROOT="$TMP_ROOT/kb-flood"
  mkdir -p "$KB_ROOT/knowledge-base/project/learnings" \
           "$KB_ROOT/knowledge-base/project/sessions"
  st_write "$KB_ROOT/knowledge-base/project/learnings/target.md" \
    '---' 'category: migrations' '---' '# Schema Drift Reasoning' \
    'discussing schema drift across pinned migrations.'
  local i
  for i in $(seq 1 30); do
    st_write "$KB_ROOT/knowledge-base/project/sessions/session-state-${i}.md" \
      "# Session State Schema Drift Notes ${i}" "Session $i unrelated content."
  done
  {
    echo '# Knowledge Base Index'; echo
    for i in $(seq 1 30); do
      echo "- [Session State Schema Drift Notes ${i}](project/sessions/session-state-${i}.md)"
    done
    echo '- [Schema Drift Reasoning](project/learnings/target.md)'
  } > "$KB_ROOT/knowledge-base/INDEX.md"
  (cd "$KB_ROOT" && git init -q && git add -A \
    && git -c user.email=t@t -c user.name=t commit -q -m fixture)
  local prev_repo="$REPO_ROOT" prev_idx="$INDEX_PATH"
  REPO_ROOT="$KB_ROOT"; INDEX_PATH="$KB_ROOT/knowledge-base/INDEX.md"
  local rk
  rk=$(kbsearch_rank "schema drift" "knowledge-base/project/learnings/target.md" "[]")
  if [[ -n "$rk" && "$rk" -le 8 ]]; then
    SELF_TEST_PASS=$((SELF_TEST_PASS+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
    echo "  PASS: flood-pathology: kbsearch_rank finds target despite 30 noise titles (rank=$rk)"
  else
    SELF_TEST_FAIL=$((SELF_TEST_FAIL+1)); SELF_TEST_TOTAL=$((SELF_TEST_TOTAL+1))
    echo "  FAIL: flood-pathology: kbsearch_rank lost target (rank=$rk)"
  fi
  REPO_ROOT="$prev_repo"; INDEX_PATH="$prev_idx"
}
# Invoke from self_test() main body (one new line).
```

**Pre-commit FAIL demonstration (PR body):** before staging Phase 2, run:

```bash
git stash --keep-index   # park unfinished Phase 2 changes
bash scripts/learning-retrieval-bench.sh --self-test 2>&1 | tee /tmp/fail.log
# Expect: FAIL line from flood-pathology (run against pre-fix kbsearch_rank)
git stash pop
```

Paste `/tmp/fail.log`'s flood-pathology line in the PR description. This is the regression-anchor proof; the file itself records only the post-fix assertion.

Commit message: `feat(kb-search): cap-split 8/12 + tier-1 learnings scope (lockstep SKILL.md + bench + fixture)`.

### Phase 3 — Bench rerun (operator) and gate decision

```bash
doppler run -p soleur -c prd_scheduled -- bash scripts/learning-retrieval-bench.sh --confirm
# ~70min, ~$3.07
```

Outputs land at `knowledge-base/project/learning-retrieval-metrics-<date>.json` and a new diagnostic-findings learning under `knowledge-base/project/learnings/`. Commit both.

Apply spec FR7 ladder (decision-5 above resolves the overlap):

```bash
POST=$(jq '.r5.heavy_kbsearch' knowledge-base/project/learning-retrieval-metrics-*.json | tail -1)
# Spec FR7:
#   POST ≥ 0.4              → pass → close #4119 + unblock #4042
#   0.3  ≤ POST < 0.4       → file Stage 1.5 deferred issue (IDF/stopword)
#   0.18 ≤ POST < 0.3       → file Stage 2 deferred issue (LLM paraphrase pre-pass)
#   POST < 0.18             → file Stage 3 deferred issue (embeddings, ADR-trigger)
```

The 0.18 floor = 0.1331 baseline + 0.05 envelope absorbing first-fill Haiku non-determinism. Below 0.18 means the fix made no measurable difference.

### Phase 4 — Ship

`/soleur:ship`. PR `## Changelog` + `semver:patch` label. No Phase 5.5 gates apply (no CMO/GDPR/deploy-pipeline surfaces).

## Acceptance

- **AC1.** `MISSING_FM_PRE` and `MISSING_FM_POST` recorded in Phase 1 commit body; post = 0 (modulo documented exclusions).
- **AC2.** SKILL.md Phase 3 reflects 8/12 split + learnings-scoped tier-1.
- **AC3.** `kbsearch_rank` updated in lockstep with SKILL.md, same commit.
- **AC4.** `bash scripts/learning-retrieval-bench.sh --self-test` passes including the new `self_test_flooding_pathology` invocation, AND the existing `synced_to` min-rank test (line 919-934) continues to pass — confirms `synced_paths_json` behavior preserved.
- **AC5.** Pre-fix FAIL log pasted in PR body.
- **AC6.** Post-change bench JSON + findings learning committed.
- **AC7.** Gate decision documented in PR body with `jq`-extracted value and the FR7 branch reached.
- **AC8.** If pass → #4119 closed + #4042 unblock comment; if fail → exactly one Stage 1.5/2/3 deferred-tracking issue filed with milestone `Post-MVP / Later` and bench-rerun trigger condition.

## Risks

| Risk | Mitigation |
|---|---|
| Backfill's category inference is wrong on a few files | Standalone commit; spot-check 5 in PR body; `chore` prefix signals non-functional |
| Post-fix R@5(heavy) lands in 0.3-0.4 → Stage 1.5 needed | Already in the ladder. One follow-up issue. |
| `--self-test` flooding-pathology fixture passes for the wrong reason (e.g., decoy paths under `sessions/` would also be excluded by `learnings-only` scope, so they could never compete in tier-2) | Acknowledged: this fixture's value is verifying tier-1 scope AND cap-split working as a unit. The pre-fix FAIL log (AC5) confirms the pathology against the prior implementation. |
| Bench rerun cost ($3, 70min) blocks shipping if API errors mid-run | One-shot; if it fails, rerun. Acceptable for a single $3 step. |

## Test Strategy

- `bash scripts/learning-retrieval-bench.sh --self-test` — existing tests (lines 832-958) plus new `self_test_flooding_pathology`.
- `bash scripts/generate-kb-index.sh && git diff knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt` — diff should reflect only frontmatter-backfill-derived tag/category additions, not structural INDEX.md changes (since D6 is a runtime filter, not a generator edit).
- `bun test plugins/soleur/test/components.test.ts` — SKILL.md body edits do not touch `description:` frontmatter; budget invariant preserved.

## Domain Review

**Domains relevant:** Engineering (carry-forward from brainstorm 2026-05-20).

### Engineering

**Status:** reviewed (brainstorm carry-forward; CTO assessment 2026-05-20).
**Assessment:** Stage 1 mechanical structural fixes recommended over Stages 2/3 because bench evidence locates a displacement bug, not a semantic-search deficit. Lockstep SKILL.md ↔ `scripts/learning-retrieval-bench.sh:492-507` requirement preserved as AC3. Observability satisfied by bench-as-surface (rerunnable on demand). Stage 3 (embeddings) flagged as ADR-trigger if reached. No new capability gaps.

## Out of Scope

- Stages 1.5, 2, 3 (deferred per spec FR7 ladder; file follow-up issues conditionally).
- INDEX.md schema changes (D6 is a runtime filter; `generate-kb-index.sh` untouched).
- New `kb-search` programmatic consumers.

## Cross-References

- Spec: [feat-kb-retrieval-reopen-4119/spec.md](../specs/feat-kb-retrieval-reopen-4119/spec.md)
- Brainstorm: [2026-05-20-kb-retrieval-reopen-brainstorm.md](../brainstorms/2026-05-20-kb-retrieval-reopen-brainstorm.md)
- Hard rules touched: `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`, `wg-when-deferring-a-capability-create-a`, `cq-test-fixtures-synthesized-only`
