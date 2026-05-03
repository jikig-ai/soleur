---
name: schedule
description: "This skill should be used when creating, listing, or deleting scheduled agent tasks via GitHub Actions cron workflows. It generates workflow YAML files that invoke Soleur skills on a recurring schedule using claude-code-action."
---

# Schedule Manager

Generate GitHub Actions workflow files that run Soleur skills on a schedule. Two modes:

- **Recurring** (`--cron`): Standard cron-triggered workflow that fires on every matching tick.
- **One-time** (`--once --at <YYYY-MM-DD>`): Single-fire workflow that self-disables after running. Useful for "remind me to do X in 2 weeks" style tasks.

Each schedule becomes a standalone `.github/workflows/scheduled-<name>.yml`.

## When to use this skill vs harness `schedule`

Two skills exist with the name `schedule`. They serve different jobs:

| Use this (`soleur:schedule`) when | Use harness `schedule` when |
|---|---|
| Push commits, open PRs, modify the user's repo | Analyze, summarize, report — no repo writes |
| Use repo secrets (Doppler, Vercel, Cloudflare) | No secrets needed |
| Invoke a Soleur skill (`/soleur:<skill>`) | Generic Claude API task |
| Run Terraform / migrations / deploys | Read-only research, posting somewhere |

Examples for `soleur:schedule`:

- "Open a cleanup PR removing feature flag X in 2 weeks" → `--once`
- "Run a weekly Terraform drift check" → recurring

Examples for `harness schedule`:

- "Summarize recent issues every Monday and post to Slack"
- "Check if a vendor's API changed and email the diff"

If the agent doesn't need access to your repo, prefer harness `schedule`.

## Commands

### `create`

Generate a new scheduled workflow.

**Step 0a: Mode detection (recurring vs one-time)**

Inspect `$ARGUMENTS`:

- If both `--cron` and `--once` are present → error: `Cannot specify both --once and --cron`. Stop.
- If neither `--cron` nor `--once` is present → error: `Specify either --once <YYYY-MM-DD> or --cron <expression>`. Stop. (No silent default — the operator must declare intent.)
- If `--once` is present → **one-time mode**. Validate per Step 0c below, then skip to Step 2 → Step 3b.
- If `--cron` is present → **recurring mode**. Continue with Step 0b below.

**Step 0b: Check arguments (recurring mode)**

If `$ARGUMENTS` contains `--name`, `--skill`, `--cron`, and `--model` flags, extract values directly and skip to Step 2. Validate each value using the same rules below. If any required flag is missing, proceed to Step 1 for the missing parameters only. Optional flags: `--timeout` (minutes, default 30) and `--max-turns` (default 30).

**Step 0c: Check arguments (one-time mode)**

For `--once`, all five flags are MANDATORY. There is no AskUserQuestion fallback (Step 1 is recurring-only). Operator-supplied values are required so the workflow file is self-documenting at `delete`/cleanup time. Each value MUST match its regex EXACTLY before substitution into the YAML — these regexes are the load-bearing defense against shell/YAML injection at fire time.

If ANY regex below fails, emit `ERROR: --<flag> value '<value>' does not match required pattern <regex>` to stderr and stop.

- `--once` (mode flag, no value)
- `--at <YYYY-MM-DD>` — strict ISO date pattern `^\d{4}-\d{2}-\d{2}$`. Default time = 09:00 UTC. Natural-language dates (`"2 weeks from now"`, `tomorrow`) and ISO datetimes (`2026-05-17T03:00`) are intentionally rejected. Validate with:

  ```bash
  python3 -c "
  import re, sys
  from datetime import datetime, timezone, timedelta
  if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', sys.argv[1]):
      sys.exit(f\"ERROR: --at value '{sys.argv[1]}' does not match required pattern ^\\\d{{4}}-\\\d{{2}}-\\\d{{2}}\$\")
  d = datetime.fromisoformat(sys.argv[1]).replace(tzinfo=timezone.utc)
  now = datetime.now(timezone.utc)
  if d.date() < now.date():
      sys.exit('ERROR: --at date is in the past')
  if (d - now) > timedelta(days=50):
      sys.exit('ERROR: --at date is more than 50 days out (GHA auto-disables workflows after 60d inactivity; 10d margin)')
  " '<AT_VALUE>'
  ```

- `--issue <N>` — GitHub issue number, pattern `^[1-9][0-9]{0,8}$` (positive integer, no leading zeros, ≤9 digits).
- `--comment <id>` — GitHub comment ID, pattern `^[1-9][0-9]{0,18}$` (positive int64, no leading zeros). Look it up via `gh api repos/<OWNER>/<REPO>/issues/<N>/comments --jq '.[] | "\(.id) \(.user.login) \(.created_at): \(.body | .[0:80])"'` if the operator needs to find it.
- `--name <kebab-case>` — schedule name, pattern `^[a-z][a-z0-9-]{0,49}$` (lowercase, leading letter, ≤50 chars). Reject if `.github/workflows/scheduled-<name>.yml` already exists with the exact error:

  ```text
  ERROR: .github/workflows/scheduled-<name>.yml already exists. Pick a different --name (no --force flag in v1).
  ```

**Comment integrity capture (D5 — comment-author-pin defense):**

The fire-time agent fetches the task spec from the referenced comment body. If the comment is editable between authoring and fire, an attacker with comment-edit access can rewrite the task — single-user incident vector. Pin the comment at create time:

```bash
COMMENT_META=$(gh api "repos/${REPO_OWNER_AND_NAME}/issues/comments/${COMMENT_ID}" \
  --jq '"\(.user.login)\t\(.created_at)\t\(.updated_at)"' 2>/dev/null) || {
  echo "ERROR: --comment <id> not found or not accessible" >&2; exit 1; }

EXPECTED_AUTHOR=$(echo "$COMMENT_META" | cut -f1)
COMMENT_CREATED_AT=$(echo "$COMMENT_META" | cut -f2)
COMMENT_UPDATED_AT=$(echo "$COMMENT_META" | cut -f3)

if [[ "$COMMENT_CREATED_AT" != "$COMMENT_UPDATED_AT" ]]; then
  echo "ERROR: comment $COMMENT_ID has been edited (created_at != updated_at)." >&2
  echo "Re-post the task spec as a fresh comment and pass the new --comment <id>." >&2
  exit 1
fi
```

Both `$EXPECTED_AUTHOR` and `$COMMENT_CREATED_AT` are embedded into the workflow's `env:` block (Step 3b) and re-checked by the fire-time pre-flight (D5) — see Step 3b below.

**Default-branch warning:**

If the current branch is not the default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`), print a **WARNING** (not an error):

```text
WARNING: GHA cron triggers fire only from workflows on the default branch.
Merge this workflow before <FIRE_DATE> or it will not fire.
```

If any one-time validation fails, stop. Do not write the file.

**Step 1: Collect inputs (recurring mode only)**

One-time mode does not pass through Step 1 — all flags are mandatory at the command line so the resulting workflow is self-documenting. For recurring mode, use the **AskUserQuestion tool** to gather missing inputs one at a time:

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

5. **Timeout (minutes)** — Job-level timeout to prevent runaway billing. Default: 30. Validate: positive integer, minimum 5 minutes.

6. **Max turns** — Maximum number of agent turns before stopping. Default: 30. Validate: positive integer, minimum 5 turns. Budget formula: plugin overhead (~10 turns) + task tool calls + error buffer (~5). Multi-platform data collection or PR-based persist workflows typically need 40-50 turns.

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

For workflows that process PRs (e.g., ship-merge, compound-review), use `gh pr checks --required` for CI gating rather than reimplementing `statusCheckRollup` filtering in jq — GitHub CLI already respects the repo's required checks configuration.

If `gh api` fails, **do not generate the workflow**. Display: "Could not resolve action SHAs. Check network connectivity and `gh auth status`, then retry." The user can retry when they have network access.

**Step 3a: Generate the workflow file (recurring mode)**

Skip to **Step 3b** if running in one-time mode.

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
  id-token: write

jobs:
  run-schedule:
    runs-on: ubuntu-latest
    timeout-minutes: <TIMEOUT>
    steps:
      - name: Checkout repository
        uses: actions/checkout@<CHECKOUT_SHA> # v4

      - name: Ensure label exists
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh label create "scheduled-<NAME>" \
            --description "Scheduled: <DISPLAY_NAME>" \
            --color "0E8A16" 2>/dev/null || true

      - name: Run scheduled skill
        uses: anthropics/claude-code-action@<ACTION_SHA> # v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: 'https://github.com/<REPO_OWNER>/<REPO_NAME>.git'
          plugins: 'soleur@soleur'
          claude_args: >-
            --model <MODEL>
            --max-turns <MAX_TURNS>
            --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch
          prompt: |
            Run /soleur:<SKILL_NAME> on this repository.
            After your analysis is complete, create a GitHub issue titled
            "[Scheduled] <DISPLAY_NAME> - <today's date in YYYY-MM-DD format>"
            with the label "scheduled-<NAME>" summarizing your findings.
```

**Step 3b: Generate the workflow file (one-time mode)**

For `--once`, generate the cron expression from `--at <YYYY-MM-DD>`:

```bash
python3 -c "
from datetime import datetime
d = datetime.fromisoformat('<AT_VALUE>')
print(f'0 9 {d.day} {d.month} *')
"
```

Result is a 5-field cron with explicit single-day + single-month + `*` year (e.g., `0 9 17 5 *`). The `*` year means the cron will repeat every year — the load-bearing **D3 date guard** inside the agent prompt aborts non-target-year fires; **D4 self-disable** as the final agent step revokes the workflow on first successful fire so the cron never matches again. Both defenses must be present.

**Defenses summary (D1-D5):**

- **D1 — runtime context fetch.** Task spec is fetched from the referenced comment at fire time, never inlined into the committed YAML. Prevents secret leak via committed prompt.
- **D2 — stale-context preamble.** Pre-flight verifies issue OPEN, repo not archived, comment matches issue. Prevents wrong action against drifted state.
- **D3 — in-prompt date guard (PRIMARY).** `[[ $(date -u +%F) == $FIRE_DATE ]]` aborts cross-year re-fires. Cannot fail silently.
- **D4 — in-prompt self-disable (SECONDARY).** `gh workflow disable` as the LAST instruction inside the agent prompt. Same-year re-fire defense (cron `0 9 17 5 *` matches every May 17 forever otherwise). MUST live inside the prompt — `claude-code-action` revokes its App token AFTER the step, so a post-step YAML-level disable would 403.
- **D5 — comment-author + immutability pin.** `EXPECTED_AUTHOR` and `EXPECTED_CREATED_AT` env vars are captured at create time (Step 0c) and re-checked in pre-flight. Prevents "attacker edits the comment between create and fire to swap the task" — the brand-survival single-user-incident vector that D1-D4 alone do not cover.

Create `.github/workflows/scheduled-<NAME>.yml` with this content, replacing all `<PLACEHOLDER>` values. The HTML markers `<!-- once-template-begin -->` / `<!-- once-template-end -->` below frame the canonical template; the test suite extracts between them, so do NOT add new fences inside the markers and do NOT remove them.

<!-- once-template-begin -->

```yaml
name: "Scheduled (once): <DISPLAY_NAME>"

on:
  schedule:
    - cron: '<ONE_TIME_CRON>'
  workflow_dispatch: {}

# `actions: write` is required for `gh workflow disable` (D4) inside the agent
# prompt. Do NOT remove. `id-token: write` is intentionally omitted — one-time
# fires have no OIDC use case.
permissions:
  contents: read
  issues: write
  actions: write

concurrency:
  group: schedule-once-<NAME>
  cancel-in-progress: false

env:
  ISSUE_NUMBER: "<N>"
  COMMENT_ID: "<id>"
  FIRE_DATE: "<YYYY-MM-DD>"
  WORKFLOW_NAME: "scheduled-<NAME>.yml"
  EXPECTED_AUTHOR: "<COMMENT_AUTHOR_LOGIN>"
  EXPECTED_CREATED_AT: "<COMMENT_CREATED_AT>"

jobs:
  run-once:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - name: Checkout repository
        uses: actions/checkout@<CHECKOUT_SHA> # v4

      - name: One-time fire (with self-disable)
        uses: anthropics/claude-code-action@<ACTION_SHA> # v1
        env:
          GH_TOKEN: ${{ github.token }}
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: 'https://github.com/<REPO_OWNER>/<REPO_NAME>.git'
          plugins: 'soleur@soleur'
          # --allowedTools mirrors the recurring template (Step 3a). Do NOT
          # widen — the fire-time prompt is fed an externally-fetched comment
          # body (D1), so least-privilege tool surface is load-bearing.
          claude_args: >-
            --max-turns 25
            --allowedTools Bash,Read,Write,Edit,Glob,Grep
          prompt: |
            ## Pre-flight (abort with observation comment if any check fails)

            1. **Date guard (PRIMARY cross-year defense, D3):**
               First, refuse to run if `$FIRE_DATE` is empty or malformed:
               `[[ "$FIRE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "FIRE_DATE empty or malformed: '$FIRE_DATE'"; gh workflow disable "$WORKFLOW_NAME"; exit 0; }`
               Then assert the calendar match:
               `[[ "$(date -u +%F)" == "$FIRE_DATE" ]]` must be true. If false, run
               `gh workflow disable "$WORKFLOW_NAME"` and exit 0. Take no other action.
               This is D3, the load-bearing defense against cron `0 9 <day> <month> *`
               re-firing every year. Cannot fail silently.
            2. **Idempotency:** if the workflow is in any disabled state, exit 0.
               `state=$(gh workflow view "$WORKFLOW_NAME" --json state --jq .state)`
               then `[[ "$state" == "active" ]] || exit 0`.
            3. **Repo not archived:**
               `[[ "$(gh repo view --json isArchived --jq .isArchived)" == "false" ]]`.
            4. **Issue OPEN + same repo:** fetch
               `gh issue view "$ISSUE_NUMBER" --json state,repository_url`. The state
               must be OPEN, and `repository_url` must end in `${{ github.repository }}`.
            5. **Comment exists + matches issue:**
               `gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq .issue_url`
               must end in `/issues/$ISSUE_NUMBER`.
            6. **Comment-author pin (D5, FIRST half):** the comment's author MUST equal `$EXPECTED_AUTHOR`.
               `actual_author=$(gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq .user.login)`
               then `[[ "$actual_author" == "$EXPECTED_AUTHOR" ]]`.
            7. **Comment-immutability pin (D5, SECOND half):** the comment MUST NOT have been edited after authoring.
               `meta=$(gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq '"\(.created_at)\t\(.updated_at)"')`
               then verify `created_at == EXPECTED_CREATED_AT` AND `created_at == updated_at`.
               Reject on mismatch — an edited comment between schedule and fire is the brand-survival vector D5 is designed to catch.

            If ANY pre-flight check fails: post a single observation comment to issue
            #$ISSUE_NUMBER naming which check failed, then run
            `gh workflow disable "$WORKFLOW_NAME"` and exit 0. Take no other action.

            ## Task

            Fetch the documented task spec from the referenced comment:

            `body=$(gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq .body)`

            If `$body` is empty (`[[ -z "$body" ]]`), treat as a pre-flight failure: post observation comment "comment body is empty", disable, exit 0.

            Otherwise execute the documented work as instructed by `$body`. When complete, post results as a follow-up comment on issue #$ISSUE_NUMBER (re-verify `gh issue view "$ISSUE_NUMBER" --json repository_url` matches `${{ github.repository }}` immediately before posting — defends against issue-transfer-after-preflight).

            ## Final step (mandatory, last)

            Run `gh workflow disable "$WORKFLOW_NAME"`. This is D4 — the secondary
            self-disable. D3 (the date guard above) is the primary cross-year defense;
            disable can fail (token revocation, transient API error), the date guard
            cannot.

            If `gh workflow disable` returns non-zero, post a follow-up comment to
            issue #$ISSUE_NUMBER with this exact body:
            "Workflow ran but auto-disable failed. Manual: gh workflow disable $WORKFLOW_NAME".
            Do NOT add any post-step to this workflow file — `claude-code-action`
            revokes the App token after this step, so a YAML-level disable would
            silently fail.
```

<!-- once-template-end -->

YAML write verification (one-time mode — same primitive as recurring, additional asserts on the one-time-specific env block):

```bash
python3 -c "
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d['on']['schedule'][0]['cron'] == '<ONE_TIME_CRON>', 'cron mismatch'
assert d['env']['ISSUE_NUMBER'] == '<N>', 'ISSUE_NUMBER mismatch'
assert re.fullmatch(r'\d{4}-\d{2}-\d{2}', d['env']['FIRE_DATE']), 'FIRE_DATE empty or malformed'
assert d['env']['FIRE_DATE'] == '<YYYY-MM-DD>', 'FIRE_DATE substitution mismatch'
assert d['env'].get('EXPECTED_AUTHOR'), 'EXPECTED_AUTHOR missing (D5 author-pin defense)'
assert d['env'].get('EXPECTED_CREATED_AT'), 'EXPECTED_CREATED_AT missing (D5 immutability pin)'
assert d['permissions']['actions'] == 'write', 'actions:write missing (gh workflow disable will fail)'
" .github/workflows/scheduled-<NAME>.yml
```

**Step 4: Validate and confirm**

After writing the file, validate the YAML syntax:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-<NAME>.yml'))" 2>&1 || echo "WARNING: YAML syntax error detected"
```

Display a summary:

```text
Schedule created: .github/workflows/scheduled-<NAME>.yml

  Name:      <DISPLAY_NAME>
  Skill:     /soleur:<SKILL_NAME>
  Cron:      <CRON_EXPRESSION>
  Model:     <MODEL>
  Timeout:   <TIMEOUT> minutes
  Max turns: <MAX_TURNS>
  Output:    GitHub Issues

Prerequisites:
  - ANTHROPIC_API_KEY must be set as a repository secret
  - .claude-plugin/marketplace.json must exist at the repo root

The schedule activates once this file is merged to the default branch.
```

**Step 5: Verify workflow after merge**

After the PR containing the new workflow is merged to the default branch, trigger a manual run and verify it succeeds:

```bash
# Trigger the workflow
gh workflow run scheduled-<NAME>.yml

# Wait for the run to appear (may take a few seconds)
sleep 5
RUN_ID=$(gh run list --workflow=scheduled-<NAME>.yml --limit=1 --json databaseId --jq '.[0].databaseId')

# Poll until complete
gh run watch "$RUN_ID"

# Check conclusion
CONCLUSION=$(gh run view "$RUN_ID" --json conclusion --jq '.conclusion')
if [ "$CONCLUSION" != "success" ]; then
  echo "WORKFLOW FAILED — investigate before moving on"
  gh run view "$RUN_ID" --log-failed | tail -50
fi
```

If the run fails, diagnose the issue, fix the workflow file, and re-run. Do not close the task until the workflow has completed successfully at least once.

### `list`

Display all existing scheduled workflows, distinguishing recurring from one-time by cron shape.

If `$ARGUMENTS` contains `--json`, output a JSON array with `name`, `cron`, `mode` (string: `"recurring"` or `"one-time"`), and `skill` fields. Otherwise display a formatted list with a mode tag.

```bash
ls .github/workflows/scheduled-*.yml 2>/dev/null
```

If no files found, display: "No scheduled workflows found."

For each file, extract the cron expression and classify by shape. The shape definition below is canonical — if Step 3b ever changes the generated cron pattern, update this classifier in the same edit:

- 5-field cron with explicit single integer for minute, hour, day-of-month, AND month, with `*` for year (e.g., `0 9 17 5 *`) → `[one-time]`.
- Anything else → `[recurring]`.

Mode detection (per file):

```bash
cron=$(python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); print(d['on']['schedule'][0]['cron'])" "$file")
fields=($cron)
mode=recurring
if [[ "${fields[2]}" =~ ^[0-9]+$ ]] && [[ "${fields[3]}" =~ ^[0-9]+$ ]] && [[ "${fields[4]}" == "*" ]] && [[ "${fields[0]}" =~ ^[0-9]+$ ]] && [[ "${fields[1]}" =~ ^[0-9]+$ ]]; then
  mode=one-time
fi
```

Display:

```text
[recurring] weekly-audit       (cron: 0 9 * * 1)
[one-time]  verify-hook-fires  (cron: 0 9 17 5 *)
```

V1 reports mode + cron only. Richer state (`pending` / `disabled_inactivity` / `fired-failed`) is deferred — operators can run `gh workflow list` and `gh workflow view <NAME>` directly for now.

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
- **No skill-specific arguments** — The template prompt does not pass arguments (e.g., `--tiers 0,3`) to the invoked skill. Manual prompt edit required after generation.
- **No cascading priority selection** — Generated workflows that select issues by label hardcode a single priority tier. When that tier is empty, the bot sits idle while higher-priority bugs accumulate. Manually add a priority cascade loop (p3 -> p2 -> p1) after generation.
- **`--once` requires merge-before-fire.** GHA cron triggers fire only from workflows on the default branch. A `--once` workflow on a feature branch must be merged before its `--at` date or it will not fire.
- **`--at` caps at 50 days.** GHA auto-disables workflows after 60 days of inactivity. The 50-day cap leaves a 10-day margin so a freshly merged `--once` workflow is still active when its cron tick arrives.
- **Cron variance ~15 min.** GitHub Actions cron schedules trigger on a best-effort basis. `--at 2026-05-17` may fire any time between 09:00 and 09:15 UTC.
