---
title: "feat: founder approval cards PR-D, the legal-acceptance check endpoint and the web-acceptance hold gate"
date: 2026-11-05
slug: legal-acceptance-verify-endpoint-and-hold-gate
branch: feat-one-shot-12011-pr-d-verify-endpoint
issue: 12011
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-11-05
**Sections enhanced:** Research Insights (verification record), Acceptance Criteria (one post-merge item), Sharp Edges
**Agents used:** repo-research-analyst, learnings-researcher, CTO (rulings F1 to F6 and the ADR-320 follow-up), CLO, plus the plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CPO); the deepen-plan halts 4.6 to 4.13 were run mechanically (results below)

### Key improvements

1. Every platform claim the design leans on was re-read from source in this pass (Next `after`, Sentry `flush`, the registry error mapping, the infra workflow trigger, Sentry initialisation under the custom server); the commands and output are quoted under Research Insights.
2. A dead-emitter risk was named and given a post-merge check: if the production process never resolved `flush` to true, no ack would ever be written and `row_without_event` would fire for every row (AC20).
3. The plan survived the halts: User-Brand Impact present with a valid threshold, Observability schema complete, no PAT-shaped variable, no UI surface, Encryption Posture complete, Guard Contract lint green (3 guards), Scope Check complete, all cited issues and rule ids exist.

### New considerations discovered

- The decide route runs inside the custom server, whose entry point imports the Sentry server config first, so `Sentry.flush` talks to the same client the events were captured on. If the DSN were ever unset, `flush` resolves false and no ack is written (correct: nothing was sent).
- `after` is exported from `next/server` in the installed Next 16.4.3; whether it runs its callback under the custom server is checked by a test at work time, with the caught fire-and-forget promise as the fallback.

## Overview

Last slice of #12011. The founder's web card (PR-C) and the write-once record (PR-B, migration 184) are live. PR-D lets a script read that record and closes the gaps PR-C named:

1. A read-only check endpoint, `GET /api/internal/legal-acceptance/[key]?hash=<64 hex>`, that returns `{status, text_hash, decided_at, row_ok}` for the configured founder and nothing else.
2. A parameterised bearer secret name in `lib/internal-auth.ts`, so the endpoint has its own token (`LEGAL_ACCEPTANCE_VERIFY_TOKEN`) and does not share the Inngest one.
3. A `web-acceptance <key> <hash>` kind in the ship hold evaluator, so a hold backed by a founder's recorded Yes discharges by evidence.
4. A pull-only delivery path for the Request changes note (the team reads it; nothing is pushed anywhere; no card copy changes).
5. The emitter that makes the Sentry rule `legal-acceptance-row-without-event` live: a small acknowledgement table (migration 185) written after the `accepted` event is flushed, and a per-row reconciliation in the endpoint.
6. The Terraform secrets for the endpoint, as a PLAN ONLY under `## Operator Holds`. No `.tf` file ships in this PR; a separate follow-up change carries it after the operator approves the plan, and the merge of that change is the apply.

The PR body says `Ref #12011`, never `Closes`: #12011 stays open until the enabling conditions below are met. The code merges dark (the endpoint answers 503 until both configuration values exist).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (original plan / ADR-319 / task text) | Reality (verified in this worktree) | Plan response |
|---|---|---|
| Terraform secrets file `legal-acceptance-secrets.tf` ships in PR-D (original plan, Terraform changes) | `.github/workflows/apply-web-platform-infra.yml` triggers on a push to main touching `apps/web-platform/infra`, so merging a `.tf` there applies it to production. The founder uuid does not exist in any config yet | No `.tf` in this PR. The shape is a plan under `## Operator Holds` (Operator-reserved). The endpoint is fail-closed (503) until the values exist |
| "Both secrets created by Terraform" (AC17) | ADR-320 (proposed, 2026-11-04) bars `random_password` in the Tier-A-readable web-platform root for secrets that grant write, root or production access. A founder uuid is not a secret at all | CTO ruling 2026-11-05: the read-only token is outside ADR-320 decision 1 and stays Terraform-created; the uuid is entered by the operator outside Terraform (AC18 restated below) |
| "`row_without_event`: reconciliation query run by the verify function" | `verify_legal_acceptance` (184) only reads the row. Sentry is not queryable from SQL, `legal_acceptance` is write-once, and `legal_reauth_event` is purged at 30 days | Migration 185: an ack table written after the flushed `accepted` event, plus an `ack_state` read (CTO F1) |
| "Request changes note is delivered to the team" (ADR amendment enabling condition) | The note lives only in `legal_acceptance.requested_edit`; no code path notifies anyone; `service_role` has no table privilege and the agent process holds a service client | Pull-only delivery by the operator through an owner-level read, runbook shipped; no push, no email, no issue (CTO F2, CLO ruling) |
| `hold-gate-eval.sh` plan mode "exits 3 without a `Delegation:` line" | True today; exit 3 hands the plan to the caller's prose path | A plan that carries any `web-acceptance` gate and no delegation never exits 3 (CTO F3) |
| `verify_legal_acceptance` returns the same envelope as the other RPCs | It returns `{status, text_hash, decided_at, row_ok}` with NO `outcome` key, so `service.ts call()` (which requires `outcome`) would throw `bad_payload` on every call | A dedicated strict `verifyAcceptance` wrapper; `call()` is not loosened |
| `texts/` holds committed legal texts | `apps/web-platform/server/legal-acceptance/texts/` holds only `README.md` and `.gitattributes`; no real text is committed | Every key answers 404 at the endpoint today; the post-merge probe is the 503 dark check, and the gate cannot discharge anything until a text exists |
| The founder page shows state for every verify result | `deriveLegalCardState` has six states; `invalid` has none, so the page shows a failed-checksum row as recorded | CTO F4: no card state in this PR (needs a wireframe, copy under the CLO gate, a service-role read from the page). The gap is written into the ADR amendment and filed as a follow-up; `invalid` is never collapsed into `none` anywhere PR-D touches |
| "A registry read failure is 503, not 404" (CTO F5) | `getLegalText` in `server/legal-acceptance/canonical.ts` catches every `readFileSync` error and rethrows it as `unknown_key`, so an unreadable directory would read as 404 | Edit `canonical.ts` to throw a distinct `read_failed` for anything but ENOENT; the route maps `read_failed` and parse errors to 503 and only `unknown_key` to 404 |
| The new C4 edges are enough | `model.c4` requires a regenerated `model.likec4.json` with every description change (the `c4-model-freshness` gate), the store description and a comment say no agent tool reaches the store, and the plugin components view lists neither `webapp` nor `doppler` | Phase D7 regenerates the JSON, rewrites both sentences, adds the operator read edge and extends the plugin view |
| `lib/internal-auth.ts` is a free-standing helper | `scripts/home-census-trigger.sh` (`CENSUS_PATHS`) and its test bind `lib/internal-auth.ts` into the census gate | Task: run `home-census-trigger.test.sh` after the edit and update the bound set or its record if the pin moves |

## Research Insights

**Deepening verification (2026-11-05, commands re-run in this pass).**

```text
grep '"version"' apps/web-platform/node_modules/next/package.json            -> "version": "16.4.3"
grep -n "after" apps/web-platform/node_modules/next/server.d.ts              -> export { after } from 'next/dist/server/after'
grep -n "function flush" node_modules/@sentry/core/build/types/exports.d.ts  -> export declare function flush(timeout?: number): Promise<boolean>;
sed -n 135,146p apps/web-platform/server/legal-acceptance/canonical.ts       -> readFileSync inside try { } catch { throw new LegalTextError("unknown_key", ... ) }
sed -n 14,20p .github/workflows/apply-web-platform-infra.yml                 -> on: push: branches: [main]; paths: - "apps/web-platform/infra/**"
sed -n 1,5p apps/web-platform/server/index.ts                                -> import "../sentry.server.config";  (instrumentation.ts register() is NOT called with custom servers)
```

Verify-the-negative sweep: "the agent never sees the note" holds in the SQL (`verify_legal_acceptance` builds its jsonb from `status`, `text_hash`, `decided_at`, `row_ok` only, migration 184) and no file under `plugins/` or the agent tools references `legal_acceptance`; "no `.tf` in the PR" is enforced by AC13 as a diff-scope check. Post-edit self-audit: the dropped symbols (`verify_failed`, `ack_failed`, `HELD_UNROUTED`, the dedupe, Guard 4, Operator Hold 2) appear only in the Cut List and Plan Review Rulings, not in any phase, file list, test or acceptance criterion.

**Premise validation (Phase 0.6).** #12011, #12080 and #12031 are open; draft PR #12187 is this branch's own PR (the collision pre-check reported it and foreign `test-all.sh` runs in two sibling worktrees, none touching these files). PR-C is merged as `15ce2469fa`. `verify_legal_acceptance`, `legal_acceptance_row_hash` and the four migration-184 RPCs exist on `origin/main`; migration 185 is free (latest on `origin/main` is 184; no open PR names 185). ADR-319 is the decision record for this store; ADR-320 is the newest ordinal and is relevant to the secrets plan. The mechanism (a bearer-gated read endpoint plus an evaluator kind) is the one the original plan, Phase D1/D2, already specified; none of it sits in an ADR's rejected-alternatives table.

**Property list.**

1. A script on the operator's machine can learn, by key and text hash, whether the configured founder decided that exact text in an authenticated web session, and what they decided.
2. A hold is discharged only for an `accepted` answer whose text hash equals the committed text's hash; every other answer, and every inability to ask, keeps the hold.
3. A row whose checksum no longer matches is never reported as undecided and never discharges anything.
4. A recorded decision that did not pass through the web route (no acknowledgement) becomes a Sentry event the next time that row is verified. The alert is pull-driven: a row nobody verifies stays silent until a sweep exists (filed follow-up).
5. The team can read a Request changes note; the agent cannot, and no new copy of the note is created.
6. The endpoint is dark and fail-closed until the operator supplies its two configuration values.

**Cut list.**

| Mechanism | Property | What covers it / why cut |
|---|---|---|
| Email, Inngest function or private GitHub issue carrying the note | 5 | A second unerasable copy; the agent holds the GitHub identity (CLO and CTO rulings). Pull-only read covers it |
| Ack column on `legal_reauth_event` | 4 | Purged at 30 days, so old rows would read as unacknowledged |
| Reading Sentry's API from the endpoint | 4 | Extra read-token secret and a hard dependency of the gate on Sentry |
| A sweep over all rows for missing acks | 4 | The per-row check on the verify call covers the rows a script cares about; a sweep is a filed follow-up with a stated trigger (before the flag is on for a non-operator founder) |
| In-process emission dedupe and its 10-minute window | 4 | Sentry already groups the event into one issue and the rule throttles per issue (`frequency_minutes = 46`); the only caller is one script (plan review, simplicity and DHH seats) |
| Drafted Sentry rules, a second Operator Hold for them and a `HELD_UNROUTED` ratchet in the contract test | 4 | Nothing in the asks or rulings requires paging on `record_invalid` or a store failure in this slice; the gate is loud (UNEVAL) and the events are in the Sentry stream. A follow-up issue carries the draft rules |
| Separate `verify_failed` and `ack_failed` ops | 4 | One op `store_failed` with `tags.stage` in `verify`, `ack_state`, `ack` meets the mirror-to-Sentry rule |
| A separate Guard 4 with its own mutation table | 1 | One cross-layer test, folded into Guard 2 as a row and a harness row |
| A new founder-page card state for `invalid` | 3 | Needs a wireframe and CLO-gated copy; deferred and tracked (CTO F4) |
| A `.tf` file for the secrets in this PR | 6 | Merge applies it to production; operator-reserved |
| Registry-hash comparison inside the endpoint | 2 | The gate computes it from the committed file; a row for an older hash is true evidence about the text the founder saw |
| Loosening `service.ts call()` to accept payloads without `outcome` | 3 | A dedicated wrapper keeps the unknown-outcome-is-never-success rule intact |

**Key file facts (verified).**

- `apps/web-platform/lib/internal-auth.ts`: `readInternalBearerSecret()` hard-codes `INNGEST_MANUAL_TRIGGER_SECRET`; `bearerMatches(header, secret)` is length-guarded `timingSafeEqual`. Four callers: `trigger-cron`, `schedule-reminder`, `cohort`, and `server/home-census.ts`. A defaulted, closed-union name argument leaves all four unchanged. `egress-audit-ingest` has its own local copy and is untouched.
- `lib/routes.ts` `PUBLIC_PATHS`: the middleware test is `pathname === p || pathname.startsWith(p + "/")` (middleware.ts), so one narrow entry `/api/internal/legal-acceptance` covers the dynamic `[key]` route and no sibling. Learning `2026-06-01-new-internal-api-route-needs-public-paths-registration`: route-level tests alone miss the 307 to `/login`; test through the middleware predicate.
- `server/approval/ops.ts` `LEGAL_OPS` already registers `rowWithoutEvent` (error level). `getLegalText` in `canonical.ts` maps every read error to `unknown_key` (see Research Reconciliation). `reportLegalOp` is the only emitter helper; tags `feature=legal-acceptance`.
- `test/sentry-legal-acceptance-alert-op-contract.test.ts` derives the op set from `server/legal-acceptance`, `app/api/legal-acceptance` and `LEGAL_OPS`, and pins `infra/sentry/alert-reference.json` to the Terraform filters. New ops need the test updated in the same PR.
- `hold-gate-eval.sh`: `known_kind`, `eval_gate`, `need_tools`, the no-delegation exit 3 line, `print_result_line` (`NEEDS` prints no reason today), 27 `# mut:<name>` markers and a mutation arm in `plugins/soleur/test/hold-gate-eval.test.sh` (a PATH `gh` stub that refuses unknown argv with 64).
- `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` is the precedent for the token read: `doppler secrets get … --plain`, token-shape guard, bearer on curl's config (never argv), `--disable --noproxy '*'`, hard-coded `https://app.soleur.ai`.
- `apps/web-platform/infra/inngest.tf` and `egress-audit.tf` are the `random_password`/`random_id` plus `doppler_secret` precedents; `apply-web-platform-infra.yml` applies on push.
- Card copy (`lib/legal-acceptance-copy.ts`) says "Your note is saved with your decision" and nothing about delivery; the copy test bans em dashes and a list of assurance words but does not pin "saved" or "delivered", so a copy change would not be caught: PR-D makes none.
- C4 (read from `model.c4` and `views.c4`): `legalAcceptanceStore` and `webapp -> legalAcceptanceStore` both say "the verify endpoint arrives in PR-D", which this PR falsifies; `views.c4` includes the store in `containers`. `ship` is a component of the plugin. No existing edge from the ship component to the web application or to Doppler.

**Institutional learnings applied.**

- `2026-11-05-a-skip-keyed-on-the-record-not-on-the-success…`: the ack is written only on proof the event was flushed, not on the existence of the row; the gate treats only a validated 200 body as an answer; one limit counted once across layers; the flag is global.
- `2026-06-01-new-internal-api-route-needs-public-paths-registration`: narrow `PUBLIC_PATHS` entry plus a middleware-level test.
- `2026-10-06-an-argv-bearer-sweep…` and the `trigger.sh` precedent: bearer through curl's config file, token-shape guard, no argv.
- `2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success…`: no `--retry` in the evaluator; PATH stubs fail on HTTP 4xx.
- `2026-09-20-the-gate-i-built-to-resolve-a-run-could-be-redirected-by-one-env-var`: the base URL is a literal, no env override, no redirects.
- `2026-11-03-fixture-fields-must-match-the-wire-shape-and-jq-coalesce-swallows-false`: `row_ok` is checked with an explicit jq type predicate, never `//`.
- `2026-10-25-a-framing-guard-for-a-channel-nobody-feeds-ships-green-and-inert`: name the producer of every field an alert reads; the `row_without_event` emitter and its ack producer are both in this PR.
- `2026-07-03-dark-launch-pr-must-exclude-operator-prerequisite-infra`: no `.tf` whose merge-triggered apply needs operator prerequisites.

## Plan Review Rulings

Ruled by CTO agent, 2026-11-05 (binding):

- F1: migration 185 adds a service-role-only ack table (acceptance id and `acked_at`, no founder id, no foreign key). The decide route writes the ack after `accepted` is emitted and `Sentry.flush` resolves true. The verify endpoint calls `ack_state` only when a row exists and emits `row_without_event` when there is no ack and the row is older than 120 s. Per verify call for the one row read, not a sweep. Alert-only: the response and the gate are unchanged. Proves "the route did not ack", not "Sentry received the event".
- F2: team-side pull only. No email, no Inngest function, no GitHub issue. The note stays in `legal_acceptance.requested_edit`; the team reads it with an owner-level query; no `service_role` RPC returns the note. No card copy change. The ADR enabling condition becomes "pull-only delivery, no push".
- F3: `web-acceptance` becomes a known kind. With no `Delegation:` line, a plan whose non-reserved holds carry only `web-acceptance` gates is evaluated without a delegation; a plan mixing `web-acceptance` with another kind and no delegation exits 2, not 3; any other no-delegation plan keeps exit 3. `Operator-reserved:` holds still always stand.
- F4: `invalid` is UNEVAL (exit 2), printed `the record failed its check`; the endpoint passes it through with `row_ok:false` and emits `record_invalid` (error). No new founder-page card state in this PR.
- F5: `GET /api/internal/legal-acceptance/[key]?hash=`, check order 503, 401, 400, 404, lookup; the key is checked against the registry (a registry read failure is 503, not 404); the hash is answered from the database for the exact hash; the mismatch against the committed text is the gate's job. Narrow `PUBLIC_PATHS` entry. The evaluator reads the token with `doppler secrets get LEGAL_ACCEPTANCE_VERIFY_TOKEN --plain --project soleur --config prd`.
- F6: no `.tf` in this PR; the Terraform shape is plan-only under `## Operator Holds`; no `ignore_changes` (follow `egress-audit.tf`).
- Follow-up on ADR-320: "Outside ADR-320 decision 1: read-only status token, reviewed under decision 4 on 2026-11-05. Rotating it does not repair a leak, and it would move out of Terraform if it ever gains write reach." The founder uuid is not a secret: it is entered by the operator into the Doppler dev and prd configs outside Terraform and checked by a read, never `TF_VAR`.

Ruled by CLO agent, 2026-11-05 (draft, not legal advice): the no-note-text, pull-only mechanism adds no recipient, processor or transfer; emailing the note or filing a private issue is not acceptable now (a second, unerasable copy; GitHub is not a PA-40 recipient). The ack table carries no founder id, no note and no decision field, and is listed in PA-40(c). The endpoint must never return the note, must not collapse `invalid` into `none`, and no log line or Sentry payload may carry the note (tested). This PR updates PA-40 only, as an addendum conditioned on the merge (not past tense); the attestation line "the note reaches no one" is narrowed with a `Superseded` marker; the LIA and the three published documents are unchanged here and stay a gate before any non-operator founder. No card copy change.

Plan review (2026-11-05), consolidated from the DHH, Kieran, simplicity, architecture and spec-flow seats and the CPO advisory. Mechanical findings were applied to this plan: the dedupe, the `HELD_UNROUTED` ratchet, the drafted-rules hold and Guard 4 as a separate guard were cut; `verify_failed` and `ack_failed` were merged into `store_failed`; the registry `read_failed` split, the no-delegation classification, the verdict plumbing and exit codes, the flush-throws case, the closed reason table, the C4 completeness items (regenerated JSON, rewritten no-agent-reach sentences, operator read edge, plugin view), the ADR-320 scope note, the order of operations and the AC numbering were added. CPO: signed off with conditions (the invalid-card-state follow-up filed before merge; enabling-condition wording; 8.1 as a tracked follow-through; CP2 to read "In progress (legal-acceptance slice)", never Done). Taste and user-challenge items are in `decision-challenges.md` (splitting the PR; no heal in the `already_recorded` branch; the production-write hold class).

Operator decisions already standing (not re-asked): email-code-only strength (password and provider deferred to #12031), operator first, `Ref #12011` never `Closes`, CI is the merge gate.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A verify endpoint that reads a legal_acceptance row and its checksum." [task, PR-D scope 1] | Phase D2 (endpoint) | mapped |
| 2 | "A parameterised internal-auth for that endpoint." [task, PR-D scope 2] | Phase D2 (`internal-auth.ts`) | mapped |
| 3 | "Terraform secrets for it. Plan only, then stop for approval" [task, PR-D scope 3] | `## Infrastructure (IaC)` and `## Operator Holds` | mapped (plan only) |
| 4 | "A `web-acceptance` kind in hold-gate-eval.sh" [task, PR-D scope 4] | Phase D3 | mapped |
| 5 | "A delivery path for the Request changes note." [task, PR-D scope 5] | Phase D5 (pull-only runbook, no push) | mapped |
| 6 | "An emitter for `row_without_event`." [task, PR-D scope 6] | Phase D1 (migration 185) and D4 (ack and emit) | mapped |
| 7 | "The verify result `invalid` (row checksum mismatch) has no card state. Do not collapse it into `none`." [task, traps] | Guard 1 and Guard 2 (never `none`), ADR amendment, follow-up issue | mapped (card state deferred by CTO ruling) |
| 8 | "Enabling conditions … NOT part of this PR; list as post-merge/operator items" [task] | `## Enabling conditions and post-merge items` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Endpoint, auth parameterisation, gate kind, Terraform plan | asks 1 to 4 | asked |
| Delivery runbook (pull-only) | ask 5 | asked |
| Migration 185 ack table and RPCs | ask 6 | asked (the only way to emit the event, CTO F1) |
| Two new ops (`record_invalid`, `store_failed`) | ask 7 | asked (an `invalid` and a failed read or ack must be visible) |
| ADR-319 amendment, C4 edits | — | inferred — justification: the endpoint and the ack table are a new trust boundary and store, so `wg-architecture-decision-is-a-plan-deliverable` requires the record |
| PA-40 addendum, attestation narrowing | — | inferred — justification: the CLO ruling requires the delivery path and the ack table to be recorded before the flag |
| Cross-layer limit test (key, hash) | "Check every layer for any shared limit" [task, traps] | asked |

### Split Assessment

- Subsystems touched: 3 (`apps/web-platform`, `plugins/soleur`, `knowledge-base`)
- Planned files: about 30 | Estimated changed lines: about 1500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: the file and line estimates exceed the thresholds. The DHH seat recommended splitting into D-a (endpoint, auth, hold gate, docs) and D-b (migration 185, ack, reconciliation); the CPO named the ack table and its ops as the first thing to drop if CI fights back. The operator's stated PR-D scope lists all six items together, so the split is a user-challenge and is recorded in `decision-challenges.md` with the default of one PR. If CI trouble appears, cut D-b (Phase D1 and the ack part of D4) and keep `row_without_event` inert, as it is today.

## Open Code-Review Overlap

None. Nine planned edit paths (`internal-auth.ts`, `hold-gate-eval.sh` and its test, `service.ts`, the decide route, `ops.ts`, `routes.ts`, `canonical.ts`, `article-30-register.md`, `.env.example`) were searched against open `code-review` issues; no body names any of them.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-319 with `## Amendment 2026-11-05 (PR-D)` (not a new ADR: the decision extends the same record). It records:

- the read path as built: endpoint shape, check order, the four-field response, the founder id from configuration, the token separate from the Inngest one;
- the ack table and what `row_without_event` proves and does not prove (CTO F1 wording), alert-only, 120 s grace;
- the note delivery decision: pull-only by the operator, no push, no copy change; the enabling condition in the PR-C amendment ("no delivery path to the team until PR-D") is restated as "pull-only delivery, no push";
- the `invalid` rule: UNEVAL at the gate, `row_ok:false` at the endpoint, and the standing gap that the founder page still shows such a row as recorded (a follow-up with a wireframe, an enabling condition before the flag goes beyond the canary);
- the hold-gate semantics (F3), including that a recorded Yes authorizes no production act;
- the flag remains effectively global (`approval-queue` read with `workspaceId: null`); the endpoint does not read the flag at all;
- the hard limits on the endpoint are the 48-character bearer token, the read-only RPC and the single configured founder id; a wrong token is answered 401 with no throttle, which the token length makes acceptable; a Tier-A reader (a branch workflow) can read the token from state and query one founder's status, which is bounded and is the consequence of choosing Terraform over a Doppler-only token;
- the alert is pull-driven (it fires when a row is verified); `already_recorded` never acks, because a heal there would hide a row that was written through the RPC directly; a row whose ack was lost is reconciled by the operator through the runbook after confirming with the founder; a sweep is a filed follow-up;
- a recorded Yes authorizes no production act and a `web-acceptance` gate backs only a hold on that legal acceptance itself, for a text written for that hold;
- the ADR-320 review on the verify token (the sentence quoted under Plan Review Rulings), plus a one-line scope note added to ADR-320 itself that points to this amendment, so the next reader applying decision 4 finds the ruling.

Status stays `adopting`: no real row has been recorded and the endpoint has not run against one.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) are read in Phase D7 before the edit. Enumeration checked against them now:

- External human actors: the founder (modeled as `founder`, interacts with `webapp`); the reader of the note is the operator, the same actor. No new human actor.
- External systems: Supabase (the store container is modeled), Doppler (modeled; the token is read from the `soleur/prd` config), Sentry (modeled; the new events use the existing `webapp -> sentry` edge). No Resend or GitHub edge is added because nothing is pushed.
- Data stores: `legalAcceptanceStore` (modeled) gains the ack table; its description and the `webapp -> legalAcceptanceStore` edge both say "the verify endpoint arrives in PR-D" and must be rewritten.
- Actor-to-surface access relationships that change: a new edge from the plugin's `ship` component to `webapp` (read-only HTTPS bearer to the check endpoint) and from the `ship` component to `doppler` (read of the one token); and the operator's owner-level read of the stored note, a `founder -> legalAcceptanceStore` edge described as operator-only and not agent-reachable. The comment that says there is deliberately no `engine -> legalAcceptanceStore` edge and the store description that says no agent tool reaches it are rewritten to say the agent can read four fields about one decision and can never read the note. The plugin components view in `views.c4` does not list `webapp` or `doppler`; both are added so the edges render (the file's #7332 comment). `knowledge-base/engineering/architecture/diagrams/model.likec4.json` is regenerated with `scripts/regenerate-c4-model.sh` and the `c4-model-freshness` test must pass.

Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` (the new edges must not move a cardinality the parity gate derives; run it and read the result).

### Sequencing

ADR amendment and C4 edits ship in this PR with the code they describe.

## Infrastructure (IaC)

### Terraform changes

PLAN ONLY. No `.tf` file is created or edited by this PR. The following is what the operator is asked to approve (see `## Operator Holds`):

- `apps/web-platform/infra/legal-acceptance-secrets.tf` (new; applied by the approved apply path, not by this PR's merge): a `random_password` per config (`dev`, `prd`; length 48, `special = false`) and a `doppler_secret` per config named `LEGAL_ACCEPTANCE_VERIFY_TOKEN`, `project = "soleur"`, `visibility = "masked"`, with no `ignore_changes` (follow `egress-audit.tf`, so a `-replace` of the random resource reaches Doppler). Providers already declared in the root (doppler, random); no new provider or version pin.
- `LEGAL_ACCEPTANCE_FOUNDER_ID` is NOT a Terraform resource: it is the operator's Supabase auth user uuid for each project (dev and prd differ because the projects differ), entered by the operator into the Doppler `dev` and `prd` configs outside Terraform and verified by a read. Reason: it is a pseudonymous data-subject identifier, not a secret, and keeping it outside Terraform keeps it out of Tier-A-readable state and out of `TF_VAR`.
- Documentation: both names are added to `apps/web-platform/.env.example` as Doppler-only commented entries (this part IS in the PR; a comment only).
- ADR-320 review (decision 4): the verify token is a read-only status token (four fields about one decision, no write, no host or database reach), outside decision 1. Rotating it does not repair a leak of Tier-A-readable state, and it moves out of Terraform if it ever gains write reach.

### Apply path

<!-- lint-infra-ignore start: plan-only operator-reserved hold; prescribes an approval, applies nothing in this PR -->
Not a host change. A `doppler_secret` apply through the existing web-platform infra workflow, which applies on the push that merges the `.tf`; so the apply IS the merge of a follow-up change that carries `legal-acceptance-secrets.tf`, and Operator Hold 1 is the approval of that merge. The follow-up's plan output is what the operator reviews. Order of operations: this PR merges and deploys (migration 185 applies with the deploy and `verify/185` reports `bad = 0`; the decide route's ack call fails soft, `store_failed`, if it ever ran ahead of the migration) → the operator approves the plan → the follow-up `.tf` merges and applies → the operator enters the founder uuid per project → the web app restarts to read both values → the dark probe turns from 503 to 401 → the first real acceptance (8.1) is verified by the gate → only then the flag. The web app reads the values at its next restart; no downtime. The endpoint answers 503 until both values exist, so code-first is safe.
<!-- lint-infra-ignore end -->

### Host fan-out

Not applicable: no `terraform_data` SSH provisioner is added or edited.

### Distinctness / drift safeguards

One `random_password` per config, so `dev != prd` by construction (no HCL comparison, as `anthropic-ci-key.tf` and ADR-244 ruled); the live check is a names-only read of both configs plus a value-inequality probe that prints booleans only. State holds the token value (Tier-A readable root; reviewed under ADR-320 above). The founder uuid differs per project and is verified by a read that prints booleans only: uuid-shaped, and present in that project's `auth.users` (a typo or a swapped dev and prd value would otherwise make every call answer `none`).

### Vendor-tier reality check

Doppler: no tier gate on a secret in an existing project and config. Supabase: the ack table is two small RPCs and one tiny table on the existing project. No new vendor account.

## Observability

```yaml
liveness_signal:
  what: "Sentry feature tag legal-acceptance, op=accepted per recorded row (existing); op=row_without_event (now has an emitter, live once the endpoint is configured), record_invalid and store_failed (new) from the endpoint and the decide path; the hold evaluator prints one verdict line per hold"
  cadence: "per request (decide) and per verify call"
  alert_target: "legal-acceptance-row-without-event (committed in PR-C, applied; reachable only once the endpoint answers 200); record_invalid and store_failed have no paging rule in this PR, a follow-up issue carries the draft rules"
  configured_in: "apps/web-platform/server/approval/ops.ts (LEGAL_OPS), apps/web-platform/infra/sentry/issue-alerts.tf (existing rule, unchanged), apps/web-platform/server/legal-acceptance/service.ts"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN, feature=legal-acceptance"
  fail_loud: "endpoint: 503 when the token or founder id is unset or malformed, or the registry cannot be read; 401 on a wrong token; 502 on an unrecognised RPC payload; the hold evaluator keeps the hold and prints a distinct reason for every case (endpoint not configured yet, token rejected, key not in the deployed registry, answer not understood, no decision recorded for this text version, hash mismatch, declined, changes requested, the record failed its check, unreachable)"

failure_modes:
  - mode: "a legal_acceptance row exists with no ack older than 120 s (written outside the route, or the route died between commit and ack, or the flush failed)"
    detection: "a verify call reads ack_state and emits op=row_without_event (pull-driven: only when that row is verified)"
    alert_route: "Sentry issue alert legal-acceptance-row-without-event (page)"
  - mode: "a row fails its checksum (status invalid)"
    detection: "verify_legal_acceptance returns invalid; endpoint emits op=record_invalid and answers row_ok=false"
    alert_route: "Sentry stream, no paging rule in this PR (follow-up issue); the gate is UNEVAL and says so in the ship session"
  - mode: "the verify RPC, the ack_state RPC or the ack RPC fails, throws, or answers an unrecognised payload"
    detection: "op=store_failed with tags.stage in verify, ack_state, ack; the endpoint answers 503 or 502 and the decide response is unaffected"
    alert_route: "Sentry stream, no paging rule in this PR; a lost ack later surfaces as row_without_event"
  - mode: "hold evaluator cannot reach the endpoint, has no token, or gets a non-validated body"
    detection: "evaluator verdict UNEVAL with the specific cause (exit 2)"
    alert_route: "visible in the session and PR body; no silent discharge"

logs:
  where: "Sentry events (no note, code, address or text in any payload; tested) and the evaluator's stdout"
  retention: "Sentry default 90 days; ack rows are retained with the acceptance row (PA-40 addendum)"

discoverability_test:
  command: "grep -o web-acceptance plugins/soleur/skills/ship/scripts/hold-gate-eval.sh"
  expected_output: "web-acceptance"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Supabase Postgres, table legal_acceptance_ack (prd project), same project as legal_acceptance"
    mechanism: "provider-managed:supabase-postgres-aes256"
    evidence: "scripts/encryption-posture-ledger.json, Supabase store entries (mechanism string provider-managed:supabase-postgres-aes256)"
    defends_against: "theft of a storage volume or backup without database credentials"
    does_not_defend: "a holder of the service-role key or a database owner, who can write both an acceptance row and its ack; the table holds an acceptance id and a time only"
    disclosed_as: "PA-40 addendum in the Art. 30 register"
    live_verification: "lint-encryption-posture.py in CI resolves the ledger entry"
in_transit:
  - connection: "hold evaluator on the operator's machine to https://app.soleur.ai/api/internal/legal-acceptance (bearer over TLS); web app to Supabase RPC; decide route to Sentry"
    tls: "TLS 1.2+ on all three"
    cert_verification: on
    does_not_defend: "a compromised operator machine or an agent that already holds the verify token (it can read one decision's status, nothing else)"
    disclosed_as: "Data Protection Disclosure transport section; PA-40 addendum"
```

## Guard Contract

### Guard 1 — web-acceptance hold gate (`hold-gate-eval.sh`)

**Property.** A hold backed by a web acceptance is discharged only when the endpoint confirms status `accepted` with `row_ok` true for exactly the text hash named in the plan, and that hash equals the sha256 of the committed text file; every other state, and every inability to ask, keeps the hold with its own printed reason; a plan carrying a `web-acceptance` gate and no delegation never reaches the legacy prose path, and a no-delegation plan without such a gate still does.

**Assembly.** `known_kind`, `eval_gate`, the new `gate_web_acceptance` function and its helpers (input validation, local hash, token read via the shared bearer helper, curl call, body validation), the new `PERSON` result value and its mapping in the aggregation loop, the plan-level classification that decides between exit 3, exit 2 and evaluation (which routes through the same structural checks as today: stray-marker count, one section, no orphan gate, zero-hold check, `need_tools`), `print_result_line`, the grammar comment, and the three outcomes of every hold (`discharged`, `held`, `unevaluable`). All verdicts flow through `eval_gate` into the one aggregation loop: TRUE discharges, FALSE and PERSON stand (exit 1), UNEVAL stands (exit 2); the `Operator-reserved:` branch is a second chokepoint and stays untouched.

Closed table of what the gate prints (every row is a test):

| Endpoint answer | Verdict | Printed reason |
|---|---|---|
| committed text hash differs from the gate hash | FALSE | `hash mismatch` |
| 200, `accepted`, `row_ok` true, echoed hash equal | TRUE | `decided <UTC date>` in the checked suffix |
| 200, `none` | FALSE | `no decision recorded for this text version` |
| 200, `declined` | PERSON | `declined; a revised text with a new hash is needed` |
| 200, `changes_requested` | PERSON | `changes requested; read the note per knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md` |
| 200, `invalid` | UNEVAL | `the record failed its check` |
| 503 | UNEVAL | `endpoint not configured yet` |
| 401 | UNEVAL | `token rejected` |
| 404 | UNEVAL | `key not in the deployed registry` (a text added in the same PR is not deployed yet: such a hold is a post-merge hold) |
| 400, 502, a non-JSON, extra-key or wrong-type body, a status outside the closed set, an echoed hash that differs | UNEVAL | `answer not understood` |
| timeout, DNS or connect failure, oversize body, redirect | UNEVAL | `unreachable` |
| no `doppler`, no token, a token that fails the shape guard, no hash tool | UNEVAL | `no access to the verify token` or `no hash tool` |

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Treat a 5xx, a timeout or an empty body as discharged | unreadable must hold |
| 2 | Discharge any status other than `accepted` (one run per status: `changes_requested`, `declined`, `none`, `invalid`), or map `invalid` to FALSE, TRUE or the `none` wording | only `accepted` discharges and `invalid` is UNEVAL with its own reason |
| 3 | Skip the local committed-file hash comparison | a revised text must not inherit an old acceptance |
| 4 | Skip the echoed `text_hash` equality with the gate hash | the endpoint must answer about the text asked |
| 5 | List `web-acceptance` in `known_kind` but leave `eval_gate` without the case | a gate that evaluates 0 and exits 0 is vacuous |
| 6 | Accept a malformed gate: path characters, a 64-char key, uppercase hex, a missing or extra token, a tab or NBSP | input is validated before any request |
| 7 | Follow a redirect, drop `--max-redirs 0`, or read the base URL from the environment | the base is a literal and redirects are refused |
| 8 | Route a no-delegation plan with a web-acceptance gate to exit 3, or let a plan mixing it with `pr-merged` and no delegation reach exit 0 or 1 | the prose path could discharge it, and a mix without a delegation is exit 2 |
| 9 | Stop exiting 3 for a no-delegation plan that has only `Operator-reserved:` holds, or only gate-less holds | the converse: legacy prose holds keep the prose path |
| 10 | Check `row_ok` with `//` or truthiness | `row_ok` false must hold |
| 11 | Put the token on argv or in a world-readable file | the bearer reaches curl through a 0600 config only |

**Harness rows.** Remove the `curl` PATH stub so every case sees "unreachable": the suite must fail rather than pass on all-held. Remove the `doppler` stub: the suite must fail. Must-PASS inputs other than the canonical: a committed text containing `|`, `"`, a multibyte character and a trailing newline (its sha256 matches `sha256sum`); a plan with two holds where only the second is a web acceptance; a plan with a valid delegation and a web-acceptance gate beside a `pr-merged` gate; an `Operator-reserved:` hold beside a web-acceptance hold (the reserved one stands, the other discharges).

**Anchor.** The independent anchor is the committed text and its hash: changing the plan hash alone does not match a recorded row, and changing the committed text changes the hash the gate computes. A holder of the service key can write a row and its ack; that is the disclosed ADR-319 residual, and the gate says nothing about it. The gate reads no freshness bound: a text must be written for the hold it backs, and `operator-holds.md` says so.

### Guard 2 — verify endpoint (`app/api/internal/legal-acceptance/[key]/route.ts`)

**Property.** The endpoint returns data only to a request carrying the exact configured token, only about the founder id in its own configuration, and the 200 body has exactly the four keys `status`, `text_hash`, `decided_at`, `row_ok`; `invalid` is passed through as `invalid` with `row_ok:false`; and the key and hash shapes it accepts are the same predicate in TypeScript, SQL and bash.

**Assembly.** The route handler (check order), `readInternalBearerSecret(name)` and `bearerMatches`, the founder-id read and uuid check, the registry key check and the `read_failed` versus `unknown_key` split in `canonical.ts`, the `verifyAcceptance` wrapper (strict payload validation), the response builder, the `PUBLIC_PATHS` entry, `.env.example`, and the key and hash shapes (`KEY_RE`, `TEXT_HASH_RE`, the migration 184 and 185 predicates, the bash gate regexes). Every status the route can emit is in one closed set `{200, 400, 401, 404, 502, 503}` declared once and used by the tests.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Look up the row before comparing the token | token is checked before any lookup |
| 2 | Return 401 when the token is unset, or 503 on a wrong token | unset is 503, wrong is 401 |
| 3 | Accept an empty-string token or an empty configured secret | an empty secret is unset |
| 4 | Add `requested_edit` (or any fifth key) to the body | the agent must never see the note |
| 5 | Read the founder id from the query or a header | the id comes only from configuration |
| 6 | Map `invalid` to `none`, or drop `row_ok:false` | `invalid` has no collapse |
| 7 | Turn an unknown key into 200 `none`, or a registry read failure (`read_failed`) into 404 | unknown key is 404, a failed read is 503 |
| 8 | Accept a second, wrong token after a right one (two-token compare) | exactly one configured token |
| 9 | Remove the `PUBLIC_PATHS` entry, or widen it to `/api/internal` | the middleware would 307 to `/login`, and the entry must stay narrow |
| 10 | Allow a 64-character key in `KEY_RE`, or uppercase hex in the bash hash check, or a leading hyphen in the bash key check | the three layers must refuse what the SQL CHECK refuses |

**Harness rows.** Remove the RPC stub: the suite must fail. The cross-layer test extracts the SQL CHECK expression (migration 184, and the RPC argument checks in 185) and the bash regexes from the source files and compares them with `KEY_RE` and `TEXT_HASH_RE`; an empty extraction fails the test. Must-PASS inputs other than the canonical: the bare token without the Bearer prefix (the helper accepts both), a key at the 63-character limit and one at 62, a hash that is not the registry's current hash (answered from the database, not rejected).

**Anchor.** The response key set is pinned by the keys of `jsonb_build_object` in migration 184's `verify_legal_acceptance`, read by the test from the SQL file, and the key and hash shape by the deployed migration 184 CHECK constraints, so a column added to the RPC and not to the endpoint (or a shape widened in one layer) is red.

### Guard 3 — `row_without_event` reconciliation (ack write and ack read)

**Property.** A `legal_acceptance` row that the web route did not acknowledge after a flushed `accepted` event becomes a `row_without_event` Sentry event whenever it is verified more than 120 s after it was written; an acknowledgement is written only on proof the event was flushed; and nothing in the flush or the ack can change the founder's response to a recorded decision.

**Assembly.** The chain `record_legal_acceptance` returns, `reportLegalOp("accepted")`, `flushEvents` (injected into `decideLegal`), `ack_legal_acceptance`, run off the request path (after the response, `after()` from `next/server` where it works under the custom server, otherwise a caught fire-and-forget promise; chosen at work time with a test); the `ack_legal_acceptance` and `legal_acceptance_ack_state` RPCs; the verify route's emitter; the `already_recorded` branch (a second tab must not ack on behalf of a first tab that died, and must not hide a row written through the RPC directly). The ack table is the single store; no other path writes it.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|----------|---------------------|
| 1 | Write the ack before the flush, or when the flush returned false | the ack is proof of a flushed event |
| 2 | Ack in the `already_recorded` branch | a second tab proves nothing about the first, and it would hide a pre-empted row |
| 3 | Skip the ack-state read when a row exists and is older than the grace | the emitter would be dead (the rule stays inert) |
| 4 | Emit when the row is younger than 120 s | a write in progress is not a gap |
| 5 | Let a throwing flush, a throwing ack or an ack RPC error turn the decide response into 500 or `decideRejected` | a recorded row must never be reported as not recorded |
| 6 | Emit `row_without_event` for a `none` status, or skip the check for `invalid` | no row, no gap; an invalid row is the one most likely to lack an ack |
| 7 | Add a founder id or any decision field to the ack table | the ack carries an acceptance id and a time only |
| 8 | Let the ack function set the write-door setting of `legal_acceptance` | the ack must not open the write door |

**Harness rows.** Make the Sentry flush stub never answer true: the suite must fail (no ack written). Must-PASS: a row acked 1 s after the write (no event); two rows for different hashes where only the second lacks an ack (one event); a flush that never resolves (the response is still returned).

**Anchor.** The Sentry rule `legal-acceptance-row-without-event` and the alert contract test pin the op name outside this PR's new code (committed in PR-C); the ack table's column set is pinned by the migration static test. An actor with the service key writes both a row and its ack; stated in the ADR, not defended.

## GDPR / Compliance Gate (advisory)

Ran `soleur:gdpr-gate` at plan time on this plan (migration 185 is a `.sql` path, and the brand threshold is `single-user incident`). **This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.** The CLO ruled on the same surface on 2026-11-05 (see Plan Review Rulings); the gate adds these checks against the planned schema (column names only, no values):

| check_id | Severity | Finding | Disposition in this plan |
|---|---|---|---|
| GDPR-Art-6 | Important | New table `legal_acceptance_ack` needs a `-- LAWFUL_BASIS:` annotation | Phase D1: legitimate interests, Art. 6(1)(f), same LIA and PA-40 as `legal_acceptance` |
| GDPR-Art-5e | Important | New table needs retention metadata | Phase D1: `-- RETENTION:` states it is kept with the acceptance row, period unconfirmed by counsel (#12080) |
| GDPR-Art-17 | Important | No foreign key to `users` and no erasure cascade | Intentional and identical to 184: pseudonymous uuid join key, kept under Art. 17(3)(e); CLO ruled the table acceptable with no founder id, no note, no decision field |
| GDPR-Chapter-V | none | No new vendor, SDK or env var carrying personal data (the Doppler token read and Sentry events are existing flows; no note text reaches either) | Tested: no payload carries the note |
| GDPR-Art-9 | none | Columns `acceptance_id`, `acked_at` match no special-category name; the free-text note (`requested_edit`) is an existing 184 column and can incidentally hold anything | No new exposure: the endpoint never returns it, the runbook restricts who reads it; redaction path stays #12080 |
| DSAR completeness | Important | A new table must be in the DSAR allowlist or its exclusions | Added to `DSAR_TABLE_EXCLUSIONS` with a reason (Files to Edit) |

No Critical finding, so no `compliance-posture.md` write and no `compliance/critical` issue is triggered by the gate. The PA-40 addendum is the CLO-ruled record.

## User-Brand Impact

- **If this lands broken, the founder experiences:** a hold that discharges on the wrong answer (a Decline, a changes-request, a record whose checksum failed, or an older text's acceptance) so an agent proceeds with a legal step the founder did not approve; or a hold that never discharges after a real Yes, with a reason the founder cannot read; or a recorded decision that was written outside their web session and nobody is told. Covered by Guards 1 to 3 and AC1 to AC12.
- **If this leaks, the user's data is exposed via:** the verify endpoint returning more than four fields (in particular the free-text `requested_edit` note, which can contain personal data), the verify token read from Tier-A-readable Terraform state or printed on a command line, or a delivery path that copies the note into a mailbox, an issue or a log. Covered by Guard 2 mutation 4, Guard 1 mutation 11, the pull-only ruling, and the no-note-in-any-payload test.
- **Artifacts and vectors added by this slice:** the ack table (acceptance id and time; pseudonymous by linkage), the bearer token (read-only; held by whoever can read the Doppler prd config, including the agent by design), the founder uuid in configuration, and a Request changes note that the team reads through an owner-level query.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one hold discharged on a record that was forged, mis-matched or failed its integrity check ends trust in "the founder decides", so the tier is the highest rather than an aggregate pattern.

CPO sign-off is required before `soleur:work` begins (carried from the brainstorm and the original plan; recorded under Domain Review). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings F1 to F6 and the ADR-320 follow-up are recorded under `## Plan Review Rulings`. Residuals: the `accepted` event is warn-level and a Request changes row pages nobody (the operator is the first user and the gate prints `changes requested` with the runbook path); a holder of the service key writes both a row and its ack; rows nobody verifies are not checked until a sweep exists; `record_invalid` and `store_failed` have no paging rule until the follow-up issue is done.

### Legal (CLO)

**Status:** reviewed
**Assessment:** See `## Plan Review Rulings`. Counsel remains the gate for the retention period and the note redaction path (#12080, counsel item 17); the delivery path must not create a copy outside it.

### Product (CPO)

**Status:** reviewed, signed off with conditions (plan review 2026-11-05)
**Assessment:** PR-D adds no UI surface: no component, page or copy file is created or edited, so the Product/UX gate does not fire at BLOCKING (the mechanical UI-surface scan of the Files lists found no match). Conditions, all applied: the follow-up issue for the failed-checksum card state is filed before merge with a wireframe requirement; the enabling-condition wording no longer assumes a canary (the flag is global); 8.1 is a tracked follow-through; roadmap CP2 reads "In progress (legal-acceptance slice)", never Done. Before any customer founder: a named reader role with a response expectation, a count-only "note waiting" signal, a visible acknowledgement and closed loop for the founder, CLO-approved card copy that matches the real delivery behaviour, a runbook a non-engineer can follow, and the 8.3 UX test as a hard gate.

### Product/UX Gate

**Tier:** none
**Decision:** skipped (no UI-surface path in Files to Create or Edit)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Implementation Phases

### Phase D1 — Migration 185 (ack table and two RPCs)

`apps/web-platform/supabase/migrations/185_legal_acceptance_ack.sql` (+ `.down.sql` that refuses while rows exist, + `verify/185_legal_acceptance_ack.sql` sentinel). Precondition `DO` block (`public.legal_acceptance` exists). Table `legal_acceptance_ack(acceptance_id uuid primary key, acked_at timestamptz not null default now())`: no foreign key, no founder id, RLS on, all privileges revoked from every api role, a `soleur:no-data-api` comment as 184 does. `ack_legal_acceptance(p_founder_id, p_key, p_text_hash)` and `legal_acceptance_ack_state(p_founder_id, p_key, p_text_hash)`: `SECURITY DEFINER`, `SET search_path = public, pg_temp`, refuse a caller with `auth.uid() IS NOT NULL` (42501, as `verify_legal_acceptance` does), raise on a `p_key` or `p_text_hash` that fails the 184 shape predicate, `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` then `GRANT EXECUTE … TO service_role`. The ack inserts with `ON CONFLICT DO NOTHING` and answers `{outcome: acked | not_found}`; `ack_state` answers `{outcome: none}` or `{outcome: row, acked: boolean, age_seconds: integer}` with the age computed in the database (no clock skew). Neither function sets the write-door setting of `legal_acceptance`. The migration carries the same annotations 184 does (`-- LAWFUL_BASIS: legitimate_interests (Art. 6(1)(f))`, `-- RETENTION:` with the acceptance row's period, unconfirmed by counsel, and a DSAR note), and `server/dsar-export-allowlist.ts` gets a `legal_acceptance_ack` entry in `DSAR_TABLE_EXCLUSIONS` with a stated reason (`test/dsar-allowlist-completeness.test.ts` fails otherwise). Number 185 is re-verified against `origin/main` and open PR heads at PR time. Tests first: `test/legal-acceptance/migration-185-legal-acceptance-ack.test.ts` (static shape, mirrors 184) plus the tenant-isolation test extended for the new table.

### Phase D2 — Endpoint, registry split and internal-auth

`server/legal-acceptance/canonical.ts`: `getLegalText` throws a distinct `read_failed` for any error other than a missing file; unit test for the split. `lib/internal-auth.ts`: `readInternalBearerSecret(name: InternalBearerSecretName = "INNGEST_MANUAL_TRIGGER_SECRET")` with `InternalBearerSecretName` a closed union of `"INNGEST_MANUAL_TRIGGER_SECRET" | "LEGAL_ACCEPTANCE_VERIFY_TOKEN"`; the four existing callers are unchanged. `server/legal-acceptance/service.ts`: `verifyAcceptance` (strict: `status` in `none|accepted|declined|changes_requested|invalid`, `text_hash` equals the requested hash, `none` has null `decided_at` and `row_ok`, `invalid` has `row_ok:false`, `accepted|declined|changes_requested` have `row_ok:true` and a timestamp; anything else throws `bad_payload`), `ackAcceptance`, `ackState`; the 40001 retry helper is shared, `call()` is not loosened. `app/api/internal/legal-acceptance/[key]/route.ts`: `GET`, `dynamic = "force-dynamic"`, `Cache-Control: no-store`, order 503, 401, 400, 404, lookup; on a row the route reads `ackState` and emits `row_without_event` on every verify of a row that is unacked and at least 120 s old (the grace is a named constant with a comment); `invalid` also emits `record_invalid`; an RPC failure or throw emits `store_failed` (tag `stage`) and never turns into a 200. `lib/routes.ts`: narrow `PUBLIC_PATHS` entry. `.env.example`: the two names as Doppler-only comments. Run the census tests after the `internal-auth.ts` edit.

### Phase D3 — The `web-acceptance` hold gate and the shared bearer helper

A small sourced helper `plugins/soleur/scripts/lib/bearer-curl.sh` carries the token read (`doppler secrets get <name> --plain --project soleur --config prd`, fixed project and config, shape guard, no value in any output), the 0600 curl config written with `printf` under the caller's scratch dir, the hardened curl flags (`--disable --noproxy '*' --proto =https --max-redirs 0 --connect-timeout 5 --max-time 15 --max-filesize 4096`, no retry, refuse under xtrace, the TLS env variables unset) and the status capture. `trigger-cron/scripts/trigger.sh` adopts it only if its existing suite passes unchanged; otherwise adoption is a filed follow-up and the helper is the single copy for the new code. `hold-gate-eval.sh`: add the kind, `gate_web_acceptance`, the `PERSON` result value (mapped to the `NEEDS` line with a reason, a standing hold, exit 1; `print_result_line` appends a reason only when one is given, so the zero-gate wording is unchanged) and the plan-level classification: a plan with at least one `web-acceptance` gate and no delegation is evaluated through the same structural checks as today (stray-marker count, one section, no orphan, zero-hold check, `need_tools`); mixed kinds with no delegation exit 2; a no-delegation plan with no `web-acceptance` gate (including reserved-only and gate-less plans) keeps exit 3. The function validates the two tokens, hashes the committed blob `HEAD:apps/web-platform/server/legal-acceptance/texts/<key>.md` (`sha256sum`, else `shasum -a 256`; a CR byte or a missing blob is UNEVAL), compares with the gate hash, calls the hard-coded `https://app.soleur.ai` URL through the helper and validates the body with `jq -e` (exact keys, closed status set, echoed hash equal, explicit `row_ok` type predicate). Verdicts and reasons follow the closed table under Guard 1. Update the grammar comment, `operator-holds.md` (three kinds; the no-delegation rule; what each reason means; what ship does per exit code: print the card route `/dashboard/approvals/legal/<key>`, offer defer-with-issue, and say that a declined or changes-requested hash is terminal so a revised text is needed; that a `web-acceptance` gate backs only a hold on that legal acceptance for a text written for that hold) and `standing-delegation.md` section 3. Tests first in `hold-gate-eval.test.sh` with PATH stubs for `doppler` and `curl` that refuse unknown argv with 64, plus new `# mut:` markers and `mutate`/`killed` rows for every row of Guard 1.

### Phase D4 — Ack and ops on the decide path

`ops.ts`: add `recordInvalid` (`record_invalid`, error) and `storeFailed` (`store_failed`, error; `tags.stage` in `verify`, `ack_state`, `ack`). `decideLegal` gets an injected `flushEvents` dependency: after `recorded` it emits `accepted`, returns the founder's result immediately, and off the request path (`after()` where it works under the custom server, otherwise a caught fire-and-forget promise) awaits a bounded flush (2 s) and, only when it returned true, calls `ackAcceptance`. A flush that returns false leaves the row unacknowledged; a flush or ack that throws is caught and reported as `store_failed` and never reaches the response or `decideRejected`. `already_recorded` never acks. Update `test/sentry-legal-acceptance-alert-op-contract.test.ts`: the derived op set includes the two new ops, which sit in a plain exempt list naming #12195 (no ratchet).

### Phase D5 — Delivery runbook (pull-only)

`knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md` (under 40 lines): a procedure the operator performs personally, not an agent session, because the agent must never see the note. It names the read mechanism (the operator's own Supabase login, SQL editor on the project, no ssh), the query that lists `request_changes` rows (key, version, time) and reads one note, the rule that the note is not forwarded or pasted into tickets, how a revised text is published (a new text hash is a new row; a decline needs the same), and how an operator reconciles a row whose ack was lost after confirming with the founder. The card copy is not touched.

### Phase D6 — Legal records

`knowledge-base/legal/article-30-register.md`: PA-40 addendum (the pull-only note read, the ack table in (c), the endpoint as a read-only service-role access), worded as taking effect on the merge of this PR. `…/2026-11-founder-legal-acceptance-attestation.md`: narrow the section 2 line "the note reaches no one" with a `Superseded` marker, sign-off block untouched. `compliance-posture.md` row only if the register addendum changes an Active Item. `soleur:gdpr-gate` advisory output is attached (already run at plan time; see below).

### Phase D7 — ADR amendment, ADR-320 note, C4, README

ADR-319 amendment and the one-line ADR-320 scope note (see above); the `legal-acceptance/README.md` (endpoint, ack, ops, "the post-deploy registry smoke stays open because no text is committed"); the C4 edits after reading all three `.c4` files, `scripts/regenerate-c4-model.sh`, the C4 tests (`c4-code-syntax`, `c4-render`, `c4-model-freshness`, `c4-count-parity`).

### Phase D8 — Gates and ship

File-selected test runs only (CI is the merge gate): the affected vitest files, `hold-gate-eval.test.sh`, the census tests, the c4 tests, markdown lint of the touched docs. File the follow-up issues before merge (the founder-page card state for a failed checksum; the sweep over unacked rows; the paging rules for `record_invalid` and `store_failed`; the post-deploy registry smoke; the 8.1 first-acceptance follow-through) with milestones. Review with full coverage (single-user incident). Commit with `LEFTHOOK_EXCLUDE=bun-test`; push only after `prepush-secret-scan.sh`. PR body `Ref #12011`. Post-merge: `deploy-arm.sh` for the delivering arm, then the dark probe in the post-merge list.

## Operator Holds

<!-- lint-infra-ignore start: plan-only operator-reserved hold; prescribes an approval, applies nothing in this PR -->
This reserves the apply decision to the operator. It is plan-only: this PR applies nothing, the endpoint stays dark (503) until it is cleared, and its tracking issue is #12196. The follow-up change that carries `legal-acceptance-secrets.tf` is a separate merge, and its merge is the apply. The flag turn-on and the production application of migration 185 (which rides the normal deploy pipeline; the `verify-migrations` job runs the `verify/185` sentinel on deploy) are not holds: they are in the enabling conditions and post-merge items below. The Sentry paging rules for the two new ops are not in this PR at all; the follow-up issue #12195 carries their draft.

- Hold: Operator-reserved: approve the Terraform plan for the verify-endpoint token, per the Infrastructure section above: a token per config (dev and prd) created by Terraform in a follow-up change whose plan output the operator reviews, the founder uuid entered by the operator for each project, then the merge that applies it. Nothing is applied before the operator says so.
<!-- lint-infra-ignore end -->

## Enabling conditions and post-merge items

Not part of this PR. They gate turning `approval-queue` on for any founder. The flag is read with `workspaceId: null`, so it is effectively global: there is no canary and no per-user scope. Until the founder-page card state in item 7 ships, the flag stays off in prd, or the operator exercises the card in dev only.

1. Counsel decides the retention period and the note redaction path (#12080, PA-40 item 17); the `(c-2)` placeholder is replaced.
2. The three published privacy documents are updated together (and, before any non-operator founder, a named reader role for the note and a no-forwarding rule).
3. Confirm the Supabase "single session per user" setting is off (the throwaway `verifyOtp` would otherwise end the founder's web session).
4. Live browser check of the card (CI e2e is the authority).
5. Card copy stays PROVISIONAL under the CLO sign-off gate; no placeholder wording is removed.
6. The Terraform secrets and the founder uuid exist and the web app restarted (Operator Holds 1), so the endpoint stops answering 503; the `verify/185` sentinel reported `bad = 0` on the production deploy; the first real acceptance (8.1) was verified by the gate.
7. The founder-page card state for a record that fails its checksum: a wireframe and CLO-gated copy before the flag is on (follow-up issue).
8. The post-deploy registry smoke (a key loaded from inside the container) waits for the first committed text.

Before any customer founder (not just the operator): a named reader role for the note with a response expectation; a count-only "note waiting" signal with no note text; a visible acknowledgement and a closed loop for the founder when the text is revised; CLO-approved card copy that matches the real delivery behaviour; a runbook a non-engineer can follow; the 8.3 UX test with a non-technical founder as a hard gate.

Open post-merge items from the task: 8.1 ADR-319 adopting to accepted after the first real acceptance; 8.2 CLO and counsel review before enabling beyond the canary; 8.3 UX test with a non-technical founder; 8.4 roadmap CP2 correction, to read "In progress (legal-acceptance slice)", never Done. Known unrelated alert: Better Stack issue 12180 (egress-gw probe silent), not a target.

## Deferrals (tracking issues, filed 2026-11-05)

| Deferred item | Tracking issue |
|---|---|
| Founder-page card state for a row that fails its checksum (wireframe, CLO-gated copy) | #12193 |
| Sweep over rows with no ack | #12194 |
| Sentry paging rules for `record_invalid` and `store_failed` (draft HCL in the issue) | #12195 |
| Terraform secrets for the endpoint (operator-reserved plan; Operator Holds 1) | #12196 |
| First real acceptance verified by the gate (8.1), registry smoke, CP2 wording (8.4) | #12197 |

## Files to Create

- `apps/web-platform/supabase/migrations/185_legal_acceptance_ack.sql`
- `apps/web-platform/supabase/migrations/185_legal_acceptance_ack.down.sql`
- `apps/web-platform/supabase/verify/185_legal_acceptance_ack.sql`
- `apps/web-platform/app/api/internal/legal-acceptance/[key]/route.ts`
- `apps/web-platform/test/legal-acceptance/migration-185-legal-acceptance-ack.test.ts`
- `apps/web-platform/test/legal-acceptance/verify-route.test.ts`
- `apps/web-platform/test/legal-acceptance/verify-service.test.ts`
- `apps/web-platform/test/legal-acceptance/ack-reconciliation.test.ts`
- `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts`
- `plugins/soleur/scripts/lib/bearer-curl.sh` (and its test)
- `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md`
- `plugins/soleur/test/fixtures/hold-gate-eval/plan-web-acceptance-only.md`
- `plugins/soleur/test/fixtures/hold-gate-eval/plan-web-acceptance-mixed.md`
- `plugins/soleur/test/fixtures/hold-gate-eval/plan-reserved-only.md`
- `plugins/soleur/test/fixtures/hold-gate-eval/web-acceptance-text.md` (synthesized, with `|`, a quote, a multibyte character and a trailing newline)

## Files to Edit

- `apps/web-platform/lib/internal-auth.ts` (parameterise the secret name)
- `apps/web-platform/lib/routes.ts` (narrow `PUBLIC_PATHS` entry)
- `apps/web-platform/server/legal-acceptance/canonical.ts` (`read_failed` split)
- `apps/web-platform/server/legal-acceptance/service.ts` (`verifyAcceptance`, `ackAcceptance`, `ackState`; injected flush; ack off the request path)
- `apps/web-platform/app/api/legal-acceptance/[key]/decide/route.ts` (wire the injected flush and the off-path ack)
- `apps/web-platform/server/approval/ops.ts` (two ops)
- `apps/web-platform/server/dsar-export-allowlist.ts` (`legal_acceptance_ack` exclusion with reason)
- `apps/web-platform/server/legal-acceptance/README.md`
- `apps/web-platform/.env.example` (two Doppler-only comment entries)
- `apps/web-platform/test/sentry-legal-acceptance-alert-op-contract.test.ts`
- `apps/web-platform/test/server/legal-acceptance.tenant-isolation.test.ts`
- `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh`
- `plugins/soleur/test/hold-gate-eval.test.sh`
- `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` (adopts the shared helper only if its suite passes unchanged)
- `plugins/soleur/skills/ship/references/operator-holds.md`
- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` (grammar section 3)
- `knowledge-base/engineering/architecture/decisions/ADR-319-legal-acceptance-record.md` (amendment)
- `knowledge-base/engineering/architecture/decisions/ADR-320-terraform-minted-secrets-must-not-land-in-tier-a-readable-state.md` (one-line scope note)
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4` and the regenerated `model.likec4.json`
- `knowledge-base/legal/article-30-register.md`
- `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-attestation.md`
- `knowledge-base/product/roadmap.md` (CP2 wording, only if the founder confirms placement at ship; otherwise 8.4 stays open)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: the endpoint answers 503 when the token or the founder id is unset or malformed or the registry cannot be read, 401 on a wrong token (checked before any lookup), 400 on a malformed key or hash, 404 on a key not in the registry, and on a right token exactly `{status, text_hash, decided_at, row_ok}`; the status set the route can emit is `{200, 400, 401, 404, 502, 503}` and a test asserts it. (`app/api/internal/legal-acceptance/[key]/route.ts`, `canonical.ts`, Guard 2)
- [ ] AC2: `invalid` reaches the caller as `invalid` with `row_ok:false` and emits `record_invalid`; no layer maps it to `none`. (route, `verifyAcceptance`, `gate_web_acceptance`; Guard 1 row 2, Guard 2 row 6)
- [ ] AC3: no response, log line or Sentry payload carries `requested_edit`; a test seeds a note and greps the response and every captured event. (Guard 2 row 4)
- [ ] AC4: `readInternalBearerSecret` takes a closed-union name defaulting to the Inngest secret; the four existing callers' tests pass unchanged, and the census tests pass (or their bound set is updated in the same PR). (`lib/internal-auth.ts`)
- [ ] AC5: `/api/internal/legal-acceptance/<key>` is reachable without a session cookie through the middleware predicate and `/api/internal/legal-acceptance-foo` is not; the entry is exact. (`lib/routes.ts`, Guard 2 row 9)
- [ ] AC6: migration 185 applies on the dev project; its down file refuses while rows exist; `verify/185` reports `bad = 0`; the ack table has no founder id, no foreign key and no api-role privilege; both RPCs refuse a caller with a user context, raise on a malformed key or hash, and pin `search_path = public, pg_temp`; `legal_acceptance_ack` is in `DSAR_TABLE_EXCLUSIONS` and the DSAR completeness test passes.
- [ ] AC7: the ack is written only after a flush that returned true; `already_recorded` never acks; a throwing flush or ack, or an ack RPC error, reports `store_failed` and leaves the decide response unchanged; a row older than 120 s without an ack makes every verify call of it emit `row_without_event`. (`decideLegal`, route, Guard 3)
- [ ] AC8: `hold-gate-eval.sh` discharges `web-acceptance <key> <hash>` only on `accepted`, `row_ok` true, echoed hash equal to the gate hash AND to the sha256 of the committed text; every row of the closed reason table in Guard 1 is a test, a held gate always prints its reason, FALSE and PERSON exit 1 and UNEVAL exits 2. (Guard 1)
- [ ] AC9: a plan with a `web-acceptance` gate and no `Delegation:` line is evaluated (never exit 3); mixed with `pr-merged` and no delegation it exits 2; a no-delegation plan with only `Operator-reserved:` or gate-less holds still exits 3; with a valid delegation the gate is evaluated beside the others; an `Operator-reserved:` hold still stands in every case. (Guard 1 rows 8 and 9)
- [ ] AC10: every mutation row of Guards 1 to 3 is driven RED by a test (`# mut:` markers for the shell script; vitest mutation helpers for the rest), and every harness row fails the suite when its stub is removed.
- [ ] AC11: key and hash shapes agree across `canonical.ts`, the migration 184 CHECKs, the migration 185 RPC checks and the bash gate, derived from the source files by a test that fails on an empty extraction. (Guard 2 row 10)
- [ ] AC12: the alert contract test covers the two new ops in a plain exempt list that names the follow-up issue; `row_without_event` has an emitter reachable from the endpoint test.
- [ ] AC13: `.env.example` documents `LEGAL_ACCEPTANCE_VERIFY_TOKEN` and `LEGAL_ACCEPTANCE_FOUNDER_ID` as Doppler-only values; no file under `apps/web-platform/infra/` (including `infra/sentry/`) is added or edited (diff-scope check: `git diff --name-only origin/main...HEAD` contains no such path).
- [ ] AC14: ADR-319 amendment, the ADR-320 scope note, C4 edits (both "arrives in PR-D" sentences and both no-agent-reach statements rewritten; the `ship` to `webapp`, `ship` to `doppler` and operator read edges added; the plugin view extended; `model.likec4.json` regenerated), PA-40 addendum (merge-conditioned wording), attestation narrowing with a `Superseded` marker and the runbook are in the PR; the C4 tests (including `c4-model-freshness` and `c4-count-parity`) pass.
- [ ] AC15: `legal-acceptance-copy.ts` and the card components are unchanged (`git diff --name-only` shows neither), and the ADR amendment states that the note is delivered pull-only and the flag is effectively global.
- [ ] AC16: the decide response does not wait on the flush (a test with a flush that never resolves still gets the recorded result), and the ADR amendment states that the alert is pull-driven and that the endpoint's hard limits are the token, the read-only RPC and the single founder id.
- [ ] AC17a: the follow-up issues (failed-checksum card state with a wireframe requirement, sweep over unacked rows, paging rules for the two ops, registry smoke, first-acceptance follow-through, secrets plan tracking) exist with milestones and are linked from the plan.

### Post-merge (follow-through)

- [ ] AC17: `deploy-arm.sh` confirms the delivering arm; the dark probe `curl -s -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/internal/legal-acceptance/probe` prints `503` before the secrets exist (not `307`, which would mean the middleware entry is missing) and `401` with a wrong token after they exist and the web app restarted.
- [ ] AC18: after the approved apply, `LEGAL_ACCEPTANCE_VERIFY_TOKEN` differs between dev and prd; `LEGAL_ACCEPTANCE_FOUNDER_ID` is uuid-shaped in both and present in that project's `auth.users`, each verified by a read that prints booleans only.
- [ ] AC20: after the first real decision in the production process, the matching `legal_acceptance_ack` row exists and verifying that row emits no `row_without_event` (this proves `flush` resolves true there; if it does not, the emitter would fire for every row and the ack path is the first thing to debug).
- [ ] AC19: ADR-319 status moves from `adopting` to `accepted` after the first real acceptance has run end to end and the gate discharged it (8.1); counsel review before enabling beyond the canary (8.2); UX test with a non-technical founder (8.3); roadmap CP2 reads "In progress (legal-acceptance slice)" (8.4).

## Test Scenarios

1. Endpoint, dark: no env, any request: 503 with no body detail; with the token set and no founder id: 503; with an unreadable texts directory: 503 (not 404).
2. Endpoint, auth: wrong token 401 before any RPC call (the RPC stub records zero calls); bare token and Bearer-prefixed token both pass.
3. Endpoint, statuses: stubbed RPC returns each of the five statuses; the body has four keys; `invalid` is `invalid`; an unrecognised status is 502 and `store_failed`.
4. Endpoint, registry: unknown key 404.
5. Reconciliation: a row 200 s old with no ack emits `row_without_event` on every verify; a row 30 s old emits nothing; an acked row emits nothing; two hashes where only the second is unacked emit once.
6. Decide path: recorded then flush true then ack; flush false then no ack; flush throws then `store_failed` and the founder still gets `recorded`; ack RPC error then `store_failed` and no throw; a flush that never resolves and the response still returns; `already_recorded` then no ack.
7. Hold gate: accepted with matching hashes discharges; every row of the closed reason table; a two-hold plan where only the second is a web acceptance; delegation-present and delegation-absent forms; mixed kinds without delegation exit 2; reserved-only and gate-less no-delegation plans exit 3; `Operator-reserved:` beside a web acceptance.
8. Token handling: the token never appears in the evaluator's stdout, stderr or `ps`-visible argv (the `curl` stub records argv and the test greps it).
9. Cross-layer: a 63-character key accepted by all layers; a 64-character key refused by all layers.
10. Note privacy: seed a `request_changes` row with a recognisable note; no endpoint response, Sentry payload or evaluator output contains it.

## Dependencies & Risks

- **Operator hold gates the useful state.** Until the operator approves the Terraform plan, the follow-up merges and the uuid is entered, the endpoint is dark and every web-acceptance hold stands (UNEVAL `endpoint not configured yet`). That is the safe direction.
- **No text is committed.** Every key is a 404 today, so the first end-to-end run needs a committed text and a real acceptance (8.1); a web-acceptance hold on a text added in the same PR is a post-merge hold.
- **Unpaged new ops.** `record_invalid` and `store_failed` are visible in Sentry but page nobody until the follow-up rules are applied; the gate is loud at ship time in the meantime.
- **The alert is pull-driven.** A row nobody verifies is not checked; the sweep follow-up carries a trigger (before the flag is on for a non-operator founder).
- **A real Yes with a lost ack pages on each verify.** That is the intended signal; the runbook has the reconcile step. Healing it in `already_recorded` would hide a row pre-empted through the RPC.
- **`internal-auth.ts` is bound into the census gate.** Run the census test after the edit.
- **Migration number.** 185 is re-checked at PR time; a sibling can claim it first.
- **ADR-320 is `proposed`.** The token ruling cites decision 4 and adds a scope note to ADR-320; if ADR-320 is accepted with a wider scope, the token moves out of Terraform.
- **Not in scope:** #12020 to #12023, #12031, #12080, the founder-page invalid card state (follow-up), a sweep over unacked rows (follow-up), paging rules for the new ops (follow-up), and any copy change.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one names the threshold `single-user incident`.
- Markers in this file: the evaluator counts every `Hold` and `Gate` marker line in the whole file and compares with what it parsed inside the `## Operator Holds` section; examples elsewhere sit inside inline text, never at the start of a line.
- `Sentry.flush` returns false when no client is configured (dev, tests): the ack is then not written, which is correct (no event was sent) and means dev rows are unacked by design.
- The gate reads the token from the prd Doppler config, which the agent can also read: the token is deliberately a read-only status token; do not give it write reach without moving it out of Terraform (ADR-320).
- If the production process never resolves `Sentry.flush` to true, every row stays unacked and the alert fires for each one: AC20 is the check, not an assumption.
- The `accepted` event is warn-level and not paged; a Request changes row is noticed at the gate (`changes requested`) or by searching `choice:request_changes`.

## References

- Issue #12011; related #12080, #12031, #12020 to #12023; draft PR #12187
- ADR-319 (and its 2026-11-05 amendment), ADR-309, ADR-320, ADR-289, ADR-241, ADR-244
- Original plan: `knowledge-base/project/plans/archive/20261104-000420-2026-11-03-feat-founder-approval-cards-plan.md` (PR-D, AC15 to AC18)
- PR-C tasks: `knowledge-base/project/specs/archive/20261105-131233-feat-founder-approval-cards-pr-c/tasks.md`
- Learning: `knowledge-base/project/learnings/2026-11-05-a-skip-keyed-on-the-record-not-on-the-success-made-a-false-sent-and-four-sibling-defects-the-review-found.md`
- `apps/web-platform/server/legal-acceptance/README.md`, `plugins/soleur/skills/ship/references/operator-holds.md`
