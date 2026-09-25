---
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-25-fix-grep-q-pipe-guard-or-false-positive-plan.md
issue: 8807
---

# Tasks: fix(hooks) grep-q-pipe-guard `||` false positive (#8807)

## 1. Setup

- 1.1 Re-fetch `origin/main` and confirm `.claude/hooks/grep-q-pipe-guard.test.sh` still has the unanchored `PATTERN=` (plan Research Reconciliation).
- 1.2 Check whether #8848 has merged (`gh pr view 8848 --json state`). If it has, rebase first.

## 2. Core implementation

- 2.1 RED: in `.claude/hooks/grep-q-pipe-guard.test.sh`, replace the `printf` probes and their check with the Phase 1 block: heredocs with 4 bad and 3 good lines, `[[ -s ]]` on both files, `! grep -qvE` for bad and `! grep -qE` for good. Leave the `# Non-vacuity:` comment and the `probe=`/`trap` lines as they are.
- 2.2 Run the suite with the old PATTERN. Expect exit 1, `forbidden lines matched: 3/4` and `fixed lines matched:     2` (AC2).
- 2.3 GREEN: set `PATTERN='(^|[^|])\|&?[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'` and update its comment (Phase 2).
- 2.4 Sibling: apply the same prefix to both row-10 literals in `tests/scripts/test-lint-supabase-deprecated-endpoints.sh` (Phase 3).

## 3. Testing and verification

- 3.1 AC1, AC3: run `bash .claude/hooks/grep-q-pipe-guard.test.sh`. Expect exit 0 and 3 PASS lines.
- 3.2 AC5: the census grep prints only the two dispositioned infra lines. The anchored-literal counts are 1 and 2.
- 3.3 AC6: run `bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh`. Expect `45 passed, 0 failed`.
- 3.4 AC7: `git diff --name-only origin/main...HEAD -- apps/web-platform/infra/` prints nothing.
- 3.5 AC8: the PR body has `Closes #8807`, the class-sweep dispositions (#8869), the #8848 note, and the `decision-challenges.md` entries.
