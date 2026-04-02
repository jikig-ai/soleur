# Tasks: fix ship review-evidence detection

## Phase 1: Update ship SKILL.md Phase 1.5

- [ ] 1.1 Read `plugins/soleur/skills/ship/SKILL.md` Phase 1.5 section
- [ ] 1.2 Add Step 3: get PR number for current branch via `gh pr list --head <branch>`
- [ ] 1.3 Add Step 4: search for code-review issues referencing PR via `gh issue list --label code-review --search "PR #<number>"`
- [ ] 1.4 Update decision logic to "If **any** step produced output"
- [ ] 1.5 Update coupling note to document all three signals and their sources

## Phase 2: Update ship SKILL.md Phase 5.5

- [ ] 2.1 Read Phase 5.5 Code Review Completion Gate section
- [ ] 2.2 Add the same Signal 3 check (GitHub issues with `code-review` label)
- [ ] 2.3 Update coupling note at bottom of Phase 5.5

## Phase 3: Update pre-merge hook

- [ ] 3.1 Read `.claude/hooks/pre-merge-rebase.sh` Guard 6 section
- [ ] 3.2 Extract PR number from `$CMD` regex
- [ ] 3.3 Add `gh issue list` query for code-review issues (with error handling)
- [ ] 3.4 Update conditional to include `REVIEW_ISSUES` variable
- [ ] 3.5 Handle edge case: PR number not in command args (fallback to branch-based lookup)
- [ ] 3.6 Handle edge case: `gh` unavailable or network failure (fail open on signal 3 only)

## Phase 4: Update coupling documentation

- [ ] 4.1 Update Phase 1.5 `**Note:**` to list all three signals
- [ ] 4.2 Update Phase 5.5 `**Note:**` to list all three signals
- [ ] 4.3 Update pre-merge hook header comment to list all three signals

## Phase 5: Verify and test

- [ ] 5.1 Run markdownlint on modified `.md` files
- [ ] 5.2 Run `shellcheck` on modified `.sh` file
- [ ] 5.3 Manually verify hook logic handles all edge cases from test scenarios
