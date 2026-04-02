---
title: "fix: ship skill review-evidence detection broken after #1288"
type: fix
date: 2026-04-02
---

# fix: ship skill review-evidence detection broken after #1288

## Overview

PR #1329 changed the review skill to create GitHub issues (with the `code-review` label) instead of local `todos/*.md` files. The ship skill's review-evidence detection in Phase 1.5, Phase 5.5, and the pre-merge hook still look for only two signals -- both of which now false-negative:

1. `grep -rl "code-review" todos/` -- no local todo files are created anymore
2. `git log origin/main..HEAD --oneline | grep "refactor: add code review findings"` -- no commit is created for review findings (issues are remote)

This causes ship to abort in headless mode or force redundant re-reviews in interactive mode.

## Problem Statement

Three files contain review-evidence detection logic that is now stale:

| File | Location | Current Detection | Status |
|------|----------|-------------------|--------|
| `plugins/soleur/skills/ship/SKILL.md` | Phase 1.5 (lines 77-93) | `grep -rl "code-review" todos/` + commit grep | Both false-negative |
| `plugins/soleur/skills/ship/SKILL.md` | Phase 5.5 (lines 229-237) | Same two signals | Both false-negative |
| `.claude/hooks/pre-merge-rebase.sh` | Guard 6 (lines 59-76) | Same two signals | Both false-negative |

The review skill (`review/SKILL.md` Step 5 + `review-todo-structure.md`) now creates GitHub issues with:

- Label: `code-review`
- Title prefix: `review:`
- Labels also include `priority/p1-high|p2-medium|p3-low` and `domain/engineering`

## Proposed Solution

Add a third detection signal: check for GitHub issues labeled `code-review` that were created from (or reference) the current branch's PR. Keep the old `todos/` check and commit-message check for backward compatibility with branches that were reviewed before #1329 merged.

### Detection Logic (3-signal OR)

For ship SKILL.md (prose instructions to the LLM):

1. **Signal 1 (legacy):** `grep -rl "code-review" todos/` -- backward compat
2. **Signal 2 (legacy):** `git log origin/main..HEAD --oneline | grep "refactor: add code review findings"` -- backward compat
3. **Signal 3 (current):** Query GitHub issues with `code-review` label that reference the current branch's PR number

For the pre-merge hook (bash script):

1. **Signal 1 (legacy):** Same grep on `todos/`
2. **Signal 2 (legacy):** Same git log grep
3. **Signal 3 (current):** `gh issue list --label code-review --search "PR #<number>" --json number --jq '.[0].number // empty'` or search by PR number extracted from the `gh pr merge` command arguments

### Signal 3 Implementation Detail

The review skill creates issues with body containing `**Source:** PR #<pr_number> review`. To detect these:

**In ship SKILL.md (LLM instructions):**

The skill already has access to the current branch name. The detection sequence is:

1. Get the PR number for the current branch: `gh pr list --head <branch-name> --state open --json number --jq '.[0].number // empty'`
2. Search for code-review issues referencing that PR: `gh issue list --label code-review --search "PR #<number>" --json number --jq '.[0].number // empty'`
3. If the result is non-empty, review evidence is found.

**In the pre-merge hook (bash):**

The hook intercepts `gh pr merge <number>`. The PR number can be extracted from the command arguments. Then:

1. Extract PR number from the `gh pr merge` command (already in `$CMD`)
2. Query: `gh issue list --label code-review --search "PR #<number>" --json number --jq '.[0].number // empty'`
3. If non-empty, set `REVIEW_ISSUES` variable

**Network concern for the hook:** Signal 3 requires network access (`gh` API call). The hook already makes network calls (`git fetch origin main`), so this is consistent. If `gh` fails, treat it as no-evidence (same as the existing fail-open pattern for fetch).

## Acceptance Criteria

- [ ] Ship Phase 1.5 checks all three signals (local todos, commit message, GitHub issues)
- [ ] Ship Phase 5.5 checks all three signals (same)
- [ ] Pre-merge hook Guard 6 checks all three signals (same)
- [ ] Old `todos/` signal still works for branches reviewed before #1329
- [ ] Old commit-message signal still works for branches reviewed before #1329
- [ ] New GitHub issue signal detects review evidence created by the current review skill
- [ ] Hook fails open if `gh` is unavailable or returns an error (no network)
- [ ] Ship SKILL.md coupling note is updated to reference all three signals and their sources
- [ ] AGENTS.md PreToolUse hooks description is accurate (currently says "gh pr merge without review evidence" which is still correct)

## Test Scenarios

- Given a branch reviewed after #1329 (GitHub issues only, no todos), when ship Phase 1.5 runs, then review evidence is detected and ship continues
- Given a branch reviewed before #1329 (local todos only), when ship Phase 1.5 runs, then review evidence is detected via legacy signal
- Given a branch with no review evidence at all, when ship Phase 1.5 runs in headless mode, then ship aborts with error message
- Given a branch reviewed after #1329, when `gh pr merge` is attempted, then the pre-merge hook allows it
- Given a branch with no review evidence, when `gh pr merge` is attempted, then the pre-merge hook blocks with deny message
- Given the hook runs without network access (gh fails), when `gh pr merge` is attempted with no local evidence, then the hook blocks (fails closed on the check, since signals 1 and 2 are local)
- Given the hook runs without network access but local todos exist, when `gh pr merge` is attempted, then the hook allows it (signal 1 suffices)

## Technical Approach

### Files to Modify

1. **`plugins/soleur/skills/ship/SKILL.md`** -- Phase 1.5 and Phase 5.5 sections
2. **`.claude/hooks/pre-merge-rebase.sh`** -- Guard 6 section

### Phase 1: Update ship SKILL.md Phase 1.5

Update the review evidence detection instructions to add Signal 3.

**Current code in Phase 1.5 (Step 1):**

```bash
grep -rl "code-review" todos/ 2>/dev/null | head -1 || true
```

**Current code in Phase 1.5 (Step 2):**

```bash
git log origin/main..HEAD --oneline | grep "refactor: add code review findings" || true
```

**Add Step 3:** Get the PR number for the current branch, then search for code-review issues referencing it. This requires two separate Bash calls (no command substitution per SKILL.md rules).

Update the decision logic: "If **any** step produced output: Review evidence found."

Update the coupling note to mention all three signals and their sources:

- Signal 1 coupled to: legacy `todos/` workflow (pre-#1329)
- Signal 2 coupled to: legacy review SKILL.md Step 5 commit message (pre-#1329)
- Signal 3 coupled to: `review-todo-structure.md` issue body template (`**Source:** PR #<number>`)

### Phase 2: Update ship SKILL.md Phase 5.5

Phase 5.5 currently says "Check for review evidence using the same signals as Phase 1.5" and repeats the two bash blocks. Update to:

1. Add the same Signal 3 check
2. Update the coupling note at the bottom of Phase 5.5

### Phase 3: Update pre-merge hook

Add Signal 3 to `.claude/hooks/pre-merge-rebase.sh` Guard 6.

**Implementation:**

1. Extract PR number from `$CMD` using regex (e.g., `echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+'`)
2. If PR number found, query GitHub: `gh issue list --label code-review --search "PR #<number>" --json number --jq '.[0].number // empty' 2>/dev/null`
3. Store result in `REVIEW_ISSUES`
4. Update the conditional: `if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then`

**Edge cases:**

- PR number not extractable from command (e.g., `gh pr merge` without number uses current branch) -- in this case, fall back to `gh pr list --head <branch> --json number` to get PR number, or skip Signal 3 if that also fails
- `gh` not installed or auth fails -- treat as empty (fail open on Signal 3 specifically, but the overall gate still fails closed if signals 1 and 2 are also empty)
- Network timeout -- `gh` has a default timeout; if it hangs, the hook will block. Add a timeout wrapper or rely on Claude Code's command timeout.

**Fail strategy:** Signal 3 failure should not change the overall fail behavior. If signals 1 and 2 are empty and signal 3 errors, the gate still blocks (correct behavior -- we cannot confirm review ran). If signal 3 errors but signal 1 or 2 succeeds, the gate passes (also correct).

### Phase 4: Update coupling documentation

Update the `**Note:**` comments in both Phase 1.5 and Phase 5.5 to document all three signals and what they are coupled to.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal tooling/workflow fix.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Remove old signals entirely | Simpler code | Breaks branches reviewed before #1329 | Rejected -- backward compat needed |
| Only check GitHub issues | Clean single-source | Network dependency in hook; breaks old branches | Rejected |
| Add a marker file during review | Local, fast, no network | Another file to manage; review skill just moved away from files | Rejected |
| Three-signal OR (proposed) | Backward compat; covers current review flow; fails safely | Slightly more complex detection | **Accepted** |

## References

- Issue: [#1336](https://github.com/jikig-ai/soleur/issues/1336)
- PR that caused the break: [#1329](https://github.com/jikig-ai/soleur/pulls/1329) (feat(review): create GitHub issues instead of local todos)
- Original review refactor issue: [#1288](https://github.com/jikig-ai/soleur/issues/1288)
- Ship SKILL.md: `plugins/soleur/skills/ship/SKILL.md`
- Pre-merge hook: `.claude/hooks/pre-merge-rebase.sh`
- Review SKILL.md: `plugins/soleur/skills/review/SKILL.md`
- Review todo structure: `plugins/soleur/skills/review/references/review-todo-structure.md`
