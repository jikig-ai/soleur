---
title: Cloud-task silence detection via label-cadence watchdog
date: 2026-04-21
category: workflow-issues
tags: [github-actions, observability, scheduled-tasks, claude-code-cloud, watchdog, bash, strict-mode]
---

# Learning: Detect silence in scheduled tasks by monitoring audit-issue cadence, not task-runtime signals

## Problem

On 2026-03-25 (PR #1095), three scheduled GitHub Actions workflows (content-generator, campaign-calendar, growth-audit) were migrated from GHA cron to Claude Code Cloud scheduled tasks in the `soleur-scheduled` environment. The migration succeeded: manual dispatches and the first ~week of scheduled fires produced expected audit issues.

Then `content-generator` went silent on 2026-03-31. For 21 days, no audit issue appeared with label `scheduled-content-generator`. Neither a `[Scheduled] Content Generator - <date>` success issue nor a `FAILED - <date>` error issue — the task simply did not run. Peer Cloud tasks (`community-monitor`, `growth-audit`, `campaign-calendar`) kept firing reliably during the same window, so this was not a platform-wide failure.

The issue was only noticed when #2714 was filed during a manual audit — four weeks after first silence.

## Root cause (class of problem, not this instance)

Cloud scheduled tasks live outside the GHA observability surface. When the task runs and errors, it produces a labeled audit issue (a "signal present" event). When the task fails to run at all (paused, deleted, orphaned session, rate-limited, auth expired), there is **nothing to observe** — no GHA run, no Sentry event, no error log, no notification email. The only usable signal is the **absence of the expected artifact**.

The migration plan preserved the GHA YAML for rollback but shipped zero monitoring for the new execution surface. The 2026-04-03 cadence-gap learning (`knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`) already identified the class of risk; Prevention step 3 proposed "automated overdue detection" but was never implemented.

## Solution

Build a GHA watchdog that treats "no labeled audit issue in N days" as the fault signal:

```yaml
# scheduled-cloud-task-heartbeat.yml (simplified)
- for each (task, label, max_gap_days) in hardcoded TASKS array:
-   gh issue list --label <label> --state all --limit 5 --json createdAt
-   jq guard for non-JSON response (plaintext 5xx, rate-limit HTML)
-   if last createdAt older than max_gap_days: open "cloud-task-silence" issue
-   else if open silence issue exists: auto-close with recovery comment
```

Key design choices:

- **Label-based, not run-based.** Queries GitHub Issues by label rather than workflow-run API — Cloud tasks have no GHA run surface, but every task-prompt ends with `gh issue create --label <task-label>`, so the label is the only cross-surface signal.
- **Exact-prefix dedup.** `find_silence_issue()` helper does `gh issue list --label cloud-task-silence --search "$task in:title" --json number,title --jq '.[] | select(.title | startswith("ops: \($task) ")) | .number'`. The trailing space in `"ops: <task> "` blocks prefix-collisions (`content-generator` won't false-match `content-generator-v2`).
- **Recovery auto-close.** When a silenced task starts firing again, the watchdog closes its own open issue with a recovery comment — prevents "open forever" anti-pattern.
- **Per-task thresholds with slack.** Threshold = observed-max-cadence-gap + one-cycle-slack. content-generator's threshold is deliberately tight (4 days) because the prior silence was 21 days; a conservative threshold defeats the point.
- **Warnings, not errors, on ambiguous states.** `::warning::no audit issues ever seen for <label> — skipping` for newly-added tasks. `::warning::non-JSON response` for transient API blips. Neither crashes the step.

Full implementation: `.github/workflows/scheduled-cloud-task-heartbeat.yml`. Operator runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`.

## Key Insight

**When migrating scheduled work to a new execution surface, build the absence-of-artifact watchdog BEFORE relying on the migration.** Success-case monitoring ("the task ran and errored") is insufficient — the failure mode you most need to catch is "the task did not run at all," and that mode has no runtime signal to observe. The only reliable proxy is the expected output being missing.

This is a specific instance of a general pattern: **in any system where the absence of output is a valid failure mode, build monitoring around output cadence, not runtime telemetry.** It's why cron-sentry services exist (dead-man's-switch pattern). The watchdog here is the same pattern scoped to GitHub issue labels.

## Related pitfall: strict-mode arithmetic comparison on non-numeric

The plan's Test Scenario T10 asserted that a malformed TASKS row (e.g., missing colons) would be "caught by threshold comparison" and skipped. In practice:

```bash
set -euo pipefail
days_since=5
max_gap_days="malformed-string"
[[ "$days_since" -gt "$max_gap_days" ]]  # CRASHES the step under -e
```

Bash's `-gt` expects numeric operands. With a non-numeric right-side and `set -e` active, the whole step dies — the subsequent `continue` the plan assumed would fire never runs. QA caught this pre-merge (commit `dc57a601`); the fix is an explicit regex guard before the comparison:

```bash
if [[ -z "$label" || "$label" == "$task" || ! "$max_gap_days" =~ ^[0-9]+$ ]]; then
  echo "::warning::malformed TASKS row: $task_row — skipping"
  continue
fi
```

**Generalization:** When writing a test scenario that says "bad input is caught by <operator>", verify the operator's behavior under `set -euo pipefail`. Common operators that crash instead of catch under strict mode: `-gt`/`-lt`/`-eq` on non-numeric, `$(( ))` on non-numeric, `${var?}` under unset. See also `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` for sibling pitfalls (bare positional args, pipefail turning off silent-fallback patterns).

## Prevention

1. **Migration gate:** any PR that moves scheduled work to a new execution surface must ship an artifact-cadence watchdog in the same PR (not a follow-up).
2. **Audit-issue labels are a contract.** Every scheduled-task prompt must produce a labeled audit issue on BOTH success and failure paths. Silent exits are the failure mode the watchdog was built to detect — don't normalize them.
3. **Threshold documentation co-located with watchdog.** Threshold-derivation table lives in the runbook next to the TASKS array; drift between the two is flagged by cross-reference comments in the workflow.
4. **Strict-mode trap:** For any bash workflow with `set -euo pipefail`, validate numeric shell vars before arithmetic comparison. `[[ "$n" =~ ^[0-9]+$ ]]` is one line and prevents a class of crashes.

## Session Errors

- **`security_reminder_hook.py` rejected first `Write` of `scheduled-cloud-task-heartbeat.yml` with advisory output, not an explicit deny.** Identical-content retry succeeded. Same pattern on first `Edit` of `scheduled-content-generator.yml`. Root cause unclear — the hook's own response contract (`.claude/hooks/security_reminder_hook.py` lines 11-15) says "safe edit → exit 0, no stdout". The advisory text fired even though no `github.event.*` sinks were present in the new content. Recovery: retry. Prevention: if the false-positive rate is material in practice, file an issue to tighten the hook's regex; otherwise the retry cost is acceptable.
- **T10 edge case not caught by plan.** Plan T10 said a malformed TASKS row would be "caught by threshold comparison"; under `set -euo pipefail`, bash arithmetic on non-numeric crashes instead of catches. QA phase caught it pre-merge. Recovery: explicit regex guard (commit `dc57a601`). Prevention: when deepening a test scenario that claims "bad input is caught by <operator>", verify the operator actually catches vs crashes under strict mode (see skill-route proposal below).
- **Test-polluted label description.** T7 label-idempotency test created `cloud-task-silence` with placeholder description `"already exists"`; required `gh label edit` to restore correct description. Recovery: `gh label edit --description`. Prevention: use a throwaway label name for idempotency tests, or gate first-run label creation behind a test fixture rather than the real label.

## References

- Issue: #2714
- PR: #2716
- Foundational learning: `knowledge-base/project/learnings/2026-04-03-content-cadence-gap-cloud-task-migration.md`
- Sibling strict-mode learnings: `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`, `knowledge-base/project/learnings/2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`
- Peer watchdog pattern: `.github/workflows/scheduled-cf-token-expiry-check.yml`
- Runbook: `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md`
- AGENTS.md: `cq-ci-steps-polling-json-endpoints-under`, `cq-workflow-pattern-duplication-bug-propagation`
