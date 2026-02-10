---
name: ship
description: This skill should be used when preparing a feature for production deployment. It enforces the complete feature lifecycle checklist, ensuring all artifacts are committed, documentation is updated, learnings are captured, and version is bumped before creating a PR. Triggers on "ready to ship", "create PR", "ship it", "ready to merge", "/ship".
---

# ship Skill

**Purpose:** Enforce the full feature lifecycle before creating a PR, preventing missed steps like forgotten /compound runs, uncommitted artifacts, and missing version bumps.

## Phase 0: Context Detection

Detect the current environment:

```bash
# Determine current branch and worktree
git rev-parse --abbrev-ref HEAD
git worktree list
pwd
```

Load project conventions:

```bash
if [[ -f "CLAUDE.md" ]]; then
  cat CLAUDE.md
fi
```

Identify the base branch (main/master) for comparison:

```bash
git remote show origin | grep 'HEAD branch'
```

## Phase 1: Validate Artifact Trail

Check that feature artifacts exist and are committed. Look for files related to the current feature branch name:

```bash
# Extract feature name from branch (e.g., feat-user-auth -> user-auth)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
FEATURE=$(echo "$BRANCH" | sed 's/^feat-//' | sed 's/^feature\///' | sed 's/^fix-//' | sed 's/^fix\///')

# Check for brainstorm artifacts
ls knowledge-base/brainstorms/*${FEATURE}* 2>/dev/null

# Check for spec artifacts
ls knowledge-base/specs/feat-${FEATURE}/spec.md 2>/dev/null

# Check for plan artifacts
ls knowledge-base/plans/*${FEATURE}* 2>/dev/null

# Check for uncommitted files
git status --porcelain knowledge-base/
```

**If artifacts exist but are not committed:** Stage and commit them.

**If no artifacts exist:** Note this in the checklist but do not block. Not all features go through the full brainstorm/plan cycle.

## Phase 2: Capture Learnings

Check if /compound was run for this feature:

```bash
# Look for recent learnings matching this feature
ls knowledge-base/learnings/**/*${FEATURE}* 2>/dev/null
git log --oneline --since="1 week ago" -- knowledge-base/learnings/
```

**If no recent learning exists:** Ask the user:

"No learnings documented for this feature. Run /compound to capture what you learned?"

- **Yes** -> Run `/soleur:compound`
- **Skip** -> Continue without documenting

## Phase 3: Verify Documentation

Check if new commands, skills, or agents were added in this branch:

```bash
# Compare against base branch for new additions
git diff --name-status $(git merge-base HEAD origin/main)..HEAD -- \
  plugins/soleur/commands/ \
  plugins/soleur/skills/ \
  plugins/soleur/agents/
```

**If new components were added:**

1. Verify `plugins/soleur/README.md` component counts are accurate
2. Verify new entries appear in the correct tables
3. If counts are wrong, fix them

**If no new components:** Skip this step.

## Phase 4: Version Bump

Check if plugin files were modified in this branch:

```bash
git diff --name-only $(git merge-base HEAD origin/main)..HEAD -- plugins/soleur/
```

**If plugin files were modified:**

Read `plugins/soleur/AGENTS.md` for versioning rules, then:

1. Determine bump type:
   - New skill/command/agent -> MINOR (e.g., 1.6.0 -> 1.7.0)
   - Bug fix/docs only -> PATCH (e.g., 1.6.0 -> 1.6.1)
   - Breaking changes -> MAJOR (e.g., 1.6.0 -> 2.0.0)

2. Update these three files (the versioning triad):
   - `plugins/soleur/.claude-plugin/plugin.json` (version field)
   - `plugins/soleur/CHANGELOG.md` (new entry with today's date)
   - `plugins/soleur/README.md` (verify component counts)

3. Sync version to all external references:
   - `README.md` (root) -- update the version badge: `![Version](https://img.shields.io/badge/version-X.Y.Z-blue)`
   - `.github/ISSUE_TEMPLATE/bug_report.yml` -- update the placeholder version

**If no plugin files modified:** Skip version bump.

## Phase 5: Final Checklist

Create a TodoWrite checklist summarizing the state:

```text
Ship Checklist for [branch name]:

- [x/skip] Artifacts committed (brainstorm/spec/plan)
- [x/skip] Learnings captured (/compound)
- [x/skip] README updated (component counts)
- [x/skip] Version bumped (plugin.json + CHANGELOG + README)
- [x/skip] Version synced (root README badge + bug report template)
- [ ] Tests pass
- [ ] Push to remote
- [ ] Create PR
```

## Phase 6: Run Tests

Run the project's test suite:

```bash
bun test
```

**If tests fail:** Stop and fix before proceeding.

## Phase 7: Push and Create PR

```bash
# Push branch to remote
git push -u origin $(git rev-parse --abbrev-ref HEAD)

# Create PR using gh CLI
gh pr create --title "[type]: [description]" --body "$(cat <<'PREOF'
## Summary
- [bullet points from commits]

## Checklist
- [x] Artifacts committed
- [x] Learnings captured
- [x] Documentation updated
- [x] Version bumped
- [x] Tests pass

Generated with [Claude Code](https://claude.com/claude-code)
PREOF
)"
```

Present the PR URL to the user.

## Phase 8: Post-Merge Cleanup

After the PR is created, ask the user:

"PR created. Want to merge now, or merge later?"

- **Merge now** -> Run `gh pr merge <number> --squash` then proceed to cleanup below
- **Later** -> Stop here. Cleanup will happen via SessionStart hook next session.

**If merged (either now or user says "merge PR" later in the session):**

```bash
# Clean up worktree and local branch for the merged PR
cd $(git rev-parse --show-toplevel) && bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged
```

This detects `[gone]` branches (where the remote was deleted after merge), removes their worktrees, archives spec directories, and deletes local branches.

**If working from a worktree:** Navigate to the main repo root first, then run cleanup.

## Important Rules

- **Never skip the versioning triad.** If plugin files changed, all three files must be updated.
- **Ask before running /compound.** The user may have already documented learnings.
- **Do not block on missing artifacts.** Not every change needs a brainstorm or plan.
- **Confirm the PR title and body** with the user before creating it.
