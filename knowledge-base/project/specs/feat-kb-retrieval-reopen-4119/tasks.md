# Tasks: KB Retrieval Reopen — Stage 1

**Plan:** [../../plans/2026-05-20-feat-kb-retrieval-reopen-stage1-plan.md](../../plans/2026-05-20-feat-kb-retrieval-reopen-stage1-plan.md)  
**Spec:** [spec.md](spec.md)  
**Issue:** #4119  
**Branch:** `feat-kb-retrieval-reopen-4119`  
**PR:** #4156 (draft)

## Phase 0: Pre-change Baseline (operator)

- [ ] 0.1 Provision paraphrase-cache directory: `mkdir -p /tmp/kb-bench-cache`
- [ ] 0.2 Run baseline bench with cache: `doppler run -p soleur -c prd_scheduled -- bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-cache/paraphrases-2026-05-20.ndjson` (~70min, ~$3.07)
- [ ] 0.3 Verify output JSON: `jq '.r5.heavy_kbsearch, .r5.heavy_grep, .corpus_count' knowledge-base/project/learning-retrieval-metrics-*.json` — pick up the just-created `pre`-tagged file
- [ ] 0.4 Rename output to baseline-tagged path: `mv knowledge-base/project/learning-retrieval-metrics-<date>.json knowledge-base/project/learning-retrieval-metrics-2026-05-20-pre.json` (and the diagnostic learning file similarly)
- [ ] 0.5 Commit: `chore(bench): pre-change baseline on 1152-doc corpus (R@5(heavy)=<value>)`

## Phase 1: Frontmatter Backfill (mechanical)

- [ ] 1.1 Pre-count: `find knowledge-base/project/learnings -name '*.md' -exec head -1 {} \; | grep -vc '^---'` → record baseline count (expect ~324)
- [ ] 1.2 Run backfill: `doppler run -p soleur -c dev -- python3 scripts/backfill-frontmatter.py`
- [ ] 1.3 Capture stats output (processed/created/augmented/skipped/errors) for commit body
- [ ] 1.4 Post-count verify: same find pipeline → expect 0 (modulo intentional exclusions documented inline)
- [ ] 1.5 Spot-check 5 random newly-backfilled files for inferred category sanity (`grep -A1 '^category:' <file>`)
- [ ] 1.6 Commit: `chore(learnings): backfill frontmatter on ~324 files (PyYAML, idempotent)` — body notes backfill does NOT affect bench retrieval scoring (per plan D3)

## Phase 2: Lockstep Strategy + Bench + Fixture (single commit)

- [ ] 2.1 Edit `plugins/soleur/skills/kb-search/SKILL.md` Phase 3 prose: tier-1 cap=8 + `/learnings/` scope; tier-2 cap=12 + `learnings/`-only scope (per plan Phase 2a)
- [ ] 2.2 Edit `scripts/learning-retrieval-bench.sh` `kbsearch_rank` (lines 492-507) per plan Phase 2b
  - [ ] 2.2.1 `tier1 = rank_indexmd_by_token_overlap | awk '/\/learnings\//' | head -8`
  - [ ] 2.2.2 `tier2 = rank_paths_by_token_overlap_corpus learnings-only | head -12`
  - [ ] 2.2.3 Remove `| head -20` from combined dedup; tiers self-cap
  - [ ] 2.2.4 Preserve `synced_paths_json` arg + `rank_paths_min_rank` call (D5)
- [ ] 2.3 Add `legacy_kbsearch_rank` (frozen pre-fix impl) in self-test section only, with `# DO NOT REMOVE: regression-fail anchor. Delete after Stage 1.5 or six weeks (2026-07-01).` comment
- [ ] 2.4 Add `self_test_flooding_pathology` function (plan Phase 2c) and invoke it from `self_test` main body
- [ ] 2.5 Single commit: `feat(kb-search): cap-split 8/12 + tier-1 learnings scope (lockstep SKILL.md + bench + fixture)` — body cites brainstorm D1-D6 and links spec + plan

## Phase 3: Self-test Gate (CI)

- [ ] 3.1 Run `bash scripts/learning-retrieval-bench.sh --self-test` locally
- [ ] 3.2 Confirm new `self_test_flooding_pathology` reports PASS on both assertions
- [ ] 3.3 Confirm all existing tests (lines 832-958) still pass — especially the `synced_to` min-rank test (D5 preservation)
- [ ] 3.4 Confirm bench self-test is invoked in CI (`.github/workflows/ci.yml`); if not, add to PR scope as TR3 gate

## Phase 4: Generator Non-regression Check

- [ ] 4.1 Re-run `bash scripts/generate-kb-index.sh`
- [ ] 4.2 `git diff knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt` — diff must reflect ONLY frontmatter-backfill-derived tag/category additions, not structural INDEX.md changes
- [ ] 4.3 If unexpected structural diff appears: halt, investigate, file note in PR body

## Phase 5: Plugin Loader Budget Check

- [ ] 5.1 Run `bun test plugins/soleur/test/components.test.ts` — must pass (SKILL.md description size unchanged; body edits only)

## Phase 6: Post-change Bench Rerun (cache-hit, free)

- [ ] 6.1 Rerun with cache: `bash scripts/learning-retrieval-bench.sh --confirm --cache-paraphrases /tmp/kb-bench-cache/paraphrases-2026-05-20.ndjson` (~minutes, no LLM spend)
- [ ] 6.2 Rename output to `-post` tagged path
- [ ] 6.3 Write `knowledge-base/project/learnings/2026-05-20-retrieval-stage1-findings.md` summarizing pre→post R@5(heavy) delta + ladder branch reached
- [ ] 6.4 Commit: `chore(bench): post-Stage-1 metrics (R@5(heavy)=<value>; cache-hit)`

## Phase 7: Gate Decision + Ladder Action

- [ ] 7.1 Extract metrics: `PRE=$(jq .r5.heavy_kbsearch ...-pre.json); POST=$(jq .r5.heavy_kbsearch ...-post.json); echo "$PRE → $POST"`
- [ ] 7.2 Apply ladder (plan D1):
  - [ ] 7.2.1 If POST ≥ 0.42 → pass
  - [ ] 7.2.2 If 0.38 ≤ POST < 0.42 → borderline; re-run bench once (cache-hit, free), average; if avg ≥ 0.40 → pass
  - [ ] 7.2.3 If 0.30 ≤ POST < 0.38 → Stage 1.5 deferred issue
  - [ ] 7.2.4 If 0.18 ≤ POST < 0.30 → Stage 2 deferred issue + budget disclosure
  - [ ] 7.2.5 If POST < 0.18 → Stage 3 deferred issue + ADR-trigger
- [ ] 7.3 If pass: close #4119 with bench link; comment on #4042 to unblock
- [ ] 7.4 If fail: file exactly one deferred-tracking issue with milestone `Post-MVP / Later`, trigger condition, and bench-rerun gate
- [ ] 7.5 Update PR body with `jq`-extracted numbers, ladder branch outcome, and decision rationale

## Phase 8: Ship

- [ ] 8.1 Mark PR ready: `gh pr ready 4156`
- [ ] 8.2 Apply `semver:patch` label and add `## Changelog` section to PR body
- [ ] 8.3 Confirm Phase 5.5 conditional gates (cmo-content, gdpr-gate, deploy_pipeline_fix) all evaluate NONE
- [ ] 8.4 Run `/soleur:ship`
- [ ] 8.5 Post-merge: verify all post-merge workflows succeed (Version Bump, CI, CodeQL, secret-scan, skill-security-scan)
- [ ] 8.6 Worktree cleanup via session-state lock

## Phase 9: Calendar Reminder

- [ ] 9.1 Add reminder for 2026-07-01: delete `legacy_kbsearch_rank` from `learning-retrieval-bench.sh` self-test section (or upon Stage 1.5 landing, whichever first)
