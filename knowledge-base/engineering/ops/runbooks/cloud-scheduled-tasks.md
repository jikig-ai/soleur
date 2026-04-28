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

### H6 — Sub-agent auth inheritance (check FIRST if prompt invokes `/soleur:*` skills)

Cloud Routine sub-agent sessions (spawned by `/soleur:content-writer --headless`, `/soleur:social-distribute --headless`, or any other `/soleur:*` skill invocation inside the routine prompt) do NOT inherit GitHub MCP / Doppler auth from the top-level routine session. Any `gh pr create` / `gh issue create` / `gh pr merge` call made after a sub-agent returns operates in an unauthenticated context and silently fails. The Cloud Routines UI still reports "Success" because the MCP loop terminated cleanly.

**Signature (load-bearing):** run history shows SUCCESS rows in the silence window, BUT `gh pr list` and `gh issue list` scoped to the same date range both return `[]`. Content files may have been generated locally and branches may have been pushed via the git proxy — but no GitHub API side effects occurred.

**Verify (do this BEFORE H1):**

1. Cross-check the routine's run history against `gh pr list --state all --search "created:<silence-start>..<silence-end>"` and `gh issue list --state all --search 'created:<silence-start>..<silence-end> "<label>"'`. If the routine shows runs but GitHub shows zero artifacts → H6 confirmed.
2. Open a single SUCCESS-marked session in Claude Code UI and scroll to the end. Look for model-output strings: `"Doppler returned Forbidden"`, `"GitHub MCP tools unavailable"`, `"gh CLI unauthenticated"`, `"git proxy handles only git operations"`.
3. Compare against a peer routine (e.g., Daily Issue Triage) that invokes `gh` directly from top-level prompt — if peer succeeds and target fails, the sub-agent boundary is the differentiator.

**Restore (H6):**

Revert to GitHub Actions scheduling (the only reliable fix — Cloud Routines do not expose a way to pass auth into sub-agent sessions). Mirror the pattern from Growth Audit rollback PR #2050 / Content Generator rollback PR #2744:

1. In `.github/workflows/<task>.yml`, uncomment the `schedule: - cron: ...` block that was disabled during the #1095 Cloud migration.
2. Via `claude.ai/code/routines/<id>`: toggle Active → off, rename to `<Task Name> (DISABLED — migrated back to GHA)` for historical reference.
3. After PR merge, trigger a manual `gh workflow run <task>.yml` to verify the restored GHA path end-to-end.

**Affected tasks (as of 2026-04-21):** content-generator (this PR), growth-audit (#2050 — already reverted), community-monitor (currently Paused, H6 remediation pending if/when re-enabled).

**Why this is H6 not H1:** H1 assumes the routine is paused/deleted/orphaned — visible in Cloud UI as Inactive or missing. H6 presents as Active + running on schedule + UI-reported Success. The runbook's original H1-H5 set was authored from the pre-rebrand "Scheduled Tasks" model; H6 emerged from the #2742 diagnosis after the UI's rename to "Routines". See `knowledge-base/project/learnings/2026-04-21-cloud-routine-subagent-auth-inheritance-H6.md` for full diagnosis.

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

### H7 — GHA-scheduled-task max-turns starvation

GHA-scheduled tasks (campaign-calendar, competitive-analysis, roadmap-review,
growth-execution, seo-aeo-audit, daily-triage) invoke
`anthropics/claude-code-action` with a `--max-turns` budget. If the budget is
too tight for the task's plugin overhead (~10 turns) + task work (per-step
turn estimate) + error buffer (~5 turns), the agent reaches max turns
mid-STEP and the GHA workflow exits with a `failure` conclusion. The
audit-issue step is typically the LAST step (PR persist), so a starved run
produces zero artifacts → silent gap → watchdog flags after threshold.

**Signature:**

- GHA run conclusion: `failure`
- Run log contains: `Reached maximum number of turns (N)`
- Latest audit issue (label-based query) is older than threshold

**Verify:** `grep -E '\-\-max-turns' .github/workflows/scheduled-*.yml`,
read each row, compute against the 2026-03-20 ratio table.

**Fix:** Raise `--max-turns` to peer median (40), and raise
`timeout-minutes` proportionally (≥ 0.75 min/turn). See
`knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md`.

**Reference incident:** PR #2974 — campaign-calendar at `--max-turns 20`
failed on 2026-04-27 with 3 overdue items to file (#2968/#2969/#2970);
issue #2968 was an exact-title duplicate of the still-open #2146 (filed
2026-04-13), which motivated the STEP 2 dedup logic. The schedule-fire on
2026-04-20 ran at the wall (`num_turns: 21`) and produced no audit issues,
triggering the watchdog (#2896) on 2026-04-25. Fix raised budget to
`--max-turns 40` + `timeout-minutes: 30` (0.75 min/turn ratio) and added
STEP 2 dedup + STEP 2.5 heartbeat issue.

### H8 — Frontmatter parser truncates multi-colon values (`awk -F': '`)

Workflow STEP 2 dedup logic compares a frontmatter-derived title against
existing-issue titles via `gh issue list --search "\"$CANONICAL_TITLE\" in:title"`.
If the parser truncates the title at an inner `: ` or leaves a trailing
quote artifact, the search returns no match — dedup misfires and a fresh
duplicate issue is filed each run. Two failure modes share the root cause:

1. **`awk -F': '` field-split.** Sets the awk Field Separator to `: `;
   `$2` returns only the chunk between the first and second `: `. A title
   like `"Show HN: Soleur — agents that call APIs"` parses as `Show HN`.
2. **`sub(/^"|"$/, "", s)` regex alternation.** POSIX `sub()` replaces
   ONE match. Alternation `^"|"$` matches the leading `"` first; the
   trailing `"` survives untouched. `Agents That Use APIs, Not Browsers"`
   carries the trailing quote into the canonical title.

**Signature:**

- New audit issues filed with titles missing inner-colon content
  (`[Content] Overdue: Show HN (was scheduled for …)`).
- New audit issues with trailing `\"` artifact in the canonical title.
- Existing canonical issues remain open in parallel — DEDUP counter
  never increments for those slots.

**Verify:**

```bash
for f in knowledge-base/marketing/distribution-content/*.md; do
  title=$(awk -F': ' '/^title:/{sub(/^"|"$/,"",$2); print $2; exit}' "$f")
  echo "$(basename "$f") | [$title]"
done | grep -E '\["?(Show HN|[^"]*"$)'
```

Any line with `[Show HN]` (truncated) or `…"]` (trailing-quote) is broken.

**Fix:** Replace the FS-based parser with `match() + substr()` and use
TWO `sub()` calls per quote style:

```bash
TITLE_RAW=$(awk 'match($0, /^title: ?/) {
  s = substr($0, RLENGTH + 1)
  sub(/^"/, "", s); sub(/"$/, "", s)
  sub(/^'\''/, "", s); sub(/'\''$/, "", s)
  print s; exit
}' "$FILE")
```

`match()` + `substr()` are POSIX awk and run on `mawk 1.3.4` (GHA
`ubuntu-latest` default), `gawk`, and BSD `nawk`. Fix applies anywhere
a workflow extracts a frontmatter scalar — copy this template instead
of re-deriving an FS-based parser.

**Limitations:** does NOT handle YAML block scalars (`title: >-`) or
multi-line folded strings. The corpus does not currently use them; if
a future content file does, audit the parser before merging.

**Reference incident:** issue #2987 — campaign-calendar run 25043177327
(2026-04-28) filed duplicates #2982/#2983/#2984 against existing
canonical audits #2146/#2969/#2970. Root cause: STEP 2 step (a) inline
parser carried the FS-based form forward from PR #2974. Fixed in
PR #<this-PR> (closes #2987); duplicates closed as duplicate-of-bug
post-merge per `wg-when-fixing-a-workflow-gates-detection`.

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
