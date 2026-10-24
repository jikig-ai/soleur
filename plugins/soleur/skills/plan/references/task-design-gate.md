# Task-Design Gate (Conditional) — canonical contract

Loaded by plan §2.9.3 (emit) and deepen-plan §4.13 (halt). The field schema ships
verbatim in `plan-issue-templates.md` (all three templates, after `## Observability`).

Every plan that creates a NEW autonomous-task surface MUST emit a `## Task Design`
section — one `task:` block per created task. **Create-time only**: never a retrofit
onto existing `scheduled-*.yml` workflows or Inngest functions.

## Detection

A `## Files to Create` entry matching, OR the plan creates a new registered
reminder/sweeper check (a `CHECK_REGISTRY` entry or an armed named-check):

- `\.github/workflows/scheduled-.*\.yml`
- `apps/*/server/inngest/functions/(cron|oneshot)-.*\.ts`

## Required schema (verbatim from `plan-issue-templates.md`)

```yaml
task:              # name/slug of the autonomous task being created (one block per created task)
trigger:           # what fires it — cron / event / label / dispatch / upstream run
services:          # services or data surfaces it reads from and writes to
next:              # what it triggers next ("nothing" is a valid answer)
human_reentry:     # how a human resumes, redirects or stops it mid-run
dedupe:            # mechanism preventing semantic double-work — MUST name something beyond
                   # `concurrency: group:` (it serializes overlapping RUNS, not the work itself)
source_dedupe:     # how the ticket source dedupes this task, or the literal "not a ticket source"
```

## Reject conditions (deepen-plan §4.13)

Section missing entirely while detection fires; a created task with no `task:` block
of its own; a field absent, empty, or matching
`^\s*<field>:\s*(TODO|TBD|N/A|placeholder)\s*$`; a `dedupe` answer naming ONLY
`concurrency: group:` / workflow-level concurrency with no semantic mechanism
(idempotency precheck, marker dedupe, immutable ticket key).

## Skip silently

When the plan creates no new autonomous-task surface — detection is Files-to-**Create**-
scoped, never prose-scoped: a plan that merely mentions `scheduled-*.yml` does not fire.

**Why:** #11015 — every answer to the six task-design questions exists somewhere in the
machinery (`concurrency: group:`, idempotency prechecks, `action-required` re-entry,
dedupe markers), but none was required at design time.
