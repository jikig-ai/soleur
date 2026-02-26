---
title: "feat: Draft PR at Worktree Creation + Commit Per Phase"
type: feat
date: 2026-02-25
---

# feat: Draft PR at Worktree Creation + Commit Per Phase

[Updated 2026-02-25: Applied review feedback from DHH, Kieran, Code Simplicity reviewers]

## Overview

Change the Soleur workflow to create a draft PR immediately when a worktree or feature branch is created, and commit artifacts at the end of each skill boundary. This protects against hardware failure / session crashes and enables cross-device handoff.

## Problem Statement / Motivation

Brainstorm and plan phases produce markdown artifacts (brainstorm docs, specs, plans, tasks) that exist only on local disk. No commits or pushes happen until `ship` Phase 7. A crash, power loss, or device switch loses all uncommitted work. Cross-device pickup is impossible until the PR is created at the very end of the pipeline.

The `work` skill already does incremental WIP commits (Phase 2) — this extends that pattern to brainstorm and plan.

## Proposed Solution

1. **`draft-pr` subcommand in `worktree-manager.sh`** — new function that creates an empty commit, pushes the branch, and opens a draft PR. Idempotent. Reuses existing color constants and error handling patterns.
2. **SKILL.md edits** — add commit+push instructions at skill boundaries in brainstorm, plan, one-shot, and workshop reference files.
3. **Ship adaptation** — detect existing draft PR, replace body, mark ready. Falls through to `gh pr create` when no draft PR exists (backwards compatible with direct /plan or /work entry).

## Technical Considerations

### Architecture

- `draft-pr` is a subcommand of `worktree-manager.sh` (not a separate script). It reuses existing color constants, `GIT_ROOT`, and error handling patterns. One file to maintain, not two.
- Ship Phase 7 gains a conditional: if draft PR exists → edit + ready; else → create (backwards compatible)
- Intermediate pushes (brainstorm end, plan end) bypass Ship's pre-push compound gate — they are plain `git push`, not routed through Ship

### Error Handling

Block on git failures (state corruption). Warn and continue on network failures (push, PR create/edit). The `gh pr list` idempotency check distinguishes "no PR found" from "gh CLI failed" by capturing stderr.

### Open Questions Closed

- **Brainstorm Q1 (PR title convention):** `WIP: <branch-name>` — simple, machine-parseable, overwritten by Ship.
- **Brainstorm Q2 (empty commit message):** `chore: initialize <branch-name>` — collapsed by squash merge.
- **Brainstorm Q3 (work skill push):** No. Work already does incremental commits. Ship handles the final push. Adding push to work boundaries would be redundant.

## Implementation Phases

### Phase 1: Add `draft-pr` subcommand to `worktree-manager.sh`

**File:** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

Add a `create_draft_pr()` function and a `draft-pr` case in `main()`.

```bash
# Create a draft PR for the current branch
# Idempotent: skips if a PR already exists
# All push/PR failures warn but do not block (returns 0)
create_draft_pr() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  # Guard: refuse to run on main/master
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo -e "${RED}Error: Cannot create draft PR on $branch${NC}"
    return 1
  fi

  # Check if PR already exists (idempotent)
  local existing_pr
  if ! existing_pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>&1); then
    echo -e "${YELLOW}Warning: Could not check for existing PR: $existing_pr${NC}"
    # Continue anyway -- push will still work
    existing_pr=""
  fi

  if [[ -n "$existing_pr" ]]; then
    echo -e "${GREEN}Draft PR #$existing_pr already exists for $branch${NC}"
    return 0
  fi

  # Create empty initial commit
  git commit --allow-empty -m "chore: initialize $branch"

  # Push branch to remote (warn on failure, do not block)
  local push_error
  if ! push_error=$(git push -u origin "$branch" 2>&1); then
    echo -e "${YELLOW}Warning: Push failed. Work is committed locally.${NC}"
    echo "  $push_error"
    return 0
  fi

  # Create draft PR (warn on failure, do not block)
  local pr_body="Draft PR created automatically. Content will be added as work progresses."
  local pr_url
  if ! pr_url=$(gh pr create --draft --title "WIP: $branch" --body "$pr_body" 2>&1); then
    echo -e "${YELLOW}Warning: Draft PR creation failed. Branch is pushed to remote.${NC}"
    echo "  $pr_url"
    return 0
  fi

  echo -e "${GREEN}Draft PR created: $pr_url${NC}"
}
```

Add to `main()` dispatch:

```bash
draft-pr)
  create_draft_pr
  ;;
```

**Acceptance criteria:**
- [ ] Idempotent: returns 0 if PR already exists
- [ ] Warns but continues on network failure
- [ ] Blocks on main/master (returns 1)
- [ ] Uses existing color constants (no `${RED:-}` fallbacks)
- [ ] Distinguishes "no PR found" from "gh CLI failed"

### Phase 2: Modify brainstorm SKILL.md

**File:** `plugins/soleur/skills/brainstorm/SKILL.md`

**Edit 1 — Phase 3:** After step 3 (Set worktree path), add step 4:

```markdown
4. **Create draft PR:**

   Switch to the worktree and create a draft PR:

   ```bash
   cd .worktrees/feat-<name>
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
   ```

   This creates an empty commit, pushes the branch, and opens a draft PR. If the push or PR creation fails (no network), a warning is printed but the workflow continues.
```

**Edit 2 — End of Phase 3.6:** At the end of Phase 3.6, after step 5 (Save spec.md) and before step 6 (Switch to worktree), add:

```markdown
5b. **Commit and push all brainstorm artifacts:**

    After the brainstorm document (Phase 3.5) and spec (Phase 3.6) are both written, commit and push everything:

    ```bash
    git add knowledge-base/brainstorms/ knowledge-base/specs/feat-<name>/
    git commit -m "docs: capture brainstorm and spec for feat-<name>"
    git push
    ```

    If the push fails (no network), print a warning but continue. The artifacts are committed locally.
```

Note: This is a single commit covering both the brainstorm doc and spec, pushed once at the skill boundary.

### Phase 3: Modify workshop reference files

**File:** `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`

After step 1 (Create worktree), within step 3 (Navigate to worktree), append the draft-pr call:

```markdown
   After verifying the path, create a draft PR:

   ```bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
   ```

   If this fails (no network), print a warning but continue.
```

After step 4 (Hand off to brand-architect), before step 5 (Display completion), add:

```markdown
4b. **Commit and push workshop artifacts:**

    ```bash
    git add knowledge-base/overview/brand-guide.md
    git commit -m "docs: capture brand guide"
    git push
    ```

    If the push fails, print a warning but continue.
```

**File:** `plugins/soleur/skills/brainstorm/references/brainstorm-validation-workshop.md`

Same pattern: add draft-pr call within step 3, add commit+push after step 4 for `knowledge-base/overview/business-validation.md`.

### Phase 4: Modify one-shot SKILL.md

**File:** `plugins/soleur/skills/one-shot/SKILL.md`

After Step 0b branch creation text, add:

```markdown
After creating the feature branch, create a draft PR:

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr
```

If this fails (no network), print a warning but continue. The branch exists locally.
```

### Phase 5: Modify plan SKILL.md

**File:** `plugins/soleur/skills/plan/SKILL.md`

**Single edit — Save Tasks section:** After step 3 (Announce tasks saved), add:

```markdown
4. **Commit and push plan artifacts:**

   After both the plan file and tasks.md are written, commit and push everything:

   ```bash
   git add knowledge-base/plans/ knowledge-base/specs/feat-<name>/tasks.md
   git commit -m "docs: create plan and tasks for feat-<name>"
   git push
   ```

   If the push fails (no network), print a warning but continue.
```

Note: The plan file (from the Output Format section) and tasks.md are committed together in one commit, pushed once at the skill boundary.

### Phase 6: Modify ship SKILL.md

**File:** `plugins/soleur/skills/ship/SKILL.md`

Replace the PR creation block in Phase 7 (lines 248-262, after the push section) with:

```markdown
**Check for existing PR on this branch:**

Get the branch name:

```bash
git rev-parse --abbrev-ref HEAD
```

Check for an existing open PR:

```bash
gh pr list --head BRANCH_NAME --state open --json number,isDraft --jq '.[0]'
```

**If an open PR exists:**

1. The PR was likely created as a draft earlier in the workflow.
2. Confirm the PR title and body with the user before editing.
3. Update the PR:

   ```bash
   gh pr edit PR_NUMBER --title "the pr title" --body "## Summary
   - bullet points

   ## Test plan
   - checklist

   Generated with [Claude Code](https://claude.com/claude-code)"
   ```

4. If the PR is a draft, mark it ready:

   ```bash
   gh pr ready PR_NUMBER
   ```

5. Present the PR URL to the user.

**If no open PR exists:**

Fall through to the current behavior: create a new PR with `gh pr create`. This handles cases where the user entered the pipeline through `/plan` or `/work` directly (skipping brainstorm/one-shot).
```

The push section (lines 234-246) remains unchanged — it still runs before the PR check.

### Phase 7: Version bump

- [ ] Bump version in `plugin.json` (PATCH — no new skills/agents/commands)
- [ ] Update `CHANGELOG.md` with changes
- [ ] Verify `README.md` component counts (unchanged — no new components)
- [ ] Update root `README.md` version badge
- [ ] Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder

## Acceptance Criteria

- [ ] Brainstorm Phase 3 calls `worktree-manager.sh draft-pr` after worktree creation
- [ ] Brainstorm end (Phase 3.6) commits brainstorm doc + spec together, then pushes
- [ ] Brand Workshop calls `worktree-manager.sh draft-pr` and commits+pushes workshop artifacts
- [ ] Validation Workshop calls `worktree-manager.sh draft-pr` and commits+pushes workshop artifacts
- [ ] One-shot Step 0b calls `worktree-manager.sh draft-pr` after branch creation
- [ ] Plan end commits plan + tasks.md together, then pushes
- [ ] Ship Phase 7 detects existing draft PR and uses `gh pr edit` + `gh pr ready`
- [ ] Ship Phase 7 falls through to `gh pr create` when no draft PR exists

## Test Scenarios

- Given a fresh worktree, when `worktree-manager.sh draft-pr` runs, then an empty commit is created, branch is pushed, and a draft PR is opened
- Given `draft-pr` already ran, when it runs again (idempotent), then it detects existing PR and exits 0 without creating a duplicate
- Given no network, when `draft-pr` runs, then it warns about push failure but exits 0
- Given brainstorm completes, when Phase 3.6 ends, then brainstorm doc + spec are committed AND pushed in one commit
- Given plan completes, when tasks.md is written, then plan + tasks are committed AND pushed in one commit
- Given Ship Phase 7 finds a draft PR, when it runs, then it edits the PR body and marks it ready (no duplicate PR created)
- Given Ship Phase 7 finds no PR (direct /plan entry), when it runs, then it creates a new PR via `gh pr create` (backwards compatible)

## Dependencies & Risks

**Dependencies:**
- `gh` CLI must be authenticated (already required by the pipeline)
- Remote must be reachable for push (graceful degradation if not)

**Risks:**
- CI noise from pushes to draft PRs (accepted — draft PRs may not trigger full CI depending on repo config)
- Empty commits pollute git history (mitigated — squash merge at Ship time collapses all commits)

## References & Research

- Brainstorm: `knowledge-base/brainstorms/2026-02-25-draft-pr-workflow-brainstorm.md`
- Spec: `knowledge-base/specs/feat-draft-pr-workflow/spec.md`
- Issue: #304
- Learning: `knowledge-base/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` (commit early, never stash)
- Learning: `knowledge-base/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` (scope `|| true`)
- Learning: `knowledge-base/learnings/2026-02-24-extract-command-substitution-into-scripts.md` (no `$()` in SKILL.md)
- Ship SKILL.md Phase 7: `plugins/soleur/skills/ship/SKILL.md:214`
- worktree-manager.sh: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:127`
