---
title: "fix: hash the sessionId on the untrusted-classify log line"
type: fix
date: 2026-11-08
slug: fix-untrusted-classify-session-id-hash
branch: feat-one-shot-9601-untrusted-classify-session-hash
issue: 9601
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: hash the sessionId on the untrusted-classify log line

## Enhancement Summary

**Deepened on:** 2026-11-08
**Sections enhanced:** Phase 2 test design, Guard 1 assembly, Files to Edit entry 3
**Research agents used:** security-sentinel (code-grounded), code-simplicity-reviewer (at plan time), CTO agent (four forks), learnings-researcher; deepen-plan halt gates 4.6, 4.7, 4.8, 4.11, 4.12 all passed.

### Key Improvements

1. Test haystack must not be lowercased: the existing test lowercases its serialized haystack, so a mixed-case sentinel would make a raw-id leak undetectable. The new suite keeps case and adds a positive control per row.
2. One real-logger case so the redaction formatter, `REDACT_PATHS` and the Sentry breadcrumb mirror are actually exercised (every other case swaps the logger for a spy).
3. The distinct-id must-PASS case moved into the pepper-set graph; under the pepper-unset graph both ids collapse to the sentinel. `afterEach` resets stubbed env and modules.

### New Considerations Discovered

- Security review confirmed `emit()` is the single write site of the raw id on this op and that the Sentry `extra` and `hook-error` paths never carry it.
- With the pepper missing in production every session shows `pepper_unset` and per-session correlation is lost; the only signal is the existing module-load boot warning. Stated in the plan and left as is (no new alert; out of scope).

Ref #9601 (epic, slice 2 precondition). Precondition for the untrusted-data work in Ref #4671 and its Article 30 follow-up Ref #10195. The PR body uses `Ref`, never `Closes`: the epic and both trackers stay open.

Spec lacks valid `lane:` (one-shot path, no spec.md) - defaulted to cross-domain (fail-closed).

## Overview

The WebFetch injection-scan hook (`createUntrustedContentHook`) logs one WARN line per classification, `op: "untrusted-classify"`. `emit()` in `apps/web-platform/server/untrusted-content.ts` writes `workspaceIdHash` (pepper-keyed HMAC via `hashUserId`) next to a RAW `sessionId` (the conversation id, forwarded from `cc-dispatcher.ts` as `untrustedContentTelemetry.sessionId`). The raw id is the only identifier on that line that is not pseudonymised.

The CTO ruling (binding, 2026-11-08) is one small PR: replace the raw field with `sessionIdHash: ctx.sessionId ? hashUserId(ctx.sessionId) : undefined` inside `emit()`. Every emit path (flagged, unflagged, truncated, both unscored arms) already funnels through `emit()`, so the production change is one line plus its comment. The hook option `sessionId?: string` and the dispatcher call site keep carrying the raw id; the hash is applied only at the log boundary. No flag, scorer behaviour, field list (apart from the rename) or other surface changes.

## Research Insights

**Premise validation (Phase 0.6).** Checked: #9601, #4671 and #10195 are all OPEN; PR 12415 is this branch's own draft PR (the only open change naming #9601); the collision pre-check reported only unrelated test processes owned by another worktree. Cited code confirmed on this branch: `emit()` at `apps/web-platform/server/untrusted-content.ts` (the `sessionId: ctx.sessionId` line sits directly under `workspaceIdHash`), the `sessionId?: string` hook option, the dispatcher forward in `apps/web-platform/server/cc-dispatcher.ts` (`untrustedContentTelemetry: { workspaceId, sessionId: args.conversationId }`), the forwarding in `apps/web-platform/server/agent-runner-query-options.ts` (`...args.untrustedContentTelemetry`), and the two tests that pin the raw field (`untrusted-content.test.ts` at the "telemetry carries metadata only" case, `untrusted-content-wiring.test.ts` at the "forwards the telemetry context" case). The runbook field list is the `op:"untrusted-classify"` section of `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`. Nothing stale.

**ADR-corpus check (mechanism).** The mechanism is ADR-029 (rename-at-boundary pseudonymisation; hash with the shared pepper, sentinel when unset) applied to one more field; ADR-287 is the record for this log line. Neither lists the mechanism as a rejected alternative. No other consumer of the `sessionId` key on this op exists: `git grep untrusted-classify` hits only the source, the runbook, the ADR and archived planning docs; `apps/web-platform/infra` has no reference to `sessionId`.

**Property List (Phase 0.6b).**

1. P1: no `untrusted-classify` line (any emit path) carries a `sessionId` key or the raw id in any value.
2. P2: the line still lets an operator correlate lines of one session: `sessionIdHash` equals `hashUserId(<id>)`.
3. P3: with the pepper unset the value is the existing `pepper_unset` sentinel and the raw id is never a fallback.
4. P4: the telemetry path stays fail-open and no flag or scorer behaviour changes.

**Cut List.** Candidate mechanisms cut before research: a pino `formatters.log` rename for `sessionId` (buys P1 only for this op by widening the shared logger boundary; ADR-029 says widening needs an ADR amendment, and `emit()` is the single chokepoint that already hashes `workspaceId`); a runtime strip of any caller-supplied `sessionId` key in `emit()` (all callers are in-file, the four-path test is the guard, and silent key-dropping hides mistakes - CTO F2); hashing in `cc-dispatcher.ts` or `agent-runner-query-options.ts` (the binding ruling says hash only at the log boundary, and a second site would be a second place to forget).

**Institutional learnings applied.**

- `knowledge-base/project/learnings/test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md`: `SENTRY_USERID_PEPPER` is read once at module load in `server/observability.ts`, so each pepper state needs its own module graph (dedicated file for the unset pin, `vi.resetModules` + `vi.stubEnv` + dynamic import for the set case).
- `knowledge-base/project/learnings/2026-10-30-the-plan-said-the-audit-line-reaches-better-stack-and-the-shipper-drops-info.md`: the shipper forwards WARN and above only. The line is logged at WARN, so `sessionIdHash` reaches Better Stack; the runbook field list stays accurate.
- `knowledge-base/project/learnings/2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md` and the plan-skill sharp edge on whole-event privacy claims: the "raw id appears nowhere" test serializes every sink the hook can reach (all four logger levels and the debounced Sentry mirror), not only `log.warn` args.
- `knowledge-base/project/learnings/2026-09-18-my-supersession-pointer-named-the-wrong-bracket.md`: the ADR addendum is anchored by an explicit dated heading, not "above"/"below" wording.
- `knowledge-base/project/learnings/2026-05-12-brainstorm-issue-body-option-and-inventory-staleness-pino-userid.md`: operators must be able to turn a raw id into its hash before grepping; the runbook change says how (Phase 4).

**Sinks the event reaches (whole-event enumeration).** (1) `getLog().warn(obj, "untrusted-classify")` - the pino stdout line, shipped to Better Stack; (2) the pino-to-Sentry breadcrumb mirror, which receives the SAME `obj` (`server/logger.ts`), so it carries the hash and nothing else once `emit()` is fixed; (3) `mirrorOnce` Sentry events - `extra` holds only `workspaceIdHash` and an error-class `cause`, never the session id; (4) the `hook-error` catch - `cause` is `err.name` only. Scope of the property: this op's line only. Other log lines elsewhere that carry `conversationId` are out of scope and the PR body must not claim otherwise.

**Lines already shipped.** Lines emitted before this change keep the raw id until log retention expires. A backfill scrub would be an operator-held production write and is not part of this change (CTO F4); it is stated once in the ADR addendum and once in the PR body.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing in the product. `emit()` is wrapped in a fail-open `try/catch`, so a defect can only lose or mis-key the per-session correlation on the telemetry line (non-prod environments without the pepper collapse every session to `pepper_unset`, by design).
- **If this leaks, the user's workflow data is exposed via:** the existing log line, where the raw conversation id sits beside `workspaceIdHash` in Better Stack rows and in the Sentry breadcrumb trail. This change removes that identifier; a regression that re-adds it is what the negative test pins.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change only removes an identifier from one telemetry line (strictly less exposure), so `single-user incident` would over-weigh it; it is not `none` because it sits on a privacy-posture surface (server path, Article 30 register pending). Ruled by the CTO agent (F3); flips to `single-user incident` only if the hash is shown not to be pseudonymous (for example a public pepper).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "hash the sessionId on the `untrusted-classify` log line" | Phase 1 (`emit()` edit) | mapped |
| 2 | "replace the raw `sessionId` field with `sessionIdHash`, computed with `hashUserId(ctx.sessionId)`" | Phase 1; Files to Edit entry 1 | mapped |
| 3 | "Apply to ALL emit paths: flagged, unflagged, unscored, truncated." | Phase 1 (single chokepoint) and Phase 2 six-fixture table | mapped |
| 4 | "keep passing the raw id in; hash only at the log boundary" | Phase 1 (hook option and dispatcher untouched); AC7 | mapped |
| 5 | "No new fields; touch no flag, no scorer behaviour, no other surface." | AC7 diff-scope AC | mapped |
| 6 | "No emitted untrusted-classify line carries a `sessionId` key; a test serializes the logged object and asserts the raw id string appears nowhere." | Phase 2 new test file; Guard 1 | mapped |
| 7 | "with pepper unset the value is the existing "pepper_unset" sentinel and the raw id is NEVER a fallback (test pins this)" | Phase 2 pepper-unset describe | mapped |
| 8 | "Update the two tests pinning the raw field ... add a negative assertion that `sessionId` is absent." | Phase 2 existing-test edits | mapped |
| 9 | "Update the field list in knowledge-base/engineering/operations/runbooks/betterstack-log-query.md" | Phase 4 | mapped |
| 10 | "add one dated append-only addendum to ADR-287" | Phase 4 | mapped |
| 11 | "Enable/create nothing; classify and wrap flags unchanged." | Non-goals; AC7 | mapped |
| 12 | "The PR body states the Article 30 PA-8(c) amendment is still owed and is operator/CLO-class, not part of this PR." | Phase 5 PR-body reminder | mapped |
| 13 | "plan's test plan records that the slow local --affected battery is not awaited because CI is the ship gate" | Test Plan, last bullet | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `untrusted-content.ts` `emit()` edit and its comment | "replace the raw `sessionId` field with `sessionIdHash`" | asked |
| `untrusted-content.test.ts` edit | "Update the two tests pinning the raw field" | asked |
| `untrusted-content-wiring.test.ts` edit | "Update the two tests pinning the raw field" | asked |
| `betterstack-log-query.md` edit | "Update the field list in knowledge-base/engineering/operations/runbooks/betterstack-log-query.md" | asked |
| ADR-287 addendum | "add one dated append-only addendum to ADR-287" | asked |
| New `untrusted-content-session-hash.test.ts` | "with pepper unset the value is the existing "pepper_unset" sentinel and the raw id is NEVER a fallback (test pins this)" | asked (a dedicated file is the CTO-ruled mechanism: the pepper is read once at module load, so two pepper states need two module graphs) |
| One-line runbook sentence on turning a raw id into its hash | "Update the field list" | inferred - justification: a field that is a hash is unusable for lookup unless the runbook says how to compute it (learning 2026-05-12 pino userId), and it is the same section being edited |
| Guard Contract section | "a test serializes the logged object and asserts the raw id string appears nowhere" | asked (the assertion is a guard under plan Phase 2.12) |
| `decision-challenges.md` and `tasks.md` | "spawn `soleur:engineering:cto` for forks and record `Ruled by CTO agent, <date>: <decision> - <rationale>` as rows" | asked |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform` (server, test), `knowledge-base`
- Planned files: 7 (5 edited, 1 created test, plus the plan artifacts) | Estimated changed lines: ~170, mostly tests
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies were checked for the five edited paths (`untrusted-content.ts`, the two test files, the runbook, the ADR); no match.

## Files to Edit

1. `apps/web-platform/server/untrusted-content.ts` - in `emit()` replace `sessionId: ctx.sessionId,` with `sessionIdHash: ctx.sessionId ? hashUserId(ctx.sessionId) : undefined,`; update the `emit()` doc comment ("`workspaceId` is logged as a hash ..." gains the session id) and the `sessionId?: string` option comment (raw in, hashed at the log boundary).
2. `apps/web-platform/test/untrusted-content.test.ts` - in "telemetry carries metadata only", drop `sessionId: "se1"` from the `toMatchObject`, add `expect(fields).not.toHaveProperty("sessionId")` and a `sessionIdHash` string check that is not the raw id.
3. `apps/web-platform/test/untrusted-content-wiring.test.ts` - in "forwards the telemetry context", set a fixed `SENTRY_USERID_PEPPER` inside the `vi.hoisted` block, before any import of `observability` (the `importOriginal` mock loads the real module, which reads the pepper once, so a late assignment is ignored) (so a wrong or missing forward is visible; with the pepper unset every id hashes to the same sentinel and the value cannot be told apart), assert `sessionIdHash` equals an independently computed HMAC of `"sess-forwarded"`, and add the negative `sessionId` assertion.
4. `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` - field list: `sessionId` becomes `sessionIdHash`; one sentence that it is `hashUserId` of the conversation id (`pepper_unset` when the pepper is unset) and how to compute it for a lookup.
5. `knowledge-base/engineering/architecture/decisions/ADR-287-untrusted-content-annotate-not-block-heuristic-first.md` - append one dated addendum at the end of the file (text in Phase 4).

## Files to Create

1. `apps/web-platform/test/untrusted-content-session-hash.test.ts` - dedicated pepper-state and no-raw-id suite (Phase 2). Registered automatically: the `unit` vitest project includes `test/**/*.test.ts` and it is not a repo-wide suite.
2. `knowledge-base/project/specs/feat-one-shot-9601-untrusted-classify-session-hash/tasks.md` and `decision-challenges.md` (planning artifacts; the latter already holds the four CTO rulings).

## Implementation Phases

### Phase 1 - Production change (one line)

In `emit()`, change the logged object so the tail reads:

```ts
workspaceIdHash: ctx.workspaceId ? hashUserId(ctx.workspaceId) : undefined,
sessionIdHash: ctx.sessionId ? hashUserId(ctx.sessionId) : undefined,
```

`hashUserId` is already imported from `./observability`. `...fields` is spread before both hash keys and no internal caller passes `sessionId`, so no `sessionId` key can appear. An absent or empty session id yields no value (never `hashUserId("")`, which would be one constant that correlates unrelated lines). Do not touch `UntrustedContentHookOptions.sessionId`, `cc-dispatcher.ts`, `agent-runner-query-options.ts`, `mirrorOnce`, flags or the scorer.

### Phase 2 - Tests (write first, see them fail, then Phase 1)

New `untrusted-content-session-hash.test.ts` (synthetic fixtures only, per `cq-test-fixtures-synthesized-only`; sentinel id longer than 12 characters and not a substring of any field name or value, for example `"sess-SENTINEL-9c41e7d2"`, with a precondition assertion on its length):

- Mocks as in `untrusted-content.test.ts`: `@/server/logger` (`createChildLogger` returning a spy object with `info`/`warn`/`error`/`debug`) and `mirrorWithDebounce`.
- Describe A, pepper unset: `vi.hoisted(() => { delete process.env.SENTRY_USERID_PEPPER })` (precedent `observability-pepper-unset.test.ts`). Table-driven over six hook inputs, one per emit path: flagged (synthetic override phrase), unflagged (benign text), truncated-only (benign filler longer than `SCORE_MAX_CHARS`), flagged and truncated, unscored `shape` (`{ weird: true }`), unscored `error` (`vi.spyOn(String.prototype, "normalize")` throwing once, as the existing scorer-error test does). For each: exactly one `log.warn` call; `fields` has no `sessionId` own key; `fields.sessionIdHash === "pepper_unset"`; `JSON.stringify` of all four logger spies plus `mirrorWithDebounce.mock.calls` does not contain the sentinel, in a haystack that is NOT lowercased (the existing test lowercases its haystack, which would make an upper-case sentinel unfindable and any leak invisible), with a positive control in the same row that the serialized sink does contain `sessionIdHash`; a floor that the table produced six emits (a vacuity guard on the test's own dispatch).
- Describe B, pepper set: `vi.resetModules()`, `vi.stubEnv("SENTRY_USERID_PEPPER", "<fixed test pepper>")`, dynamic import of the module under test, then the same six paths: `sessionIdHash` equals `createHmac("sha256", pepper).update(id).digest("hex")` computed in the test with `node:crypto` (an independent oracle, not the production `hashUserId`), is 64 hex characters, is not the raw id, and serialized sinks do not contain the raw id. A second sentinel id (the must-PASS case, differing from the canonical) yields a different hash from the first, proving the field is per-session; this can only be asserted here, because under the static pepper-unset graph both ids collapse to the sentinel. `afterEach` calls `vi.unstubAllEnvs()` and `vi.resetModules()` so the stubbed pepper cannot leak into later cases.
- Describe C, absent id (static pepper-unset graph): `createUntrustedContentHook({ workspaceId: "ws1" })` and `sessionId: ""` give no `sessionIdHash` value and no `sessionId` key.
- One real-logger case (pepper-unset graph, `@sentry/nextjs` mocked with an `addBreadcrumb` spy, real `createChildLogger`, pino output captured by spying on stdout): the pino line and the breadcrumb payload contain `sessionIdHash` and not the raw sentinel. Every other case swaps the logger for a spy, so `redactLogArgs`, `formatters.log`, `REDACT_PATHS` and the breadcrumb mirror would otherwise never be exercised, and `sessionId` is not in `SENSITIVE_KEY_NAMES` (`server/sensitive-keys.ts`), so the redaction layer would not catch a regression; the tests are the only guard.

Edits to the two existing tests as listed under Files to Edit; the existing "telemetry carries metadata only" serialization already covers `log.warn` and the mirror, the new file widens it to every logger level.

### Phase 3 - Local confidence, not the gate

Targeted vitest runs of the three touched test files only, from `apps/web-platform` (`./node_modules/.bin/vitest run test/untrusted-content.test.ts test/untrusted-content-wiring.test.ts test/untrusted-content-session-hash.test.ts`), plus `./node_modules/.bin/tsc --noEmit`. The slow local `--affected` battery is NOT awaited: CI is the ship gate (see Test Plan).

### Phase 4 - Docs

Runbook, in the `op:"untrusted-classify"` section: replace `sessionId` with `sessionIdHash` in the field list and add: "`sessionIdHash` is `hashUserId` of the conversation id (the same keyed hash as `workspaceIdHash`; the literal `pepper_unset` when the pepper is unset, never the raw id). To find one session, compute the HMAC-SHA256 of the conversation id keyed with `SENTRY_USERID_PEPPER` from Doppler `prd` and filter on that value; never put the pepper on a command line."

ADR-287, appended at the end of the file (after "Consequences"), one block:

```markdown
## Addendum 2026-11-08 (#9601 slice 2): `untrusted-classify` logs `sessionIdHash`, not `sessionId`

The `untrusted-classify` line carried the raw conversation id next to the hashed workspace id. It now carries `sessionIdHash`, the same pepper-keyed HMAC as `workspaceIdHash` (`hashUserId`); with the pepper unset the value is the literal `pepper_unset` and the raw id is never a fallback. The hook option and the dispatcher call site still pass the raw id; the hash is applied only inside `emit()`. No flag, scorer behaviour or other field changes, and the decision above is unchanged. Lines emitted before this change keep the raw id until log retention expires; no backfill scrub is part of this change. The Article 30 register amendment (PA-8(c)) is still owed and is operator/CLO-class work, tracked with #10195.
```

### Phase 5 - Ship notes

PR body: `Ref #9601`, `Ref #4671`, `Ref #10195` (no `Closes`); states that the Article 30 PA-8(c) amendment is still owed and is operator/CLO-class, not part of this PR; states that lines already shipped keep the raw id until log retention expires; no public security claim. Run `bash scripts/markdown-lint.sh --repo-sweep` and `npx markdownlint-cli2` on the plan and tasks before committing markdown.

## Guard Contract

### Guard 1 - no raw session id on any untrusted-classify emit

**Property.** No `untrusted-classify` log call, and no sink the same hook invocation reaches, contains a `sessionId` key or the raw session id string, on any emit path.

**Assembly.** The chokepoint is `emit()` in `apps/web-platform/server/untrusted-content.ts`; its callers are the five `emitHere`/`emit` sites inside `createUntrustedContentHook` (shape-unscored, scorer-error unscored, unflagged, flagged and/or truncated), exercised as six fixtures. Sinks: the four pino methods of the child logger, `mirrorWithDebounce` calls (`extra`), and the breadcrumb mirror, which receives the same object as the `warn` call (exercised by the one real-logger case). The wiring test covers the one forwarding path (`agent-runner-query-options.ts` spreads `untrustedContentTelemetry` into the hook options). If a new emit site is added later it must go through `emit()`, and the table's emit-count floor makes an unexercised path visible instead of silently green.

**Mutation matrix.**

| # | Mutation (must turn the suite RED) | Target |
|---|-----------------------------------|--------|
| 1 | Revert `emit()` to `sessionId: ctx.sessionId` | no-raw-key and serialized-sink assertions, every row of the table |
| 2 | Emit `sessionIdHash` AND keep `sessionId: ctx.sessionId` | `not.toHaveProperty("sessionId")` (value is hashed, key still present) |
| 3 | Add a raw `sessionId` only on the unscored-`error` arm (first arm compliant, second not) | per-path table row for the second member |
| 4 | Make `emitHere` return before `emit()` on the truncated-only path | emit-count floor and per-path `log.warn` count (dispatch vacuity) |
| 5 | Fall back to the raw id when the hash is the sentinel (`h === "pepper_unset" ? ctx.sessionId : h`) | pepper-unset describe |
| 6 | Leave the hash keyed with a different secret or compute `hashUserId(ctx.workspaceId)` | pepper-set equality against the independent `node:crypto` oracle |
| 7 | Put the raw id in the `mirrorOnce` Sentry `extra` | serialized `mirrorWithDebounce` calls in the sink assertion |
| 8 | Harness: shorten the suite's sentinel id to one character | precondition assertion on the sentinel length/uniqueness |
| 9 | Harness (must-PASS, differs from canonical): different sentinel id with the pepper set | still green, hash differs from the first id's hash |

**Anchor.** The pepper-set case compares the log value to an HMAC computed in the test from `node:crypto` with a pepper the test itself sets, not to the production `hashUserId` output, so a change to the hash function cannot move both sides at once. The pepper-unset case compares to the literal `"pepper_unset"`.

## Observability

```yaml
liveness_signal:
  what: the untrusted-classify WARN line itself, with a sessionIdHash field, in Better Stack rows from web-egress sessions with the classify flag on (flag unchanged by this change)
  cadence: per WebFetch result in a flagged-on session
  alert_target: none new - the liveness and count-mismatch alerts are tracked on #10195 and are not provisioned here
  configured_in: apps/web-platform/server/untrusted-content.ts (emit)

error_reporting:
  destination: Sentry web-platform via the existing mirrorOnce path (feature untrusted-content), unchanged
  fail_loud: emit() is fail-open by design; a telemetry fault never alters the turn, scorer faults mirror one debounced Sentry event per workspace and class

failure_modes:
  - mode: sessionId key reintroduced on the line
    detection: the negative assertions in untrusted-content-session-hash.test.ts and the two edited tests run in CI on every PR that touches the affected paths
    alert_route: CI failure on the PR
  - mode: hash collapses to the pepper_unset sentinel in prd (pepper missing)
    detection: the existing observability boot warning for SENTRY_USERID_PEPPER, and the pepper-unset test pins that the raw id is never the fallback
    alert_route: existing boot-warning path, unchanged

logs:
  where: Better Stack (app-container shipper forwards WARN and above), op untrusted-classify
  retention: Better Stack retention; lines emitted before this change keep the raw id until it expires

discoverability_test:
  command: grep -n sessionIdHash apps/web-platform/server/untrusted-content.ts
  expected_output: sessionIdHash
```

The probe prints nothing on the pre-change tree (exit 1) and the matching source line once Phase 1 lands; preflight Check 10 runs it against the finished diff at ship time. A live Better Stack read needs Doppler credentials and is an operator-side read, not the declared probe.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled four technical forks (test mechanism, absent-id handling and no runtime strip, brand-survival threshold, treatment of already-shipped lines and ADR placement); rulings are rows of `knowledge-base/project/specs/feat-one-shot-9601-untrusted-classify-session-hash/decision-challenges.md`. The binding scope ruling (2026-11-08) is the plan's input.

### Legal

**Status:** reviewed (carry-forward from the operator brief; no agent spawned)
**Assessment:** The Article 30 register amendment (PA-8(c)) is still owed and is operator/CLO-class; legal wording sign-off and any public security claim are operator holds. This plan edits no legal document and makes no public claim; it records the owed amendment in the ADR addendum and the PR body only.

No Product/UX surface (server log line and docs only). GDPR gate (plan Phase 2.7): not triggered - no schema, migration, auth, API-route or `.sql` file, no new processing activity, threshold is not `single-user incident`; the change reduces what is logged.

## Architecture Decision (ADR/C4)

No new architectural decision: the change applies the existing ADR-029 rename-at-boundary pattern to one more field. The ADR-287 addendum (Phase 4) is the in-PR record. C4: the model carries no element or relationship keyed on a log field; actors/systems/relationships checked against `model.c4`, `views.c4` and `spec.c4` for this change: no new external actor, vendor, data store or access relationship (Better Stack and Sentry are already modeled as the log and error sinks and are unchanged). The `c4-count-parity` gate reads derived cardinalities that this change does not move.

## Test Plan

- New `untrusted-content-session-hash.test.ts`: six emit paths x two pepper states plus the absent-id and distinct-id cases (Phase 2).
- Edited `untrusted-content.test.ts` and `untrusted-content-wiring.test.ts`: raw-field pin removed, negative `sessionId` assertion added, wiring test proves the forwarded id by value under a fixed pepper.
- Mutation matrix above is derived from the design and run by hand once against the finished suite during work (each row applied, suite observed RED, reverted). The shared mutation battery is not touched, so its floors (356 rows, MIN_CHECKS 763) and the eslint `no-control-regex` baseline of 19 are neither read nor moved.
- The slow local `--affected` battery is NOT awaited: CI is the ship gate. Local confidence is the three targeted vitest files plus `tsc --noEmit` (Phase 3).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `git grep -n "sessionId" apps/web-platform/server/untrusted-content.ts` shows `sessionId` only as the option name, its comments and the `ctx.sessionId` read inside the hash call; no logged key named `sessionId` remains.
- [ ] AC2: `untrusted-content-session-hash.test.ts` fails against the pre-change `emit()` (all six path rows) and passes after Phase 1.
- [ ] AC3: pepper unset gives `sessionIdHash === "pepper_unset"` on all six paths and the raw id appears in no serialized sink; pepper set gives the independently computed HMAC.
- [ ] AC4: both existing tests no longer pin `sessionId` and assert its absence; the wiring test proves the forwarded id by value.
- [ ] AC5: runbook field list reads `sessionIdHash` (no `sessionId` in the `untrusted-classify` field list); ADR-287 has exactly one new dated addendum appended at the end and no earlier line changed (`git diff origin/main...HEAD -- <ADR path>` shows additions only).
- [ ] AC6: `bash scripts/markdown-lint.sh --repo-sweep` and `npx markdownlint-cli2` on the plan and `tasks.md` are clean; `technical-ruling-gate.sh --branch` passes.
- [ ] AC7: diff scope, measured against the merge-base (`git diff --name-only origin/main...HEAD`) is a subset of: the five Files to Edit, the new test file, this plan, `tasks.md`, `decision-challenges.md` (the files the pipeline writes). No flag, scorer, `cc-dispatcher.ts`, `agent-runner-query-options.ts`, `docs/legal`, `plugins/soleur/docs`, `scripts` or `.github` file appears.
- [ ] AC8: PR body states the Article 30 PA-8(c) amendment is still owed and is operator/CLO-class, not part of this PR; uses `Ref`, not `Closes`.
- [ ] AC9: CI is green on the PR (the required checks are the ship gate).

### Post-merge

None. Nothing is enabled, created or flipped; classify and wrap flags are unchanged, and any production read or write stays an operator hold.

## Non-Goals

- Hashing or removing `conversationId` on any other log line, Sentry event or surface.
- A backfill scrub of lines already shipped (operator-held production write).
- The Article 30 PA-8(c) amendment and any legal wording (operator/CLO-class, tracked with #10195).
- Any flag, flag default, environment, scorer behaviour, field addition or alert.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one carries all three lines.
- The pepper is read once at module load. A test that needs a different pepper state must use a fresh module graph (own file, or `vi.resetModules` + dynamic import); assigning `process.env` after import changes nothing.
- With the pepper unset every session hashes to `pepper_unset`; an equality assertion against `hashUserId(id)` alone cannot tell a correct forward from a wrong one, which is why the wiring test fixes a pepper.
- A one-character or short sentinel id would match field names in the serialized sinks and fail for the wrong reason; the suite asserts the sentinel is long and distinctive.
- The ADR addendum is appended at the end of the file; inserting it next to the 2026-10-25 amendment would break the trailing Alternatives/Consequences structure and the append-only record.
