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

Run `git rev-parse --abbrev-ref HEAD` to get the current branch name. Extract the feature name by stripping the `feat-`, `feature/`, `fix-`, or `fix/` prefix.

Then search for related artifacts:

- Brainstorms: `ls knowledge-base/brainstorms/*<feature>* 2>/dev/null`
- Specs: `ls knowledge-base/specs/feat-<feature>/spec.md 2>/dev/null`
- Plans: `ls knowledge-base/plans/*<feature>* 2>/dev/null`
- Uncommitted files: `git status --porcelain knowledge-base/`

**If artifacts exist but are not committed:** Stage and commit them.

**If no artifacts exist:** Note this in the checklist but do not block. Not all features go through the full brainstorm/plan cycle.

## Phase 2: Capture Learnings

Check if /compound was run for this feature:

```bash
# Look for recent learnings matching this feature
ls knowledge-base/learnings/**/*${FEATURE}* 2>/dev/null
git log --oneline --since="1 week ago" -- knowledge-base/learnings/
```

**If no recent learning exists:** Check for unarchived KB artifacts before offering a choice:

Search for unarchived artifacts matching the feature name (excluding `*/archive/*` paths):

- Brainstorms in `knowledge-base/brainstorms/`
- Plans in `knowledge-base/plans/`
- Spec directory at `knowledge-base/specs/feat-<feature>/`

If any unarchived artifacts are found, set `HAS_ARTIFACTS=true`.

**If artifacts exist (`HAS_ARTIFACTS=true`):** Do NOT offer Skip. Explain:

```text
Unarchived KB artifacts found for this feature:
${BRAINSTORMS}
${PLANS}
${SPECS}

/compound must run to consolidate and archive these artifacts before shipping.
Running /soleur:compound now...
```

Then run `/soleur:compound`. The compound flow will automatically consolidate and archive the artifacts on `feat-*` branches.

**If no artifacts exist (`HAS_ARTIFACTS=false`):** Offer the standard choice:

"No learnings documented for this feature. Run /compound to capture what you learned?"

- **Yes** -> Run `/soleur:compound`
- **Skip** -> Continue without documenting

## Phase 3: Verify Documentation

Check if new commands, skills, or agents were added in this branch:

First, find the merge base by running `git merge-base HEAD origin/main`. Then use that commit hash to compare:

```bash
git diff --name-status <merge-base>..HEAD -- \
  plugins/soleur/commands/ \
  plugins/soleur/skills/ \
  plugins/soleur/agents/
```

**If new components were added:**

1. Verify `plugins/soleur/README.md` component counts are accurate
2. Verify new entries appear in the correct tables
3. If counts are wrong, fix them
4. If `knowledge-base/overview/brand-guide.md` exists, check for stale agent/skill counts and update them

**If no new components:** Skip this step.

## Phase 3.5: Merge Main Before Version Bump

Merge the latest main branch to ensure version bumps start from the current version, reducing merge conflicts on version files:

```bash
git fetch origin main
git merge origin/main
```

**If merge conflicts arise:** Resolve them now (before version bump). This is cheaper than resolving version conflicts after bumping.

**If merge is clean:** Proceed to Phase 4.

## Phase 4: Version Bump

Check if plugin files were modified in this branch:

Run `git merge-base HEAD origin/main` to get the merge base hash, then:

```bash
git diff --name-only <merge-base>..HEAD -- plugins/soleur/
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
   - `README.md` (root) -- verify the "With ❤️ by Soleur" badge is present
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
- [x/skip] Tests exist for new source files
- [ ] Tests pass
- [ ] Push to remote
- [ ] Create PR
- [ ] PR is mergeable (no conflicts)
- [ ] CI checks pass
```

## Phase 6: Run Tests

First, verify that new source files have corresponding test files:

Find new source files added in this branch by running `git merge-base HEAD origin/main` first, then `git diff --name-only --diff-filter=A <merge-base>..HEAD`. Filter for `.ts`, `.js`, `.rb`, `.py` files (excluding test/spec/config files).

For each new source file, check if a corresponding test file exists (e.g., `foo.ts` -> `foo.test.ts` or `foo.spec.ts`). Report any source files missing test coverage.

**If test files are missing:** Ask the user whether to write tests now or continue without them. Do not silently proceed.

Then run the project's test suite:

```bash
bun test
```

**If tests fail:** Stop and fix before proceeding.

## Phase 7: Push and Create PR

### Pre-Push Gate: Verify /compound completed

Before pushing, re-verify that unarchived KB artifacts have been consolidated. This is a hard gate -- do not proceed if it fails.

Get the current branch with `git rev-parse --abbrev-ref HEAD` and extract the feature name (strip `feat-`/`feature/`/`fix-`/`fix/` prefix). Then search for unarchived KB artifacts matching the feature name in brainstorms, plans, and specs directories (excluding `archive/` paths).

If any unarchived artifacts are found, BLOCK the push and instruct the user to run `/soleur:compound` first.

**If blocked:** Stop. Run `/soleur:compound` to consolidate and archive artifacts, then return to this phase. Do NOT bypass this check.

**If clear:** Proceed to push.

Push the branch to remote: run `git rev-parse --abbrev-ref HEAD` to get the branch name, then `git push -u origin <branch-name>`.

Create the PR:

```bash
gh pr create --title "the pr title" --body "$(cat <<'EOF'
## Summary
<bullet points>

## Test plan
<checklist>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

IMPORTANT: Do not quote flag names. Write `--title` not `"--title"`.

Present the PR URL to the user.

## Phase 7.5: Verify PR Mergeability

After pushing (or after any subsequent push), verify the PR has no merge conflicts with the base branch:

```bash
git fetch origin main
gh pr view --json mergeable,mergeStateStatus | jq '{mergeable, mergeStateStatus}'
```

**If `mergeable` is `MERGEABLE`:** Continue to Phase 8.

**If `mergeable` is `CONFLICTING`:**

1. Merge the base branch locally to surface conflicts:

   ```bash
   git merge origin/main --no-commit --no-ff
   ```

2. Identify conflicted files:

   ```bash
   git diff --name-only --diff-filter=U
   ```

3. Read each conflicted file and resolve. Common conflict patterns:
   - **Version numbers** (plugin.json, README badge, bug_report.yml): Keep the higher version from the feature branch
   - **CHANGELOG entries**: Keep both entries in descending version order
   - **Component counts**: Use the feature branch count (it includes the new additions)
   - **Code conflicts**: Resolve based on intent of both changes

4. Stage resolved files and commit the merge:

   ```bash
   git add <resolved files>
   git commit -m "Merge origin/main -- resolve conflicts"
   ```

5. Push and re-verify:

   ```bash
   git push
   gh pr view --json mergeable | jq '.mergeable'
   ```

6. If still `CONFLICTING` after resolution: stop and ask the user for help.

**If `mergeable` is `UNKNOWN`:** Wait 5 seconds and re-check (GitHub may still be computing). After 3 retries, warn and continue.

### CI Status Check

After confirming mergeability, verify CI checks pass:

```bash
gh pr checks --watch --fail-fast
```

**If all checks pass:** Continue to Phase 8.

**If a check fails:**

1. Read the failure details:

   ```bash
   gh pr checks --json name,state,description | jq '.[] | select(.state != "SUCCESS")'
   ```

2. If the failure is in tests: investigate the failing test, fix locally, commit, push, and re-run this phase.
3. If the failure is in a flaky or unrelated check: warn the user and ask whether to proceed or wait for a re-run.

## Phase 8: Wait for CI, Merge, and Cleanup

After the PR is created and Phase 7.5 confirms mergeability and CI status, merge the PR. Do NOT ask "merge now or later?" -- always wait for CI to pass first.

```bash
# If CI hasn't been checked yet (e.g., Phase 7.5 was skipped), run it now:
gh pr checks --watch --fail-fast
```

**Once CI passes:** Merge immediately.

```bash
gh pr merge <number> --squash
```

**CRITICAL: Do NOT use `--delete-branch` on merge.** The guardrails hook blocks `--delete-branch` whenever ANY worktree exists in the repo -- not just the one for the branch being merged -- so the restriction applies unconditionally during parallel development. Merge with `--squash` only, then `cleanup-merged` handles branch deletion after removing the worktree.

**If merged (either now or user says "merge PR" later in the session):**

1. **Release creation is automatic.** When a merge to main includes a plugin.json version change, the `auto-release.yml` GitHub Actions workflow creates a GitHub Release and posts to Discord. No manual step needed.

   If the workflow did not fire (e.g., path filter didn't match), run `/release-announce` manually as a fallback.

2. Clean up worktree and local branch:

   Navigate to the repository root directory, then run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.

This detects `[gone]` branches (where the remote was deleted after merge), removes their worktrees, archives spec directories, and deletes local branches.

**If working from a worktree:** Navigate to the main repo root first, then run cleanup.

**If the session ends before cleanup runs:** The next session will handle it automatically via the Session-Start Hygiene check in AGENTS.md. The `cleanup-merged` script is idempotent and safe to run at any time.

## Important Rules

- **Never skip the versioning triad.** If plugin files changed, all three files must be updated.
- **Ask before running /compound.** The user may have already documented learnings.
- **Do not block on missing artifacts.** Not every change needs a brainstorm or plan.
- **Confirm the PR title and body** with the user before creating it.
