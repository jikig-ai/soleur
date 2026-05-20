# Tasks: KB Retrieval Reopen — Stage 1

**Plan:** [../../plans/2026-05-20-feat-kb-retrieval-reopen-stage1-plan.md](../../plans/2026-05-20-feat-kb-retrieval-reopen-stage1-plan.md)
**Spec:** [spec.md](spec.md)
**Issue:** #4119 · **PR:** #4156 (draft)

## Phase 1: Frontmatter Backfill

- [ ] 1.1 Record pre-count: `MISSING_FM_PRE=$(find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---')` (expect ~324)
- [ ] 1.2 Run backfill: `doppler run -p soleur -c dev -- python3 scripts/backfill-frontmatter.py`
- [ ] 1.3 Record post-count: same find pipeline (expect 0)
- [ ] 1.4 Spot-check 5 random newly-backfilled files for inferred-category sanity
- [ ] 1.5 Commit: `chore(learnings): backfill frontmatter via scripts/backfill-frontmatter.py` — body includes both counts and "does not move R@5; hygiene only"

## Phase 2: Lockstep SKILL.md + bench + fixture (single commit)

- [ ] 2.1 Edit `plugins/soleur/skills/kb-search/SKILL.md` Phase 3 keyword-only branch per plan §2a
- [ ] 2.2 Replace `scripts/learning-retrieval-bench.sh` lines 492-507 (`kbsearch_rank`) per plan §2b — anchored awk filter, learnings-only tier-2, no outer head -20
- [ ] 2.3 Add `self_test_flooding_pathology` function and invoke from `self_test` main body per plan §2c
- [ ] 2.4 Demonstrate pre-fix FAIL: `git stash --keep-index && bash scripts/learning-retrieval-bench.sh --self-test 2>&1 | tee /tmp/fail.log && git stash pop` — paste flood-pathology FAIL line in PR body
- [ ] 2.5 Run `bash scripts/learning-retrieval-bench.sh --self-test` — all tests pass including new fixture AND existing synced_to test (lines 919-934)
- [ ] 2.6 Verify generator non-regression: `bash scripts/generate-kb-index.sh && git diff knowledge-base/INDEX.md` — only frontmatter-backfill-derived deltas, no structural change
- [ ] 2.7 Verify plugin budget: `bun test plugins/soleur/test/components.test.ts`
- [ ] 2.8 Commit: `feat(kb-search): cap-split 8/12 + tier-1 learnings scope (lockstep SKILL.md + bench + fixture)`

## Phase 3: Bench Rerun + Gate

- [ ] 3.1 Run: `doppler run -p soleur -c prd_scheduled -- bash scripts/learning-retrieval-bench.sh --confirm` (~70min, ~$3.07)
- [ ] 3.2 Commit metrics JSON + diagnostic findings learning
- [ ] 3.3 Extract: `POST=$(jq '.r5.heavy_kbsearch' knowledge-base/project/learning-retrieval-metrics-*.json | tail -1)`
- [ ] 3.4 Apply spec FR7 ladder (resolving overlap per plan decision-5):
  - [ ] 3.4.1 POST ≥ 0.4 → pass: close #4119 + comment #4042 to unblock
  - [ ] 3.4.2 0.3 ≤ POST < 0.4 → file Stage 1.5 issue (IDF/stopword)
  - [ ] 3.4.3 0.18 ≤ POST < 0.3 → file Stage 2 issue (LLM paraphrase pre-pass) with budget disclosure
  - [ ] 3.4.4 POST < 0.18 → file Stage 3 issue (embeddings, ADR-trigger)
- [ ] 3.5 Update PR body with `jq`-extracted value, FR7 branch reached, and decision rationale

## Phase 4: Ship

- [ ] 4.1 `gh pr ready 4156`
- [ ] 4.2 PR `## Changelog` section + `semver:patch` label
- [ ] 4.3 Run `/soleur:ship` — Phase 5.5 gates all evaluate NONE (no CMO/GDPR/deploy)
- [ ] 4.4 Post-merge verify: Version Bump, CI, CodeQL, secret-scan, skill-security-scan
