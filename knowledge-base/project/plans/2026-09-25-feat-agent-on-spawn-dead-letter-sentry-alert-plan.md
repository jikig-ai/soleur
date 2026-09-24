---
title: "observability: no Sentry alert rule for agent-on-spawn-requested dead-letters (leader loop)"
date: 2026-09-25
slug: feat-agent-on-spawn-dead-letter-sentry-alert
branch: feat-one-shot-8719-spawn-dead-letter-alert
issue: 8719
closes: 8719
type: feat
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# Page on leader-loop dead-letters of agent-on-spawn-requested

## Enhancement Summary

**Deepened on:** 2026-09-25
**Sections enhanced:** Proposed Solution, Files to Create/Edit, Implementation Phases, User-Brand
Impact, Observability, Guard Contract, Acceptance Criteria, Test Scenarios, Non-Goals.
**Agents used:** verify-the-negative sweep, observability-coverage-reviewer, test-design-reviewer,
security-sentinel, architecture-strategist, framework-docs-researcher (after the plan-review panel:
DHH, Kieran, code-simplicity, CTO).

### Key Improvements

1. The reason union and the paging decision move to a neutral `lib/failure-reason.ts`
   (`PAGES_OPERATOR`), so no server module takes a value import from `components/`.
2. The report's fallback path is observable: a throw inside the report still sends a tagged
   `report failed` message that the same rule matches, plus a pino-mirror exception with the cause.
3. The founder id is pseudonymized on this event (`founderId` → `userId` → `userIdHash`); the plain
   error object is built field by field; the model-chosen tool name is allowlisted.
4. Tests cannot pass vacuously: env-pinned logger with a breadcrumb positive control, a
   message-conditioned forced throw with a `mock.results` check, a literal six-reason pin, an
   exact-set copy check, and `null`/`undefined`/prototype-less inputs.

### New Considerations Discovered

- inngest 3.54.2's `StepError` keeps only `name`/`message`/`stack`/`cause`, so `pg_code` never
  reaches an `acknowledgment_persist_failed` event (confirmed in `node_modules/inngest/components/StepError.js`).
- `@sentry/core` 10.59.0 defaults `attachStacktrace` to `false`, so the message event groups by
  message text — one Sentry issue per reason (confirmed in `@sentry/core` `options.d.ts`).
- The handler's other log lines still carry the raw `founderId`; out of scope here, tracked by an
  issue filed at ship (tasks.md 4.3).

## Overview

The BYOK leader loop (`agent.spawn.requested`) sends every dead-lettered spawn to Sentry from
`persistFailure`, but no Sentry alert rule matches that emission, and the Error-path capture
loses its `feature`/`op` tags to the pino mirror (#8629). This plan moves the dead-letter
emission to the message path, promotes the failure reason to a searchable tag, and adds a
Terraform-managed `sentry_alert` that emails the operator for the leader-loop failure reasons
that indicate a defect on our side or whose founder copy promises the CTO was notified.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this one-shot branch.)

## Research Insights

### Premise Validation

- #8719 is OPEN; no open PR references it or #8629 (`gh pr list --search "8719 OR 8629"` returned `[]`).
- #8629 (Error-path tag loss) is OPEN, so the issue's precondition holds: a tag-filtered rule over
  the current Error-path emission would never match. The operator chose the local workaround
  (message path) over the fleet-wide fix.
- #8758 is MERGED (2026-09-24T22:41Z), so the operator's "after #8758" ordering is satisfied.
- `persistFailure` exists at `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`
  (`async function persistFailure(`) and calls `reportSilentFallback(err instanceof Error ? err : new Error(String(err)), { feature: "spawn-agent", op: "agent-on-spawn-requested", message: \`agent-on-spawn deadlettered: ${reason}\`, extra })`.
- **Stale premise found (not in the issue):** the issue assumes a `reason` tag exists to filter on.
  It does not. `persistFailure` passes no `tags`, and `reportSilentFallback` promotes only
  `feature`, `op`, `pg_code`, `art_33_breach` plus caller `tags`. `reason` appears only inside the
  message string. The plan therefore adds `tags: { reason }` — without it, a `reason` filter never
  matches even on the message path.
- The three reasons the issue names exist in the `FailureReason` union: `anthropic_request_rejected`,
  `leader_response_truncated`, `leader_tool_invalid`. A fourth leader-loop reason, `leader_refused`,
  was added by #8717 in the same PR whose plan filed #8719; the issue does not list it. Its
  classification is decided below, not silently skipped.
- **Second stale premise (found by the plan-time CTO review):** the founder copy in
  `components/dashboard/failure-reason-copy.ts` already says "CTO has been notified" for
  `anthropic_request_rejected`, `leader_tool_invalid`, `leader_refused` and `leader_class_disabled`.
  No notification exists for any of them today. The paged set therefore follows the copy, which
  widens it past the issue's three (recorded as DC-1 in `decision-challenges.md`).
- `acknowledgment_persist_failed` also fires inside the leader loop (the `end_turn` path's
  `mark-acknowledged` write), after the GitHub side effect landed.
- ADR corpus: no ADR rejects the message-path workaround. ADR-042's 2026-09-24 amendment states
  "the dead-letter log line and the Sentry event are the signal" for a returned rejection, which
  this plan makes true for paging. ADR-031 (Sentry as IaC) governs the rule; no amendment needed.

### Property List

- P1. A leader-loop dead-letter whose reason indicates a defect on our side, or whose founder copy
  promises "CTO has been notified", emails a human.
- P2. The dead-letter Sentry event carries `feature`, `op` and `reason` as searchable tags.
- P3. The Anthropic SDK's original error message and stack stay attached to the Sentry event and the
  pino line (the triage property #8717 deliberately built).
- P4. A rename of any tag literal or paged reason, on either the emitter or the rule side, fails CI.
- P5. Adding a new `FailureReason` forces an explicit page/quiet decision (reverse guard), and no
  reason whose copy promises a notification can be quiet.

### Cut List

- "Fix #8629 fleet-wide (reorder `reportSilentFallback`)" → P2 → cut from this PR by operator
  decision; the message path buys P2 locally, as `server/anthropic-credit.ts` does. #8629 stays open.
- "Wrap the Sentry emit in `step.run` so replays do not re-emit" → no property in the list. Replays
  re-emit 2-3 events per dead-letter today; they fold into the same Sentry issue and the rule's
  `frequency_minutes` throttles paging per issue, so no duplicate page results.
- "A second Better Stack log alert on the pino line" → P1 → already bought by the Sentry rule. The
  `betterstack` element in `model.c4` records that log-content alarms are in-repo pollers, with one
  exception (ADR-218) for stateless per-bucket counts; a per-reason dead-letter page is neither.

### Relevant files

- Emitter: `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` —
  a private `type FailureReason` (19 members, identical to the exported union in
  `components/dashboard/failure-reason-copy.ts`), `persistFailure`, and the leader-loop call sites
  (`isTurnRejection(stepResult)` → `stepResult.rejected`; the non-`end_turn`/`tool_use` stop →
  `leader_refused` / `leader_response_truncated`; the allowlist miss → `leader_tool_invalid`).
- Message-path precedent: `apps/web-platform/server/anthropic-credit.ts` (header block "MESSAGE PATH
  ON PURPOSE"), its emitter test `apps/web-platform/test/server/anthropic-credit.test.ts` (real
  logger + real observability, `@sentry/nextjs` mocked, asserts `captureException` not called), and
  its rule contract `apps/web-platform/test/sentry-anthropic-credit-alert-op-contract.test.ts`.
- `apps/web-platform/server/observability.ts` `reportSilentFallback`: `err instanceof Error` →
  `captureException`, else `captureMessage(safeMessage, { level: "error", tags, extra: { err, ...extra } })`.
  `logger.error({ err, feature, op, ...extra }, safeMessage)` runs first and does NOT include `tags`.
- `apps/web-platform/server/logger.ts` `mirrorToSentry`: captures only when `data.err instanceof Error`.
  A plain-object `err` is not captured, so nothing pre-empts the tagged `captureMessage`.
- `apps/web-platform/server/pii-redact.ts` `redactErrorForEmit`: handles plain-object errors
  (`redactValue`), so a `{ name, message, stack }` object is still address-redacted.
- `apps/web-platform/sentry.server.config.ts`: no `attachStacktrace`, no `beforeSend` fingerprint. A
  message event therefore groups by message text — one Sentry issue per reason.
- Leader-loop suite: `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`
  mocks `@/server/observability`; `deadletterCall()` finds the call whose `message` contains
  `deadlettered`, then asserts `(call![0] as Error).message.startsWith("400 ")` and
  `(call![0] as Error).stack` equals the original stack. A plain object with the same `message` and
  `stack` keys keeps both assertions true.
- Rule root: `apps/web-platform/infra/sentry/issue-alerts.tf` (the newest rules,
  `ops_email_delivery_failure` and `anthropic_credit_exhausted`, are appended at the end; both use the
  four-trigger shape with `event_frequency_count { interval = "1h", value = 0 }`).
- Live `frequency_minutes` values in the root (comments stripped): 5, 10-27, 30, 31, 60-63, 1440,
  1441. **1442 is unused.**
- Count pins: `apps/web-platform/infra/sentry/README.md` line 5 (the bold "34 `sentry_alert` rules" phrase and
  "(34 alert rules total)") is pinned by T25 in `apps/web-platform/scripts/sentry-monitors-audit.test.sh`.
  `knowledge-base/engineering/architecture/diagrams/model.c4` `sentry -> founder` says "31 of the 33
  `sentry_alert` rules in issue-alerts.tf"; `plugins/soleur/test/c4-count-parity.test.sh` does NOT
  pin it (its registry rows are C1-C8, none about `sentry_alert`), so it must be edited by hand.
- Reference snapshot: `apps/web-platform/infra/sentry/alert-reference.json` (keyed by rule name),
  held equal to the plan by `scripts/sentry-alert-reference-gate.sh` in `plan_pr`; regenerated per
  the README ("Adding or editing a rule = a resource block + a regenerated `alert-reference.json`"),
  including the credential-free PR round-trip (`gh run download <run-id> -n sentry-alert-reference-expected-<run-id>`).
- Apply: `.github/workflows/apply-sentry-infra.yml` auto-applies the whole `infra/sentry/**` root on
  push to `main`; post-apply `scripts/sentry-alert-live-fidelity.sh` checks every `sentry_alert`
  field-for-field; `scheduled-sentry-alert-drift.yml` re-checks daily.
- No Better Stack alert, runbook or verdict query keys on `op=agent-on-spawn-requested`, `spawn-agent`
  or the pino `err.type` of this line (`git grep` over `apps/web-platform/infra`, `knowledge-base/engineering`,
  `scripts`, `.github` returned only ADR prose).

### Institutional learnings applied

- `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md` — "pages" is three hops: the emit keeps
  the filtered fields, the rule exists, the rule routes to a person. Each hop gets its own check
  here (emitter test, contract test, `ActiveMembers` fallthrough assertion).
- `best-practices/2026-06-04-revert-fallback-must-preserve-alert-emit-and-op-scoped-alert-needs-reverse-guard.md` —
  a filter over an `in` list needs a reverse guard, or a new value silently falls outside it. Here
  that is `PAGES_OPERATOR: Record<FailureReason, boolean>` in `lib/failure-reason.ts`, exhaustive
  over the one shared union, enforced by `tsc`.
- `best-practices/2026-05-30-routing-through-shared-tag-filtered-alert-primitive-needs-all-filter-tags.md` —
  with `logic_type = "all"`, the emit must carry every filtered tag (hence the `reason` tag).
- `2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md` —
  high-cardinality message text mints a fresh issue per event. The message stays
  `agent-on-spawn deadlettered: <reason>` (19 possible values).
- `best-practices/2026-07-02-inngest-side-effect-outside-step-run-duplicates-on-replay.md` — code
  outside `step.run` re-runs on replay. Acceptable for an idempotent-by-grouping Sentry event; would
  not be for a founder notification (which is already inside `step.run("notify-cost-breaker")`).
- `2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md` — the unique
  `frequency_minutes` check must scan the whole `infra/sentry/` root, not one file.

### CLAUDE.md / AGENTS.md conventions in play

- `cq-silent-fallback-must-mirror-to-sentry`, `hr-observability-as-plan-quality-gate`,
  `hr-all-infrastructure-provisioning-servers` (the rule is Terraform, applied by CI),
  `cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`, `cq-assert-anchor-not-bare-token`.

### Research decision

Strong local context (two in-repo precedents, #8505 and #7989). No external research run.
Functional-overlap check: no community skill or agent covers this; nothing installed.

## Problem Statement

A leader-loop spawn that dead-letters because of a defect on our side — the Anthropic API rejects
the request we built, the response is cut off, the model calls a tool outside the class allowlist,
the class has no leader module, or the acknowledgment write fails after the GitHub side effect
landed — shows the founder a failure row on the Today card and reaches Sentry, but pages no one.
For four of those reasons the founder's copy already says "CTO has been notified"
(`components/dashboard/failure-reason-copy.ts`), which today is untrue. Two independent defects
cause the silence:

1. **No rule.** `apps/web-platform/infra/sentry/issue-alerts.tf` has no `sentry_alert` matching
   `feature=spawn-agent` or `op=agent-on-spawn-requested`.
2. **No tags on the event.** `persistFailure` reports through the Error path. `reportSilentFallback`
   logs first, the pino hook captures the same Error as `feature=pino-mirror`, and `@sentry/core`
   then drops the tagged `captureException` as already captured (#8629). And even on a path that kept
   tags, `reason` is not one of them.

A leader-loop failure class that fails deterministically fails for every founder who triggers that
class, so the first person to learn about it today is a founder.

## Proposed Solution

Three code changes and one rule, in dependency order:

1. **One neutral home for the reason union and the paging decision:
   `apps/web-platform/lib/failure-reason.ts`** (new). It declares the `FailureReason` union (moved
   verbatim, 19 members) and `PAGES_OPERATOR: Record<FailureReason, boolean>` with a one-line
   rationale comment on each `true` row. The exhaustive `Record` makes `tsc` force a paging decision
   for every new reason (P5). The file has no imports, so the client bundle (the Today card imports
   the copy table) and the server both import it safely.
   - `components/dashboard/failure-reason-copy.ts` replaces its own union with
     `import type { FailureReason } from "@/lib/failure-reason"` plus
     `export type { FailureReason }`, so its existing importers are unaffected. No copy text changes
     and no field is added to the UI rows.
   - `server/inngest/functions/agent-on-spawn-requested.ts` deletes its private union and
     `import type`s the same one. One declaration now serves the handler, the copy table and the
     paging decision.
   - (Deepen-plan, architecture review: a first revision put a `pagesOperator` field on the UI copy
     rows and had the server import a VALUE from `components/`. No `server/**` module does that today
     — `server/inbox-sources.ts` imports a type only — and `.dependency-cruiser.cjs` guards only
     client→server, so nothing would catch a later `"use client"` or client-only import in the copy
     module breaking the server. `lib/` is the neutral layer.)

2. **A leaf emitter module, `apps/web-platform/server/spawn-dead-letter.ts`** (new), modelled on
   `server/anthropic-credit.ts`. It owns:
   - the tag literals `SPAWN_DEAD_LETTER_FEATURE = "spawn-agent"` and
     `SPAWN_DEAD_LETTER_OP = "agent-on-spawn-requested"` (values unchanged from today);
   - `PAGED_DEAD_LETTER_REASONS`, derived from `PAGES_OPERATOR` (keys whose value is `true`),
     sorted; the contract test compares it to the rule and pins it;
   - `reportSpawnDeadLetter({ reason, err, extra })`, the only emitter, with `reason: FailureReason`.
     It calls
     `reportSilentFallback(toMessagePathError(err), { feature, op, message, tags: { reason }, extra: toReportExtra(extra, reason) })`,
     where `message` is the template `agent-on-spawn deadlettered: ${reason}` — byte-identical to
     today, so Sentry groups one issue per reason and the leader-loop suite's `deadletterCall()`
     still finds the call. `toReportExtra` copies the caller's extra, renames `founderId` to
     `userId` (which `reportSilentFallback` hashes to `userIdHash` and uses for the event's user
     scope; today the raw founder UUID reaches Sentry and Better Stack, because only the `userId` /
     `user_id` keys are pseudonymized), and adds `reason`. No runbook, query or alert reads
     `founderId` from this line (`git grep founderId` over `knowledge-base/engineering`,
     `apps/web-platform/infra`, `scripts`, `.github` finds only an unrelated `finance.payment_failed`
     query).
   - **The whole body is wrapped in one `try/catch`.** `reportSilentFallback`'s own `try/catch`
     covers only the two Sentry calls; `hashExtraUserId`, `sanitizeLogMessage`, `logger.error` and
     `userScopeFromExtra` run before it (`server/observability.ts`), and a throw from any of them
     would otherwise skip the `persist-failure` step and leave the founder's card without a terminal
     state. The catch must itself be observable and must not throw:
     - in its own nested `try`, `logger.error({ err: caught, reason, feature, op }, "agent-on-spawn deadlettered: report failed")`
       — `caught` is an `Error`, so the pino mirror sends a `feature=pino-mirror` exception event
       with the cause;
     - in a second nested `try`, `Sentry.captureMessage("agent-on-spawn deadlettered: report failed", { level: "error", tags: { feature, op, reason } })`
       — tagged, so the alert rule still matches a paged reason even when the normal path failed;
     - each nested `catch {}` carries a `// review: swallowed` comment, per the repo convention for
       deliberate swallows.
   - `toMessagePathError(err)` returns a **fresh plain object** — never an `Error` instance —
     `{ name, message, stack, code }` built field by field (never `...err`, which would carry the
     Anthropic SDK's `headers` and error body, or PostgREST's `details`/`hint`; the header comment
     says so). Rules: `null`/`undefined` → `{ name: "Error", message: String(err) }`; a string →
     `{ name: "Error", message: err }`; any object (including one with no prototype) → `name` and
     `message` read with `typeof x === "string" ? x : String(x ?? "")` semantics that cannot throw
     on a prototype-less object, `stack` and `code` copied only when they are strings. `code` keeps
     `pg_code` for a direct caller that passes a PostgREST error. It is NOT a production property of
     `acknowledgment_persist_failed`: that error crosses the `mark-acknowledged` step boundary, and
     inngest 3.54.2's `StepError` constructor (`node_modules/inngest/components/StepError.js`) keeps
     only `name`, `message`, `stack` and `cause` — `serialize-error-cjs` carries `code` on the wire,
     but the rebuilt error drops it. Side improvement: today a plain-object PostgREST error thrown
     from a direct caller is reported as `new Error("[object Object]")`; after this change its
     `message` survives.
   - A header block stating "MESSAGE PATH ON PURPOSE" with the #8629 mechanism, so nobody "restores
     the stack trace" by passing the Error back, and naming `server/anthropic-credit.ts` as the
     sibling workaround to revert together when #8629 lands.

   Why a plain object rather than `null` (what `anthropic-credit.ts` passes): #8717 deliberately
   sends the SDK's original message and stack to Sentry for triage (ADR-042 amendment 2026-09-24).
   A plain object keeps both — in Sentry `extra.err` and in the pino line's `err` — while
   `err instanceof Error` stays false in `reportSilentFallback` and in `mirrorToSentry`. It also keeps
   the leader-loop suite's existing `call![0].message` / `.stack` assertions valid unchanged (they
   use `as Error`, a compile-time cast only). The cost is Sentry's stack-frame view: the stack
   survives as a string in `extra.err.stack`. The email subject also improves: today it is the SDK's
   own error text; after this change it is the fixed template plus an enum.

3. **`persistFailure` calls `reportSpawnDeadLetter`** instead of `reportSilentFallback` directly. The
   `extra` it passes is unchanged (founderId, messageId, actionClass, sourceRef, actionSendId plus the
   caller's `extra`); the leaf does the `founderId` rename, so the class stays on every event without
   being a tag. The `leader_tool_invalid` call site gains
   `extra: { turn: n, model: leaderModule.model, tool: safeToolName(tu.name) }`, where
   `safeToolName` (in the leaf) returns the name when it matches `/^[A-Za-z0-9_-]{1,64}$/` and
   `"[invalid]"` otherwise — the name is chosen by the model and must not carry control characters,
   U+2028/U+2029 or unbounded length into the log line or Sentry. Ordering (Sentry mirror, then
   `notify-cost-breaker`, then `persist-failure`), return values and step ids are untouched.

4. **`sentry_alert.spawn_agent_dead_letter`**, appended at the end of `issue-alerts.tf` after
   `anthropic_credit_exhausted`, with its own comment block (emitter, why the message path, trigger
   rationale, frequency choice, where the paging decision lives, and how to read a
   `leader_class_disabled` email: `extra.err.message` says either "disabled via
   LEADER_CLASSES_DISABLED" — the kill switch working — or "no leader module for class X" — a defect):

   ```hcl
   resource "sentry_alert" "spawn_agent_dead_letter" {
     organization      = var.sentry_org
     name              = "spawn-agent-dead-letter"
     enabled           = true
     frequency_minutes = 1442
     monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

     trigger_conditions = [
       { first_seen_event = {} },
       { reappeared_event = {} },
       { regression_event = {} },
       { event_frequency_count = { interval = "1h", value = 0 } },
     ]

     action_filters = [
       {
         logic_type = "all"
         conditions = [
           { tagged_event = { key = "feature", match = "eq", value = "spawn-agent" } },
           { tagged_event = { key = "op", match = "eq", value = "agent-on-spawn-requested" } },
           { tagged_event = { key = "reason", match = "in", value = "acknowledgment_persist_failed,anthropic_request_rejected,leader_class_disabled,leader_refused,leader_response_truncated,leader_tool_invalid" } },
         ]
         actions = [
           { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
         ]
       },
     ]

     lifecycle {
       ignore_changes = [environment]
     }
   }
   ```

   - **Triggers.** The issue asked for first-seen and regression. The event is a message event with
     no stack trace, so Sentry groups it by message text: one Sentry issue per reason for its whole
     life. Transition triggers alone would page once per reason, ever, then go silent while the
     class keeps failing — the defect `ops_email_delivery_failure`'s comment describes.
     `event_frequency_count > 0 / 1h` keeps a persisting reason re-paging, and
     `frequency_minutes = 1442` bounds that to once a day per reason. `reappeared_event` is included
     for parity with the two newest rules (an archived-then-recurring issue re-pages).
   - **`frequency_minutes = 1442`**: unused anywhere in the root (1440 =
     `sentry_alert.anthropic_credit_exhausted` in `issue-alerts.tf`, 1441 =
     `sentry_alert.cron_monitor_failure` in `cron-monitor-alerts.tf`). Daily cadence, same rationale
     as the credit rule.
   - **Route**: `issue_owners` with `ActiveMembers` fallthrough — the project has no ownership rule,
     so `NoOne` would page nobody.
   - **Label and name** are new, so the first CI apply creates the rule; no `import{}`/`removed{}`.

### Paging decision for every reason (`PAGES_OPERATOR`)

The rule for `true`: the failure is a defect on our side (request shape, prompt/tool surface, token
budget, missing class module, our DB write), OR the founder's copy promises the CTO was notified.
Every reason whose copy mentions a notification is `true`; the contract test enforces that.

| Reason | `PAGES_OPERATOR` | Why |
|---|---|---|
| `anthropic_request_rejected` | **true** | We built a request the API rejects deterministically (400/404/413/422). Copy: "CTO has been notified." |
| `leader_tool_invalid` | **true** | The model called a tool outside the class allowlist: prompt and tool surface disagree. Copy: "CTO has been notified." |
| `leader_refused` | **true** | Copy: "The agent declined this task. CTO has been notified." A systematic refusal on one class is a prompt defect. |
| `leader_class_disabled` | **true** | Copy: "…not enabled yet. CTO has been notified." Two arms: `LEADER_CLASSES_DISABLED` (deliberate kill switch — re-pages at most daily while founders click it) and "no leader module for class X" (a defect). See DC-2. |
| `leader_response_truncated` | **true** | Named by the issue. A non-`end_turn`/`tool_use`/`refusal` stop (e.g. `max_tokens`): our token budget or prompt is wrong for the class. Its copy says retry usually works, so a low background rate re-pages daily — see DC-1. |
| `acknowledgment_persist_failed` | **true** | The GitHub side effect landed but our `action_sends` write failed; the founder sees a failure for work that exists. Our DB fault. |
| `leader_max_turns_exceeded` | false | Cost breaker; the founder is notified (`COST_BREAKER_NOTIFY_REASONS`); copy says "contact CTO", not "notified". |
| `byok_cap_exceeded`, `cost_ceiling_exceeded`, `cap_check_unavailable` | false | Cost breakers; founder notified; the BYOK cap has its own rule (`byok_cap_exceeded`, feature `byok-delegations`). |
| `byok_lease_unavailable` | false | The founder's key, billing, or spend cap. Founder-actionable. |
| `anthropic_timeout`, `anthropic_rate_limited` | false | Transient. (`anthropic_timeout` is also the catch-all for a retry-exhausted error whose status the step boundary stripped — #8783 tracks that mislabel.) |
| `cancelled_by_operator`, `run_paused` | false | Intentional founder stops. |
| `github_installation_unauthorized`, `github_target_not_found`, `github_api_error` | false | GitHub-side or founder-connection state; the copy tells the founder what to do. |
| `malformed_source_ref` | false | No call site in this function emits it today; the row exists because the union requires one. |

## Files to Create

- `apps/web-platform/lib/failure-reason.ts` — the `FailureReason` union (moved) and
  `PAGES_OPERATOR`. No imports.
- `apps/web-platform/server/spawn-dead-letter.ts` — the leaf emitter module (literals, paged set,
  `reportSpawnDeadLetter`, `toMessagePathError`, `toReportExtra`, `safeToolName`).
- `apps/web-platform/test/server/spawn-dead-letter.test.ts` — emitter test with the REAL logger and
  REAL observability, `@sentry/nextjs` mocked (Guard 3).
- `apps/web-platform/test/sentry-spawn-dead-letter-alert-op-contract.test.ts` — emitter/rule contract
  (Guard 1) and the copy-promise check (Guard 2).

## Files to Edit

- `apps/web-platform/components/dashboard/failure-reason-copy.ts` — replace the local union with
  `import type { FailureReason } from "@/lib/failure-reason"` and `export type { FailureReason }`;
  update the header's "Adding a new failure_reason" checklist: extend the union in
  `lib/failure-reason.ts`, add a `PAGES_OPERATOR` row there (and, when `true`, the rule's `in`
  list), then the copy row here. No copy text or row shape changes.
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` — delete the private
  `type FailureReason` union and `import type { FailureReason } from "@/lib/failure-reason"`;
  `persistFailure` calls `reportSpawnDeadLetter`; drop the now-unused `reportSilentFallback`
  import; add `extra: { turn: n, model: leaderModule.model, tool: safeToolName(tu.name) }` to the
  `leader_tool_invalid` call; update the stale comment near the `run_paused` call ("persistFailure's
  reportSilentFallback mirrors it to Sentry") to name `reportSpawnDeadLetter`. (Both unions have the
  same 19 members today, so `tsc` has nothing to report.)
- `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` —
  - move `deadletterCall()` from inside the "Guard 2 — deterministic rejections are returned from
    the step (ADR-042 §I1)" `describe` to module scope, so the AC10 cases in the "Anthropic leader
    loop (PR-B)" `describe` can use it;
  - in the Guard 2 400 case and the `it.each([404, 413, 422])` case, add
    `expect(call![0]).not.toBeInstanceOf(Error)` and
    `expect((call![1] as { tags: Record<string, string> }).tags).toEqual({ reason: "anthropic_request_rejected" })`;
  - add the matching `tags` assertion to "AC10 leader_response_truncated: stop_reason=max_tokens →
    persist failure", "AC10 leader_tool_invalid: out-of-allowlist tool call → persist failure" (plus
    `extra.tool`, `extra.turn`, `extra.model`), and the `it.each` in the "stop_reason other than
    end_turn/tool_use is terminal" `describe` (the only coverage of `leader_refused`);
  - add one forced-throw case: make `reportSilentFallbackSpy` throw ONLY when its options'
    `message` contains `"deadlettered"` (so an unrelated earlier caller cannot absorb the throw),
    drive a 400 dead-letter, then assert: the spy's `mock.results` holds a `{ type: "throw" }` entry
    for that call; the handler still returns
    `{ acknowledged: false, failureReason: "anthropic_request_rejected" }`; and the step double's
    `memoized` map has `persist-failure`;
  - update the stale "persistFailure's reportSilentFallback" comment near the Sentry-mirror
    assertion.
  The existing `.message` / `.stack` assertions stay unchanged.
- `apps/web-platform/infra/sentry/issue-alerts.tf` — append `sentry_alert.spawn_agent_dead_letter`
  with the comment block described above.
- `apps/web-platform/infra/sentry/alert-reference.json` — regenerated, not hand-edited (Phase 3).
- `apps/web-platform/infra/sentry/README.md` — line 5: the bold "34 `sentry_alert` rules" and
  "(34 alert rules total)" → 35/35, and "32 are fully Terraform-owned (31 in `issue-alerts.tf` …" →
  33 (32 in `issue-alerts.tf`); append "#8719" to the rule-history list and one sentence to the
  history paragraph ("#8719 then added `spawn_agent_dead_letter`, a new rule").
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `sentry -> founder` edge: "31 of the
  33 `sentry_alert` rules in issue-alerts.tf" → "32 of the 34". (Not an architecture change; the
  count is prose this change would otherwise falsify, and no parity test pins it.)

## Implementation Phases

### Phase 1 — Emitter (RED first)

1. Write `test/server/spawn-dead-letter.test.ts` (Guard 3) and
   `test/sentry-spawn-dead-letter-alert-op-contract.test.ts` (Guards 1 and 2), and the leader-loop
   suite additions. Run them; they fail on the missing modules.
2. Create `lib/failure-reason.ts` (move the union; add `PAGES_OPERATOR`); point
   `failure-reason-copy.ts` at it.
3. Create `server/spawn-dead-letter.ts`.
4. In `agent-on-spawn-requested.ts`: replace the private union with the type import; point
   `persistFailure` at `reportSpawnDeadLetter`; add the `leader_tool_invalid` `extra`; fix the stale
   comment. Fix the suite's stale comment.
5. From `apps/web-platform`: `./node_modules/.bin/tsc --noEmit`, then
   `./node_modules/.bin/vitest run test/server/spawn-dead-letter.test.ts test/sentry-spawn-dead-letter-alert-op-contract.test.ts test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts test/components/dashboard/failure-reason-copy.test.ts`
   (the contract test's rule half stays red until Phase 2). Also run the dependency-cruiser gate
   named in `apps/web-platform/server/README.md`, since a new `lib/` module is imported from both
   sides.

### Phase 2 — Rule

1. Append the `sentry_alert` block. The contract test goes green.
2. `terraform fmt -check` and, after `terraform init -backend=false`, `terraform validate` in
   `apps/web-platform/infra/sentry` (no credentials needed).
3. Update README counts and the C4 count; run `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh`
   (T25) and the C4 suite (`bash plugins/soleur/test/c4-count-parity.test.sh`,
   `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`).

### Phase 3 — Reference snapshot

Regenerate `alert-reference.json` per the README's "Adding or editing a rule" procedure. The
credential-free route is the PR round-trip: push, let `plan_pr` red on
`sentry-alert-reference-gate.sh`, `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>`,
copy the file over `apps/web-platform/infra/sentry/alert-reference.json`, commit, push. With
Doppler `prd_terraform` read access available, the README's local plan → `jq -f
tests/scripts/lib/sentry-alert-projection.jq` route produces the same bytes. Either way the file is
generated, never hand-written.

### Phase 4 — Ship and verify (automated)

Merge applies the rule through `apply-sentry-infra.yml`; its post-apply step runs
`scripts/sentry-alert-live-fidelity.sh` against the plan projection. Verification reads that run's
conclusion (`gh run list --workflow apply-sentry-infra.yml --branch main --limit 1 --json conclusion`).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Fix #8629 fleet-wide first (reorder `reportSilentFallback`) | Operator decision: this ships alone. #8629 would also revive every Error-path tag rule at once, which needs its own enumeration (the issue says so). |
| `reportSilentFallback(null, …)` exactly like `anthropic-credit.ts` | Loses the SDK message and stack #8717 added for triage; the pino line would lose its `err`. |
| Keep the Error but add a Sentry `fingerprint`/scope | Does not address #8629: the tagged capture is dropped before grouping. |
| Filter the rule on the message text instead of a `reason` tag | Message filters are substring matches on prose; a tag is the stable contract, and the contract test can pin it. |
| Page only the three reasons the issue lists | Leaves the "CTO has been notified" copy false for `leader_refused` and `leader_class_disabled`, and leaves `acknowledgment_persist_failed` (our DB fault) silent. CTO assessment. |
| Page every reason | Cost breakers and founder-state reasons already notify the founder or are expected; paging them trains the reader to ignore the email. |
| A separate server-side policy record next to a second copy of the union (plan v1) | Two unions that could drift. Replaced by one union and `PAGES_OPERATOR` in `lib/failure-reason.ts`. |
| A `pagesOperator` field on the UI copy rows (plan v2) | Made the server import a VALUE from `components/`, a direction no gate guards; alert policy does not belong on UI copy. Deepen-plan architecture review. |
| Class in the message and an `action_class` tag (plan v1) | One Sentry issue per (reason, class) needed a bounded-class normalisation and a Sharp Edge. For a solo operator, a second class breaking on an already-paging reason is covered by the daily re-page and by `extra.actionClass` on the event. Plan-review cut it (both panels). |
| Generate the "CTO has been notified." suffix from the paging decision | Removes the phrase check entirely, but changes how founder copy is built in a UI module; the pinned `/notif/i` check keeps the rendered text untouched. |
| Put the emitter in the Inngest function file | The contract test would have to import the whole function module (Inngest client, Supabase, Anthropic SDK); the leaf mirrors `anthropic-credit.ts` and keeps the test cheap. |

## Non-Goals

- #8629 itself. It stays open; this call site simply stops depending on it.
- Moving the Sentry emit inside `step.run`. Replays re-emit the same message into the same Sentry
  issue; the rule's per-issue throttle means no duplicate page.
- #8783 (retry-exhausted 429 labelled `anthropic_timeout`). A classification fix on a quiet reason;
  it depends on the step-harness migration (#8764).
- Changing any founder-facing copy text. The paging decision is made to match the copy.
- Pseudonymizing `founderId` on the handler's OTHER log lines (e.g. the `persist-failure` warn). This
  PR fixes it on the dead-letter event only; a tracking issue is filed at ship (tasks.md 4.3).

## Open Code-Review Overlap

- #8783 (leader loop labels a retry-exhausted 429 as `anthropic_timeout`) touches
  `agent-on-spawn-requested.ts` and its leader-loop suite. **Acknowledge**: different concern (the
  classifier of a quiet reason), blocked on #8764's harness migration; this plan edits neither
  `classifyAnthropicOrLeaseError` nor the retry tests. Both reasons involved are quiet here, so the
  fix will not change paging.
- #3739 (extract `reportSilentFallbackWithUser`) names `server/observability.ts`, which this plan does
  not edit. **Acknowledge**: no overlap in the edited lines.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder's failed autonomous run whose card never
  reaches a terminal failure state — if the report threw, the `persist-failure` step that writes
  `action_sends.failure_reason` would not run. The `try/catch` around the whole of
  `reportSpawnDeadLetter` prevents that, and a leader-loop test forces the throw. A quieter failure
  mode: the rule never matches, founders keep being the first to see a broken leader class, and the
  "CTO has been notified" copy stays false (today's state).
- **If this leaks, the user's data is exposed via:** no new vector, and one existing one narrows.
  The Sentry event carries the fields the current Error-path event carries (SDK error message and
  stack, messageId, actionClass, sourceRef, actionSendId), now in `extra` instead of the exception
  payload. The founder id, which today reaches Sentry and Better Stack raw as `founderId`, is sent as
  `userId` and pseudonymized to `userIdHash` at the emit boundary. The plain object is built field
  by field, so the Anthropic SDK's `headers` and error body and PostgREST's `details`/`hint` are not
  carried. The model-chosen tool name is added only when it matches `/^[A-Za-z0-9_-]{1,64}$/`. The
  issue title / email subject becomes a fixed template plus an enum, instead of the SDK's error
  text. Address-shaped substrings are still redacted by `redactErrorForEmit` (plain objects
  included) and by the global `beforeSend` scrub. Residual: other log lines in the handler (e.g.
  the `persist-failure` warn) still log `founderId` raw; unchanged by this PR.
- **Brand-survival threshold:** `aggregate pattern`

## Observability

```yaml
liveness_signal:
  what: "Sentry monitor sentry_alert.spawn_agent_dead_letter (name spawn-agent-dead-letter) on the web-platform issue stream. Its LIVE state is verified without SSH by scripts/sentry-alert-live-fidelity.sh, which runs after every apply in apply-sentry-infra.yml and daily in scheduled-sentry-alert-drift.yml (workflow run log; ::error:: annotation on drift); gh run list --workflow apply-sentry-infra.yml reads the latest verdict"
  cadence: "per dead-letter event; re-pages at most once per 1442 minutes per reason while it keeps failing; fidelity check post-apply and daily"
  alert_target: "email to issue owners with ActiveMembers fallthrough (the operator)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (resource sentry_alert.spawn_agent_dead_letter); paging decision apps/web-platform/lib/failure-reason.ts (PAGES_OPERATOR); emitter apps/web-platform/server/spawn-dead-letter.ts"

error_reporting:
  destination: "Sentry web-platform project via @sentry/nextjs (SENTRY_DSN), message event 'agent-on-spawn deadlettered: <reason>' tagged feature=spawn-agent, op=agent-on-spawn-requested, reason (layer 1 sentry-correlation adds inngest.run_id); extra.err carries the SDK message and stack; extra carries actionClass, userIdHash, actionSendId, sourceRef and, per site, status/turn/model/tool"
  fail_loud: "pino error line 'agent-on-spawn deadlettered: <reason>' with fields feature, op, reason, actionClass, status, turn, model to Better Stack source 2457081; if the report itself throws, a pino-mirror exception event plus a tagged Sentry message 'agent-on-spawn deadlettered: report failed'"

failure_modes:
  - mode: "A leader class dead-letters with a paged reason (anthropic_request_rejected, leader_tool_invalid, leader_refused, leader_class_disabled, leader_response_truncated, acknowledgment_persist_failed)"
    detection: "in-surface, layer: Sentry (the handler's own dead-letter event). The reason tag plus extra.actionClass/status/turn/model/tool and extra.err.message discriminate request-shape rejection vs truncation vs tool-surface mismatch vs refusal vs kill switch vs missing module vs DB write in one event. Limit: acknowledgment_persist_failed carries no pg_code in production (the step boundary drops code), so DB failure kinds are told apart by extra.err.message only"
    alert_route: "Sentry monitor sentry_alert.spawn_agent_dead_letter → operator email (first event per reason immediately; then daily while it persists)"
  - mode: "The report itself throws before reaching Sentry (hashing, sanitizing, logging)"
    detection: "layer: Sentry — the catch sends a pino-mirror exception event with the cause and a tagged captureMessage 'agent-on-spawn deadlettered: report failed'; layer: CI — the leader-loop forced-throw case and the emitter test's throwing-reporter case"
    alert_route: "Sentry monitor sentry_alert.spawn_agent_dead_letter (the fallback message carries the same feature/op/reason tags) → operator email; CI failure on the PR"
  - mode: "The emit regresses to the Error path and loses its tags (#8629 class)"
    detection: "layer: CI workflow run log (::error:: annotation) — test/server/spawn-dead-letter.test.ts asserts captureMessage with the tags and captureException never called, using the real logger and observability"
    alert_route: "CI failure on the PR"
  - mode: "A tag literal or paged reason drifts between the emitter and the rule"
    detection: "layer: CI workflow run log — test/sentry-spawn-dead-letter-alert-op-contract.test.ts imports the literals and paged set from the emitter"
    alert_route: "CI failure on the PR"
  - mode: "A founder-copy row promises a notification for a reason that does not page"
    detection: "layer: CI workflow run log — the contract test checks the set of FAILURE_REASON_COPY rows matching /notif/i equals the promised four and each is true in PAGES_OPERATOR"
    alert_route: "CI failure on the PR"
  - mode: "A new FailureReason is added without a paging decision"
    detection: "layer: CI workflow run log — tsc: PAGES_OPERATOR is Record<FailureReason, boolean>"
    alert_route: "CI failure on the PR"
  - mode: "The live rule is deleted, disabled or edited out of band"
    detection: "layer: workflow run log — scripts/sentry-alert-live-fidelity.sh post-apply and in scheduled-sentry-alert-drift.yml daily, against alert-reference.json"
    alert_route: "the drift workflow's issue filing"
  - mode: "A quiet reason (cost breakers, transient Anthropic errors, founder stops, GitHub state) persists"
    detection: "layer: pino → Better Stack line, and the reason tag in Sentry (one issue per reason); founder-facing Today card copy"
    alert_route: "none by design (see the paging table)"

logs:
  where: "Better Stack Logs source 2457081 (web host pino WARN+ via Vector); Sentry issue stream"
  retention: "Better Stack source retention for 2457081; Sentry event retention per plan"

discoverability_test:
  command: "jq -r '.\"spawn-agent-dead-letter\".actionFilters[0].actions[0].fallthroughType' apps/web-platform/infra/sentry/alert-reference.json"
  expected_output: "ActiveMembers"
```

The discoverability test reads the committed `alert-reference.json`, which
`sentry-alert-reference-gate.sh` holds equal to the Terraform plan at PR time. So it reports the
rule's INTENDED routed state, not the live one; live state is what `sentry-alert-live-fidelity.sh`
checks after every apply and daily (named in `liveness_signal`). The command has no pipe, `$`,
redirect or backtick (preflight Check 10's shell-active reject), and prints `null` if the entry is
missing, so it cannot match `ActiveMembers` by way of another rule.

## Encryption Posture

Detection fires (`.tf` in Files to Edit). The plan adds no persistent store and no new
cross-component connection; the posture is inherited and restated here.

```yaml
at_rest:
  - store: Terraform state for apps/web-platform/infra/sentry (existing R2 object, soleur-terraform-state)
    mechanism: provider-managed:Cloudflare R2 AES-256-GCM at rest with AICPA SOC 2 Type II attestation, unchanged here
    evidence: developers.cloudflare.com/r2/reference/data-security/ and cloudflare.com/trust-hub/compliance-resources/soc-2/ (the attestation formalized by the 2026-07-24 R2 SOC 2 attestation plan; retrieved_on 2026-07-24); state location per ADR-006, credentials per ADR-241
    defends_against: disclosure from the provider's storage media
    does_not_defend: anyone holding the R2 state credential; the rule definition is not secret either way
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no new store is introduced; nothing new to verify
in_transit:
  - connection: web-platform server -> Sentry ingest (existing @sentry/nextjs envelope, unchanged)
    enforced_at: apps/web-platform/sentry.server.config.ts (DSN is https)
    tls: HTTPS, TLS 1.2+
    cert_verification: on
    does_not_defend: Sentry itself reading the event; the payload fields are the same as today's exception event
    disclosed_as: existing Sentry processor entry (Art. 30 register)
```

No `exception` block: no `plaintext-exception`, no `cert_verification: off`.

## Infrastructure (IaC)

### Terraform changes

- Existing root `apps/web-platform/infra/sentry` (provider `jianyuan/sentry`, pinned in
  `versions.tf`, unchanged). One new resource, `sentry_alert.spawn_agent_dead_letter`. No new
  variables, secrets or providers.

### Apply path

**Does merging this PR alone change production? Yes, twice, with no further dispatch:**
`apply-sentry-infra.yml` (push to `main`, `paths:` = the whole `apps/web-platform/infra/sentry/**`
tree, full-root plan) creates the rule, and `web-platform-release.yml` deploys the emitter change.
No other workflow applies this root: `scheduled-terraform-drift.yml` and
`scheduled-sentry-alert-drift.yml` only read it, and `sentry-audit-gate.yml` is an advisory PR check.
The PR body's first line states this.

CI apply on merge: `apply-sentry-infra.yml` plans the full root and applies it on push to `main`.
The new address has no state entry and no live object, so the plan is one create; no downtime and
no effect on the other 34 rules. No `-target`, no import.

### Distinctness / drift safeguards

- `lifecycle { ignore_changes = [environment] }`, like every non-frozen rule.
- `sentry-alert-reference-gate.sh` (PR), `sentry-alert-live-fidelity.sh` (post-apply, daily) and the
  twice-daily full-root drift plan cover the new rule automatically; none needs a change.
- The frozen-rule tripwire (`sentry-issue-alert-create-tripwire.sh`) only concerns the two
  `ignore_changes = all` rules and does not fire on a new `sentry_alert`.

### Vendor-tier reality check

`sentry_alert` with `tagged_event` `in` filters and `event_frequency_count` triggers is already live
in this root (`ops_email_delivery_failure`, `anthropic_credit_exhausted`); no tier gate applies.

## Guard Contract

Scope trimmed at plan review (DHH, code-simplicity): the two source-grep checks (a re-declared union
in the handler; a direct `reportSilentFallback(` call) were cut as refactor-fragile and covered by
`tsc` plus the leader-loop tag assertions. Rows that only change which reasons are in the set count
as one row.

### Guard 1 — emitter/rule contract

**Property.** Every `tagged_event` filter in `sentry_alert.spawn_agent_dead_letter` equals the value
the emitter actually sets: `feature` and `op` equal the exported literals with `match = "eq"`, and
the `reason` filter's comma-separated value, as a set, equals `PAGED_DEAD_LETTER_REASONS` with
`match = "in"`; the paged set is exactly the six reasons this plan decides; the rule ANDs the
filters (`logic_type = "all"`), routes to `ActiveMembers`, is enabled, is bound to the web-platform
issue stream, and has a `frequency_minutes` no other rule in the root uses.

**Assembly.** One rule block located by resource label in the comment-stripped text of
`apps/web-platform/infra/sentry/issue-alerts.tf`; its `action_filters[].conditions[]` (every
`tagged_event` — the test requires exactly one condition per key); the literals exported by
`apps/web-platform/server/spawn-dead-letter.ts` and the paged set it derives from
`PAGES_OPERATOR` in `apps/web-platform/lib/failure-reason.ts` (the only place the decision is
written); a literal six-reason list in the test itself (the pin); and, for the frequency check,
every `.tf` file in `apps/web-platform/infra/sentry/` (the POST-time dedup is root-wide). The live
side belongs to `sentry-alert-live-fidelity.sh`. On a set mismatch the failure message prints the
exact sorted `in` string to paste and the `alert-reference.json` regeneration route.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | TF `op` value → `agent-on-spawn` | RED |
| 2 | Change the TF `in` set (drop `leader_tool_invalid`, or append `cancelled_by_operator`, or flip `run_paused` to `true` in `PAGES_OPERATOR` alone) | RED (set differs) |
| 3 | Flip `leader_response_truncated` to `false` in `PAGES_OPERATOR` AND remove it from the TF list | RED (the six-reason pin) |
| 4 | Add a second `{ tagged_event = { key = "reason", … } }` condition after the compliant one | RED (count of `key = "reason"` ≠ 1) |
| 5 | `feature` with `match = "co"` | RED |
| 6 | `logic_type = "any"` | RED |
| 7 | `enabled = false` | RED |
| 8 | Remove `monitor_ids` | RED |
| 9 | `fallthrough_type = "NoOne"` | RED |
| 10 | `frequency_minutes = 1441` (collides with `cron_monitor_failure` in another file) | RED (root-wide scan) |
| 11 | Rename the resource label so the block lookup finds nothing | RED (fixture throws; never a silent pass) |

**Harness rows:**

| # | Edit | Expected |
|---|---|---|
| H1 | Replace the `filterValue` regex in the suite with one that matches nothing | RED (fixture throws "filter not found"), not green |
| H2 | Must-PASS non-canonical: the TF `in` list written in a different order | PASS (set semantics, which the contract permits) |

**Anchor.** A consistent rename on both sides (emitter literal and TF value) is legitimate and
passes; the anchor for "the emitter really sets this literal" is Guard 3, which drives the real
emitter through real `reportSilentFallback`. Dropping a paged reason on both sides is caught by the
six-reason pin (row 3), which a reviewer sees change in the same diff.

### Guard 2 — the founder copy's promise matches the paging decision

**Property.** The set of `FAILURE_REASON_COPY` rows whose `copy` matches `/notif/i` equals exactly
`{anthropic_request_rejected, leader_tool_invalid, leader_refused, leader_class_disabled}`, and each
of them is `true` in `PAGES_OPERATOR`.

**Assembly.** Every row of `FAILURE_REASON_COPY` in
`apps/web-platform/components/dashboard/failure-reason-copy.ts` (the table the Today card renders),
read against `PAGES_OPERATOR` in `apps/web-platform/lib/failure-reason.ts`. Completeness over the
union is `tsc`'s job (`PAGES_OPERATOR: Record<FailureReason, boolean>`), not this guard's.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Set `PAGES_OPERATOR.leader_refused = false` | RED |
| 2 | Add "Our team has been notified." to `run_paused`'s copy | RED (the matched set grows to five; `run_paused` is `false`) |
| 3 | After the four compliant rows, add a fifth reason with notification copy and a `false` entry | RED |
| 4 | Reword `leader_refused`'s copy to "CTO was alerted." | RED (the matched set shrinks to three — the pin forces a conscious update) |

**Harness rows:**

| # | Edit | Expected |
|---|---|---|
| H1 | Change the suite's regex to one that matches nothing | RED (matched set ≠ the pinned four) |
| H2 | Must-PASS non-canonical: `leader_max_turns_exceeded`'s copy "…contact CTO." with `false` | PASS |

**Anchor.** The copy is the product contract rendered on the founder's card, in a different file
and layer from the paging decision. Weakening a promised reason requires changing what the founder
reads in the same diff — a visible product change.

### Guard 3 — the dead-letter reaches Sentry tagged, on the message path, and never breaks the terminal write

**Property.** Every dead-letter report produces exactly one `Sentry.captureMessage` carrying
`feature`, `op` and `reason` tags and the error's message and stack in `extra.err`, and no
`Sentry.captureException` (neither the tagged one nor the pino mirror's), for any `err` value;
the raw founder id never appears in the event; and a throw anywhere inside the report never escapes
`reportSpawnDeadLetter` and still yields a tagged `report failed` message, so `persistFailure` still
reaches its `persist-failure` step.

**Assembly.** The chokepoint is `reportSpawnDeadLetter`; `persistFailure` is its only caller and
every dead-letter call site in the handler flows through `persistFailure`. The first half is tested
in `test/server/spawn-dead-letter.test.ts` against the real `server/logger.ts` and
`server/observability.ts` (only `@sentry/nextjs` mocked), with `SENTRY_BREADCRUMB_LEVEL=warn` and
`LOG_LEVEL=info` pinned via `vi.stubEnv` + `vi.resetModules()` before the logger is imported, and a
positive control that `addBreadcrumb` received `{ category: "pino", message: "agent-on-spawn deadlettered: <reason>" }`
— without it, a high `LOG_LEVEL` or breadcrumb level would make "no pino-mirror capture" pass
without the hook ever running. The throwing-reporter half is tested twice: in the emitter test via
`vi.doMock("@/server/observability", …)` + a fresh import (asserts the tagged `report failed`
`captureMessage` and no throw), and in the leader-loop suite (asserts the terminal write).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pass the `Error` through (`reportSilentFallback(err, …)`) | RED (`captureException` called; tags absent) |
| 2 | Drop `tags: { reason }` | RED |
| 3 | Early-return in `reportSpawnDeadLetter` | RED (`captureMessage` not called exactly once) |
| 4 | Remove the outer `try/catch` | RED (the forced-throw cases reject instead of returning) |
| 5 | Remove the catch's `captureMessage` | RED (no tagged `report failed` message) |
| 6 | Spread `...err` into the plain object | RED (a `{ headers, error }` field appears in `extra.err`) |
| 7 | Keep `founderId` instead of renaming to `userId` | RED (the raw id appears in `extra`; `userIdHash` absent) |
| 8 | Drop `code` from the plain object | RED (a direct `{ code: "42501", message }` input loses `pg_code`) |

**Harness rows:**

| # | Edit | Expected |
|---|---|---|
| H1 | `vi.mock("@/server/observability")` in the main emitter describe | RED (`captureMessage` never reached; the breadcrumb control fails) |
| H2 | Must-PASS non-canonical inputs: a string; `null`; `undefined`; `Object.create(null)`; a StepError-shaped plain object `{ name: "Error", message, stack, cause: "fetch_failed" }`; a PostgREST-shaped object `{ code, message, details }` whose `message` must survive; an Error subclass with `status` | PASS (one tagged `captureMessage` each, never swallowed into the catch) |
| H3 | `safeToolName` must-pass: `"github_comment"` kept; `"x y"` and a 65-char name → `"[invalid]"` | PASS |

**Anchor.** `@sentry/nextjs` is the mocked boundary; the real logger hook and real
`reportSilentFallback` run, so a change to either that re-routes a plain object to
`captureException` reds this suite.

## Acceptance Criteria

- [ ] AC1. `apps/web-platform/lib/failure-reason.ts` exists with no imports and exports
  `FailureReason` and `PAGES_OPERATOR: Record<FailureReason, boolean>`; `failure-reason-copy.ts` and
  `agent-on-spawn-requested.ts` import the type from it and declare no union of their own.
- [ ] AC2. `apps/web-platform/server/spawn-dead-letter.ts` exists and exports
  `SPAWN_DEAD_LETTER_FEATURE`, `SPAWN_DEAD_LETTER_OP`, `PAGED_DEAD_LETTER_REASONS`,
  `reportSpawnDeadLetter` and `safeToolName`; its header states the message-path rule, cites #8629,
  forbids `...err`, and names `server/anthropic-credit.ts` as the sibling workaround.
- [ ] AC3. `PAGED_DEAD_LETTER_REASONS` equals `["acknowledgment_persist_failed", "anthropic_request_rejected", "leader_class_disabled", "leader_refused", "leader_response_truncated", "leader_tool_invalid"]`,
  pinned literally in the contract test. No `copy` string in `failure-reason-copy.ts` changed.
- [ ] AC4. `agent-on-spawn-requested.ts` has no `reportSilentFallback` import; `persistFailure` calls
  `reportSpawnDeadLetter` before `notify-cost-breaker` and `persist-failure` (order and step ids
  unchanged); the `leader_tool_invalid` call passes `turn`, `model` and `safeToolName(tu.name)`.
- [ ] AC5. `test/server/spawn-dead-letter.test.ts` passes with the real logger and observability and
  covers Guard 3: tags, `extra.err` shape, no `captureException`, the breadcrumb positive control,
  every H2/H3 must-pass input, `pg_code` for a direct `{ code: "42501" }` input, `userIdHash`
  present and no raw founder id, and the throwing-reporter fallback.
- [ ] AC6. `test/sentry-spawn-dead-letter-alert-op-contract.test.ts` passes and covers Guards 1 and 2.
- [ ] AC7. The leader-loop suite passes with the relocated `deadletterCall()`, the added
  `not.toBeInstanceOf(Error)` and `tags` assertions (including the stop-reason `it.each` that covers
  `leader_refused`), and the message-conditioned forced-throw case; its existing `.message` /
  `.stack` assertions are unchanged.
- [ ] AC8. `issue-alerts.tf` declares `sentry_alert.spawn_agent_dead_letter` exactly as in Proposed
  Solution; `terraform fmt -check` and `terraform validate` pass.
- [ ] AC9. `alert-reference.json` contains a `spawn-agent-dead-letter` entry generated by the
  projection (not hand-written) and `sentry-alert-reference-gate.sh` passes on the PR.
- [ ] AC10. `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` passes (T25: README says
  35 `sentry_alert` rules and 35 total); README's owned-count sentence reads 33 / 32.
- [ ] AC11. `model.c4`'s `sentry -> founder` edge reads "32 of the 34"; `c4-count-parity.test.sh`,
  `c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- [ ] AC12. `./node_modules/.bin/tsc --noEmit` in `apps/web-platform` passes;
  `test/components/dashboard/failure-reason-copy.test.ts` passes unchanged; the dependency-cruiser
  gate passes.
- [ ] AC13. `knowledge-base/project/specs/feat-one-shot-8719-spawn-dead-letter-alert/decision-challenges.md`
  records DC-1 (the paged set widened past the issue's three) and DC-2 (the kill-switch arm pages).
- [ ] AC14 (post-merge, automated). The `apply-sentry-infra.yml` run for the merge commit concludes
  `success`, including its post-apply live-fidelity step.

## Test Scenarios

- Given an Anthropic 400 on turn 1, when the leader loop dead-letters, then `reportSilentFallback`
  receives a non-Error first argument whose `message` starts with "400 " (status, then a space) and
  whose `stack` is the SDK's, and `tags` equal `{ reason: "anthropic_request_rejected" }`
  (leader-loop suite).
- Given `reportSilentFallback` throws for the dead-letter call, when the leader loop dead-letters,
  then the handler still returns the dead-letter result and `persist-failure` is memoized.
- Given the real logger and a `reportSilentFallback` that throws, when `reportSpawnDeadLetter` runs,
  then nothing escapes and one tagged `captureMessage("agent-on-spawn deadlettered: report failed")`
  is sent.
- Given an out-of-allowlist tool call, then the dead-letter call's `extra` carries `turn`, `model`
  and the sanitized `tool`.
- Given `reportSpawnDeadLetter({ reason: "leader_tool_invalid", err: new Error("tool x not in allowlist"), extra: { founderId: "<synthetic uuid>" } })`
  with the real logger, then exactly one tagged `captureMessage`, zero `captureException`, a pino
  breadcrumb, `extra.userIdHash` present and the synthetic uuid absent from the event.
- Given `null`, `undefined`, `Object.create(null)`, a string, a StepError-shaped object or a
  PostgREST-shaped object as `err`, then each produces one tagged `captureMessage`; the PostgREST
  object's `message` survives and a direct `{ code: "42501" }` yields `pg_code: "42501"`.
- Given the TF rule, when the contract test parses it, then the `reason` set equals the pinned six
  and `frequency_minutes` is unique across `infra/sentry/*.tf`.
- Given `FAILURE_REASON_COPY`, then the rows matching `/notif/i` are exactly the promised four and
  each is `true` in `PAGES_OPERATOR`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO (plan time, then devex pass at plan review). Small, low-risk change. Two policy
premises in the first draft were wrong and are corrected: `acknowledgment_persist_failed` is a
leader-loop reason and our DB fault, so it pages; four copy rows promise "CTO has been notified"
(`anthropic_request_rejected`, `leader_tool_invalid`, `leader_refused`, `leader_class_disabled`), so
all four page, and a check ties the paging decision to that copy. Devex pass: the email supports
triage without SSH once the `leader_tool_invalid` call site carries `turn`/`model`/`tool`; the
copy check should key on a structured decision rather than the exact phrase (adopted as
`PAGES_OPERATOR` plus a pinned `/notif/i` check); kill-switch paging (DC-2) is acceptable, and the rule's
comment explains how to tell the kill switch from a missing module. Earlier CTO suggestions to add
an `action_class` tag and split issues per class were cut at plan review (both panels) in favour of
`extra.actionClass`.

No other domain is relevant. The copy module gains a data field the card does not render, and no
founder-facing text changes; no legal, marketing, sales, finance, operations or support implication.

## Sharp Edges

- `toMessagePathError` must return a plain object in every branch. An `Error` anywhere (including a
  redacted copy from `redactErrorForEmit`, which preserves the prototype of an Error input) would
  send the call back down the Error path; convert BEFORE `reportSilentFallback`, whose own redaction
  then walks a plain object.
- Keep the message text `agent-on-spawn deadlettered: <reason>` byte-identical: the leader-loop
  suite's `deadletterCall()` finds the call by `deadlettered`, and Sentry groups by this string.
  Do not add status, turn, model, class or ids to it; they belong in `extra`.
- The `in` value is comma-separated with no spaces, like `ops_email_delivery_failure`'s.
- No Inngest step changes its id or its return shape (`notify-cost-breaker`, `persist-failure` and
  the `turn-${n}-claude` steps are untouched), so a run memoized under the old code resumes on the
  new code without a shape-tolerant reader. The only moved code runs outside any step.
- `pg_code` is a property of direct callers only. An error returned out of a `step.run` loses its
  `code`, so do not write an AC or runbook line that expects `pg_code` on an
  `acknowledgment_persist_failed` event.
- The live counts in README and `model.c4` move together with the resource; T25 catches README,
  nothing catches `model.c4`.
- Any `discoverability_test.command` edit must stay free of `|`, `;`, `&`, `<`, `>`, `$` and
  backticks (preflight Check 10).
- `LEADER_CLASSES_DISABLED` now pages (at most daily) while founders click a disabled class. That is
  the copy's promise; if it proves noisy, the fix is a copy change plus a `PAGES_OPERATOR` flip in the
  same diff (DC-2) — Guard 2 forbids the flip alone.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.

## References

- Issue #8719; #8629 (Error-path tag loss); #8505 / PR #8618 (message-path precedent and
  `anthropic_credit_exhausted`); #8717 (leader-loop rejection reporting); #8783, #8764 (related
  leader-loop classification work).
- `apps/web-platform/server/anthropic-credit.ts`, `apps/web-platform/test/server/anthropic-credit.test.ts`,
  `apps/web-platform/test/sentry-anthropic-credit-alert-op-contract.test.ts`,
  `apps/web-platform/components/dashboard/failure-reason-copy.ts`.
- ADR-031 (Sentry as IaC), ADR-042 (Anthropic SDK inside the Inngest leader loop, 2026-09-24 amendment).

## Plan Review Record

Panel: DHH, Kieran, code-simplicity (eng); CTO devex (named). All findings below were engineering
corrections or simplifications and were applied as Mechanical; the two Taste decisions (DC-1, DC-2)
are in `decision-challenges.md`.

- Applied: one paging table (`pagesOperator` on the copy row) instead of a second policy record
  (DHH, CTO); class removed from the message and tags (DHH, code-simplicity; Kieran's bounded-class
  finding dissolved with it); source-grep checks cut (DHH, code-simplicity); `toMessagePathError`
  narrowed to `{ name, message, stack, code }` (DHH, code-simplicity); outer `try/catch` over the
  whole report plus a forced-throw test (Kieran); `pg_code` claimed for direct callers only (Kieran,
  code-simplicity); `deadletterCall()` moved to module scope and the refusal `it.each` covered
  (Kieran); two stale comments added to Files to Edit (Kieran); plain-object PostgREST message
  preserved as a stated improvement with a must-pass row (Kieran); `leader_tool_invalid` extra
  (CTO); paste-ready failure message in the contract test (CTO); kill-switch vs missing-module
  reading in the rule comment (CTO); mutation matrices trimmed (DHH).
- Declined: generating the "CTO has been notified." suffix from the field (DHH) — it would change
  how founder text is built in a UI module; the field plus the `/notif/i` check keeps the text
  untouched.
- Superseded at deepen-plan: the `pagesOperator` field on the copy row moved to `PAGES_OPERATOR` in
  `lib/failure-reason.ts` (architecture review). See the Deepen-Plan Record.

## Deepen-Plan Record

Applied (all engineering corrections, Mechanical):

- Architecture: union + `PAGES_OPERATOR` moved to `lib/failure-reason.ts`; no server value import
  from `components/`. `server/spawn-dead-letter.ts` names `server/anthropic-credit.ts` as the
  sibling #8629 workaround to revert together.
- Observability: the catch path logs the cause with `err` (pino-mirror exception) and sends a tagged
  `report failed` message; failure_modes cite their layers; the discoverability test is described as
  the INTENDED state and `liveness_signal` names the live-fidelity check; the
  `acknowledgment_persist_failed` discrimination limit is stated.
- Security: `founderId` → `userId` (hashed) on this event; `toMessagePathError` never spreads `err`;
  `safeToolName` allowlist; residual raw `founderId` on other lines tracked at ship.
- Test design: message-conditioned forced throw with `mock.results`; env-pinned logger plus a
  breadcrumb positive control; `null`/`undefined`/`Object.create(null)` must-pass inputs; literal
  six-reason pin; exact four-row copy set; Guard 1 rows for `logic_type`, `enabled`, `match`,
  `monitor_ids`; set-changing rows merged.
- Verified premises (confirm): mirror captures only `instanceof Error`; `reportSilentFallback`'s
  try/catch wraps only Sentry calls; `redactErrorForEmit` keeps plain objects plain; no
  `attachStacktrace`/fingerprint override; `sanitizeLogMessage` leaves the message unchanged; the
  two unions match (19); exactly four copy rows mention a notification; 1442 unused;
  `persistFailure` is the only Sentry emitter in the handler; the leader-loop `.message`/`.stack`
  assertions survive a plain object; `failure-reason-copy.ts` has no imports and no `"use client"`;
  `tagged_event` `in` with comma-joined values and `event_frequency_count` have in-root precedent at
  provider 0.15.7.
- Gates: User-Brand Impact, Observability (jq verb, literal `ActiveMembers`), Encryption Posture,
  Guard Contract (`lint-guard-contract.py` green), PAT sweep (none), UI wireframe (no UI-surface
  file) all pass.
