---
name: ship
description: "Prepare a feature for production deployment. Enforces the complete feature lifecycle checklist: artifacts committed, documentation updated, learnings captured, tests passing, PR created with semver label, CI verified, and post-merge validation."
triggers:
- ship
- ship it
- create PR
- merge PR
- deploy
- push and merge
---

# Ship — Deploy a Feature to Production

Enforce the full feature lifecycle before creating a PR, preventing missed steps like forgotten compound runs and uncommitted artifacts. Version bumping happens automatically in CI at merge time via semver labels.

## Phase 0: Context Detection

Detect the current environment:

```bash
git rev-parse --abbrev-ref HEAD
git worktree list
pwd
```

**Branch safety check (defense-in-depth):** If the branch is `main` or `master`, abort immediately with: "Error: ship cannot run on main/master. Checkout a feature branch first."

**Load project conventions:**

```bash
if [[ -f "AGENTS.md" ]]; then
  cat AGENTS.md
fi
```

Identify the base branch for comparison:

```bash
git remote show origin | grep 'HEAD branch'
```

## Phase 1: Validate Artifact Trail

Check that feature artifacts exist and are committed. Extract the feature name from the current branch (strip `feat-`, `feature/`, `fix-`, `fix/` prefix).

Search for related artifacts:

- Brainstorms: `knowledge-base/project/brainstorms/*FEATURE*`
- Specs: `knowledge-base/project/specs/feat-FEATURE/spec.md`
- Plans: `knowledge-base/project/plans/*FEATURE*`
- Uncommitted files: `git status --porcelain knowledge-base/`

**If artifacts exist but not committed:** Stage and commit them.
**If no artifacts exist:** Note in checklist but do not block.

## Phase 1.5: Review Evidence Gate

Check for evidence that a review was performed on the current branch.

**Step 1:** Search for review artifacts: `grep -rl "code-review" todos/ 2>/dev/null | head -1 || true`

**Step 2:** Check commit history: `git log origin/main..HEAD --oneline | grep "refactor: add code review findings" || true`

**Step 3:** Check for GitHub issues with `code-review` label:

```bash
# Step 3a: get current branch
git branch --show-current
# Step 3b: get PR number for branch
gh pr list --head <branch-name> --state open --json number --jq '.[0].number // empty'
# Step 3c: search for review issues referencing the PR
gh issue list --label code-review --search "PR #<number>" --limit 1 --json number --jq '.[0].number // empty'
```

**If any signal found:** Continue to Phase 2.

**If no signal found:** Ask the user: "No evidence that a review ran on this branch. How would you like to proceed?"

- **Run review now** — use the review skill, then continue
- **Skip review** — continue (user accepts the risk)
- **Abort** — stop shipping

## Phase 2: Capture Learnings

Check if compound was run for this feature:

```bash
git log --oneline --since="1 week ago" -- knowledge-base/project/learnings/
```

Also search `knowledge-base/project/learnings/**/*FEATURE*`.

**If no recent learning exists:**

Search for unarchived artifacts matching the feature name (excluding `archive/` paths).

**If unarchived artifacts exist:** Do NOT offer Skip. Explain that compound must run to consolidate and archive them. Use the compound skill.

**If no unarchived artifacts exist:** Ask: "No learnings documented for this feature. Run compound to capture what you learned?" (Yes / Skip)

## Phase 3: Verify Documentation

Check if new commands, skills, or agents were added in this branch.

**Step 1:** Get merge base: `git merge-base HEAD origin/main`

**Step 2:** Check for new components: `git diff --name-status <merge-base>..HEAD -- plugins/soleur/commands/ plugins/soleur/skills/ plugins/soleur/agents/`

**If new components added:**

1. Run `bash scripts/sync-readme-counts.sh` to update counts
2. Verify new entries in `plugins/soleur/README.md`
3. Check `knowledge-base/marketing/brand-guide.md` for stale counts

**If no new components:** Run `bash scripts/sync-readme-counts.sh --check` to verify sync.

## Phase 4: Run Tests

Verify new source files have corresponding test files:

```bash
git diff --name-only --diff-filter=A <merge-base>..HEAD
```

Filter for `.ts`, `.js`, `.rb`, `.py` files (excluding test/spec/config). Report any missing test coverage.

**If test files missing:** Ask whether to write tests now or continue without them.

Run the full test suite:

```bash
bash scripts/test-all.sh
```

**If tests fail:**

1. Check if failures are pre-existing (same on main)
2. If caused by this branch: stop and fix
3. If pre-existing: create a tracking issue (`gh issue create --title "fix: N pre-existing test failures" --milestone "Post-MVP / Later" --label bug`), then continue

## Phase 5: Final Checklist

Use `task_tracker` to create a ship checklist:

```text
Ship Checklist for [branch name]:
- [x/skip] Artifacts committed (brainstorm/spec/plan)
- [x/skip] Learnings captured (compound)
- [x/skip] README counts synced
- [x/skip] Tests pass
- [ ] Code review completed (Phase 5.5 gate)
- [ ] Push to remote
- [ ] Create PR with semver label
- [ ] PR is mergeable (no conflicts)
- [ ] CI checks pass
```

## Phase 5.5: Pre-Ship Review Gates

### Code Review Completion Gate (mandatory)

Defense-in-depth re-check that review ran. Same three signals as Phase 1.5.

**If no evidence found:** Display warning and invoke the review skill. After review, if P1/P2 findings exist, resolve them before continuing.

### CMO Content-Opportunity Gate (conditional)

**Trigger:** PR touches `knowledge-base/product/research/`, `knowledge-base/marketing/`, has `semver:minor`/`semver:major` label, or title matches `^feat(\(.*\))?:`.

**If triggered:** Use `delegate` to spawn the CMO agent for content assessment. Present recommendations. Options: Create content now, Schedule (create GitHub issue), Skip. If content is scheduled, update `knowledge-base/marketing/content-strategy.md`.

### CMO Website Framing Review Gate (conditional)

**Trigger:** PR modifies `knowledge-base/marketing/brand-guide.md` positioning sections.

**If triggered:** Spawn CMO agent for website framing audit. Present findings.

### COO Expense-Tracking Gate (conditional)

**Trigger:** PR creates recurring expenses (new SaaS signups, API key provisioning, infrastructure scaling).

**If triggered:** Spawn COO agent for expense tracking. Create tracking entries.

## Phase 6: Create PR

1. **Stage and commit** any remaining changes:

   ```bash
   git add -A
   git commit -m "chore: ship preparation for feat-<name>"
   ```

2. **Push to remote:**

   ```bash
   git push -u origin <branch-name>
   ```

3. **Determine semver label:**
   - `semver:patch` — bug fixes, documentation, small improvements
   - `semver:minor` — new features, new skills, new agents
   - `semver:major` — breaking changes

   Ask the user which label applies (or recommend based on changes).

4. **Create PR:**

   ```bash
   gh pr create --title "<type>: <description>" --body "..." --label "<semver-label>" --milestone "<milestone>"
   ```

   Include in the body: summary of changes, linked issues (`Closes #N`), test results, review evidence.

5. **Verify mergeability:**

   ```bash
   gh pr view <number> --json mergeable --jq '.mergeable'
   ```

   If `CONFLICTING`: merge main, resolve conflicts, push again.
   If `UNKNOWN`: wait 5 seconds and re-check (up to 3 retries).

### CI Status Check

Queue auto-merge:

```bash
gh pr merge <number> --squash --auto
```

Do NOT use `gh pr checks --watch` — it exits immediately with "no checks reported" when CI hasn't registered yet.

## Phase 7: Poll for Merge and Cleanup

Poll until the PR is merged:

```bash
gh pr view <number> --json state --jq .state
```

Poll every 10 seconds until state is `MERGED`.

**If state becomes `CLOSED`:** Auto-merge was cancelled due to CI failure.

1. Read failure details: `gh pr checks --json name,state,description`
2. If test failure: fix locally, commit, push, re-queue auto-merge
3. If flaky/unrelated: warn and ask whether to proceed or wait

**CRITICAL: Do NOT use `--delete-branch` on merge.** Merge with `--squash` only — `cleanup-merged` handles branch deletion.

**If merged:**

1. **Version bump and release are automatic.** The CI workflow reads the PR's `semver:*` label, computes the next version, creates a GitHub Release with a `vX.Y.Z` tag. No committed files are modified.

2. **Verify release/deploy workflows.** Wait 15 seconds, then:

   ```bash
   gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion
   ```

   Poll each incomplete run every 30 seconds. If any fails, fetch logs: `gh run view <id> --log-failed | tail -n 50`. Do NOT silently proceed past failures.

3. **Post-merge workflow validation.** If the PR added or modified `.github/workflows/*.yml`:

   ```bash
   git diff --name-only --diff-filter=AM <merge-base>..HEAD -- .github/workflows/
   ```

   Trigger each affected workflow: `gh workflow run <filename>`. Poll until complete.

4. **Follow-through items.** Scan the PR body for unchecked `⏳` items. For each, create a tracking issue with `follow-through` label.

5. **Supabase migration verification.** If the PR includes `supabase/migrations/` files, verify each migration is applied to production via Supabase REST API.

6. **Terraform provisioner gate.** If the PR modified `.tf` files with `remote-exec` provisioners, warn about manual `terraform apply` requirement.

7. **Clean up worktree:**

   Navigate to the repository root, then run:

   ```bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged
   ```

## Important Rules

- **Always set a semver label.** Every PR touching `plugins/soleur/` must have `semver:patch`, `semver:minor`, or `semver:major`.
- **Never edit version fields.** `plugin.json` and `marketplace.json` versions are frozen sentinels. Version is derived from git tags.
- **Ask before running compound.** The user may have already documented learnings.
- **Do not block on missing artifacts.** Not all features go through the full brainstorm/plan cycle.
- **Confirm the PR title and body** with the user before creating it.
