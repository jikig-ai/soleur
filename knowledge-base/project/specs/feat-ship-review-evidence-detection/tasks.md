# Tasks: fix ship review-evidence detection

## Phase 1: Update ship SKILL.md Phase 1.5

- [x] 1.1 Read `plugins/soleur/skills/ship/SKILL.md` Phase 1.5 section
- [x] 1.2 Add Step 3: get PR number for current branch via `gh pr list --head <branch>`
- [x] 1.3 Add Step 4: search for code-review issues referencing PR via `gh issue list --label code-review --search "PR #<number>"`
- [x] 1.4 Update decision logic to "If **any** step produced output"
- [x] 1.5 Update coupling note to document all three signals and their sources

## Phase 2: Update ship SKILL.md Phase 5.5

- [x] 2.1 Read Phase 5.5 Code Review Completion Gate section
- [x] 2.2 Add the same Signal 3 check (GitHub issues with `code-review` label)
- [x] 2.3 Update coupling note at bottom of Phase 5.5

## Phase 3: Update pre-merge hook

- [x] 3.1 Read `.claude/hooks/pre-merge-rebase.sh` Guard 6 section
- [x] 3.2 Extract PR number from `$CMD` regex
- [x] 3.3 Add `gh issue list` query for code-review issues (with error handling)
- [x] 3.4 Update conditional to include `REVIEW_ISSUES` variable
- [x] 3.5 Handle edge case: PR number not in command args (fallback to branch-based lookup)
- [x] 3.6 Handle edge case: `gh` unavailable or network failure (fail open on signal 3 only)

## Phase 4: Update coupling documentation

- [x] 4.1 Update Phase 1.5 `**Note:**` to list all three signals
- [x] 4.2 Update Phase 5.5 `**Note:**` to list all three signals
- [x] 4.3 Update pre-merge hook header comment to list all three signals

## Phase 5: Verify and test

- [x] 5.1 Run markdownlint on modified `.md` files
- [x] 5.2 Run `shellcheck` on modified `.sh` file (shellcheck not installed; verified logic manually)
- [x] 5.3 Manually verify hook logic handles all edge cases from test scenarios
