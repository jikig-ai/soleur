# Tasks — feat-one-shot-pipeline-token-cost-optimizations

Plan: `knowledge-base/project/plans/2026-05-09-perf-one-shot-pipeline-token-cost-optimizations-plan.md`

## Phase 1 — Change 1: work reference + Phase 2 step 4 bullet

- [ ] 1.1 Create `plugins/soleur/skills/work/references/work-lockfile-bumps.md` ≤80 lines, adapted from source learning (drop session-error narrative; keep surgical pattern + ban list + frozen-lockfile validation).
- [ ] 1.2 Verify length: `wc -l` returns ≤80.
- [ ] 1.3 Edit `plugins/soleur/skills/work/SKILL.md` Phase 2 step 4: add ONE bullet linking to `references/work-lockfile-bumps.md`, gated on `bun.lock` diff.
- [ ] 1.4 Verify only one new bullet added; no other step 4 bullets reordered/removed.

## Phase 2 — Change 2: preflight Phase 0 classifier + check fast-paths

- [ ] 2.1 Edit `plugins/soleur/skills/preflight/SKILL.md` Phase 0: add Step 0.1 that runs `git diff --name-only origin/main...HEAD > /tmp/preflight-diff-files.txt` once.
- [ ] 2.2 Add fast-path SKIP overview table (per-check predicate against the cached path-set).
- [ ] 2.3 Edit Check 1 Step 1.1: replace `git diff` call with `grep -E '/supabase/migrations/[^/]+\.sql$' /tmp/preflight-diff-files.txt`.
- [ ] 2.4 Edit Check 2 Step 2.1: replace `git diff` call with `cat /tmp/preflight-diff-files.txt`; preserve subsequent grep predicate verbatim.
- [ ] 2.5 Leave Check 3 unchanged (uses `--name-status`, status letters are load-bearing).
- [ ] 2.6 Edit Check 5 path-gate: reference cached path-set in prose; preserve regex.
- [ ] 2.7 Edit Check 6 Step 6.1: replace `git diff | grep -E "$SENSITIVE_PATH_RE"` with `grep -E "$SENSITIVE_PATH_RE" /tmp/preflight-diff-files.txt`.
- [ ] 2.8 Edit Check 7 Step 7.1: update prose path-gate to reference cached path-set.
- [ ] 2.9 Edit Check 8 Step 8.2: replace `git diff` call with `grep -E '<surface>' /tmp/preflight-diff-files.txt`.
- [ ] 2.10 Leave Check 9 unchanged (uses `git ls-files`, not `git diff`).
- [ ] 2.11 Verify byte-equality of every preserved regex predicate.

## Phase 3 — Change 3: review classification sub-classes

- [ ] 3.1 Edit `plugins/soleur/skills/review/SKILL.md` Change Classification Gate (lines 63–100): expand binary judgment into 4-class decision tree (override > lockfile-only > deletion-dominated > code > non-code).
- [ ] 3.2 Add inline bash for metric computation (file count, deletion count, line count, source extension presence).
- [ ] 3.3 Add `LOCKFILE_RE`, `ALLOWED_NONLOCK_RE`, `SOURCE_RE` regex constants.
- [ ] 3.4 Add new spawn block for `lockfile-only` / `deletion-dominated` classes: 2 agents (`git-history-analyzer` + `security-sentinel`).
- [ ] 3.5 Update announce line to enumerate four classes with skipped-agent list.
- [ ] 3.6 Confirm conditional-agents block (semgrep-sast, Rails reviewers, etc.) is unaffected.

## Phase 4 — Verification

- [ ] 4.1 From worktree: `bun test plugins/soleur/test/components.test.ts` returns `1013 pass / 0 fail`.
- [ ] 4.2 From worktree: `bash scripts/test-all.sh` passes.
- [ ] 4.3 Verify `git diff --name-only origin/main...HEAD | grep -E '^(AGENTS\.md$|knowledge-base/project/constitution\.md$|agents/)'` returns empty.
- [ ] 4.4 Spot-check review classifier on 3-PR matrix (lockfile-only, deletion-dominated, mixed).
- [ ] 4.5 Spot-check preflight Phase 0 classifier emits expected fast-path SKIPs for a simulated lockfile-only diff.

## Phase 5 — Commit + ship

- [ ] 5.1 Per-change commit OK: one commit per Phase 1/2/3 acceptable.
- [ ] 5.2 Run `/soleur:compound` before final commit.
- [ ] 5.3 Push and open PR; semver label `semver:patch` (refactor, no public API change).
