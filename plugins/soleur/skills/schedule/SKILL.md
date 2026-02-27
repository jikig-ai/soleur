---
name: schedule
description: "This skill should be used when creating, listing, or deleting scheduled agent tasks via GitHub Actions cron workflows. It generates workflow YAML files that invoke Soleur skills on a recurring schedule using claude-code-action. Triggers on 'schedule a skill', 'recurring task', 'cron job', 'scheduled agent', 'automate skill', 'run periodically'."
---

# Schedule Manager

Generate GitHub Actions workflow files that run Soleur skills on a recurring cron schedule. Each schedule becomes a standalone `.github/workflows/scheduled-<name>.yml`.

## Commands

### `create`

Generate a new scheduled workflow.

**Step 0: Check arguments**

If `$ARGUMENTS` contains `--name`, `--skill`, `--cron`, and `--model` flags, extract values directly and skip to Step 2. Validate each value using the same rules below. If any required flag is missing, proceed to Step 1 for the missing parameters only.

**Step 1: Collect inputs**

Use the **AskUserQuestion tool** to gather missing inputs one at a time:

1. **Schedule name** — A short kebab-case name (e.g., `weekly-security-audit`). Validate: lowercase letters, numbers, and hyphens only. Check that `.github/workflows/scheduled-<name>.yml` does not already exist.

2. **Skill to run** — Which Soleur skill to invoke. Show available skills:

   ```bash
   ls plugins/soleur/skills/*/SKILL.md | sed 's|plugins/soleur/skills/||;s|/SKILL.md||' | sort
   ```

   Present the list and let the user choose. Prefix with `soleur:` in the generated prompt.

3. **Cron expression** — A 5-field POSIX cron expression (minute hour day-of-month month day-of-week).
   - Reject named values (`MON`, `JAN`) — GitHub Actions does not support them
   - Reject schedules more frequent than every 5 minutes
   - Note: GitHub Actions cron has ~15-minute variance in trigger timing

4. **Model** — Which Claude model to use. Default: `claude-sonnet-4-6` (good balance of cost and capability). Accept any valid Anthropic model identifier.

**Step 2: Resolve action SHAs**

Pin GitHub Actions to commit SHAs for supply-chain security. For each action (`actions/checkout@v4`, `anthropics/claude-code-action@v1`), resolve the SHA:

```bash
# Replace OWNER/REPO and TAG for each action
REF_JSON=$(gh api repos/OWNER/REPO/git/ref/tags/TAG 2>/dev/null)
TYPE=$(echo "$REF_JSON" | jq -r '.object.type')
SHA=$(echo "$REF_JSON" | jq -r '.object.sha')
if [ "$TYPE" = "tag" ]; then
  SHA=$(gh api "repos/OWNER/REPO/git/tags/$SHA" --jq '.object.sha')
fi
echo "$SHA"
```

If `gh api` fails, **do not generate the workflow**. Display: "Could not resolve action SHAs. Check network connectivity and `gh auth status`, then retry." The user can retry when they have network access.

**Step 3: Generate the workflow file**

Determine repo owner and name:

```bash
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

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
            "[Scheduled] <DISPLAY_NAME> - <today's date in YYYY-MM-DD format>"
            with the label "scheduled-<NAME>" summarizing your findings.
```

**Step 4: Validate and confirm**

After writing the file, validate the YAML syntax:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-<NAME>.yml'))" 2>&1 || echo "WARNING: YAML syntax error detected"
```

Display a summary:

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

The schedule activates once this file is merged to the default branch.
To test manually: gh workflow run scheduled-<NAME>.yml
```

### `list`

Display all existing scheduled workflows.

If `$ARGUMENTS` contains `--json`, output a JSON array with `name`, `cron`, and `skill` fields. Otherwise display a formatted table.

```bash
ls .github/workflows/scheduled-*.yml 2>/dev/null
```

If no files found, display: "No scheduled workflows found."

If files found, parse each file to extract the schedule name, cron expression, and skill:

```bash
grep -E '(cron:|name:|/soleur:)' .github/workflows/scheduled-<file>.yml
```

Display results as a table with name, cron, and skill columns.

### `delete <name>`

Remove a scheduled workflow.

1. Verify `.github/workflows/scheduled-<name>.yml` exists. If not, display: "Schedule '<name>' not found. Run `/soleur:schedule list` to see available schedules."

2. If `$ARGUMENTS` contains `--yes` or `--confirm`, skip to step 3. Otherwise, use **AskUserQuestion tool** to confirm: "Delete schedule '<name>'? This will deactivate the cron trigger once merged to the default branch."

3. Remove the file.

4. Display: "Deleted `.github/workflows/scheduled-<name>.yml`. The schedule will stop once this deletion is merged to the default branch."

## Known Limitations

- **Skills only** — Agents cannot be reliably invoked in unattended CI. Only skills (`/soleur:<skill-name>`) are supported.
- **Issue output only** — All scheduled runs report findings via GitHub Issues. PR and Discord output modes planned for v2.
- **No state across runs** — Each scheduled run starts fresh. No mechanism to carry state between executions.
