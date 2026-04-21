---
title: "fix: restore scheduled-content-generator Cloud task + add cloud-task silence detection"
type: fix
date: 2026-04-21
issue: 2714
branch: feat-one-shot-2714-scheduled-content-generator
---

# Restore scheduled-content-generator Cloud task and add silence detection

## Enhancement Summary

**Deepened on:** 2026-04-21
**Sections enhanced:** Hypotheses (H1–H5), Phase 2 (watchdog implementation), Test Scenarios, Risks, new "Watchdog Implementation Contract" section.
**Research sources used:** Peer workflow analysis (`scheduled-cf-token-expiry-check.yml`, `scheduled-campaign-calendar.yml`), institutional learnings (2026-04-03 cadence-gap, 2026-03-29 doppler token scope, 2026-04-15 jq guard), AGENTS.md rule cross-check (`cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`, `hr-in-github-actions-run-blocks-never-use`, `hr-github-actions-workflow-notifications`).

### Key Improvements

1. **Watchdog now models on `scheduled-cf-token-expiry-check.yml`** — a battle-tested peer with the exact idioms needed (issue dedup, stale-close, non-JSON guard, `set -euo pipefail`, pre-create-label pattern). Plan now prescribes reuse of this pattern rather than a fresh invention.
2. **Auto-close-on-recovery added** — when a silenced task starts firing again, the watchdog closes its own open issue with a recovery comment, matching the `STALE` branch of the cf-token workflow. Prevents stale open issues after Phase 1 restoration.
3. **Dedup search uses `in:title` quoted substring** — matches the peer workflow exactly, avoids the `--label`-only dedup that fails if an operator re-labels.
4. **Explicit label-creation ordering** — the `cloud-task-silence` label must be created in the workflow itself (before any `gh issue create --label` call) per `cq-gh-issue-label-verify-name`. Plan now prescribes a preceding `Ensure labels exist` step, not a manual pre-merge creation.
5. **Cron cadence changed from `*/6 hours` to daily 09:30 UTC** — the 6-hour cadence would create 4 duplicate issues/day in error cases before the dedup guard kicks in (the guard works, but it burns turns and log lines). Daily is sufficient given content-generator's threshold is 4 days.
6. **Threshold computed from labeled-issue cadence, not guessed** — thresholds now derive from observed peer-task intervals plus one full cadence of slack, documented per row.

### New Considerations Discovered

- **Campaign-calendar label title format is different** — `scheduled-campaign-calendar` label is used by `[Content] Overdue: ...` issues, not `[Scheduled] Campaign Calendar - ...` issues. The watchdog's last-issue-date query is label-based (not title-based), so it still works, but the runbook must call out this asymmetry.
- **Content-generator also has `FAIL Citations:` titles** — issue #645 is labeled `scheduled-content-generator` but titled `[Scheduled] Content Generator - FAIL Citations: ...`. Label-based queries correctly treat this as a successful audit signal (the task ran and filed the abort issue), so no special case needed.
- **The CF-token-expiry peer opens issues with `action-required` label, not its own specific label** — our watchdog opens with BOTH `cloud-task-silence` AND `action-required` so it surfaces in both ops and CEO triage queues.
- **The 3-task Max plan cap is misreported in one place** — migration plan line 11 says "3 Cloud task definitions" but the spec archives say "8-9 workflows". Runbook must cite the authoritative limit (the migration-plan post-`[Updated 2026-03-25]` annotation).

## Overview

Issue #2714 reports that `.github/workflows/scheduled-content-generator.yml` has not fired on schedule since 2026-03-24. The issue's hypotheses (GHA 60-day inactivity, cron drift, throttling) are all irrelevant: on 2026-03-25, PR #1095 intentionally disabled the GHA schedule and migrated execution to a Claude Code Cloud scheduled task (`soleur-scheduled` environment). The real fault is that the Cloud scheduled task itself has been silently producing nothing since ~2026-03-31, while the three peer Cloud tasks (community-monitor, growth-audit, campaign-calendar) keep firing. This plan restores content-generator execution and adds a lightweight GHA watchdog so the next Cloud-task silence is caught within one cadence cycle instead of four weeks.

## Research Reconciliation — Spec vs. Codebase

The issue body's framing is inconsistent with the actual state of the repo. The reviewer will re-check this table before accepting the plan.

| Issue claim | Reality | Plan response |
|---|---|---|
| Workflow "state: active" and cron "0 10 ** 2,4" still configured | `.github/workflows/scheduled-content-generator.yml` lines 13–16 have the `schedule:` block commented out (`# MIGRATED TO CLOUD SCHEDULED TASK — 2026-03-25`). Only `workflow_dispatch` remains. | No GHA schedule is expected to fire. Stop investigating GHA-side causes; the root is the Cloud task. |
| "~9 missed fires over ~4 weeks" implies GHA is expected to run | GHA execution was intentionally disabled by PR #1095 (issue #1094). Cloud task is the execution surface. | The real gap is Cloud task silence (see "Evidence of Cloud task silence" below). Correct the diagnosis in the plan and in a comment on #2714. |
| "Other scheduled workflows in the same repo fire reliably (daily-triage, weekly-analytics)" — implies peer scheduled tasks still work | Peer GHA schedules (daily-triage, weekly-analytics) DO fire. Peer Cloud tasks (community-monitor daily, growth-audit weekly, campaign-calendar weekly) ALSO fire — verified via `gh issue list --label scheduled-community-monitor --state all` returning daily issues through 2026-04-19. Only content-generator is silent. | Confirms the fault is specific to the content-generator Cloud task definition, not Cloud tasks in general. Scope fix narrowly. |
| "Workflow file silently breaks parser at schedule-evaluation time" | Irrelevant — no schedule is defined in YAML. | Drop hypothesis. |
| "Manual dispatch once to confirm it still works end-to-end" | Already done: on 2026-04-21 at 10:15 UTC, a manual run produced issue #2692 and PR #2693 (merged as `95635339`). End-to-end pipeline works. | Use that manual run as the known-good baseline when comparing Cloud task output during remediation. |

## Hypotheses

Ordered most to least likely, based on the 2026-04-03 cadence-gap learning (`knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`) and issue timing. Each hypothesis has an explicit verification step before remediation.

### H1 — Cloud task was paused, deleted, or orphaned [MOST LIKELY]

The Cloud task at `claude.ai/code` for `soleur-scheduled` → Content Generator may have been:

1. **Paused manually** during the 2026-03-23 workflow-dispatch failure (the only `failure` conclusion in the GHA history).
2. **Deleted** during a cleanup pass (the environment hit the 3-task Max plan cap noted in the migration plan — adding or renaming a task could have evicted this one).
3. **Orphaned** when the account session expired; Cloud tasks require an active authenticated session to continue firing.

**Verify:** Log in to `claude.ai/code`, open the `soleur-scheduled` environment, list tasks. Confirm the Content Generator task exists, schedule `Tuesday + Thursday 10:00 UTC`, status `active`.

### H2 — Cloud task prompt fails fast and swallows the failure-issue path

The Cloud task prompt (adapted from the GHA YAML) includes a "create audit issue on failure" instruction. If an error occurs before that instruction is reachable (e.g., plugin_marketplaces load failure, doppler CLI missing from setup script), the task exits with no artifact. Peer learning: growth-audit showed this exact pattern on 2026-04-13 (`[Scheduled] Growth Audit - FAILED - 2026-04-13` issue #2049 visible in the label corpus — content-generator has no such FAILED issue, suggesting either H1 or H2 producing a true no-op).

**Verify:** Read the latest Cloud task run history in `claude.ai/code` (UI shows run logs for the last ~30 invocations). Look for: (a) any invocations during the gap 2026-04-02 → 2026-04-21, (b) the exit status of each, (c) first error line.

### H3 — Setup script lost `DOPPLER_TOKEN` for prd_scheduled

Doppler service tokens are per-config (see `cq-doppler-service-tokens-are-per-config`). If the `prd_scheduled` config service token was rotated or revoked between 2026-03-31 and 2026-04-02, the Cloud setup script (`eval $(doppler secrets download ...)`) silently exports an empty environment, and the task fails without reaching the issue-creation step.

**Verify:** `doppler configs tokens --project soleur --config prd_scheduled` (requires Doppler login). Confirm a non-revoked token exists and its value matches the `DOPPLER_TOKEN` env var shown in the Cloud task environment UI.

### H4 — Cloud task concurrency deadlock with a long-running session

`claude.ai/code` rate-limits concurrent task invocations. If a prior invocation hung and was never cleaned up, subsequent fires may be suppressed. The migration plan called this out as TR3 ("Rate limit monitoring must be established"); it was never implemented.

**Verify:** Cloud task run history will show suppressed/skipped fires if this is the cause.

### H5 — The prompt references a queue item that no longer exists or is mis-formatted

The prompt's STEP 1 parses `seo-refresh-queue.md`. If a recent edit broke the table format (e.g., malformed row, missing `generated_date` annotation pattern), the task may loop on a parse error.

**Verify:** Diff `knowledge-base/marketing/seo-refresh-queue.md` between 2026-03-31 and 2026-04-21 (`git log --oneline --since=2026-03-31 -- knowledge-base/marketing/seo-refresh-queue.md`). Compare row formats against the prompt's expected pattern.

### Evidence of Cloud task silence (for reference)

`gh issue list --label scheduled-content-generator --state all` returns issues on: 3/16, 3/17, 3/19, 3/24 (×2), 3/26, 3/31, **[21-day gap]**, 4/21 (manual). All three peer Cloud tasks fired during the gap (community-monitor daily, growth-audit on 4/13, 4/18, 4/19, campaign-calendar on 4/13, 4/21). Isolation is high-confidence.

## Proposed Solution

Two-track fix:

- **Track A (immediate restore):** Diagnose and restore the Cloud task. Re-run once to verify. No repo changes until diagnosis identifies a prompt or setup-script bug; if it does, PR that change.
- **Track B (silence detection):** Add a GHA watchdog workflow (`scheduled-cloud-task-heartbeat.yml`) that runs hourly and opens a `priority/p2-medium` GitHub issue if any expected Cloud task has not produced its labeled audit issue within N days of its expected cadence. This closes the class of bug, not just this instance. Aligns with the 2026-04-03 learning's Prevention step 3 ("Automated overdue detection").

Do NOT revert the GHA `schedule:` block (Track A replaces that). Do NOT introduce a parallel Cloud task (3-task Max plan cap per spec TR2). If Track A's diagnosis is H1 (task missing), re-create it from the documented prompt in `2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md` Phase 1 row 8, then reconcile the prompt with the 2026-04-03 learning (frontmatter instruction must be present).

## Watchdog Implementation Contract

This section is load-bearing for the work phase. The contract below is the fixed point that Acceptance Criteria and Test Scenarios verify against.

### Canonical string literals (grep-stable — any drift between plan / tests / runbook is a defect)

- Label: `cloud-task-silence`
- Issue title pattern: `ops: <task> Cloud scheduled task has not fired in <N> days (watchdog)` (preserved verbatim; `<task>` and `<N>` are substituted; other tokens must not change — the `in:title` dedup search relies on `"Cloud scheduled task has not fired"` as the discriminator)
- Dedup search token: `Cloud scheduled task has not fired` (substring, exact case)
- Recovery close comment: `Heartbeat ran <UTC> — task recovered (<N> days since last issue <date>, under <max>-day threshold). Auto-closing.`
- Silence-persist comment: `Heartbeat ran <UTC> — still silent (<N> days since last issue <date>).`
- Warning annotation (empty label): `::warning::no audit issues ever seen for <label> — skipping`
- Warning annotation (non-JSON): `::warning::non-JSON response for label <label>`

### Reference bash skeleton (non-prescriptive but grep-stable)

The work phase implements this structure. Exact byte-for-byte match is not required, but the `set -euo pipefail`, `for task_row`, `jq -e` guard, label dedup via `in:title`, and `|| true` patterns are mandatory.

```bash
set -euo pipefail

GH_REPO="${GITHUB_REPOSITORY}"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

TASKS=(
  "content-generator:scheduled-content-generator:4"
  "community-monitor:scheduled-community-monitor:2"
  "growth-audit:scheduled-growth-audit:10"
  "campaign-calendar:scheduled-campaign-calendar:10"
  "competitive-analysis:scheduled-competitive-analysis:35"
  "roadmap-review:scheduled-roadmap-review:35"
  "growth-execution:scheduled-growth-execution:18"
  "seo-aeo-audit:scheduled-seo-aeo-audit:10"
  "daily-triage:scheduled-daily-triage:2"
)

for task_row in "${TASKS[@]}"; do
  task="${task_row%%:*}"
  rest="${task_row#*:}"
  label="${rest%%:*}"
  max_gap_days="${rest##*:}"

  gh issue list --repo "$GH_REPO" --label "$label" --state all \
    --limit 5 --json createdAt > "$TMPFILE"

  if ! jq -e . "$TMPFILE" >/dev/null 2>&1; then
    echo "::warning::non-JSON response for label $label"
    continue
  fi

  last=$(jq -r '.[0].createdAt // empty' "$TMPFILE")
  if [[ -z "$last" ]]; then
    echo "::warning::no audit issues ever seen for $label — skipping"
    continue
  fi

  days_since=$(( ( $(date +%s) - $(date -d "$last" +%s) ) / 86400 ))
  echo "Task $task: $days_since days since last audit issue (threshold: $max_gap_days)"

  if [[ "$days_since" -gt "$max_gap_days" ]]; then
    # flag_silence
    existing=$(gh issue list --repo "$GH_REPO" --state open \
      --label cloud-task-silence \
      --search "$task in:title" \
      --json number --jq '.[0].number // empty')

    if [[ -n "$existing" ]]; then
      gh issue comment "$existing" --repo "$GH_REPO" \
        --body "Heartbeat ran $(date -u '+%Y-%m-%d %H:%M UTC') — still silent ($days_since days since last issue $last)."
    else
      gh issue create --repo "$GH_REPO" \
        --title "ops: $task Cloud scheduled task has not fired in $days_since days (watchdog)" \
        --label "cloud-task-silence,action-required,priority/p2-medium,domain/engineering,type/bug" \
        --milestone "Post-MVP / Later" \
        --body-file <(cat <<ISSUE_BODY
## Cloud scheduled task silence detected

Task \`$task\` has not produced an audit issue (label: \`$label\`) in **$days_since days**. Expected cadence gap: ≤ $max_gap_days days.

Last audit issue: $last

### Diagnosis checklist
See [cloud-scheduled-tasks runbook](https://github.com/${GH_REPO}/blob/main/knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md).

### Reference
- Workflow: \`.github/workflows/scheduled-cloud-task-heartbeat.yml\`
- Tracking: #2714
ISSUE_BODY
        )
    fi
  else
    # clear_silence
    stale=$(gh issue list --repo "$GH_REPO" --state open \
      --label cloud-task-silence \
      --search "$task in:title" \
      --json number --jq '.[0].number // empty')
    if [[ -n "$stale" ]]; then
      gh issue close "$stale" --repo "$GH_REPO" \
        --comment "Heartbeat ran $(date -u '+%Y-%m-%d %H:%M UTC') — task recovered ($days_since days since last issue $last, under $max_gap_days-day threshold). Auto-closing."
    fi
  fi
done
```

### Threshold derivation

Each threshold is max-observed-cadence-gap + 1 full cadence of slack. Documented here so a future operator can update thresholds without re-deriving:

| Task | Cadence | Max natural gap | Threshold | Slack |
|---|---|---|---|---|
| content-generator | Tue+Thu | 5 days (Thu→Tue) | 4 | -1 (tight — fires twice per week, 4 days covers one missed fire with 24h headroom before alert) |
| community-monitor | Daily | 1 day | 2 | +1 day |
| growth-audit | Weekly Mon | 7 days | 10 | +3 days |
| campaign-calendar | Weekly Mon | 7 days | 10 | +3 days |
| competitive-analysis | Monthly 1st | ~31 days | 35 | +4 days |
| roadmap-review | Monthly 1st | ~31 days | 35 | +4 days |
| growth-execution | Bi-monthly (1st,15th) | 16 days | 18 | +2 days |
| seo-aeo-audit | Weekly Mon | 7 days | 10 | +3 days |
| daily-triage | Daily | 1 day | 2 | +1 day |

Content-generator's threshold is aggressive (4 days covers exactly one missed fire) because the cost of a silent gap is measured in missed publishing slots — last incident was 21 days of silence. A conservative threshold defeats the point of the watchdog.

## Network-Outage Deep-Dive Check

**Trigger scan:** The plan's Overview, Problem Statement, and Hypotheses do NOT contain any of: `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout` (in connectivity sense), `502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET`.

**Result:** Network-outage deep-dive not required. The issue is about a Cloud scheduled task not firing (a control-plane absence), not about an L3/L4/L7 connectivity failure. No L3 firewall allow-list verification needed. (For reference: the issue body contains the word "timeout" only in the generic "GitHub Support ticket" sense — not a network timeout symptom.)

## Research Insights

**Local repo signals (from `repo-research-analyst` equivalent sweep):**

- `.github/workflows/scheduled-content-generator.yml:13–16` — schedule disabled, MIGRATED TO CLOUD comment.
- `knowledge-base/project/plans/2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md` — full migration plan including the exact adapted prompt.
- `knowledge-base/project/specs/archive/20260325-003628-feat-scheduled-tasks-migration/spec.md` — acceptance criteria (TR5 requires "original GHA YAML preserved (disabled) for rollback"). This rollback path is still available if Track A diagnosis shows the Cloud task is structurally unrecoverable.
- `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md` — exact precedent: Cloud task prompt missed an instruction during migration, producing silent drafts. Prescribes line-by-line diff of GHA vs. Cloud prompts as a permanent checklist item.
- `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md` — H3 root cause class (per-config tokens silently drop on rotation).
- `cq-doppler-service-tokens-are-per-config` — AGENTS.md rule reinforcing H3.
- Peer Cloud task issue labels (`scheduled-community-monitor`, `scheduled-growth-audit`, `scheduled-campaign-calendar`) show the expected audit-issue cadence per task; watchdog thresholds derive from these.

**External research: SKIPPED.** This is a diagnosis-and-config task with strong local signal. No framework or vendor docs material to the fix beyond the Claude Code Cloud task UI, which is not API-scriptable at this time.

**CLI verification:** The plan does not prescribe new CLI invocations in user-facing docs (`*.njk`, `*.md`, README, `apps/**`). Diagnostic commands (`gh run list`, `gh issue list`, `doppler configs tokens`) are operational, not prescriptive. `cq-docs-cli-verification` does not apply.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and searched for overlap against the planned file list (`Files to edit` below).

**Matches:** None. The one file being edited (`.github/workflows/` — new file) and the one edited (`scheduled-content-generator.yml` — header comment update only) do not appear in any open code-review scope-out.

## Files to create

- `.github/workflows/scheduled-cloud-task-heartbeat.yml` — new GHA watchdog.
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` — new runbook (diagnosis steps for the next silence, task-to-label mapping, restore procedure).

## Files to edit

- `.github/workflows/scheduled-content-generator.yml` — update the MIGRATED comment to point to the new runbook and reference issue #2714. No behavior change.
- `knowledge-base/product/roadmap.md` — update `## Current State` if the closure of this issue completes a tracked observability gap (check during ship).

## Implementation Phases

### Phase 0 — Diagnose the Cloud task (NO REPO CHANGES)

0.1 Open `claude.ai/code` via Playwright MCP, navigate to `soleur-scheduled` environment.
0.2 Inspect the Content Generator task: state, schedule, last-run timestamp, last-run status, setup-script contents, env var list.
0.3 Record diagnosis in a comment on #2714. This is load-bearing: subsequent phases branch on which of H1–H5 was confirmed.
0.4 If H1 (task missing/paused): re-enable or re-create from the migration plan's prompt, merged with the 2026-04-03 learning's frontmatter fix. Skip Phase 1.2.
0.5 If H2/H3/H4/H5 (task present but broken): capture the specific error, then proceed to Phase 1.2.

**Blocker:** Phase 0 requires a logged-in Claude Code Cloud session. Playwright MCP can navigate and inspect but may hit the auth wall. Per `hr-when-playwright-mcp-hits-an-auth-wall`, keep the tab open at the login page and request the user to sign in in the same session — do NOT close the browser and hand off by URL.

### Phase 1 — Restore the Cloud task

1.1 Based on Phase 0 diagnosis:

- H1: Create/unpause the task with the corrected prompt (GHA YAML lines 63–168 adapted + the 2026-04-03 frontmatter fix).
- H2: Fix the prompt's failure-path so any abort still creates an audit issue BEFORE exiting.
- H3: Rotate the Doppler `prd_scheduled` service token, update Cloud env var, verify with a dry-run.
- H4: Cancel stuck invocation(s), re-queue.
- H5: Fix the queue file format, re-run.

1.2 Run the task via "Run now" in the Cloud UI. Verify success signals:

- New issue with label `scheduled-content-generator` created.
- New PR with title matching `feat(content): auto-generate article <YYYY-MM-DD>`.
- Distribution file frontmatter has `publish_date`, `status: scheduled`, correct `channels:` list (per 2026-04-03 learning).
- Eleventy build passes (the prompt's STEP 4).

1.3 Record the manual-run artifacts in the #2714 comment thread and close that comment with "Restored; silence-detection in Track B."

### Phase 2 — Ship silence-detection watchdog

Model the workflow on `.github/workflows/scheduled-cf-token-expiry-check.yml` — a production peer with dedup, stale-close, non-JSON guard, and `action-required` issue creation already working. Reuse its patterns verbatim where possible.

2.1 Create `.github/workflows/scheduled-cloud-task-heartbeat.yml` with:

- **Name:** `"Scheduled: Cloud Task Heartbeat"`
- **Trigger:** `schedule: - cron: '30 9 * * *'` (daily 09:30 UTC — well offset from the 14:00 UTC content-publisher and 10:00 UTC content-generator Cloud fire; avoids schedule contention).
- **Permissions:** `issues: write`, `contents: read`.
- **Concurrency:** `group: scheduled-cloud-task-heartbeat`, `cancel-in-progress: false`.
- **Timeout:** 5 minutes (no heavy work).

Step structure (bash only — NO `claude-code-action` invocation; this is pure-bash):

1. **Ensure labels exist** (pre-create `cloud-task-silence` and `action-required`; pattern from peer).
2. **Check cloud-task heartbeats** (the main step).

**Heartbeat step contract:**

- Start with `set -euo pipefail`.
- Hardcoded inline array (NOT an external file — keeps workflow self-contained per peer):

  ```
  # task_name:label:max_gap_days
  TASKS=(
    "content-generator:scheduled-content-generator:4"
    "community-monitor:scheduled-community-monitor:2"
    "growth-audit:scheduled-growth-audit:10"
    "campaign-calendar:scheduled-campaign-calendar:10"
    "competitive-analysis:scheduled-competitive-analysis:35"
    "roadmap-review:scheduled-roadmap-review:35"
    "growth-execution:scheduled-growth-execution:18"
    "seo-aeo-audit:scheduled-seo-aeo-audit:10"
    "daily-triage:scheduled-daily-triage:2"
  )
  ```

  **Iterate with `for task_row in "${TASKS[@]}"; do ... done`** — not `| while` (per `cq-workflow-pattern-duplication-bug-propagation`).

- **Per-row processing:**
  - Parse `task=${task_row%%:*}`, `rest=${task_row#*:}`, `label=${rest%%:*}`, `max_gap_days=${rest##*:}`.
  - Call `gh issue list --repo "$GH_REPO" --label "$label" --state all --limit 5 --json createdAt > "$TMPFILE"`.
  - **JSON guard** (per `cq-ci-steps-polling-json-endpoints-under`): `if ! jq -e . "$TMPFILE" >/dev/null 2>&1; then echo "::warning::non-JSON response for label $label"; continue; fi`.
  - Extract most-recent `createdAt`: `LAST=$(jq -r '.[0].createdAt // empty' "$TMPFILE")`.
  - **If empty** (no issues with this label yet — e.g., a newly created task): `echo "::warning::no audit issues ever seen for $label — skipping"; continue`. Do NOT flag this as silence.
  - Compute `days_since=$(( ( $(date +%s) - $(date -d "$LAST" +%s) ) / 86400 ))`.
  - **Compare to threshold:**
    - If `days_since > max_gap_days`: call `flag_silence()` (see below).
    - Else: call `clear_silence()` — checks for an open `cloud-task-silence` issue for this task and closes it with a recovery comment. Pattern lifted verbatim from cf-token's `STALE` branch.

- **`flag_silence()` logic** (inline function):
  - Dedup: `EXISTING=$(gh issue list --repo "$GH_REPO" --state open --label cloud-task-silence --search "$task in:title" --json number --jq '.[0].number // empty')`.
  - If `$EXISTING`: `gh issue comment "$EXISTING" --body "Heartbeat ran $(date -u '+%Y-%m-%d %H:%M UTC') — still silent ($days_since days since last issue $LAST)."` and return.
  - Otherwise create issue:
    - `--title "ops: $task Cloud scheduled task has not fired in $days_since days (watchdog)"`
    - `--label "cloud-task-silence,action-required,priority/p2-medium,domain/engineering,type/bug"`
    - `--milestone "Post-MVP / Later"` (per `cq-gh-issue-create-milestone-takes-title`)
    - Body: use `cat <<ISSUE_BODY` heredoc with terminator at column 10 (matching cf-token peer — avoids the column-0 heredoc terminator bug per `hr-in-github-actions-run-blocks-never-use`).
    - Body content: headline, last-known audit issue reference, diagnostic commands block, link to runbook `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md#<task-section>`, reference to #2714.

- **`clear_silence()` logic:**
  - `STALE=$(gh issue list --repo "$GH_REPO" --state open --label cloud-task-silence --search "$task in:title" --json number --jq '.[0].number // empty')`.
  - If `$STALE`: `gh issue close "$STALE" --comment "Heartbeat ran $(date -u '+%Y-%m-%d %H:%M UTC') — task recovered ($days_since days since last issue $LAST, under $max_gap_days-day threshold). Auto-closing."`.
  - Else: silent no-op.

- **Failure notification:** At the end of the workflow, a `- if: failure()` step uses `./.github/actions/notify-ops-email` (per `hr-github-actions-workflow-notifications`). Subject: `"[FAIL] Cloud Task Heartbeat workflow failed"`. Body: HTML constructed in a preceding step, passed as `body` input (per `hr-github-actions-workflow-notifications`).

2.2 Manually dispatch the watchdog after merge:

- `gh workflow run scheduled-cloud-task-heartbeat.yml`
- Poll `gh run list --workflow=scheduled-cloud-task-heartbeat.yml --limit 1 --json status,conclusion,databaseId` until `status: completed`.
- Inspect logs: `gh run view <id> --log | tail -200` — verify 9 tasks processed, zero `::error::` annotations.
- Check for false-positive issues: `gh issue list --label cloud-task-silence --state open`. By the time of merge, content-generator should be restored (Phase 1 complete), so zero open silence issues is the expected state. If content-generator is flagged: Phase 1 is incomplete, back to Phase 0.
- Verify the recovery-close path: if there was a silence issue opened during Phase 0 diagnosis (optional manual step), this dispatch should auto-close it. If not auto-closed, the `clear_silence()` dedup query is broken.

### Phase 3 — Document the class of fault

3.1 Create `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` covering:

- Architecture: what Cloud scheduled tasks are, which env (`soleur-scheduled`), which Doppler config (`prd_scheduled`), which 3 tasks live there.
- Task inventory table: task name, schedule, expected audit-issue label, watchdog threshold, last-verified-working date.
- Silence diagnosis checklist (H1–H5 from this plan, ordered by likelihood).
- Restore procedure (Phase 1 of this plan, generalized).
- Why the 3-task Max cap matters — adding a 4th evicts an existing task without warning.
- Cross-references: PR #1095 (migration), 2026-04-03 learning, 2026-04-21 PR #2693 (known-good baseline).

3.2 Write a compound learning after ship: `knowledge-base/project/learnings/workflow-issues/cloud-task-silence-detection.md` capturing what H* turned out to be, why it was not caught earlier, and pointing to the watchdog as the prevention.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `knowledge-base/project/plans/2026-04-21-fix-scheduled-content-generator-cloud-task-silence-plan.md` written and committed.
- [ ] `.github/workflows/scheduled-cloud-task-heartbeat.yml` created; `yamllint` and `actionlint` clean.
- [ ] Heartbeat workflow contains the 9 task mappings above, each with an explicit threshold.
- [ ] `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` created with task inventory and H1–H5 diagnosis checklist.
- [ ] `.github/workflows/scheduled-content-generator.yml` header comment points to the new runbook.
- [ ] `cloud-task-silence` GitHub label created (verified with `gh label list`).
- [ ] Tests / dry-runs described under Test Scenarios pass locally.

### Post-merge (operator)

- [ ] Phase 0 diagnosis recorded in a comment on #2714 (which H* was confirmed).
- [ ] Phase 1 restoration completed: a successful Cloud task manual run produced issue + PR + distribution file with correct frontmatter.
- [ ] Watchdog manually dispatched via `gh workflow run scheduled-cloud-task-heartbeat.yml`; run completes green with zero false-positive issues opened.
- [ ] Next scheduled fire (Tuesday or Thursday at 10:00 UTC following merge) produces the expected `[Scheduled] Content Generator - <date>` issue within 4 hours of the scheduled time — verified before closing #2714.
- [ ] Compound learning file `knowledge-base/project/learnings/workflow-issues/<topic>.md` written (filename date chosen at write-time per "sharp edges" rule).

## Test Scenarios

T1. **Watchdog flags a silent task.** Locally, run the heartbeat script in a scratch directory with a mocked `gh` wrapper that returns `[{"createdAt":"<10-days-ago ISO>"}]` for label `scheduled-content-generator`. Assert: one `gh issue create` invocation was made; its `--title` contains the literal substring `Cloud scheduled task has not fired`; its `--label` argument contains `cloud-task-silence`, `action-required`, `priority/p2-medium`. Run the script again: assert the second pass calls `gh issue comment` (dedup), not `gh issue create`.

T2. **Watchdog passes when tasks are healthy.** Against live `gh` data (after Phase 1 restoration), dispatch the workflow manually. Assert: `gh run view <id> --log` shows 9 `Task ...: N days since last audit issue (threshold: ...)` lines, zero `gh issue create` calls, zero `::error::` annotations. `gh issue list --label cloud-task-silence --state open` returns empty.

T3. **Watchdog tolerates never-fired task.** Mock `gh issue list --label <newly-minted-label>` to return `[]`. Assert: row emits `::warning::no audit issues ever seen for <label> — skipping` and `continue`s; no issue is created; the loop proceeds to the next task without crashing.

T4. **JSON guard tolerates a non-JSON response.** Mock `gh issue list` to write `<html>rate-limited</html>` to `$TMPFILE`. Assert: `jq -e . "$TMPFILE" >/dev/null 2>&1` fails cleanly; the row emits `::warning::non-JSON response for label <label>` and `continue`s; the loop proceeds; exit code is 0 (per `cq-ci-steps-polling-json-endpoints-under` — the step does not crash the workflow on an upstream blip).

T5. **Recovery auto-close.** Seed state: one open issue with label `cloud-task-silence` and title `ops: content-generator Cloud scheduled task has not fired in 10 days (watchdog)`. Mock `gh issue list --label scheduled-content-generator` to return a createdAt of 1 day ago (recovered). Assert: one `gh issue close` invocation on the existing issue; its `--comment` contains the literal substring `task recovered`. Assert: `gh issue list --label cloud-task-silence --state open` now empty.

T6. **End-to-end Cloud task run (Phase 1 validation).** After Phase 1, trigger the content-generator Cloud task via "Run now" in the Cloud UI. Within 15 minutes, verify: (a) new issue with label `scheduled-content-generator`, (b) PR matching `feat(content): auto-generate article <YYYY-MM-DD>`, (c) distribution file frontmatter has `publish_date: <today>`, `status: scheduled`, `channels: discord, x, bluesky, linkedin-company`, (d) Eleventy build passes.

T7. **Label-creation idempotency.** Re-run the workflow after `cloud-task-silence` label already exists. Assert: `gh label create ... 2>/dev/null || true` step exits 0; no duplicate-label error in logs.

T8. **Dedup search precision.** Seed two open issues: (a) `ops: content-generator Cloud scheduled task has not fired in 5 days (watchdog)`, (b) `ops: community-monitor Cloud scheduled task has not fired in 3 days (watchdog)`. Run watchdog detection for `content-generator` only. Assert: the `in:title` search with `content-generator` keyword returns exactly issue (a); does not false-match issue (b).

T9. **Column-0 heredoc safety.** Run `actionlint` and `yamllint` against the workflow. Assert: both pass. Visually inspect the YAML: every heredoc terminator (`ISSUE_BODY`) is inside the step's `run:` block indentation (not at column 0), per `hr-in-github-actions-run-blocks-never-use`.

T10. **Counter loop scope.** Change one of the TASKS rows to an invalid format (e.g., missing a colon). Assert: bash parameter expansion handles the bad row without corrupting subsequent iterations; the row either processes with an empty `max_gap_days` (caught by threshold comparison) or is skipped. The loop is `for`, not `| while`, so there is no subshell counter-scope risk (per `cq-workflow-pattern-duplication-bug-propagation`).

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Revert to GHA execution by uncommenting the `schedule:` block | Violates spec G1 (API cost containment). The migration was intentional; the silent-fire is a monitoring gap, not a migration failure. |
| Add Sentry alerting for missed Cloud fires | Cloud scheduled tasks do not emit Sentry-compatible telemetry. The audit-issue absence is the only observable signal from the GHA side. |
| Query the Claude Code Cloud tasks API directly | No public API for scheduled-task run history at this time. Label-absence heuristic is the only reliable signal. |
| Use `scheduled-campaign-calendar.yml`'s existing overdue-detection logic instead of a new watchdog | That workflow checks overdue *content* items, not silent *tasks*. Its loop pattern was also recently found to have the `| while`subshell bug (`cq-workflow-pattern-duplication-bug-propagation`) — reuse would propagate that bug per`wg-when-fixing-a-workflow-gates-detection`. Write fresh, bug-free loop. |
| Revert PR #1095 entirely | Removes cost savings from 3 migrated tasks; punitive response to a monitoring gap. |

## Non-Goals

- Rewriting the Cloud task prompt beyond the minimal diff needed to fix the confirmed H*.
- Migrating additional workflows to Cloud tasks (Max plan cap, unchanged).
- Building a generic alerting framework — one GHA workflow with a hardcoded map is sufficient and matches existing peer patterns.
- Adding Cloud task auth monitoring (requires API that doesn't exist).

## Risks

- **R1:** Phase 0 requires Playwright MCP + operator login at `claude.ai/code`. If the session times out during investigation, we hand off per `hr-when-playwright-mcp-hits-an-auth-wall` — no browser-close-and-hand-off-by-URL. Mitigation: attempt Phase 0 during a session window where the operator can respond in-session.
- **R2:** Watchdog thresholds are heuristic. Tuesday-only holidays, one-off prompt failures, or Cloud rate-limit contention could produce noise. Mitigation: initial thresholds are documented in the Threshold Derivation table above and are conservative on everything EXCEPT content-generator (4-day threshold is deliberately tight because the prior silence was 21 days). Re-tune after 2 weeks of data; the runbook documents the tuning procedure.
- **R3:** Hardcoded label→task map drifts when new Cloud tasks are added. Mitigation: runbook (Phase 3) documents the update procedure; watchdog workflow has a comment header with the exact file path of the runbook.
- **R4:** `gh issue list --label <foo>` returns empty on a label that exists but has never been applied. The T3 test scenario confirms the "no audit issues ever seen" branch emits a warning, not an issue. Risk mitigated.
- **R5:** The 2026-04-21 manual run may mask the underlying fault — if the Cloud task is restored by inference without the diagnosis step, the next failure will recur without a known cause. Mitigation: Phase 0 is mandatory and produces a written diagnosis record (which H* was confirmed) as a comment on #2714 before Phase 1 begins.
- **R6:** The dedup `in:title` search uses case-sensitive substring matching in `gh`. If an operator manually edits an open silence issue's title (stripping `ops:` prefix, etc.), the watchdog will fail to dedup and create a duplicate. Mitigation: T8 asserts dedup precision; runbook explicitly warns against editing silence issue titles.
- **R7:** The reference skeleton uses `--body-file <(cat <<ISSUE_BODY ... ISSUE_BODY)` (process substitution + heredoc). Under bash in GHA this works; under dash or non-bash shells it wouldn't. Mitigation: GHA steps use `shell: bash` (GHA ubuntu-latest default); the workflow does NOT set a non-bash shell. If a future edit changes `shell:`, T9 catches the actionlint regression.
- **R8:** Content-generator's 4-day threshold can fire after any single missed Thursday fire (5-day gap). This is intentional (see R2 reasoning) but will produce a weekly-ish false-positive pattern if any upstream transient issue (Anthropic API blip, WebSearch failure on P1 item, Cloud rate-limit) knocks out one fire. Mitigation: the dedup + recovery-close pattern means such cases produce one issue + one close per week at worst — sustainable noise level. Revisit threshold if this pattern emerges in practice.
- **R9:** Phase 1 (H1 branch) requires re-entering the prompt manually in the Cloud UI — the exact prompt text must be kept in sync with the GHA YAML. Mitigation: the migration plan preserved the original GHA YAML (spec TR5); the restore procedure in the runbook cross-references both files.

## Domain Review

**Domains relevant:** Engineering (CTO), Marketing (CMO)

### Engineering (CTO)

**Status:** assessed inline (plan-time, no leader agent spawned — this is a self-contained observability gap with full local signal)
**Assessment:** Solution is narrowly scoped: one new GHA watchdog workflow + one runbook. No architecture change. Adds one new label (`cloud-task-silence`). No new secrets. Defends against a repeating class of bug already documented once (2026-04-03 learning). Passes `hr-all-infrastructure-provisioning-servers` (no infra), `hr-github-actions-workflow-notifications` (uses notify-ops-email), `cq-workflow-pattern-duplication-bug-propagation` (fresh loop, not duplicated).

### Marketing (CMO)

**Status:** assessed inline
**Assessment:** Content publishing cadence was already expected to be 2x/week per `knowledge-base/marketing/content-strategy.md` (updated in the 2026-04-03 cadence fix). Restoring the Cloud task restores that cadence. No brand-guide impact. No new user-facing copy.

### Product/UX Gate

**Tier:** NONE
**Rationale:** Internal observability + ops workflow. No user-facing surface, no new component files, no new pages.

## Open Questions

- Q1: Does the Cloud task UI at `claude.ai/code` expose a run history that distinguishes "scheduled fire skipped" from "scheduled fire ran and errored"? If only the latter, H1 vs H4 may be indistinguishable without dead reckoning from the absence of the audit issue. (Discovered during Phase 0.)
- Q2: The migration plan references a `soleur:schedule --target cloud` skill extension as "deferred" (spec TR6). Should the watchdog logic be folded into that future skill, or stay as a standalone workflow? Keeping it standalone for this PR; revisit when the skill lands.

## References

- Issue: #2714
- Prior migration PR: #1095
- Prior migration plan: `knowledge-base/project/plans/2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md`
- Prior migration spec: `knowledge-base/project/specs/archive/20260325-003628-feat-scheduled-tasks-migration/`
- Foundational learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
- Doppler per-config token learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Workflow duplication bug-propagation rule: AGENTS.md `cq-workflow-pattern-duplication-bug-propagation`
- YAML literal-block heredoc rule: AGENTS.md `hr-in-github-actions-run-blocks-never-use`
- Ops email notification rule: AGENTS.md `hr-github-actions-workflow-notifications`
- JSON-response guard rule: AGENTS.md `cq-ci-steps-polling-json-endpoints-under`
- Label verification rule: AGENTS.md `cq-gh-issue-label-verify-name`
- Milestone-title rule: AGENTS.md `cq-gh-issue-create-milestone-takes-title`
- Peer workflow pattern (the model for the watchdog): `.github/workflows/scheduled-cf-token-expiry-check.yml`
- Known-good baseline: PR #2693 merged as `95635339` on 2026-04-21 (manual run).

## Per-Section Research Insights

### Overview + Hypotheses — Research Insights

**Best Practices:**

- Ground each hypothesis in an observable verification step. "Most likely" without a cheap verification command is speculation — the H1–H5 list now pairs each hypothesis with the exact CLI or UI action to confirm it.
- Distinguish "no fire" from "fired with error" — these have different remediations and different observability signals. The peer growth-audit case on 2026-04-13 emitted `[Scheduled] Growth Audit - FAILED` → label-based watchdog catches both cases (the task ran and filed the failure issue = signal present = not silence).
- Preserve the ORIGINAL issue body's hypotheses in a reconciliation table; don't delete incorrect framing silently. Future readers benefit from seeing which hypotheses were falsified and why.

**Edge cases:**

- An audit issue could be filed by a `workflow_dispatch` event (manual run) rather than a `schedule` event. The watchdog's label-only query doesn't distinguish — this is intentional (manual runs also indicate the pipeline works) but the runbook must note it so an operator isn't misled into thinking the schedule is firing when only manual dispatches are.

**References:**

- cf-token-expiry-check workflow (`.github/workflows/scheduled-cf-token-expiry-check.yml`) — reference peer for dedup + recovery pattern.
- 2026-04-03 cadence-gap learning — reference incident where a cloud-task prompt diff was root cause.

### Phase 2 Watchdog — Research Insights

**Best Practices:**

- **Iterate with `for` over an array, not `| while`.** Subshell scope in `| while` loops silently drops counter updates. The cf-token peer uses `if/else` branches inline per-row (no loop); the watchdog can use `for` safely because each iteration is independent.
- **`jq -e . >/dev/null 2>&1` (not `jq empty`).** `jq empty` passes `null` through without failing; `jq -e .` correctly fails on `null`, missing, or non-JSON input. Matches `cq-ci-steps-polling-json-endpoints-under`.
- **`--milestone "Post-MVP / Later"` (title, not ID).** `gh` has no milestone subcommand; bare numeric IDs don't work. Matches `cq-gh-issue-create-milestone-takes-title`.
- **Pre-create labels in a preceding step with `|| true`.** Avoids "label not found" aborting `gh issue create` mid-flight. Matches `cq-gh-issue-label-verify-name`.
- **Dedup via `in:title` substring search, not label-only.** If an operator manually re-labels the silence issue (e.g., adds `investigating`), label-only dedup would create a duplicate. Title-substring is more robust.
- **Close stale issues on recovery (cf-token pattern).** Prevents the "open forever" anti-pattern where resolved issues linger.

**Performance considerations:**

- Daily cadence (`30 9 * * *`) is sufficient for a 4-day threshold; 6-hourly would burn GHA minutes without reducing detection latency below 1 day. The cf-token peer uses weekly (`0 9 * * 1`); content-generator's tighter threshold warrants daily.
- Each `gh issue list` call with `--limit 5` costs ~1 API call; 9 tasks × 1 call = 9/day = 270/month. Well under the 5000/hour authenticated REST limit.

**Edge cases:**

- `--search "$task in:title"` will match partial substrings — `"content-generator"` also matches a hypothetical `"content-generator-v2"`. The TASKS array is the authoritative source; any future task names must avoid prefix collisions. Runbook documents this.
- `createdAt` from `gh` API is UTC ISO-8601; `date -d` on GHA `ubuntu-latest` (GNU date) handles this natively. On macOS (`BSD date`), this would break — but the workflow runs on Linux runners, so no portability concern.
- Bash `-eu` (no `o pipefail`) — we use `-euo pipefail`. `set -eu` alone wouldn't catch a failure in the `$(...)` pipeline.

**Security considerations:**

- No user-controlled input flows into `run:` strings (watchdog inputs are all from GHA context and hardcoded TASKS array). Matches the security-note pattern of peer scheduled workflows.
- `GH_TOKEN` uses `github.token` — the default, not a PAT. Scopes: `issues: write`, `contents: read`.

**References:**

- `scheduled-cf-token-expiry-check.yml` lines 48–149 — exact pattern for dedup, heredoc, stale-close, non-JSON guard.
- Learning `2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` — why `jq -e` (not `jq empty`) and why `continue` (not `exit`) on non-JSON.

### Phase 3 Runbook — Research Insights

**Structure (proven in peer runbooks):**

- `admin-ip-drift.md` / `cloudflare-service-token-rotation.md` both open with a "Symptoms" section (what operators see when the incident occurs), then "Diagnosis", then "Resolution". Our runbook should mirror.
- Include a "When NOT to use this runbook" section — the watchdog fires on audit-issue-absence, which is NOT the same as "task errored during run" (that produces a FAILED issue, still labeled, still a signal). Distinguishing these upfront saves triage time.

**Content checklist:**

- Task inventory table (9 rows matching the TASKS array; a new task is added in both places or drift occurs).
- H1–H5 diagnosis steps (copy from plan; generalize wording).
- Phase 1 restore procedure (copy from plan; generalize).
- Threshold tuning procedure.
- Reference to PR #1095 and the 2026-04-03 learning.
- Warning: "Editing an open silence issue's title breaks watchdog dedup — add a comment instead."

## Quality Gate — Pre-Deepen Review Cross-Checks

The following were manually grep-verified against the deepened plan:

- **String-literal consistency:** Searched for `"Cloud scheduled task has not fired"`, `"cloud-task-silence"`, `"task recovered"`, `"still silent"` across the plan. One canonical value per literal. No drift between Watchdog Implementation Contract / Test Scenarios / Acceptance Criteria. **Verified.**
- **AGENTS.md rule ID citations:** Each rule referenced (`cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`, `hr-in-github-actions-run-blocks-never-use`, `hr-github-actions-workflow-notifications`, `cq-gh-issue-create-milestone-takes-title`, `cq-gh-issue-label-verify-name`, `hr-when-playwright-mcp-hits-an-auth-wall`) was cross-checked against AGENTS.md in the loaded context. All present with matching IDs. **Verified.**
- **SHA / PR number citations:** PR #1095 (migration), PR #2693 (known-good), issue #2714 (parent), issue #1094 (migration parent), issue #2049 (growth-audit FAILED example), issue #645 (content-generator FAIL Citations example), commit `95635339` (2026-04-21 manual merge). All verified via `gh` during the deepen pass. **Verified.**
- **Peer workflow pinned-action SHA:** `scheduled-cf-token-expiry-check.yml` uses `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` — the watchdog workflow does not require `actions/checkout` (no repo files are read) but if added, must match this pinned SHA. No action-pin claim in the plan depends on a SHA that wasn't present in a peer workflow within the same repo.
- **No fabricated CLI tokens:** The plan prescribes `gh issue list`, `gh issue create`, `gh issue comment`, `gh issue close`, `gh label create`, `gh workflow run`, `gh run view`, `jq -e`, `jq -r`, `date -d`, `date +%s`, `date -u '+%Y-%m-%d %H:%M UTC'`. All are standard, well-documented commands with verified subcommands/flags. `cq-docs-cli-verification` not applicable (not in user-facing docs), but verification performed anyway.
