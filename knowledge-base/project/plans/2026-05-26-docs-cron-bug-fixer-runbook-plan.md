---
title: "docs: document cron-bug-fixer manual-trigger event + override semantics"
type: fix
date: 2026-05-26
lane: single-domain
---

# docs(runbook): document cron-bug-fixer manual-trigger event + override semantics

## Overview

Add a "Cron bug-fixer" section to `knowledge-base/engineering/ops/runbooks/inngest-server.md` documenting the manual-trigger event, override semantics, concurrency behavior, how to fire, how to observe results, and common failure modes. Closes #4383.

The cron-bug-fixer function (`apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`) was migrated from the GHA `scheduled-bug-fixer.yml` workflow in TR9 PR-5 (#4377). Its manual-trigger semantics are currently documented only in the source header comment and the archived PR-5 plan. An agent or operator outside the original implementation context has no canonical runbook to consult.

## Research Insights

- **Existing runbook:** `knowledge-base/engineering/ops/runbooks/inngest-server.md` (326 lines) covers bootstrap, heartbeat triage, key rotation, CLI version bump, FR5 flag flip, unpause heartbeat, SQLite retention, concurrency conventions, and fresh-host provisioning. No mention of the bug-fixer function.
- **Source of truth:** `cron-bug-fixer.ts` lines 582-839 define the handler, registration, event trigger, validation, and concurrency config.
- **Event name:** `cron/bug-fixer.manual-trigger` (registered at line 837).
- **Payload shape:** `{ issue_number?: number }` — optional positive integer (validated at lines 594-621).
- **Concurrency:** Dual scope: `fn` limit 1 + `account` key `"cron-platform"` limit 1 (lines 831-835). Retries: 1.
- **Scheduled trigger:** `0 6 * * *` UTC (line 837).
- **Sentry monitor slug:** `scheduled-bug-fixer` (line 73).
- **Event send precedent:** Sibling runbooks use two forms: `inngest send <event> --data '{...}'` (github-app-drift.md) and `inngest send '{"name":"...","data":{...}}'` (ship-merge-trigger.md). Both forms are valid.
- **No external research needed.** All content derives from the implementation source code and existing runbook patterns. Strong local context.

## User-Brand Impact

- **If this lands broken, the user experiences:** stale or incorrect runbook instructions leading to a failed manual trigger attempt.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is pure documentation with no secrets or code changes.
- **Brand-survival threshold:** `none`

## Proposed Solution

Add a new `## Cron bug-fixer` section to `inngest-server.md` (between the existing "Concurrency conventions" section and "Plan deviations" section) containing subsections for:

1. **Event name + payload shape + validation rules** — the event name, the optional `issue_number` field, type validation (positive integer), and rejection behavior.
2. **Override semantics** — bypass of the priority cascade, operator responsibility for issue-compatibility.
3. **Concurrency behavior** — fn-scoped limit 1 + account-scoped `cron-platform` limit 1 queuing.
4. **How to fire** — both `inngest send` CLI form and the Inngest dashboard UI approach.
5. **How to observe results** — Sentry monitor, `bot-fix/*` PR list on GitHub, Inngest dashboard run history.
6. **Common failure modes** — override rejected, cascade returns no qualifying issue, claude-eval over-budget, workspace setup failure, no PR detected after eval, auto-merge gate rejection (non-bot author, missing label, multi-file diff, non-p3-low source issue).

Also add a row to the Quick Reference table at the top of the file.

## Acceptance Criteria

- [x] AC1 — `knowledge-base/engineering/ops/runbooks/inngest-server.md` contains a `## Cron bug-fixer` section with subsections for: event name/payload, override semantics, concurrency, how to fire, how to observe, common failure modes.
- [x] AC2 — Quick Reference table includes a row linking to the new section.
- [x] AC3 — Event name matches source: `cron/bug-fixer.manual-trigger`.
- [x] AC4 — Payload shape documented as `{ "issue_number": <positive integer> }` (optional).
- [x] AC5 — Override semantics document that override bypasses the priority cascade and operator owns ensuring issue compatibility.
- [x] AC6 — Concurrency section documents dual-scope (fn limit 1 + account `cron-platform` limit 1) and that manual triggers queue behind in-flight runs.
- [x] AC7 — "How to fire" section shows `inngest send` CLI invocation form.
- [x] AC8 — "How to observe" section references Sentry monitor `scheduled-bug-fixer` and `bot-fix/*` PR branch prefix.
- [x] AC9 — "Common failure modes" section lists at least 5 modes documented in the handler (override rejection, empty cascade, timeout, workspace failure, no PR detected, auto-merge gate rejection).
- [x] AC10 — No `ssh ` commands appear in the new section (per `hr-no-ssh-fallback-in-runbooks`).
- [x] AC11 — PR body uses `Closes #4383` to auto-close the issue on merge.

## Test Scenarios

- Given the updated runbook, when an operator searches for "bug-fixer" within `inngest-server.md`, then the section is findable.
- Given the event name in the runbook, when an operator copies the `inngest send` command verbatim, then the Inngest server accepts the event.
- Given the documented payload shape, when an operator sends `{"issue_number": "abc"}`, then the handler rejects with a Sentry fallback report (as documented in the failure modes section).

## Implementation Phases

### Phase 1: Add cron bug-fixer section to inngest-server.md

1. Read `knowledge-base/engineering/ops/runbooks/inngest-server.md`.
2. Add a row to the Quick Reference table: `| Cron bug-fixer manual trigger | [section link] |`.
3. Insert a `## Cron bug-fixer` section between `## Concurrency conventions` and `## Plan deviations`. Content derived from `cron-bug-fixer.ts` lines 582-839.

### Phase 2: Verification

1. Verify the section heading exists: `grep -c '## Cron bug-fixer' knowledge-base/engineering/ops/runbooks/inngest-server.md` returns 1.
2. Verify no SSH commands: `grep -c 'ssh ' <new-section-content>` returns 0.
3. Verify event name: `grep -c 'cron/bug-fixer.manual-trigger' knowledge-base/engineering/ops/runbooks/inngest-server.md` returns >= 1.

## Files to Edit

- `knowledge-base/engineering/ops/runbooks/inngest-server.md` — add Quick Reference row + new `## Cron bug-fixer` section.

## Files to Create

None.

## Open Code-Review Overlap

#4383 itself is the code-review issue this plan closes. No other open code-review issues touch `inngest-server.md`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure documentation addition to an existing engineering runbook.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Runbook content drifts from implementation | Event name, payload shape, and concurrency config are derived from source code with specific line references. Future refactors should update the runbook. |
| Inngest CLI `send` invocation form changes between versions | Document the JSON-body form which is the most stable across Inngest CLI versions. |

## Context

- Source: PR #4377 (TR9 PR-5), 10-agent review. Agent-native-reviewer Observation 1.
- Implementation: `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
- Umbrella: #3948
- Existing runbook: `knowledge-base/engineering/ops/runbooks/inngest-server.md`

## References

- Issue: #4383
- PR #4377 (TR9 PR-5 — cron-bug-fixer Inngest migration)
- Plan: `knowledge-base/project/plans/2026-05-24-feat-tr9-pr5-bug-fixer-inngest-migration-plan.md`
- ADR-030 (Inngest as durable trigger layer)
