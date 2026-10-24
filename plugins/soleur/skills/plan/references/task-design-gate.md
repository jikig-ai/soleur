# Task-Design Gate (Conditional) — canonical contract

Loaded by plan §2.9.3 (emit) and deepen-plan §4.13 (halt). This file is the
CANONICAL copy of the gate contract; the `## Task Design` schema blocks in
`plan-issue-templates.md` (all three templates, after `## Encryption Posture`)
are verbatim copies.

Every plan that creates a NEW autonomous-task surface MUST emit a `## Task Design`
section — one `task:` list item per created task. **Create-time only**: never a
retrofit onto existing `scheduled-*.yml` workflows or Inngest functions.

## Detection

A `## Files to Create` entry matching, OR a `## Files to Edit` entry adding a new
registered check (a `CHECK_REGISTRY` key in
`apps/web-platform/server/inngest/functions/event-scheduled-reminder.ts` or an
arming record for a named-check):

- `\.github/workflows/scheduled-.*\.yml`
- any new non-`_`-prefixed `\.ts` under `apps/*/server/inngest/functions/` — the
  functions-dir convention prefixes shared code with `_` (`_cron-shared.ts`), so
  a new non-`_` file IS a function (`cron-*`, `oneshot-*`, `event-*`, or future)

## Required schema (canonical)

```yaml
tasks:
  - task:            # name/slug of the autonomous task being created
    trigger:         # what fires it — cron / event / label / dispatch / upstream run
    services:        # services or data surfaces it reads from and writes to
    next:            # what it triggers next ("nothing" is a valid answer)
    human_reentry:   # how a human resumes, redirects or stops it mid-run
    dedupe:          # mechanism preventing semantic double-work — MUST name something beyond
                     # `concurrency: group:` (it serializes overlapping RUNS, not the work itself)
    source_dedupe:   # how the ticket source dedupes this task, or the literal "not a ticket source"
  # one `- task:` list item per created task
```

## Reject conditions (deepen-plan §4.13)

Section missing entirely while detection fires; a created task with no `task:`
list item of its own; a field absent, empty, or matching
`^\s*<field>:\s*(TODO|TBD|N/A|placeholder)\s*$`; a `dedupe` answer naming ONLY
`concurrency: group:` / workflow-level concurrency with no semantic mechanism
(idempotency precheck, marker dedupe, immutable ticket key).

Fence-blindness: a `## Task Design` occurrence inside a fenced code block (a
schema quote) is not the section — count UNFENCED occurrences, per the §4.12
`awk` precedent.

## Skip silently

When the plan creates no new autonomous-task surface — detection is
file-list-scoped (`## Files to Create` for new task files, `## Files to Edit`
for registry/arming additions), never plan-prose-scoped: a plan that merely
mentions `scheduled-*.yml` does not fire.

**Why:** #11015 — every answer to the six task-design questions exists somewhere in the
machinery (`concurrency: group:`, idempotency prechecks, `action-required` re-entry,
dedupe markers), but none was required at design time.
