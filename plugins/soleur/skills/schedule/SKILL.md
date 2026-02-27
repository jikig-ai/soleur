---
name: schedule
description: This skill should be used when creating, listing, or deleting scheduled agent tasks via GitHub Actions cron workflows. It generates workflow YAML files that invoke Soleur skills on a recurring schedule using claude-code-action. Triggers on "schedule a skill", "recurring task", "cron job", "scheduled agent", "automate skill".
---

# Schedule Manager

Generate GitHub Actions workflow files that run Soleur skills on a recurring cron schedule. Each schedule becomes a standalone `.github/workflows/scheduled-<name>.yml`.

## Commands

### `create`

Interactively generate a new scheduled workflow.

**Step 1: Collect inputs**

Use the **AskUserQuestion tool** to gather these inputs one at a time:

1. **Schedule name** — A short, descriptive kebab-case name (e.g., `weekly-security-audit`, `monthly-legal-check`). Validate: lowercase letters, numbers, and hyphens only. Check that `.github/workflows/scheduled-<name>.yml` does not already exist.

2. **Skill to run** — Which Soleur skill to invoke on each run. Show available skills by running:

   ```bash
   ls plugins/soleur/skills/*/SKILL.md | sed 's|plugins/soleur/skills/||;s|/SKILL.md||' | sort
   ```

   Present the list and let the user choose. Prefix with `soleur:` in the generated prompt.

3. **Cron expression** — A 5-field POSIX cron expression (minute hour day-of-month month day-of-week). Validate:
   - Must have exactly 5 space-separated fields
   - Each field must contain only: `0-9`, `*`, `/`, `-`, `,`
   - Reject named values (`MON`, `JAN`, etc.) — GitHub Actions POSIX cron does not support them
   - Warn if the schedule runs more frequently than hourly
   - Reject if more frequent than every 5 minutes
   - Note to user: GitHub Actions cron has ~15-minute variance in trigger timing

4. **Model** — Which Claude model to use for each run. Options:
   - `claude-sonnet-4-6-20250514` (recommended — good balance of cost and capability)
   - `claude-haiku-4-5-20251001` (cheaper — good for simple checks)
   - `claude-opus-4-6-20250610` (most capable — for complex analysis)

**Step 2: Resolve action SHAs**

Pin GitHub Actions to commit SHAs for supply-chain security. Run these commands to resolve the current SHAs:

```bash
# Resolve actions/checkout@v4 SHA (handles annotated tags)
REF_JSON=$(gh api repos/actions/checkout/git/ref/tags/v4 2>/dev/null)
TYPE=$(echo "$REF_JSON" | jq -r '.object.type')
CHECKOUT_SHA=$(echo "$REF_JSON" | jq -r '.object.sha')
if [ "$TYPE" = "tag" ]; then
  CHECKOUT_SHA=$(gh api "repos/actions/checkout/git/tags/$CHECKOUT_SHA" --jq '.object.sha')
fi
echo "checkout SHA: $CHECKOUT_SHA"
```

```bash
# Resolve anthropics/claude-code-action@v1 SHA (handles annotated tags)
REF_JSON=$(gh api repos/anthropics/claude-code-action/git/ref/tags/v1 2>/dev/null)
TYPE=$(echo "$REF_JSON" | jq -r '.object.type')
ACTION_SHA=$(echo "$REF_JSON" | jq -r '.object.sha')
if [ "$TYPE" = "tag" ]; then
  ACTION_SHA=$(gh api "repos/anthropics/claude-code-action/git/tags/$ACTION_SHA" --jq '.object.sha')
fi
echo "claude-code-action SHA: $ACTION_SHA"
```

If either `gh api` command fails (no network, auth issues), fall back to the tag reference (`v4` or `v1`) and warn: "Could not resolve SHA. Using tag reference — consider pinning to SHA later for supply-chain security."

**Step 3: Generate the workflow file**

Create `.github/workflows/scheduled-<NAME>.yml` with this content, replacing all `<PLACEHOLDER>` values:

```yaml
name: "Scheduled: <DISPLAY_NAME>"

on:
  schedule:
    - cron: '<CRON_EXPRESSION>'
  workflow_dispatch: {}

concurrency:
  group: schedule-<NAME>
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  run-schedule:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@<CHECKOUT_SHA> # v4

      - name: Run scheduled skill
        uses: anthropics/claude-code-action@<ACTION_SHA> # v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: 'https://github.com/<REPO_OWNER>/<REPO_NAME>.git'
          plugins: 'soleur@soleur'
          claude_args: '--model <MODEL>'
          prompt: |
            Run /soleur:<SKILL_NAME> on this repository.
            After your analysis is complete, create a GitHub issue titled
            "[Scheduled] <DISPLAY_NAME> - $(date +%Y-%m-%d)"
            with the label "scheduled-<NAME>" summarizing your findings.

      - name: Notify on failure
        if: failure()
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "scheduled-failure" --color "B60205" \
            --description "Scheduled workflow failure" 2>/dev/null || true
          gh issue create \
            --title "[Scheduled] <NAME> failed - $(date +%Y-%m-%d)" \
            --body "Workflow run failed. See: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}" \
            --label "scheduled-failure"
```

To determine `<REPO_OWNER>` and `<REPO_NAME>`, run:

```bash
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

**Step 4: Confirm and write**

Display a summary of the generated workflow to the user:

```
Schedule created: .github/workflows/scheduled-<NAME>.yml

  Name:     <DISPLAY_NAME>
  Skill:    /soleur:<SKILL_NAME>
  Cron:     <CRON_EXPRESSION>
  Model:    <MODEL>
  Output:   GitHub Issues

Prerequisites:
  - ANTHROPIC_API_KEY must be set as a repository secret
  - .claude-plugin/marketplace.json must exist at the repo root

The schedule will activate once this file is merged to the default branch.
To test manually after merging: gh workflow run scheduled-<NAME>.yml
```

### `list`

Display all existing scheduled workflows.

Run:

```bash
ls .github/workflows/scheduled-*.yml 2>/dev/null
```

If no files found, display: "No scheduled workflows found."

If files found, parse each file to extract the schedule name, cron expression, and skill. For each file, run:

```bash
grep -E '(cron:|name:|/soleur:)' .github/workflows/scheduled-<file>.yml
```

Display results in a formatted table:

```
Scheduled Workflows
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Name                  Cron              Skill
─────────────────────────────────────────────────────────────
weekly-security       0 9 * * 1         /soleur:legal-audit
monthly-review        0 0 1 * *         /soleur:review
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### `delete <name>`

Remove a scheduled workflow.

1. Verify `.github/workflows/scheduled-<name>.yml` exists. If not, display: "Schedule '<name>' not found. Run `/soleur:schedule list` to see available schedules."

2. Use **AskUserQuestion tool** to confirm: "Delete schedule '<name>'? This will deactivate the cron trigger once merged to the default branch."

3. If confirmed, remove the file.

4. Display: "Deleted `.github/workflows/scheduled-<name>.yml`. The schedule will stop once this deletion is merged to the default branch."

## Known Limitations

- **Skills only** — Agents cannot be reliably invoked via prompts in unattended CI. Only skills (`/soleur:<skill-name>`) are supported. Agent support may be added in v2.
- **Issue output only** — All scheduled runs report findings via GitHub Issues. PR and Discord output modes are planned for v2.
- **No state across runs** — Each scheduled run starts fresh. There is no mechanism to carry state (e.g., "what changed since last run") between executions.
- **Cron variance** — GitHub Actions cron triggers have approximately 15 minutes of variance. A `0 9 * * 1` schedule may fire between 9:00 and 9:15.
- **Concurrency is not a true queue** — The `cancel-in-progress: false` setting allows one pending run to wait. If a third run triggers while one is running and one is pending, the pending run is replaced by the third. Long-running skills on frequent schedules may skip runs.
- **Activates on default branch only** — Schedules only trigger once the workflow file exists on the default branch (main/master). Creating a schedule in a feature branch does not activate it until merged.
- **Marketplace dependency** — The repo must have `.claude-plugin/marketplace.json` at its root for `claude-code-action` to discover the Soleur plugin. This file is included in the Soleur repo by default.

## How to Test a Schedule

After the workflow file is merged to the default branch, trigger a manual run:

```bash
gh workflow run scheduled-<name>.yml
```

Monitor the run:

```bash
gh run watch
```

Check results:

```bash
gh run list --workflow=scheduled-<name>.yml --limit 5
```
