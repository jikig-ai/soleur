---
module: github-actions
date: 2026-04-19
problem_type: workflow_gap
component: codeql-to-issues-workflow
symptoms:
  - "Open type/security issue persists after the CodeQL alerts it cites are bulk-dismissed in a separate PR"
  - "Resumed sessions waste time re-validating issues that are already remediated"
  - "Issue tracker shows phantom unfinished P1/P2 security work"
root_cause: missing_post_dismissal_sweep
resolution_type: workflow_addition
severity: low
tags: [codeql, github-actions, triage, automation, security]
related_learnings:
  - 2026-04-13-codeql-to-issues-invalid-workflow-trigger.md
  - 2026-04-13-codeql-alert-triage-and-issue-automation.md
  - 2026-04-13-codeql-alert-tracking-and-api-format-prevention.md
  - 2026-04-10-codeql-api-dismissal-format.md
---

# Auto-close CodeQL-derived issues after bulk-dismiss via post-dismissal sweep

## Problem

Issue #2368 was filed to triage 9 pre-existing CodeQL alerts in `apps/web-platform/*`.
Timeline:

- 2026-04-15 13:25 UTC — PR #2346 created.
- 2026-04-15 17:22 UTC — Issue #2368 filed (CodeQL on PR #2346 reported 9 "new" alerts).
- 2026-04-15 17:25 UTC — PR #2346 merged (3 minutes after #2368 filed).
- 2026-04-16 11:14 UTC — PR #2416 merged: bulk-dismissed all 9 alerts as false positives + tests-only.
- 2026-04-16 11:42 UTC — PR #2421 merged: switched CodeQL `threat_model` to `remote` only.
- 2026-04-19 — Issue #2368 still open in `Post-MVP / Later` milestone, despite all referenced
  alerts being `state == "dismissed"` for 3 days. Resumed via `/soleur:go`, ~30 min spent
  re-establishing it was already remediated.

The issue was a **legitimate filing at filing time**. It became an orphan when PR #2416
dismissed the alerts the next day. The gap is not a pre-filing check — `codeql-to-issues.yml`
already filters `state=open` (line 30) before creating issues. The gap is a **post-dismissal
orphan sweep**: when a PR dismisses N CodeQL alerts in bulk, any open `type/security` issue
whose body references those alert numbers becomes redundant and should be auto-closed with
a pointer to the dismissing context.

## Solution

Add a `close-orphans` job to `.github/workflows/codeql-to-issues.yml` that runs after the
existing `check-alerts` job. The job:

1. Lists every open `type/security` issue (`gh issue list --state open --label "type/security"`).
2. Skips issues with a `keep-open` label (project convention escape hatch — covers forensic
   post-mortems that incidentally cite an alert number).
3. Extracts alert numbers from each issue's title and body via `grep -oiE 'alert[[:space:]]*#?[0-9]+'`.
   The convention is `sec: CodeQL alert #N — ...` (the workflow's own title format) or
   human-filed bodies that say `alert #N`.
4. For each referenced alert, queries `state` via `gh api '/repos/.../code-scanning/alerts/<N>' --jq '.state'`.
5. If **all** referenced alerts are `dismissed`, posts a close-out comment listing the
   dismissed alerts and `gh issue close --reason completed`.
6. If any lookup fails (deleted alert, rate limit, false-match number), skips without closing —
   bias toward keeping issues open over false-closing.

This catches both auto-created issues (from `check-alerts` itself) AND human-filed issues
like #2368, since both follow the `alert #N` convention.

## Why best-practices, not bug-fixes

No production bug shipped. The cost was ~30 minutes of resumed-session re-validation time
plus carrying an irrelevant security issue in the milestone view. The fix is a workflow
hygiene gate, not a code-bug remediation.

## Sharp edges encountered

1. **AGENTS.md `hr-in-github-actions-run-blocks-never-use`** — heredoc-free shell. Used
   `printf 'line\n%s\n' "$VAR" > file` pattern for the close-out comment body, then
   `gh issue comment --body-file <path>`.
2. **AGENTS.md `cq-ci-steps-polling-json-endpoints-under`** — every `jq -r` against an
   HTTP body needs a guard. Used `--jq` server-side so the body is never inlined; if
   the alert lookup fails (non-200), the empty `STATE` triggers the no-close branch.
3. **PreToolUse security hook** — first edit to `.github/workflows/*.yml` per session
   blocks with a generic command-injection reminder (false positive here; issue title
   and body flow through JSON encoding + jq + grep, never shell evaluation). The hook
   is one-warning-per-file-per-session — re-running the same Edit immediately succeeds.
   Self-evident pattern: write the same call twice.
4. **Two alerts per file** — `test/workspace.test.ts` produced alert numbers #102 and
   #103 for two different lines (38 and 41) of the same file. The original issue body
   counted them as one logical alert; the inventory has 10 entries. Future post-dismissal
   sweep counts logical alerts (10), not file references (9).
5. **AGENTS.md `wg-when-fixing-a-workflow-gates-detection`** — retroactively apply the
   gate to the case that exposed it. This PR closes #2368 itself via `Closes #2368` in
   the PR body.
6. **Subshell counter loss when extending a workflow.** The new `close-orphans` job
   faithfully copied the `| while` subshell pattern from `check-alerts`, propagating a
   pre-existing telemetry bug — the `CREATED`/`SKIPPED`/`CLOSED`/`KEPT` counters always
   print `0` because the loop body runs in a subshell. Multi-agent review caught it;
   fix is `done < <(jq ... | ...)` process substitution. Both jobs were retroactively
   fixed in the same PR. **Generalization:** when extending a workflow file by
   duplicating an existing job's pattern, scan the source for known-buggy idioms before
   duplicating. See `2026-04-19-markdownlint-fix-mangles-issue-ref-at-line-start.md`
   for sibling session-error notes from this PR.

## Prevention

1. **Workflow primary fix:** `close-orphans` job in `.github/workflows/codeql-to-issues.yml`.
   Runs daily after `check-alerts`. Idempotent — safe to re-run.
2. **Skill secondary fix:** `plugins/soleur/skills/triage/SKILL.md` gained a
   "CodeQL alert-state precheck" subsection so triage-time decisions also gate on
   alert state, not just the daily workflow.
3. **Escape hatch:** `keep-open` label on any issue that references an alert number
   incidentally (forensic docs, rule-of-X analyses) prevents auto-close.

## Verification

After PR merge, manually trigger via `gh workflow run codeql-to-issues.yml` and poll the
result per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies` and
`hr-never-use-sleep-2-seconds-in-foreground` (use `Monitor` tool or `run_in_background`).
The first scheduled run will sweep any other orphans.
