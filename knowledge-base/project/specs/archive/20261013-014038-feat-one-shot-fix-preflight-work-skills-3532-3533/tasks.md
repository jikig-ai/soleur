---
plan: knowledge-base/project/plans/2026-05-11-fix-preflight-work-skills-worktree-and-test-all-gate-plan.md
issues: [3532, 3533]
branch: feat-one-shot-fix-preflight-work-skills-3532-3533
---

# Tasks: Fix preflight worktree-write + work test-all exit gate

## Phase 1: Preflight skill substitution (#3532)

- [ ] 1.1 **RED**: write sanity test asserting `rg '\.git/preflight-diff-files\.txt' plugins/soleur/skills/preflight/SKILL.md` returns 0 matches (test fails pre-edit because file has 12 matches).
- [ ] 1.2 **GREEN-a**: insert `PREFLIGHT_TMP="$(git rev-parse --git-dir)"` resolver block near the first use (around line 32) with a 1-sentence prose preamble citing "worktree" and `Not a directory`. Mirror review SKILL.md lines 67-69 style.
- [ ] 1.3 **GREEN-b**: substitute every occurrence of literal substring `.git/preflight-diff-files.txt` with `"$PREFLIGHT_TMP/preflight-diff-files.txt"` (Edit tool with `replace_all: true`).
- [ ] 1.4 **REFACTOR**: verify post-edit grep returns 0 for the old literal AND ≥10 for the new path; confirm resolver line appears exactly once.

## Phase 2: Work skill exit-gate clause (#3533)

- [ ] 2.1 **RED**: write sanity test asserting `rg 'bash scripts/test-all\.sh' plugins/soleur/skills/work/SKILL.md` returns ≥1 match inside Phase 2 (line range 148-425).
- [ ] 2.2 **GREEN**: insert new step 9 ("Full-Suite Exit Gate") between current step 8 (GDPR gate, line 378) and Phase 2.5 (line 386). Body: ≤3 lines + rationale referencing "orphan test suites" / PR #3512 / issue #3533.
- [ ] 2.3 **REFACTOR**: confirm Phase 3 boundary intact, step numbering monotonic, GDPR step 8 prose untouched.

## Phase 3: Lint, commit, push

- [ ] 3.1 Run `bash scripts/test-all.sh` (dogfood the rule the plan added).
- [ ] 3.2 Verify all Acceptance Criteria grep targets in the plan.
- [ ] 3.3 Run `/soleur:compound` (capture any session-error learnings).
- [ ] 3.4 Commit: `fix(skills): preflight git-dir resolution + work test-all exit gate (#3532, #3533)`.
- [ ] 3.5 Push branch; open PR with `Closes #3532` and `Closes #3533` on separate body lines.
- [ ] 3.6 Apply `semver:patch` and `bug` / `type/bug` / `domain/engineering` labels (matching parent issue labels).
