# Task-Design Gate (Conditional) — canonical contract

Loaded by plan §2.9.3 (emit) and deepen-plan §4.13 (halt). This file is the
CANONICAL copy of the gate contract; the `## Task Design` schema blocks in
`plan-issue-templates.md` (all three templates, after `## Encryption Posture`)
are verbatim schema copies (comment prologue aside).

Every plan that creates a NEW autonomous-task surface MUST emit a `## Task Design`
section — one `- task:` list item per created task (one file CAN create several:
N functions in one file ⇒ N items). **Create-time only**: never a retrofit onto
existing tasks.

## Detection

Detection is file-list + diff-scoped — `## Files to Create` / `## Files to Edit`
are the canonical headings. A plan that merely *mentions* these paths does not
fire. Trigger surfaces:

| Substrate | Signal |
|---|---|
| GHA workflow | a `## Files to Create` `.github/workflows/*.yml` (ANY new workflow — `scheduled-*` is convention, not enforcement; 14+ live autonomous workflows carry other names) OR a `## Files to Edit` adding a `schedule:`/`on:` trigger block to an existing workflow |
| Inngest function | a `## Files to Create` `.ts` under `apps/*/server/inngest/functions/` — `cron-*`/`oneshot-*`/`event-*`/unprefixed all count; a new `_`-prefixed file that adds `createFunction(`, or a function registered via an edit to `app/api/inngest/route.ts` or a `server/index.ts` `inngest.send` arm |
| Registered check | a `## Files to Edit` adding a `CHECK_REGISTRY` key in `event-scheduled-reminder.ts`, an arming record for a named-check, or a plan step arming a reminder via `scripts/arm-checkpoint.sh` / `POST /api/internal/schedule-reminder` (the API-arm path creates no file — the plan step is the signal) |
| pg_cron | a `supabase/migrations/*.sql` create/edit adding `cron.schedule(` |
| Host scheduler | a `cloud-init*`/infra create/edit adding `/etc/cron.d/` or a `.timer` `OnCalendar=` |
| In-process daemon | a `server/*.ts` create/edit adding a `setInterval(`-driven periodic task |
| Terraform-emitted | a `.tf` adding `github_repository_file` writing a `.github/workflows/*.yml` |

The non-`_` rule for Inngest files: shared code SHOULD be `_`-prefixed
(`_cron-shared.ts`), so a new non-`_` file is *presumed* a function — four
existing helpers break the rule today (`github-event-strategies.ts`,
`oauth-probe-sentinels.ts`, `action-required-sla-policy.ts`,
`content-promotion.ts`); over-fire on a new helper is the safe direction, and
new helpers should be named `_<name>.ts`.

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

Section missing entirely while detection fires; more than one unfenced
`## Task Design` section (malformed); a created task with no `- task:` item
naming it; a field absent, empty, or matching (case-insensitive)
`^\s*<field>:\s*(TODO|TBD|N/A|placeholder|WIP|FIXME|TBC|\?\?\?|-|none|see above)\s*$`;
a `dedupe` answer naming ONLY `concurrency: group:` / workflow-level
concurrency, or asserting idempotency without naming a mechanism (idempotency
precheck, marker dedupe, immutable ticket key); a `## Task Design` appearing
inside a code construct does not count — count UNFENCED `## Task Design`
headings outside ALL fence forms (```` ``` ````, `~~~`, `>` blockquote,
4-space indent).

## Skip silently

When the plan creates no new autonomous-task surface per the table above.

## Recovery

Add the `## Task Design` section per `plan-issue-templates.md` (or fix the
rejected field), then re-run deepen-plan.

**Why:** #11015 — every answer to the six task-design questions exists somewhere in the
machinery (`concurrency: group:`, idempotency prechecks, `action-required` re-entry,
dedupe markers), but none was required at design time.
