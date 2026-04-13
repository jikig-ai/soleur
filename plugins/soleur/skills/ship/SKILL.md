---
name: ship
description: "This skill should be used when preparing a feature for production deployment. It enforces the complete feature lifecycle checklist, ensuring all artifacts are committed, documentation is updated, and learnings are captured before creating a PR. Version bumping happens automatically in CI."
---

# ship Skill

**Purpose:** Enforce the full feature lifecycle before creating a PR, preventing missed steps like forgotten /compound runs and uncommitted artifacts. Version bumping is handled by CI at merge time via semver labels.

**CRITICAL: No command substitution.** Never use `$()` in Bash commands. When a step says "get value X, then use it in command Y", run them as **two separate Bash tool calls** -- first get the value, then use it literally in the next call. This avoids Claude Code's security prompt for command substitution.

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing remaining args.

When `HEADLESS_MODE=true`:

- Phase 2: auto-invoke `skill: soleur:compound --headless` (forward flag, no user prompt)
- Phase 4: if test files are missing, continue without writing (CI gate catches this)
- Phase 6: auto-accept generated PR title/body without user confirmation
- Phase 7: if CI is flaky or unrelated check fails, abort pipeline (do not ask whether to proceed)
- All failure conditions: abort with clear error message, do not prompt

## Phase 0: Context Detection

Detect the current environment:

```bash
# Determine current branch and worktree
git rev-parse --abbrev-ref HEAD
git worktree list
pwd
```

**Branch safety check (defense-in-depth):** If the branch from the command above is `main` or `master`, abort immediately with: "Error: ship cannot run on main/master. Checkout a feature branch first." This is defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI).

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

Get the current branch name:

```bash
git rev-parse --abbrev-ref HEAD
```

Extract the feature name from the result by stripping the `feat-`, `feature/`, `fix-`, or `fix/` prefix. Then search for related artifacts using the Glob and Bash tools:

- Brainstorms: glob `knowledge-base/project/brainstorms/*FEATURE*`
- Specs: check `knowledge-base/project/specs/feat-FEATURE/spec.md`
- Plans: glob `knowledge-base/project/plans/*FEATURE*`
- Uncommitted files: `git status --porcelain knowledge-base/`

**If artifacts exist but are not committed:** Stage and commit them.

**If no artifacts exist:** Note this in the checklist but do not block. Not all features go through the full brainstorm/plan cycle.

## Phase 1.5: Review Evidence Gate

Check for evidence that `/review` ran on the current branch. This is defense-in-depth --
`/one-shot` already enforces review ordering, but direct `/ship` invocations bypass it.

**Step 1: Check for review artifacts (legacy).**

Search for todo files tagged as code-review findings:

```bash
grep -rl "code-review" todos/ 2>/dev/null | head -1 || true
```

**Step 2: Check commit history for review evidence (legacy).**

If Step 1 found nothing, check for the review commit pattern:

```bash
git log origin/main..HEAD --oneline | grep "refactor: add code review findings" || true
```

**Step 3: Check for GitHub issues with `code-review` label (current).**

If Steps 1 and 2 found nothing, check for review issues linked to this branch's PR. This requires two separate Bash calls (no command substitution):

Step 3a — get the current branch name:

```bash
git branch --show-current
```

Step 3b — get the PR number for that branch (use the branch name from Step 3a literally):

```bash
gh pr list --head <branch-name> --state open --json number --jq '.[0].number // empty'
```

Step 3c — if Step 3b returned a PR number, search for code-review issues referencing it:

```bash
gh issue list --label code-review --search "PR #<number>" --limit 1 --json number --jq '.[0].number // empty'
```

If `gh` fails or is unavailable, treat as no output (fail open on Signal 3).

**Note:** Three signals are checked, any one suffices:

- Signal 1 (`todos/` grep): coupled to legacy review workflow (pre-#1329)
- Signal 2 (commit message grep): coupled to legacy review SKILL.md Step 5 commit message (pre-#1329)
- Signal 3 (`gh issue list`): coupled to `review-todo-structure.md` issue body template (`**Source:** PR #<number>`)

**If any step produced output:** Review evidence found. Continue to Phase 2.

**If no step produced output:**

**Headless mode:** Abort with: "Error: no review evidence found on this branch. Run `/review` before `/ship`, or use `/one-shot` for the full pipeline."

**Interactive mode:** Present options via AskUserQuestion:

"No evidence that `/review` ran on this branch. How would you like to proceed?"

- **Run /review now** -> invoke `skill: soleur:review`, then continue to Phase 2
- **Skip review** -> continue to Phase 2 (user accepts the risk; this also covers zero-finding reviews where review ran cleanly)
- **Abort** -> stop shipping

**Why:** Identified during #1129/#1131/#1134 implementation session when the `/one-shot` pipeline ran correctly but the gap was noted as a systemic risk for direct `/ship` invocations. See #1170.

## Phase 2: Capture Learnings

Check if /compound was run for this feature. Use the feature name extracted in Phase 1:

```bash
git log --oneline --since="1 week ago" -- knowledge-base/project/learnings/
```

Also use the Glob tool to search `knowledge-base/project/learnings/**/*FEATURE*` (replacing FEATURE with the actual name).

**If no recent learning exists:** Check for unarchived KB artifacts before offering a choice.

Search for unarchived artifacts matching the feature name (excluding `archive/` paths) using the Glob tool:

- Brainstorms: `knowledge-base/project/brainstorms/*FEATURE*`
- Plans: `knowledge-base/project/plans/*FEATURE*`
- Spec directory: `knowledge-base/project/specs/feat-FEATURE/`

**If unarchived artifacts exist:** Do NOT offer Skip. List the found artifacts and explain that compound must run to consolidate and archive them before shipping. Then use `skill: soleur:compound` (or `skill: soleur:compound --headless` if `HEADLESS_MODE=true`). The compound flow will automatically consolidate and archive the artifacts on `feat-*` branches.

**If no unarchived artifacts exist:**

**Headless mode:** Auto-invoke `skill: soleur:compound --headless` without prompting.

**Interactive mode:** Offer the standard choice:

"No learnings documented for this feature. Run /compound to capture what you learned?"

- **Yes** -> Use `skill: soleur:compound`
- **Skip** -> Continue without documenting

After compound completes (or is skipped), continue to Phase 3 immediately. Do NOT stop or wait for user input — the ship pipeline is not complete until Phase 7 finishes.

## Phase 3: Verify Documentation

Check if new commands, skills, or agents were added in this branch.

**Step 1** (separate Bash call): Get the merge base hash.

```bash
git merge-base HEAD origin/main
```

**Step 2** (separate Bash call): Use the hash from Step 1 literally in this command.

```bash
git diff --name-status HASH..HEAD -- plugins/soleur/commands/ plugins/soleur/skills/ plugins/soleur/agents/
```

Replace `HASH` with the actual commit hash from Step 1. Do NOT use `$()` to combine these.

**If new components were added:**

1. Run `bash scripts/sync-readme-counts.sh` to auto-update counts in both `README.md` and `plugins/soleur/README.md`
2. Verify new entries appear in the correct tables in `plugins/soleur/README.md`
3. If `knowledge-base/marketing/brand-guide.md` exists, check for stale agent/skill counts and update them

**If no new components:** Run `bash scripts/sync-readme-counts.sh --check` to verify counts are still in sync. Fix if drifted.

## Phase 4: Run Tests

First, verify that new source files have corresponding test files:

Find new source files added in this branch. First, get the merge base hash (reuse from Phase 3 if already obtained):

```bash
git merge-base HEAD origin/main
```

Then, in a separate Bash call, use the hash literally:

```bash
git diff --name-only --diff-filter=A HASH..HEAD
```

Replace `HASH` with the actual commit hash. Filter results for `.ts`, `.js`, `.rb`, `.py` files (excluding test/spec/config files).

For each new source file, check if a corresponding test file exists (e.g., `foo.ts` -> `foo.test.ts` or `foo.spec.ts`). Report any source files missing test coverage.

**If test files are missing:**

**Headless mode:** Continue without writing tests (CI gate catches missing coverage).

**Interactive mode:** Ask the user whether to write tests now or continue without them. Do not silently proceed.

Then run the project's full test suite (matches CI):

```bash
bash scripts/test-all.sh
```

**If tests fail:**

1. **Check if failures are pre-existing:** Run the same test command on an unmodified checkout (or compare failure count/names with main). If the exact same tests fail on main, the failures are pre-existing.
2. **If failures are caused by this branch:** Stop and fix before proceeding.
3. **If failures are pre-existing:** Create a GitHub issue to track them (`gh issue create --title "fix: N pre-existing test failures in <app>" --milestone "Post-MVP / Later" --label bug`), then continue. Do not silently bypass pre-existing failures — a red test suite normalizes breakage and masks future regressions. **Why:** In #1411, 71 pre-existing web-platform test failures were silently bypassed during ship. The tracking issue (#1413) was only created after the founder noticed post-session.

## Phase 5: Final Checklist

Create a TodoWrite checklist summarizing the state:

```text
Ship Checklist for [branch name]:

- [x/skip] Artifacts committed (brainstorm/spec/plan)
- [x/skip] Learnings captured (/compound)
- [x/skip] README counts synced (`bash scripts/sync-readme-counts.sh`)
- [x/skip] Tests pass
- [ ] Preflight passed (Phase 5.4 gate)
- [ ] Code review completed (Phase 5.5 gate)
- [ ] Push to remote
- [ ] Create PR with semver label
- [ ] PR is mergeable (no conflicts)
- [ ] CI checks pass
```

## Phase 5.4: Pre-Flight Validation

Run technical readiness checks before creating the PR. This catches unapplied migrations, missing security headers, and bare-repo execution context.

Invoke the preflight skill via the **Skill tool**:

- If `HEADLESS_MODE=true`: `skill: soleur:preflight`, args: `--headless`
- Otherwise: `skill: soleur:preflight`

**If preflight reports any FAIL:** Abort the ship pipeline. Display the preflight results table and stop. Do not proceed to Phase 5.5 or Phase 6.

**If preflight reports all PASS or SKIP:** Continue to Phase 5.5 immediately. Do NOT stop or wait for user input after preflight passes — the ship pipeline is not complete until Phase 7 finishes. Nested skill invocations (preflight, compound) return control here; losing track of the pipeline state after a nested skill is a known failure mode.

## Phase 5.5: Pre-Ship Review Gates

### Code Review Completion Gate (mandatory)

Defense-in-depth check that review ran before shipping. Phase 1.5 catches this earlier, but if context compaction erased Phase 1.5's check or the skill was invoked mid-flow, this gate is the second net.

**Detection:** Check for review evidence using the same three signals described in Phase 1.5 (Signal 1: `todos/` grep, Signal 2: commit message grep, Signal 3: GitHub issues with `code-review` label). Run the same commands in the same order. See Phase 1.5 for full details and coupling notes.

**If review evidence is found:** Pass silently.

**If no review evidence is found:**

**Headless mode:** Abort with: "Error: no review evidence found on this branch. Run `/review` before `/ship`, or use `/one-shot` for the full pipeline."

**Interactive mode:** Display warning: "No code review was run before ship." Then invoke `skill: soleur:review`. After review completes, if findings include critical or high severity issues, resolve them before continuing to Phase 6.

### Pre-Ship Domain Review (conditional)

Domain leaders are consulted at brainstorm time but not at ship time. The actual deliverables may have implications the brainstorm couldn't predict. This phase runs three conditional gates in parallel.

### CMO Content-Opportunity Gate

**Trigger:** PR matches ANY of: (a) touches files in `knowledge-base/product/research/`, `knowledge-base/marketing/`, or adds new workflow patterns (new AGENTS.md rules, new skill phases); (b) has a `semver:minor` or `semver:major` label; (c) title matches `^feat(\(.*\))?:` pattern.

**Detection:** Run `git diff --name-only origin/main...HEAD` and check file paths against trigger (a). Run `gh pr view --json labels,title` and check against triggers (b) and (c). If any trigger matches, proceed to "If triggered."

**If triggered:**

1. Spawn the CMO agent with a pre-ship content assessment prompt: "Assess content and distribution opportunities from this PR. What was produced, what data points are content-worthy, which channels should be used, and what's the recommended timing (ship with PR or schedule for later)?"
2. Present the CMO's recommendations to the user.
3. **Interactive mode:** Ask "Create content now, schedule for later, or skip?" Options: Create now (invoke content-writer/social-distribute), Schedule (create a GitHub issue with content brief), Skip.
4. **Headless mode:** Auto-create a GitHub issue with the CMO's content brief for later action. Do not block the ship.
5. **Update content strategy (mandatory if content is scheduled or created).** When a content piece is identified (option 1 or 2 above), update `knowledge-base/marketing/content-strategy.md`: add the piece to the content pipeline table under the appropriate pillar AND insert it into the rolling quarterly calendar at the correct week. A GitHub issue without a content strategy entry is an orphan — it will be forgotten. **Why:** In #1173, a methodology blog post was created as issue #1176 but never added to the content strategy calendar, requiring a manual fix.

**Why:** In #1173, a research sprint produced a novel methodology with compelling data, but no content was planned because the CMO was only consulted when the scope was "should we explore this?" — not when the actual content existed.

### CMO Website Framing Review Gate

**Trigger:** PR modifies `knowledge-base/marketing/brand-guide.md` — specifically the Value Proposition Framings, Positioning, Tagline, or Voice sections. Also triggers if the PR modifies value prop findings or competitive positioning documents that inform website copy.

**Detection:** Run `git diff --name-only origin/main...HEAD` and check for `brand-guide.md`. If present, check `git diff origin/main...HEAD -- knowledge-base/marketing/brand-guide.md` for changes to positioning-related sections.

**If triggered:**

1. Spawn the CMO agent (or conversion-optimizer for landing page specifics) with a website framing audit prompt. **Read the site source templates directly from the repo** (e.g., `apps/web-platform/`, `docs/`, or the Eleventy source directory) — do NOT use Playwright to fetch the rendered site when the source files are local. Prompt: "The brand guide's value proposition framings have been updated. Audit the website source templates for alignment: does the hero headline, subheadline, feature descriptions, and pricing page messaging match the updated framing recommendations? Identify specific copy that needs updating and propose replacements with file paths and line numbers."
2. Present the audit findings to the user.
3. **Interactive mode:** Ask "Apply website copy updates now, create issue for later, or skip?" Options: Apply now (edit site templates), Schedule (create GitHub issue with copy changes), Skip.
4. **Headless mode:** Auto-create a GitHub issue with the copy audit findings for later action.

**Why:** In #1173, the brand guide was updated with a new primary framing ("Stop hiring, start delegating"), a memory-first A/B variant, and trust scaffolding recommendations — but the website still used the old framing. Brand guide changes that don't cascade to the website create a disconnect between strategy and execution.

### COO Expense-Tracking Gate

**Trigger:** The PR or session involved signing up for new services, provisioning new tools, subscribing to APIs, or using paid external resources during implementation. Also triggers if the diff adds new entries to infrastructure configs, Terraform files, or references new SaaS tools not already in `knowledge-base/operations/expenses.md`.

**Detection:** Scan the session for: account creation actions (Playwright flows, CLI signups), new API key generation, new tool installations, new Terraform resources, or references to services not already tracked in the expense ledger. Also check `git diff origin/main...HEAD` for new domain names, new provider references in `.tf` files, or new environment variables suggesting new service integrations.

**If triggered:**

1. Spawn the COO agent with an expense-tracking prompt: "Review this PR for new tools, services, or subscriptions introduced during implementation. Check each against `knowledge-base/operations/expenses.md`. For any not already tracked, provide the service name, estimated cost, billing cycle, and category for the expense ledger."
2. Apply the COO's recommended updates to `expenses.md`.
3. **Interactive mode:** Present additions for confirmation before editing.
4. **Headless mode:** Auto-apply and commit.

**If not triggered:** Skip silently.

**Why:** New tools and subscriptions adopted during implementation often go unrecorded in the expense ledger because they feel incidental to the engineering work. The COO gate ensures every new cost is tracked at ship time, not discovered months later during a financial review.

### Retroactive Gate Application (conditional)

**Trigger:** The PR fixes a gate's detection logic (trigger conditions, assessment questions, or routing rules) AND the fix was motivated by a specific case that the gate missed.

**Detection:** Check if the PR modifies any of: Phase 5.5 gate trigger/detection sections in this file, assessment questions in `brainstorm-domain-config.md`, or domain routing rules in AGENTS.md. If yes, check the linked issue or brainstorm document for the original missed case (e.g., a PR number, feature name, or issue that exposed the gap).

**If triggered:**

1. Identify the original missed case from the issue/brainstorm (e.g., "PR #1256 PWA was not assessed for content").
2. Run the fixed gate retroactively against the missed case: spawn the relevant domain leader with the original PR/feature context and the same assessment prompt the gate would have used.
3. Produce the artifacts that would have been created if the gate had worked (content briefs, expense entries, website audits, etc.).
4. Commit the artifacts before proceeding to Phase 6.

**If not triggered:** Skip silently.

**Why:** In #1265, the CMO content gate was fixed to catch product features but the PWA feature itself was never assessed — the fix shipped without remediating the original gap. "Gate fixed" is not done — "gate fixed AND missed case remediated" is done.

## Phase 6: Push and Create PR

### Detect Associated Issue

Before creating or editing the PR, detect if the work resolves a GitHub issue. Check these sources (in order, stop at first match):

1. **Branch name:** Extract issue number from patterns like `fix/123-description`, `feat/issue-123`, `fix-123`, or any segment matching `\b(\d+)\b` after a `fix` or `issue` prefix.
2. **Commit messages:** Search recent branch commits for `#N` references:

   ```bash
   git log origin/main..HEAD --oneline
   ```

   Extract any `#N` references from the output.

3. **User context:** If the user mentioned an issue number earlier in the conversation, use it.

If an issue number is found, store it as `ISSUE_NUMBER` for use in the PR body below. If multiple are found, use all of them. If none are found, omit the `Closes` line from the PR body.

**Important:** Use `Closes #N` syntax (not `Ref #N`, not `(#N)` in the title). GitHub only auto-closes issues when the PR body contains a keyword (`Closes`, `Fixes`, or `Resolves`) followed by the issue reference.

Push the branch to remote. Get the branch name first:

```bash
git rev-parse --abbrev-ref HEAD
```

Then push in a separate Bash call, using the branch name literally:

```bash
git push -u origin BRANCH_NAME
```

Replace `BRANCH_NAME` with the actual branch name from the previous call.

**Check for existing PR on this branch:**

Check for an existing open PR using the branch name from above:

```bash
gh pr list --head BRANCH_NAME --state open --json number,isDraft --jq '.[0]'
```

Replace `BRANCH_NAME` with the actual branch name.

**If an open PR exists:**

1. The PR was likely created as a draft earlier in the workflow.
2. **Headless mode:** Auto-accept the generated PR title/body from diff analysis. **Interactive mode:** Confirm the PR title and body with the user before editing.
3. Update the PR. Pass the body as a multi-line string (no `$()` needed):

   ```bash
   gh pr edit PR_NUMBER --title "the pr title" --body "## Summary
   - bullet points

   Closes #ISSUE_NUMBER

   ## Changelog
   - changelog entries describing what changed

   ## Test plan
   - checklist

   Generated with [Claude Code](https://claude.com/claude-code)"
   ```

   If `ISSUE_NUMBER` was detected, include the `Closes #N` line. If multiple issues, list each (`Closes #N, Closes #M`). If no issue was detected, omit the `Closes` line entirely.

   Do not quote flag names -- write `--title` not `"--title"`.

4. If the PR is a draft, mark it ready:

   ```bash
   gh pr ready PR_NUMBER
   ```

5. Present the PR URL to the user.

**If no open PR exists:**

Fall through to creating a new PR. This handles cases where the user entered the pipeline through `/plan` or `/work` directly (skipping brainstorm/one-shot).

```bash
gh pr create --title "the pr title" --body "## Summary
- bullet points

Closes #ISSUE_NUMBER

## Changelog
- changelog entries describing what changed

## Test plan
- checklist

Generated with [Claude Code](https://claude.com/claude-code)"
```

If `ISSUE_NUMBER` was detected, include the `Closes #N` line. If no issue was detected, omit it.

Do not quote flag names -- write `--title` not `"--title"`.

Present the PR URL to the user.

### Semver Label and Changelog

After the PR is created or updated, determine the appropriate semver label and apply it.

**Step 1:** Analyze the diff to determine bump type. Get the merge base hash (reuse from Phase 3 if already obtained):

```bash
git merge-base HEAD origin/main
```

Then, in a separate Bash call, check for new components:

```bash
git diff --name-status HASH..HEAD -- plugins/soleur/commands/ plugins/soleur/skills/ plugins/soleur/agents/
```

Replace `HASH` with the actual commit hash.

**Step 1b:** Check for app changes (in a separate Bash call):

```bash
git diff --name-only HASH..HEAD -- apps/web-platform/ | head -1
```

If `apps/web-platform/` has changes, apply `app:web-platform` label:

```bash
gh pr edit PR_NUMBER --add-label app:web-platform
```

Only apply the label if the path has changes.

**Step 2:** Determine the bump type:

- **MAJOR**: Breaking changes (removed commands, renamed agents, restructured plugin interface)
- **MINOR**: New agents, skills, or commands added (any `A` status files in the diff above), OR new files added under `apps/*/`
- **PATCH**: Everything else (bug fixes, doc updates, improvements to existing components)

When ONLY app files changed (no plugin files), still apply `semver:*` based on app change significance — new files added means `semver:minor`, changes only means `semver:patch`.

**Step 3:** Apply the semver label to the PR:

```bash
gh pr edit PR_NUMBER --add-label semver:patch
```

Replace `semver:patch` with `semver:minor` or `semver:major` as appropriate. Replace `PR_NUMBER` with the actual PR number.

**Step 4:** Generate a `## Changelog` section from the changes and update the PR body to include it. The changelog should describe what changed in user-facing terms (not file paths). If the PR body already has a `## Changelog` section, update it. Include app changes alongside plugin changes — group by component if multiple components changed (e.g., "### Plugin", "### Web Platform").

**Step 5:** Validate consistency -- if new agents, skills, or commands were detected in Step 1 but the label is `semver:patch`, warn the user that the label may be incorrect. New components typically warrant `semver:minor`.

## Phase 6.5: Verify PR Mergeability

After pushing (or after any subsequent push), verify the PR has no merge conflicts with the base branch:

```bash
git fetch origin main
gh pr view --json mergeable,mergeStateStatus | jq '{mergeable, mergeStateStatus}'
```

**If `mergeable` is `MERGEABLE`:** Continue to Phase 7.

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

After confirming mergeability, queue auto-merge and let GitHub handle waiting for CI:

```bash
gh pr merge <number> --squash --auto
```

Do NOT use `gh pr checks --watch` -- it exits immediately with "no checks reported" when CI hasn't registered yet, causing premature merge attempts.

**If auto-merge fails to queue:** Check `gh api repos/{owner}/{repo} --jq '.allow_auto_merge'` -- it must be `true`.

## Phase 7: Poll for Merge and Cleanup

After auto-merge is queued, poll until the PR is merged. Do NOT ask "merge now or later?" -- auto-merge handles it. Do NOT use foreground `sleep` — Claude Code blocks `sleep` >= 2s in foreground Bash calls.

Use the **Monitor tool** with this shell loop (max 60 iterations = 10 minutes):

```bash
i=0
while true; do
  state=$(gh pr view <number> --json state --jq .state)
  echo "$(date +%H:%M:%S) state=$state (iteration $((i+1))/60)"
  [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ] && break
  i=$((i+1))
  if [ "$i" -ge 60 ]; then
    echo "Merge poll timed out after 10 minutes. PR state: $state"
    break
  fi
  sleep 10
done
```

Each `echo` line arrives as a Monitor notification. React to the final state. If the loop exits via timeout, report the timeout to the user and investigate why the PR has not merged.

**If state becomes `CLOSED` (not `MERGED`):** Auto-merge was cancelled due to a CI failure.

1. Read the failure details:

   ```bash
   gh pr checks --json name,state,description | jq '.[] | select(.state != "SUCCESS")'
   ```

2. If the failure is in tests: investigate the failing test, fix locally, commit, push, re-queue auto-merge.
3. If the failure is in a flaky or unrelated check: **Headless mode:** abort the pipeline with a clear error message (do not auto-proceed past failed checks). **Interactive mode:** warn the user and ask whether to proceed or wait for a re-run.

**CRITICAL: Do NOT use `--delete-branch` on merge.** The guardrails hook blocks `--delete-branch` whenever ANY worktree exists in the repo -- not just the one for the branch being merged -- so the restriction applies unconditionally during parallel development. Merge with `--squash` only, then `cleanup-merged` handles branch deletion after removing the worktree.

**If merged (either now or user says "merge PR" later in the session):**

1. **Version bump and release are automatic.** The `version-bump-and-release.yml` GitHub Actions workflow reads the PR's `semver:*` label, computes the next version from the latest release tag, creates a GitHub Release with a `vX.Y.Z` tag, and posts to Discord. No committed files are modified — version is derived from git tags.

   If the workflow did not fire (e.g., no semver label was set), run `/release-announce` manually as a fallback.

2. **Verify all release/deploy workflows triggered by the merge.** The push to main triggers release workflows based on path filters (e.g., `web-platform-release.yml` when `apps/web-platform/**` changed). These can fail for reasons unrelated to PR CI (Docker build failures, lockfile drift, deploy health mismatches). A failing release workflow means the old version keeps running in production — this is a silent outage.

   **Step 1:** Get the merge commit SHA. Use the PR number from Phase 6:

   ```bash
   gh pr view <number> --json mergeCommit --jq .mergeCommit.oid
   ```

   **Step 2:** Wait 15 seconds for workflows to trigger, then count pending runs on the merge commit:

   ```bash
   gh run list --branch main --commit <merge-sha> --json databaseId,workflowName,status,conclusion --jq '[.[] | select(.status != "completed")] | length'
   ```

   This outputs a single integer (the count of non-completed runs). If the output is empty or non-numeric, re-run the command once. If still invalid, report an error and abort.

   **Empty-result fallback:** If the pending count is `0`, verify that runs actually exist:

   ```bash
   gh run list --branch main --commit <merge-sha> --json databaseId --jq 'length'
   ```

   - If total runs > 0 and pending = 0: all runs completed. Proceed to Step 4.
   - If total runs = 0: workflows have not registered yet. Wait 15 seconds and re-query. Retry up to 3 times (45 seconds total). If still 0 after 3 retries, treat as "no workflows triggered" and skip verification (the PR only touched files outside all path filters).

   **Step 3:** For each run that is not yet `completed`, use the **Monitor tool** with a shell loop:

   ```bash
   while true; do
     result=$(gh run view <id> --json status,conclusion --jq '"\(.status) \(.conclusion)"')
     echo "$(date +%H:%M:%S) run=<id> $result"
     echo "$result" | grep -q "^completed" && break
     sleep 30
   done
   ```

   Poll until all runs report `completed`. Maximum 40 iterations (20 minutes). If the maximum is reached, report: "Release verification timed out after 20 minutes. N runs still pending: [list workflow names and IDs]." Do NOT silently continue -- investigate the stalled workflows.

   **Step 4:** Check conclusions:
   - All `success`: Report "Release verification: N/N workflows passed" and continue.
   - Any `failure`: Report which workflow failed, fetch logs with `gh run view <id> --log-failed | tail -n 50`, and investigate. Do NOT silently proceed. If the failure is in the release/deploy pipeline, it must be fixed before ending the session — production is running stale code.

   **If no workflows were triggered** (the PR only touched files outside all path filters): Skip this step.

   **Why this matters:** In #1293, PR #1275 added `@playwright/test` to `package.json` but didn't update `package-lock.json`. PR CI passed (it uses `bun test`, not `npm ci`), but the Docker build uses `npm ci` which requires lockfile sync. Five consecutive release runs failed silently — production stayed on v0.8.6 for hours while new PRs kept merging.

3. **Post-merge validation of new or modified workflows.** If the PR added or modified GitHub Actions workflow files (`.github/workflows/*.yml`), validate them by triggering each affected workflow via `workflow_dispatch` and polling for completion. This is mandatory — never leave validation as a manual step for the user.

   **Step 1:** Detect new or modified workflow files in this PR. Use the merge base hash from Phase 3:

   ```bash
   git diff --name-only --diff-filter=AM HASH..HEAD -- .github/workflows/
   ```

   Note: `--diff-filter=AM` catches both **A**dded and **M**odified files. A modified workflow is just as likely to break as a new one — both must be validated.

   **Step 2:** For each affected workflow file, trigger it:

   ```bash
   gh workflow run <workflow-filename>
   ```

   If a workflow has a long expected runtime (>10 minutes), note this to the user and continue polling. Do not skip validation because the workflow is slow.

   **Step 3:** Poll each triggered run until completion using the **Monitor tool**:

   ```bash
   while true; do
     result=$(gh run list --workflow <workflow-filename> --limit 1 --json databaseId,status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')
     echo "$(date +%H:%M:%S) $result"
     echo "$result" | grep -q "^completed" && break
     sleep 30
   done
   ```

   Poll until output starts with `completed`. Maximum 40 iterations (20 minutes). If the maximum is reached, report: "Post-merge validation timed out after 20 minutes for workflow [name]." Do NOT silently continue. Then check `conclusion`:

   - **success**: Report pass and continue
   - **failure**: Report failure, fetch logs with `gh run view <id> --log | tail -50`, and present the error to the user. Do NOT silently proceed.

   **Step 4:** Report summary: "Post-merge validation: N/N workflows passed" or "Post-merge validation: X/N workflows failed — [details]"

   **If no new or modified workflow files were detected:** Skip this step.

   **Why this matters:** The founder is a solo operator. Every "please run this manually" is a context switch. `gh workflow run` exists — use it. Modified workflows are equally risky — a prompt change, a new step, or a timeout bump can all cause failures that are invisible without a live run. **Why `AM` not just `A`:** In #1126, a modified workflow (new Steps 5.5/5.6 in growth audit) was merged without validation because the ship skill only checked for new files.

3.5. **Follow-Through: detect unchecked external dependencies and create tracking issues.** Scan the merged PR body for unchecked test plan items marked with the ⏳ emoji. For each detected item, create a GitHub issue so external dependencies are tracked and monitored after the session ends.

   **Step 1:** Read the PR body. Use the PR number from Phase 6:

   ```bash
   gh pr view <PR_NUMBER> --json body --jq .body
   ```

   **Step 2:** Scan the body for lines matching unchecked items with the ⏳ marker. Match this pattern (both lowercase `x` and uppercase `X` mean checked — skip those):

- Unchecked with marker: `- [ ] ⏳ <description>` → **create issue**
- Checked (lowercase): `- [x] ⏳ <description>` → skip
- Checked (uppercase): `- [X] ⏳ <description>` → skip
- No marker: `- [ ] <description>` → skip

   If zero unchecked ⏳ items are found, skip to Step 4 (cleanup) silently.

   **Step 3:** For each detected item, create a tracking issue.

   First, ensure labels exist:

   ```bash
   gh label create "follow-through" --description "External dependency awaiting verification" --color "C5DEF5" 2>/dev/null || true
   gh label create "needs-attention" --description "SLA exceeded, requires human action" --color "D93F0B" 2>/dev/null || true
   ```

   Then read `knowledge-base/product/roadmap.md` to determine the appropriate milestone. Default to "Post-MVP / Later" if unclear.

   When follow-through items reference `terraform apply -replace`, enumerate ALL affected resources by scanning the full PR diff for `terraform_data` and `null_resource` connection block changes -- not just the resource named in the PR title or description. Use `git diff MERGE_BASE..HEAD -- '*.tf' | grep -E '(terraform_data|null_resource)' | grep -E '(connection|provisioner)'` to detect all changed provisioner blocks.

   Before creating each follow-through issue, check for duplicates:

   ```bash
   gh issue list --label follow-through --state open --search "Source PR: #<PR_NUMBER>" --json title --jq '.[].title'
   ```

   If an issue with a matching title prefix already exists, skip creation and note "Dedup: skipped [title] -- existing issue found."

   For each item, write the issue body to a temp file (do NOT use heredocs in this step — write with `{ echo "..."; } > /tmp/follow-through-body.md`), then create the issue:

   ```bash
   gh issue create --title "follow-through: <ITEM_DESCRIPTION>" --label "follow-through" --milestone "<MILESTONE>" --body-file /tmp/follow-through-body.md
   ```

   Replace `<ITEM_DESCRIPTION>` with the text after the ⏳ emoji (trimmed). Replace `<MILESTONE>` with the value from the roadmap or "Post-MVP / Later".

   **Issue body template** (write to the temp file):

   ````text
   ## Follow-Through Item

   <ITEM_DESCRIPTION>

   **Source PR:** #<PR_NUMBER>
   **Created by:** /ship Phase 7 Step 3.5
   **Created:** <YYYY-MM-DD>

   ## Verification

   ```yaml
   type: manual
   sla_business_days: 5
   ```

   To enable automated verification, edit the YAML block above. Supported types:

   - `http-200` — add `url: https://example.com`
   - `dns-txt` — add `domain: example.com` and `expected: verification-string`
   - `dns-a` — add `domain: example.com` and `expected: 1.2.3.4`

   ## Status

   Awaiting verification. The daily follow-through monitor will check this issue.
   ````

   **Step 4:** Report: "Created N follow-through issue(s): #X, #Y, #Z"

   **Why this matters:** PR #1398 (Google OAuth brand verification) had no tracking mechanism after the session ended. External dependencies that outlive a session — DNS propagation, app store reviews, certificate issuance, brand verification — get forgotten without automated tracking. See [#1433](https://github.com/jikig-ai/soleur/issues/1433).

3.6. **Post-merge Supabase migration verification.** If the PR includes database migration files (`supabase/migrations/`), verify each migration was applied to production before proceeding to cleanup.

   **Step 1:** Detect migration files in the PR diff. Use the merge base hash from Phase 3:

   ```bash
   git diff --name-only --diff-filter=A HASH..HEAD -- '*/supabase/migrations/*.sql'
   ```

   If no migration files found, skip to Step 4.

   **Step 2:** For each new migration file, extract the column additions or table changes. Read the SQL file and identify `ADD COLUMN`, `CREATE TABLE`, or other schema changes.

   **Step 3:** Verify each schema change is live in production by querying the Supabase REST API:

   ```bash
   SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)
   SUPABASE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
   curl -s "$SUPABASE_URL/rest/v1/<table>?select=<new_column>&limit=1" \
     -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY"
   ```

- If the query returns data (even `null` values): the column exists. Report "Migration verified: `<column>` exists in `<table>`."
- If the query returns a 400/404 or `column not found` error: the migration was NOT applied. Report the failure and attempt to apply it using the Supabase CLI or Management API. Do NOT silently proceed — the deployed code expects the new schema.

   **Step 4:** Report: "Migration verification: N/N columns confirmed in production" or "Migration verification: FAILED — <details>."

   **Why this matters:** In the 2026-03-28 session, migration `010_tag_and_route.sql` was committed and deployed but never applied, causing `NOT NULL` constraint failures on every Command Center session start. In the 2026-04-03 session (#1375), migration verification was left as a manual "post-merge todo" instead of being executed — violating the "execute, don't list" rule. This step ensures migrations are verified automatically.

3.7. **Terraform provisioner gate.** If the PR modified `.tf` files, grep for `remote-exec` provisioner blocks. If found, warn: "This PR contains remote-exec provisioners that cannot run in CI. Run `terraform apply` now to prevent drift." Block the session from ending until apply is confirmed or explicitly deferred.

   **Step 1:** Detect `.tf` files in the PR diff:

   ```bash
   git diff --name-only --diff-filter=AM HASH..HEAD -- '*.tf'
   ```

   If no `.tf` files found, skip to Step 4.

   **Step 2:** Grep for `remote-exec` provisioners in changed files:

   ```bash
   grep -l 'remote-exec' <changed .tf files>
   ```

   If no matches, skip to Step 4.

   **Step 3:** Display the warning and ask: "Run `terraform apply` now, or defer with justification?" If deferred, record the justification in the PR body.

4. Clean up worktree and local branch:

   Navigate to the repository root directory, then run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.

This detects `[gone]` branches (where the remote was deleted after merge), removes their worktrees, archives spec directories, deletes local branches, and pulls latest main so the next worktree branches from the current state.

**If working from a worktree:** Navigate to the main repo root first, then run cleanup.

**If the session ends before cleanup runs:** The next session will handle it automatically via the Session-Start Hygiene check in AGENTS.md. The `cleanup-merged` script is idempotent and safe to run at any time.

## Important Rules

- **Always set a semver label.** Every PR that touches `plugins/soleur/` must have a `semver:patch`, `semver:minor`, or `semver:major` label. CI uses this label to bump the version at merge time.
- **Never edit version fields.** `plugin.json` and `marketplace.json` versions are frozen sentinels (`0.0.0-dev`). Version is derived from git tags via GitHub Releases at build time.
- **Ask before running /compound.** The user may have already documented learnings.
- **Do not block on missing artifacts.** Not every change needs a brainstorm or plan.
- **Confirm the PR title and body** with the user before creating it (skip in headless mode).
