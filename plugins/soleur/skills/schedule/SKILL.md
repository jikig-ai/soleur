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
- **D4 — in-prompt self-neutralization (SECONDARY).** The agent's last prompt instruction edits the generated workflow YAML to strip the `schedule:` trigger and pushes (direct or via PR + auto-merge). MUST live inside the prompt — `claude-code-action` revokes its App token after this step, so a post-step would silently fail. Replaces the previous `gh workflow disable` mechanism, which fails at runtime because `claude-code-action`'s App installation token does not honor the workflow's `actions: write` declaration (#3153). `contents: write` + `pull-requests: write` are the load-bearing permissions.
- **D5 — comment-author + immutability pin.** `EXPECTED_AUTHOR` and `EXPECTED_CREATED_AT` env vars are captured at create time (Step 0c) and re-checked in pre-flight. Prevents "attacker edits the comment between create and fire to swap the task" — the brand-survival single-user-incident vector that D1-D4 alone do not cover.

Create `.github/workflows/scheduled-<NAME>.yml` with this content, replacing all `<PLACEHOLDER>` values. The HTML markers `<!-- once-template-begin -->` / `<!-- once-template-end -->` below frame the canonical template; the test suite extracts between them, so do NOT add new fences inside the markers and do NOT remove them.

<!-- once-template-begin -->

```yaml
name: "Scheduled (once): <DISPLAY_NAME>"

on:
  schedule:
    - cron: '<ONE_TIME_CRON>'
  workflow_dispatch: {}

# `contents: write` is required for the D4 neutralization commit (the agent
# strips the `schedule:` trigger from this file at end-of-run). `pull-requests:
# write` is required for the PR-fallback leg when direct push is blocked by
# branch protection. `id-token: write` is required by
# `anthropics/claude-code-action@v1` for its OIDC auth handshake — without it
# the action exits before the prompt body runs (no agent execution, no D4).
#
# `actions: write` was REMOVED in #3153 — the official Anthropic GitHub App's
# installation manifest caps `actions:*` at READ. Workflow-level `actions:
# write` cannot widen the App's effective scope, so declaring it gave false
# confidence that `gh workflow disable` would work inside the agent. If you
# have installed a CUSTOM GitHub App with actions:write and configured
# claude-code-action to use it (see upstream docs/setup.md), you may add
# `actions: write` back and switch the D4 primitive to `gh workflow disable`.
#
# COPY-PASTE WARNING: if you copy this block to a recurring-cron workflow,
# REVERT `contents:` to `read` and DROP `pull-requests:` — recurring crons do
# not self-neutralize, so the wider permissions are unnecessary attack surface.
permissions:
  contents: write
  issues: write
  pull-requests: write
  id-token: write

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

      - name: One-time fire (with self-neutralization)
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
            ## Neutralization primitive (referenced by D3 abort, preflight-failure abort, and the Final step)

            To **neutralize** the workflow (prevent any future cron fires), do
            the following IN ORDER. The previous mechanism `gh workflow disable
            "$WORKFLOW_NAME"` was removed in #3153 — `claude-code-action`'s App
            installation token does not honor `actions: write`, so the disable
            returns 403 regardless of the workflow's declared permissions.

            1. **Idempotency precheck.** Read `.github/workflows/$WORKFLOW_NAME`.
               If the `on:` block has already had `schedule:` removed (or only
               contains `workflow_dispatch:`), the workflow is already
               neutralized — skip to step 6 (success, no-op).
            2. **Edit YAML.** Use the Read+Edit tools (NOT shell `sed`/`awk` —
               shell-based YAML mutation has a long history of corrupting
               workflow files in CI) to remove the `schedule:` key and its
               child list under `on:`. Leave any other triggers
               (`workflow_dispatch:`, etc.) intact. If `schedule:` is the ONLY
               trigger, replace the entire `on:` block with `on:\n  workflow_dispatch:`
               so the file remains a valid GHA workflow that can be manually
               invoked for forensic purposes.
            3. **Stage and guard against no-op commit.**
               `git add .github/workflows/$WORKFLOW_NAME` then
               `git diff --cached --quiet`. If the diff is empty (exit 0), the
               file was already neutralized between step 1 and step 2 — skip
               to step 6. (See learning `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`
               — `git commit` does not fail on empty diff; explicit guard is
               required.)
            4. **Configure git identity, then commit.**
               `claude-code-action@v1` does not pre-configure `git config
               user.name`/`user.email` inside the bash subprocess; without
               this step `git commit` aborts with "Author identity unknown."
               (This is the canonical pattern across Soleur's other scheduled
               workflows that push from inside `claude-code-action`.)
               Run:
               ```bash
               git config user.name "github-actions[bot]"
               git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
               git commit -m "chore(schedule): neutralize one-time workflow $WORKFLOW_NAME (post-fire cleanup, #$ISSUE_NUMBER)"
               ```
            5. **Push — direct first, PR fallback.**
               - **5a.** Try direct push:
                 `git push origin HEAD:${{ github.event.repository.default_branch }}`.
                 If exit 0, neutralization succeeded — go to step 6.
               - **5b.** If direct push fails (branch protection / required
                 status checks): **first check whether a stale neutralization
                 PR already exists** for this workflow:
                 `EXISTING=$(gh pr list --search "head:chore/neutralize-$WORKFLOW_NAME" --state open --json url --jq '.[0].url // empty')`.
                 If `$EXISTING` is non-empty, treat as a successful handoff
                 (the prior fire already filed a cleanup PR awaiting review)
                 — go to step 6 without opening a duplicate. Otherwise create
                 an ephemeral branch
                 `chore/neutralize-$WORKFLOW_NAME-$(date -u +%Y%m%d%H%M%S)`,
                 push it, then open a PR via
                 `gh pr create --base "${{ github.event.repository.default_branch }}" --head "$BRANCH" --title "chore(schedule): neutralize $WORKFLOW_NAME" --body "Auto-cleanup after one-time fire of #$ISSUE_NUMBER. Removes the schedule: trigger from the generated --once workflow file. See plugins/soleur/skills/schedule/SKILL.md (D4 defense)."`.
                 Then attempt auto-merge:
                 `gh pr merge --squash --auto "$PR_URL" 2>/tmp/merge.err`.
                 If `merge.err` contains `auto-merge is not allowed`, the user
                 repo has `allow_auto_merge: false` — the PR is open and
                 waiting on a human reviewer; that is still a successful
                 neutralization handoff (D3 catches any re-fire before the PR
                 lands).
            6. **Success.** No fallback comment posted; the task-result
               comment from the main work suffices.
            7. **Both legs failed.** If step 5a errored AND step 5b
               PR-creation errored (NOT auto-merge — auto-merge unavailability
               is acceptable), post the fallback comment to issue
               #$ISSUE_NUMBER with this exact body:
               "Workflow ran but auto-cleanup failed (direct push: <err>; PR
               create: <err>). Operator action required: edit
               `.github/workflows/$WORKFLOW_NAME` to remove the `schedule:`
               trigger (the same edit this run attempted), OR install the
               Anthropic Claude GitHub App as a bypass-actor on your default
               branch ruleset, OR install a custom GitHub App with `actions:
               write` and re-run with `gh workflow disable`."

            ## Pre-flight (abort with observation comment if any check fails)

            1. **Date guard (PRIMARY cross-year defense, D3):**
               First, refuse to run if `$FIRE_DATE` is empty or malformed:
               `[[ "$FIRE_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "FIRE_DATE empty or malformed: '$FIRE_DATE'"; <invoke neutralization primitive>; exit 0; }`
               Then assert the calendar match:
               `[[ "$(date -u +%F)" == "$FIRE_DATE" ]]` must be true. If false,
               invoke the Neutralization primitive above and exit 0. Take no
               other action.
               This is D3, the load-bearing defense against cron `0 9 <day> <month> *`
               re-firing every year. Cannot fail silently.
            2. **Idempotency:** if the workflow's `on:` block no longer
               contains `schedule:` (already neutralized), exit 0 immediately.
               No commit needed; the cron will not fire again from this file.
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
            #$ISSUE_NUMBER naming which check failed, then invoke the
            Neutralization primitive above and exit 0. Take no other action.

            ## Task

            Fetch the documented task spec from the referenced comment:

            `body=$(gh api "repos/${{ github.repository }}/issues/comments/$COMMENT_ID" --jq .body)`

            If `$body` is empty (`[[ -z "$body" ]]`), treat as a pre-flight failure: post observation comment "comment body is empty", invoke the Neutralization primitive, exit 0.

            Otherwise execute the documented work as instructed by `$body`. When complete, post results as a follow-up comment on issue #$ISSUE_NUMBER (re-verify `gh issue view "$ISSUE_NUMBER" --json repository_url` matches `${{ github.repository }}` immediately before posting — defends against issue-transfer-after-preflight).

            ## Final step (mandatory, last)

            Invoke the Neutralization primitive above. This is D4 — the
            secondary self-cleanup. D3 (the date guard above) is the primary
            cross-year defense; D3 is structural (cron AND date both must
            match) and cannot fail silently.

            Do NOT add any post-step to this workflow file —
            `claude-code-action` revokes the App token after this step, so a
            YAML-level cleanup would silently fail.
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
assert d['permissions']['contents'] == 'write', 'contents:write missing (D4 neutralization commit will fail)'
assert d['permissions']['pull-requests'] == 'write', 'pull-requests:write missing (D4 PR-fallback will fail)'
# Anti-regression (#3153): actions:write is NOT in the canonical template.
# The Anthropic GitHub App's installation manifest caps actions:* at READ;
# declaring actions:write at the workflow level cannot widen the App's
# effective scope and only creates false confidence for future maintainers.
assert 'actions' not in d['permissions'] or d['permissions']['actions'] != 'write', \
    'actions:write should not be in --once template (App token does not honor it; see #3153)'
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
- **`--once` D4 cleanup costs one extra GHA run on branch-protected repos.** When direct push to the default branch is blocked, D4's PR-fallback opens a cleanup PR. Required status checks fire on the ephemeral branch — that's one extra billable run per `--once` fire. To skip it, add `chore/neutralize-*` to your branch ruleset's bypass-actor list or disable required checks for that branch pattern.
- **`--once` D3 + D4-failure → annual re-fire.** If D4's neutralization fails (both direct push and PR-create fail) and the operator does not act on the fallback comment, the cron `0 9 D M *` re-fires next year on the same calendar date. D3 (date guard) catches it and immediately invokes neutralization again — no harmful action against drifted state — but the workflow stays `active` until either the operator intervenes or GHA's 60-day inactivity timer fires after a full quiet year.

## Sharp Edges

- **`--once` widens agent-prompt blast radius via `contents: write` + `pull-requests: write`.** The fire-time agent's `--allowedTools` allowlist plus the comment-fetched `$body` (D1) means a successful prompt-injection in the comment body now has push + PR-create capability, not just `gh workflow disable`. D5 (comment-author + immutability pin) gates this — but D5 only verifies *who* authored the comment, not *what* they wrote. **Pin `--comment` to a high-trust author** (yourself or an org admin), and avoid scheduling `--once` against issues where the pinned commenter could later be compromised.
