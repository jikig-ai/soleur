---
category: operations
tags: [scheduled-tasks, cloud, watchdog, claude-code-cloud, observability]
date: 2026-04-21
---

# Cloud Scheduled Tasks -- Silence Diagnosis and Restore Runbook

**Tracking issue:** #2714
**Watchdog workflow:** `.github/workflows/scheduled-cloud-task-heartbeat.yml`
**Migration context:** PR #1095 (issue #1094) migrated content-generator, campaign-calendar, and growth-audit execution from GitHub Actions to Claude Code Cloud scheduled tasks on 2026-03-25.
**Foundational learning:** `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`

## Symptom

The `scheduled-cloud-task-heartbeat` workflow opened a GitHub issue titled
`ops: <task> Cloud scheduled task has not fired in N days (watchdog)` with label
`cloud-task-silence`. OR: operator observed that a twice-weekly / daily / weekly
audit issue has not appeared in the expected window but the workflow is not yet
flagging (cadence below threshold).

The load-bearing signal is **absence of labeled audit issues**, not "the
workflow failed" — these tasks produce a `[Scheduled] <task> - <date>` issue on
every successful run (and a `FAILED` / `FAIL Citations:` issue on every errored
run). **Silence = neither success nor failure issue was created** = the task
did not run at all.

## When NOT to use this runbook

- **Task ran and errored.** A `FAILED` issue exists with the task's label. The
  watchdog correctly treats this as a signal (the task fired; fix the error
  inside the prompt, do not re-diagnose scheduling). Follow the prompt-fix
  procedure in `2026-04-03-content-cadence-gap-cloud-task-migration.md`.
- **Task ran manually.** `workflow_dispatch` runs also produce labeled audit
  issues, so the watchdog's label-based query counts them as signal. Manual
  runs mask schedule drift — the next scheduled fire is still the authoritative
  check.
- **Label exists but has never been applied.** The watchdog emits a warning
  (`::warning::no audit issues ever seen for <label> — skipping`) and does
  not flag silence. This is correct behavior for newly added tasks.

## Task Inventory

Nine tasks are monitored. Thresholds derived from observed natural cadence +
one cadence-cycle of slack; see Threshold Derivation below.

| Task | Execution surface | Schedule | Audit label | Threshold (days) |
|------|-------------------|----------|-------------|------------------|
| content-generator | Claude Code Cloud (`soleur-scheduled`) | Tue+Thu 10:00 UTC | `scheduled-content-generator` | 4 |
| community-monitor | Claude Code Cloud (`soleur-scheduled`) | Daily | `scheduled-community-monitor` | 2 |
| growth-audit | Claude Code Cloud (`soleur-scheduled`) | Weekly Mon | `scheduled-growth-audit` | 10 |
| campaign-calendar | GitHub Actions | Weekly Mon | `scheduled-campaign-calendar` | 10 |
| competitive-analysis | GitHub Actions | Monthly 1st | `scheduled-competitive-analysis` | 35 |
| roadmap-review | GitHub Actions | Monthly 1st | `scheduled-roadmap-review` | 35 |
| growth-execution | GitHub Actions | Bi-monthly (1st, 15th) | `scheduled-growth-execution` | 18 |
| seo-aeo-audit | GitHub Actions | Weekly Mon | `scheduled-seo-aeo-audit` | 10 |
| daily-triage | GitHub Actions | Daily | `scheduled-daily-triage` | 2 |

The Max plan caps the `soleur-scheduled` environment at **3 Cloud task
definitions**. Adding a 4th Cloud task evicts an existing one silently — this
is the top-priority risk the watchdog protects against.

## Diagnosis Checklist

Work hypotheses in order; each has a cheap verification step.

### H1 — Cloud task paused, deleted, or orphaned (most likely)

The Cloud task at `claude.ai/code` may have been paused during a failed run,
deleted during cleanup, or orphaned when the authenticated session expired.

**Verify:**

1. Log in to `claude.ai/code`.
2. Open the `soleur-scheduled` environment.
3. List tasks. Confirm the expected task exists with correct schedule and
   status `active`.

**Restore (H1):**

- If paused: un-pause in the UI.
- If deleted: re-create from the prompt preserved in
  `.github/workflows/scheduled-<task>.yml` (the GHA YAML was intentionally kept
  for rollback per migration spec TR5). Adapt the prompt per the 2026-04-03
  learning (frontmatter instruction must be present).
- If orphaned: re-authenticate the Cloud session; re-save the task if needed.

### H2 — Task runs but fails fast before the audit-issue step

A prompt-level error (plugin marketplace load, missing doppler CLI, invalid
queue format) may abort the task before the `create audit issue` step is
reached, producing zero artifacts.

**Verify:** In the Cloud task UI, inspect the last ~30 run logs. Look for
invocations during the silence window with non-zero exit, and read the first
error line.

**Restore (H2):** Fix the prompt's failure path so any abort path still creates
a labeled audit issue BEFORE exiting. Mirror the `STEP 1b / STEP 2 / STEP 3 /
STEP 4` early-exit guards in `scheduled-content-generator.yml` for parity.

### H3 — Doppler `prd_scheduled` service token rotated or revoked

Doppler service tokens are per-config. If the `prd_scheduled` service token was
rotated between fires, the Cloud setup script's `eval $(doppler secrets
download ...)` silently exports an empty environment and every subsequent
invocation fails before reaching the audit-issue step. See
`cq-doppler-service-tokens-are-per-config`.

**Verify:** `doppler configs tokens --project soleur --config prd_scheduled`.
Confirm a non-revoked token exists and its value matches the Cloud task env
var.

**Restore (H3):** Rotate the Doppler token, update the Cloud task env var,
dry-run the task.

### H4 — Concurrency deadlock / rate-limit suppression

`claude.ai/code` rate-limits concurrent task invocations. A hung prior
invocation can suppress subsequent fires. (Migration spec TR3 called this out;
monitoring was never implemented.)

**Verify:** Cloud task run history shows suppressed/skipped fires explicitly.

**Restore (H4):** Cancel stuck invocation(s). Re-queue. File a tracking issue
if this recurs — this is the ceiling case for the current deployment and
warrants a 2nd-gen Cloud task definition strategy.

### H5 — Task prompt parses a file whose format changed

The prompt's STEP 1 for content-generator parses
`knowledge-base/marketing/seo-refresh-queue.md`. A malformed row (missing
`generated_date` annotation, table-column drift) can loop the task on a parse
error.

**Verify:** `git log --oneline --since=<silence-start> -- knowledge-base/marketing/seo-refresh-queue.md`
and compare row formats against the prompt's expected pattern.

**Restore (H5):** Fix the file format. Re-run the task.

## Restore Procedure (generalized)

Based on the diagnosed H\* above:

1. **Apply the hypothesis-specific fix** (H1: unpause/recreate, H2: prompt
   patch, H3: doppler rotate, H4: requeue, H5: file fix).
2. **Manual dry-run** via "Run now" in the Cloud UI (Cloud tasks) or
   `gh workflow run scheduled-<task>.yml` (GHA tasks).
3. **Verify success signals** (for content-generator — adapt per task):
   - New issue with task's label created.
   - New PR matching the task's conventional-commit title pattern.
   - Distribution/artifact file frontmatter has correct `publish_date`,
     `status`, `channels` (per 2026-04-03 learning).
   - Eleventy build passes (if applicable).
4. **Record diagnosis + restoration** in a comment on the parent tracking
   issue (e.g., #2714 for the 2026-04-21 silence).
5. **Watchdog auto-closes** the `cloud-task-silence` issue on its next fire
   once the audit-issue label reappears below threshold.

## Threshold Derivation

Each threshold is observed-max-natural-gap + one cadence cycle of slack.
Documented here so a future operator can update without re-deriving.

| Task | Cadence | Max natural gap | Threshold | Slack |
|------|---------|-----------------|-----------|-------|
| content-generator | Tue+Thu | 5 days (Thu→Tue) | 4 | -1 (tight — see below) |
| community-monitor | Daily | 1 day | 2 | +1 day |
| growth-audit | Weekly Mon | 7 days | 10 | +3 days |
| campaign-calendar | Weekly Mon | 7 days | 10 | +3 days |
| competitive-analysis | Monthly 1st | ~31 days | 35 | +4 days |
| roadmap-review | Monthly 1st | ~31 days | 35 | +4 days |
| growth-execution | Bi-monthly | 16 days | 18 | +2 days |
| seo-aeo-audit | Weekly Mon | 7 days | 10 | +3 days |
| daily-triage | Daily | 1 day | 2 | +1 day |

**Why content-generator is aggressive (4 days):** The prior silence incident
was 21 days. A conservative threshold (e.g., 7 days) defeats the point of the
watchdog. 4 days covers exactly one missed Thu→Tue fire with ~24h headroom
before alert. If a single upstream transient (Anthropic API blip, WebSearch
failure, Cloud rate-limit) knocks out one fire, the watchdog opens one issue
and auto-closes on the next successful fire — sustainable noise level (~1
issue/week worst case).

## Updating the Watchdog

When a new scheduled task is added:

1. Add a row to the `TASKS` array in
   `.github/workflows/scheduled-cloud-task-heartbeat.yml` in the format
   `task-name:audit-issue-label:max_gap_days`.
2. Add a matching row to the Task Inventory and Threshold Derivation tables
   above.
3. Verify the label exists (`gh label list | grep <label>`); create if
   missing.
4. Dispatch the workflow manually (`gh workflow run scheduled-cloud-task-heartbeat.yml`)
   and confirm the new row is processed without a silence flag.

When a task is removed: delete the row from both the TASKS array and this
runbook's tables in the same PR.

## Dedup Contract

The watchdog's open-silence-issue lookup and auto-close lookup both depend on
**exact-prefix match against the title template**. Breaking either half of
this contract will cause duplicate issues or missed auto-closes.

- **Title template (load-bearing):**

  ```text
  ops: <task> Cloud scheduled task has not fired in <N> days (watchdog)
  ```

  where `<task>` is the first colon-delimited field of the `TASKS` row in
  `.github/workflows/scheduled-cloud-task-heartbeat.yml` (the task slug,
  e.g., `content-generator`). `<N>` is the computed day count.

- **Dedup token:** `<task>` (the task slug). The watchdog's
  `find_silence_issue()` helper narrows via GitHub search `"<task> in:title"`
  then filters to titles satisfying `startswith("ops: <task> ")`. The
  trailing space is significant — it is what prevents a prefix collision
  between, e.g., `content-generator` and a future `content-generator-v2`.

- **Label contract:** Every watchdog-opened issue carries the
  `cloud-task-silence` label. The helper filters on this label before
  applying the title prefix — removing the label detaches an issue from
  dedup.

## Warnings

- **Do NOT edit the title of an open `cloud-task-silence` issue.** Stripping
  the `ops: <task>` prefix (including the trailing space) or changing the
  `<task>` slug will break dedup and cause the next run to open a duplicate.
  Add a comment instead.
- **Do NOT remove the `cloud-task-silence` label.** The helper filters on
  this label; an issue without it is invisible to `find_silence_issue()`.
- **Task-name prefix collisions are guarded in code, not convention.** The
  helper uses `startswith("ops: <task> ")` so `content-generator` does NOT
  false-match `content-generator-v2`. New tasks can share prefixes, but
  avoid it anyway for human clarity.
- **Label-based query includes manual dispatches.** A `workflow_dispatch` run
  produces a labeled audit issue and counts as signal. If the schedule is
  broken but operators keep running manually, the watchdog will NOT fire.
  Weekly review of the actual schedule (cron vs. dispatch) is the backstop.

## References

- Migration PR: #1095
- Migration plan: `knowledge-base/project/plans/2026-03-24-feat-scheduled-tasks-cloud-migration-plan.md`
- Migration spec: `knowledge-base/project/specs/archive/20260325-003628-feat-scheduled-tasks-migration/`
- Silence-detection plan: `knowledge-base/project/plans/2026-04-21-fix-scheduled-content-generator-cloud-task-silence-plan.md`
- Prior incident learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
- Doppler token-scope learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Peer watchdog pattern: `.github/workflows/scheduled-cf-token-expiry-check.yml`
- AGENTS.md rules: `cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`, `hr-in-github-actions-run-blocks-never-use`, `hr-github-actions-workflow-notifications`, `cq-gh-issue-label-verify-name`, `cq-gh-issue-create-milestone-takes-title`.
