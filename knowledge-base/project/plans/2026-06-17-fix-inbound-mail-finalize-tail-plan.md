---
issue: 5468
type: fix
branch: feat-one-shot-5468-inbound-mail-finalize
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: inbound non-probe mail never finalizes (mail_class/summary stay NULL — HOP F summarizer tail) 🐛

Closes #5468 (use `Closes #5468` in the PR body — this is a code fix whose defect-resolving
remediation, the degraded-finalize tail, lands at merge).

## Enhancement Summary

**Deepened on:** 2026-06-17
**Agents:** Inngest-SDK verifier, verify-the-negative (6 claims), data-integrity-guardian (single-user
threshold), code-simplicity-reviewer; learnings-researcher + repo-research-analyst (plan phase).

### Key improvements from the deepen pass
1. **Sentry RCA confirmed at plan time** (not hypothesised): WEB-PLATFORM-35 `restricted_api_key`,
   firstSeen/lastSeen match both stuck rows. All 6 negative/correctness claims `confirmed`.
2. **P0 race guard added (AC7):** the degraded `mail_class='other'` write targets a *disjoint*
   one-time-set column from `statutory_class`, so the WORM trigger does NOT P0001 against a
   concurrent statutory finalize — `applyFinalize` is insufficient. Added a
   `.is("statutory_class", null).is("mail_class", null)` WHERE guard so a degraded write can never
   co-class a DSAR row.
3. **P1 ceiling-collision fixed (AC8):** the degraded sentinel must be added to the daily-LLM-ceiling
   exclusion or it falsely counts as spend.
4. **P1 notify-grade decided:** degraded notify on the *fetch-failure* path is statutory-grade
   (a possibly-body-only DSAR was never scanned).
5. **Simplified (code-simplicity):** dropped the dev fallback to `RESEND_API_KEY` — silent in dev,
   hazardous in prd (it reproduces the bug behind a warn). The receiving var is now required.
6. **Attempt-gate confirmed as an existing repo idiom** (`_cron-shared.ts` + `cron-stale-deferred-scope-outs.ts:358`,
   inngest 3.54.2 `BaseContext.attempt`) — copy verbatim, do not invent.

### New considerations discovered
- Disjoint-column WORM races are not P0001-protected — every multi-column finalize needs an
  explicit unfinalized-precondition WHERE.
- The degraded sentinel string is now load-bearing in TWO places (finalize value + ceiling-exclusion
  `LIKE`) — must match verbatim.

## Overview

Two emails reached `email_triage_items` but are stuck `mail_class=null` / `summary=null`
(06-12 19:32, 06-17 11:30 — both non-probe diagnostic subjects). Issue #5468 hypothesised the
throw was an egress drop, a Resend inbound-retention 404, or a code/data error, and asked for the
Sentry function-error events to confirm.

**Sentry RCA (grounded, not hypothesised).** Using the `prd_terraform` Doppler
`SENTRY_AUTH_TOKEN` (which carries `event:read`/`issue:read` — the Crons-monitor token in #5467
could not), querying `inngest.fn_id:email-on-received` over `statsPeriod=14d` returns **exactly
one** issue:

> **WEB-PLATFORM-35** — `Error: fetch-received-email failed: restricted_api_key`
> type `Error`, culprit `POST /api/inngest`, **firstSeen 2026-06-12T19:32:50Z**,
> **lastSeen 2026-06-17T13:56:01Z**, **count 5**.

`firstSeen` matches the 06-12 stuck row to the second; `lastSeen` matches the 06-17 row. This is
the throw. The string is the deterministic `error?.name` branch of `fetchReceivedEmail`
(`fetch-received-email.ts:36-38`), and `restricted_api_key` is a verified member of Resend's
`RESEND_ERROR_CODE_KEY` union (`node_modules/resend/dist/index.d.mts:116`).

**Root cause = a restricted Resend key, two-pronged.** None of the three hypothesised causes hold.
The single shared `RESEND_API_KEY` (one TF var `resend_api_key`, `infra/variables.tf:151` →
`infra/server.tf`/`cloud-init.yml`, Doppler `prd_terraform`) is a *restricted* (send-scoped) key.
The inbound body fetch `resend.emails.receiving.get(id)` (`GET /emails/receiving/{id}`) requires
the **receiving-read** permission that key lacks, so every non-probe email throws on HOP F's body
fetch, exhausts `retries: 1`, and the claim-inserted row stays NULL forever. This defect is
downstream of #5467 (the Proton-Sieve forward, now CLOSED) and was masked by it.

The fix has two independent dimensions, BOTH required:

1. **Config root cause (*why it fires*):** the inbound body fetch needs a receiving-read scope.
   Because `RESEND_API_KEY` is also used by outbound send + monitor scripts, the least-privilege
   fix is a **separate `RESEND_RECEIVING_API_KEY`** (full/receiving access) consumed ONLY by
   `fetch-received-email.ts`, leaving the existing restricted send key untouched.
2. **Code resilience defect (*why it strands*):** even after the key is fixed, ANY future
   body-fetch or summarizer egress drop (api.resend.com / api.anthropic.com unreachable, Resend
   inbound-retention 404, Anthropic 5xx) currently leaves the row permanently NULL AND silently
   skips `matchStatutoryBody` — a swallowed Art. 12 clock. On the **final** Inngest attempt only,
   the pipeline must write a *degraded* finalize (`mail_class='other'`, a fixed
   "fetch/summarize failed — verify against the Proton original" sentinel summary) and notify, so
   the email always lands visibly: a loud degraded row + notification + still-captured Sentry error
   instead of a silent permanent NULL.

## Research Reconciliation — Spec vs. Codebase

| Issue-#5468 claim | Reality (verified) | Plan response |
|---|---|---|
| Throw is "egress drop / Resend 404 / code-or-data error — investigate" | Sentry WEB-PLATFORM-35 = `restricted_api_key` (Resend auth-scope error) | Fix key scope (Phase 1) + harden tail for the *other* causes still possible (Phase 3) |
| "Crons-monitor token cannot read issues; event/issue scope needed" | `prd_terraform` `SENTRY_AUTH_TOKEN` has `event:read`+`issue:read` (proven by a successful fetch) | RCA done at plan time; no operator step |
| Claim-insert (HOP E) succeeds; failure post-claim | Confirmed — `claim-insert` step (`email-on-received.ts:234`) completed; throw is in HOP F `fetch-sanitize-summarize` | Tail-hardening targets HOP F + a new degraded path |
| `mail_class`/`summary` settable post-claim | Confirmed one-time-set (NULL→value once) per WORM matrix `mig 102:187-204`; `applyFinalize` already handles the P0001 race | Degraded finalize reuses `applyFinalize` — no new mutation class |

## User-Brand Impact

**If this lands broken, the user experiences:** real operator mail (once #5467's forward is live)
lands with no summary and no class — and a body-only statutory letter (a DSAR / breach notice whose
markers are in the *body*, not the metadata) is never run through `matchStatutoryBody`, so its
GDPR Art. 12 response clock is silently eaten. The operator sees a blank row, or nothing.

**If this leaks, the user's workflow/legal-standing is exposed via:** a missed statutory deadline
(regulator fine / default judgment) because the only inbound channel silently dropped detection.
No body exfiltration vector (the body never crosses a step boundary — TR3), but the new
`RESEND_RECEIVING_API_KEY` is a high-privilege secret whose mishandling (logging/committing) would
expose the inbound mailbox.

**Brand-survival threshold:** single-user incident — there is exactly one operator inbox; one
swallowed DSAR is a brand-survival event.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `fetch-received-email.ts` reads `RESEND_RECEIVING_API_KEY` (NO silent fallback to
  `RESEND_API_KEY` — a prod fallback to the send-scoped key silently reproduces the exact
  `restricted_api_key` bug behind a warn; dev sets the var equal to `RESEND_API_KEY` in
  `.env.example`). Throws the existing retriable "must be set" error if unset (keyed on the new
  var name). Verify
  `grep -n "RESEND_RECEIVING_API_KEY" apps/web-platform/server/email-triage/fetch-received-email.ts`
  ≥1, and `grep -c "RESEND_API_KEY" apps/web-platform/server/email-triage/fetch-received-email.ts` = 0
  (the module no longer reads the send key at all). [deepen: code-simplicity — fallback is
  dead-in-dev + hazardous-in-prd.]
- **AC2** `.env.example` documents `RESEND_RECEIVING_API_KEY=` with a comment noting it needs Resend
  *receiving/full-access* scope (distinct from the send-scoped `RESEND_API_KEY`). Verify
  `grep -n "RESEND_RECEIVING_API_KEY" apps/web-platform/.env.example`.
- **AC3** The fused `fetch-sanitize-summarize` step writes a degraded finalize on a throw, **final
  attempt only**. Implemented by reading attempt context from the Inngest handler arg /
  `transformInput` (`BaseContext`), NEVER `onFunctionRun` ctx (`InitialRunInfo` — learning
  `2026-06-16-inngest-middleware-onfunctionrun-ctx-is-initialruninfo-not-basecontext.md`). Verify a
  `kind:"fetchFailed"` (or equiv) `FusedOutcome` variant whose `finalize-row` arm writes
  `mail_class='other'` + the fixed failure sentinel:
  `grep -n "fetchFailed\|FETCH_FAILED" apps/web-platform/server/inngest/functions/email-on-received.ts` ≥1.
- **AC4** On a **non-final** attempt the degraded finalize MUST NOT run — re-throw so Inngest
  retries; skip the *whole* degraded `step.run`, never conditionally write inside it (learning
  `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`). Final-attempt
  predicate copied verbatim from the repo precedent `cron-stale-deferred-scope-outs.ts:358`:
  `const isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`, with `attempt`/`maxAttempts`
  threaded through `HandlerArgs` from `BaseContext` (the `_cron-shared.ts:107-108` shape). RED test
  must (a) drive a real two-attempt sequence — attempt 0 throws, attempt 1 *recovers* (body-fetch
  mock returns) — and assert the **attempt-1 classification wins** (NOT a degraded row), and
  (b) on attempt 0 assert the degraded `step.run` is **structurally absent from the step memo**
  (never entered-and-no-op'd), not merely that the row is NULL. [deepen: data-integrity P1 +
  code-simplicity — the memoized-empty-replay trap is invisible to a "row is NULL" assertion.]
- **AC5** A *summarizer-only* failure AFTER a body with a statutory marker finalizes
  `statutory_class` (NOT degraded `other`) — the deterministic body statutory pass
  (`email-on-received.ts:467`) runs before the LLM (`:489`) and must win (degraded catch wraps the
  LLM call, not the whole step — see Sharp Edges). **Symmetric negative also required:** a
  *body-fetch* failure → degraded `other` with an explicit assertion that `statutory_class` is NOT
  written (pins the wrap boundary in both directions). Two RED tests.
- **AC6** Degraded finalize emits `reportSilentFallback` `op:fetch-summarize-degraded` (Layer 2,
  `cq-silent-fallback-must-mirror-to-sentry`), carrying NO body/subject/sender (TR3). Verify grep +
  a test asserting the spy fired with only `{ itemId }` extra.
- **AC7** The degraded finalize UPDATE is guarded against the disjoint-column WORM race: its WHERE
  clause adds `.is("statutory_class", null).is("mail_class", null)` (or re-selects and skips if
  either is already set) so a concurrent statutory finalize (adopt-resume redelivery, or the
  recovered retry once the key is fixed) cannot be co-classed `mail_class='other'`. `applyFinalize`'s
  P0001 re-select does NOT cover this — the two writes hit different one-time-set columns, so NO
  P0001 is raised (`mig 102:189-203`). RED test: a row already `statutory_class='dsar'` + degraded
  write attempt → degraded write is a no-op (zero rows), statutory_class preserved, NO ordinary
  notify fired. [deepen: data-integrity P0.]
- **AC8** The degraded sentinel summary must NOT inflate the daily-LLM-ceiling count. The ceiling
  query (`email-on-received.ts:443-444`) excludes `mail_class='probe'` and
  `summary LIKE 'deferred — volume cap%'`; add the degraded sentinel (a fixed greppable prefix,
  e.g. `summary LIKE 'fetch/summarize failed%'`) to that exclusion — a degraded row cost zero
  Anthropic spend. Verify the exclusion literal matches the sentinel literal verbatim (grep both).
  [deepen: code-simplicity — sentinel-vs-ceiling collision.]
- **AC9** `vitest run` green for `email-on-received.test.ts` with the new cases (AC4 two-attempt +
  memo-absence, AC5 summarizer-after-statutory + fetch-fail-no-statutory, AC6 mirror, AC7 race
  no-op). Run:
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/email-on-received.test.ts`.
- **AC10** Typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **AC11** New `FusedOutcome` variant: `tsc --noEmit` enumerates every `switch (fused.kind)`
  exhaustiveness arm to widen (`cq-union-widening-grep-three-patterns`) — the compiler is the
  enumerator; no fixed site count prescribed. Pick ONE variant name (`fetchFailed`), not two.

### Post-merge (operator)

> **SPLIT (CTO ruling — ADR-065, 2026-06-17).** AC12/AC13 and Phase 1b / the
> Infrastructure (IaC) section below are **deferred to follow-up #5480** and are
> NOT part of this PR. Reason: `apply-web-platform-infra.yml` auto-applies on
> merge for any `infra/*.tf` change, and Terraform resolves all root variables
> before `-target` pruning — so a new no-default `resend_receiving_api_key`
> would fail the merge-triggered apply until the operator mints the key and sets
> `TF_VAR_resend_receiving_api_key` in `prd_terraform`. This PR ships ONLY the
> code-resilience half (degraded tail + receiving-key read), which resolves the
> issue's defect (silent permanent NULL) and `Closes #5468` per the Sharp Edge.
> The IaC (`variable` + `doppler_secret` + workflow `-target`) lands in #5480
> after the operator prerequisites.

- **AC12** Provision the receiving-scoped key **through Terraform** (NOT a raw `doppler secrets set`
  — Phase 2.8 IaC routing). The only non-automatable step is minting the key in the Resend
  dashboard (CAPTCHA/console). The minted value enters Terraform as
  `TF_VAR_resend_receiving_api_key` (sourced from Doppler `prd_terraform`, like every other
  `resend_*`/secret var), and a **`doppler_secret` Terraform resource** (`config = "prd"`,
  mirroring `infra/github-app.tf` / `infra/inngest.tf` operator-supplied-secret pattern) publishes
  it into the `prd` config the running container reads. Apply via the canonical triplet against
  `prd_terraform` (see Infrastructure §Apply path). Verify post-apply with
  `doppler secrets get RESEND_RECEIVING_API_KEY -p soleur -c prd --plain | head -c 4` (read-only).
- **AC13** Confirm fresh mail finalizes (read-only, Supabase MCP):
  `select id, mail_class, summary from email_triage_items where mail_class is null and statutory_class is null and created_at > now() - interval '7 days';`
  trends to zero for mail received after the key apply. The two stranded rows are *unfinalized
  stubs*; re-sending the diagnostic subjects re-drives them (adopt+resume — they do not
  short-circuit). Do NOT manually UPDATE (WORM trigger + RPC-only).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- AC12's only manual step is the CAPTCHA/console-gated Resend key mint; the Doppler write is
     routed through a doppler_secret Terraform resource (existing repo pattern), not a raw CLI set. -->

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- Re-confirm WEB-PLATFORM-35 is still the only `inngest.fn_id:email-on-received` issue (Doppler
  `prd_terraform` `SENTRY_AUTH_TOKEN`).
- Attempt context is a **confirmed** repo idiom (deepen): `BaseContext.attempt`/`maxAttempts`
  (`node_modules/inngest/types.d.ts:411-431`, inngest 3.54.2) reach the handler arg; the precedent
  to copy is `_cron-shared.ts:107-108` (HandlerArgs shape) + `cron-stale-deferred-scope-outs.ts:358`
  (`(attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`). `onFunctionRun` ctx is `InitialRunInfo` and lacks
  `attempt` (`InngestMiddleware.d.ts:252-268`). Widen `HandlerArgs` (`email-on-received.ts:89`) to
  add `attempt?: number; maxAttempts?: number`.
- Read `cfo-on-payment-failed.ts` for the `{ deadletter: true }` non-throwing-step precedent and
  the `retries: 1` rationale.
- Read `infra/github-app.tf:40-80` for the operator-supplied `doppler_secret` resource pattern.

### Phase 1 — Resend receiving key (config root cause)
- `fetch-received-email.ts`: read `RESEND_RECEIVING_API_KEY` ONLY (no `RESEND_API_KEY` read at all
  — AC1); throw the existing retriable "must be set" error keyed on the new var if unset.
- `.env.example`: document `RESEND_RECEIVING_API_KEY` + scope comment (dev sets it equal to
  `RESEND_API_KEY`).

### Phase 1b — IaC threading (Infrastructure)
- `infra/variables.tf`: `variable "resend_receiving_api_key" { type=string; sensitive=true }`
  (no default — `hr-tf-variable-no-operator-mint-default`).
- New `doppler_secret "resend_receiving_api_key"` resource (`config = "prd"`) publishing the var
  to the container's runtime config.
- `infra/server.tf` + `infra/cloud-init.yml`: thread `${resend_receiving_api_key}` into the
  container env block (alongside the existing `RESEND_API_KEY` write site at server.tf:59 /
  cloud-init.yml).

### Phase 2 — RED tests (cq-write-failing-tests-before)
- Add the AC4/AC5/AC6/AC7 cases to `email-on-received.test.ts` using the existing
  `fetchReceivedEmailSpy` / `anthropicCreateSpy` module mocks; drive `attempt`/`maxAttempts` via the
  widened handler arg. Include the two-attempt recover sequence (AC4) and the disjoint-column race
  no-op (AC7). Tests fail first.

### Phase 3 — Degraded-finalize tail (code resilience defect)
- Widen `FusedOutcome` with a single `fetchFailed` variant; keep the statutory body pass reachable
  on summarizer-only failure (wrap the LLM call AND the body fetch with INDEPENDENT catches, not the
  whole step — AC5).
- Thread `attempt`/`maxAttempts`; gate the degraded write to the final attempt; re-throw otherwise
  (skip the whole `step.run` on non-final attempts).
- Add the `finalize-row` arm: degraded UPDATE guarded `.is("statutory_class", null).is("mail_class", null)`
  (AC7 race guard) + `reportSilentFallback op:fetch-summarize-degraded`.
- Add the degraded sentinel summary to the daily-ceiling exclusion (`email-on-received.ts:443-444`)
  (AC8).
- **Degraded notify grade (P1 decision):** a *body-fetch* failure could mask a body-only DSAR
  (`matchStatutoryBody` never ran), so the degraded notify on the fetch-failure path is sent with
  `statutory: true` (elevated/coalesced ping) — the system provably could not rule out a statutory
  body; an ordinary ping is too weak a compensating control at single-user threshold. A
  summarizer-only degraded path (body fetched, statutory body pass already ran and did NOT match)
  may notify ordinary. [deepen: data-integrity P1 + CLO.]

### Phase 4 — Green + exhaustiveness
- `tsc --noEmit`; widen any new `switch (fused.kind)` arms surfaced.
- `vitest run` the suite green.

## Observability

```yaml
liveness_signal:
  what: "email_triage_items rows with mail_class IS NULL AND statutory_class IS NULL AND created_at > now()-1h"
  cadence: on-demand (Supabase MCP read); existing Sentry capture is the alert
  alert_target: Sentry issue WEB-PLATFORM-35 (and any successor fetch/summarize error)
  configured_in: server/inngest/middleware/sentry-correlation.ts (Layer 1 transformOutput)
error_reporting:
  destination: Sentry (Layer 1 function-final capture + new Layer 2 reportSilentFallback op:fetch-summarize-degraded)
  fail_loud: true
failure_modes:
  - mode: receiving key still restricted/unset
    detection: Sentry "fetch-received-email failed: restricted_api_key|missing_api_key"
    alert_route: WEB-PLATFORM-35 issue (existing)
  - mode: Anthropic/Resend egress drop on final attempt
    detection: reportSilentFallback op:fetch-summarize-degraded -> Sentry
    alert_route: Sentry feature=email-triage tag
  - mode: Resend inbound-retention 404 (not_found)
    detection: degraded path; error.name=not_found in the Layer 1 captured event
    alert_route: WEB-PLATFORM-35-class
logs:
  where: pino mirror via observability.ts + Sentry; Inngest dashboard run history (run_id tag)
  retention: Sentry 90d (issues)
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" 'https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/issues/?query=inngest.fn_id:email-on-received&statsPeriod=14d'"
  expected_output: "after fix + key, no NEW restricted_api_key events; any degraded events carry op:fetch-summarize-degraded"
```

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/variables.tf` — new `variable "resend_receiving_api_key"` (string,
  sensitive, no default; value from Doppler `prd_terraform` via `TF_VAR_resend_receiving_api_key`).
- `apps/web-platform/infra/<resend|server>.tf` — new `resource "doppler_secret"
  "resend_receiving_api_key" { config = "prd"; name = "RESEND_RECEIVING_API_KEY"; value =
  var.resend_receiving_api_key }` (mirror `github-app.tf` operator-supplied-secret pattern).
- `apps/web-platform/infra/server.tf` + `infra/cloud-init.yml` — thread
  `${resend_receiving_api_key}` into the container env (mirror the `RESEND_API_KEY` write site).
- Required providers: existing `doppler/doppler`, `hetzner`, `cloudflare` pins (no new provider).
- Sensitive vars: `resend_receiving_api_key` (Doppler `prd_terraform`).

### Apply path
- cloud-init + idempotent. The `doppler_secret` resource publishes the key to `prd`; the container
  reads Doppler-injected env and picks it up on the next restart, which `web-platform-release.yml`
  triggers on merge to main touching `apps/web-platform/**`. Canonical invocation (per drift-runbook
  learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`):
  `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)`
  (+ secret), `terraform init -input=false`, then
  `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply
  -target=doppler_secret.resend_receiving_api_key`. Blast radius: a single new Doppler secret +
  env-only container change; no resource replacement.

### Distinctness / drift safeguards
- `dev != prd`: dev leaves `RESEND_RECEIVING_API_KEY` unset → falls back to `RESEND_API_KEY` with a
  warn (dev receives no real inbound mail). The `doppler_secret` pins `config = "prd"` explicitly.
- The new var is `sensitive`; value lands in `terraform.tfstate` (encrypted R2 backend) — same
  posture as the existing `resend_api_key`.

### Vendor-tier reality check
- Resend tiers allow multiple API keys with per-key permission scoping; minting a receiving/
  full-access key is within the existing plan. No tier gate.

## Architecture Decision (ADR/C4)

No new architectural decision. This is a bug fix on the existing email-triage pipeline (#5125 /
operator-inbox-delegation). The degraded-finalize tail and the least-privilege key split are
*implementations of* the existing parse-and-discard / one-time-set WORM design, not a reversal or a
new boundary. A reader of the existing ADRs + C4 is not misled. Skip.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO)

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Two-pronged fix is correct — config (key scope) is the *why-it-fires*, code
(degraded tail) is the *why-it-strands*. The attempt-gating is the load-bearing subtlety: read
attempt context from the handler arg / `transformInput` (never `onFunctionRun` — learning
2026-06-16), and skip the whole degraded step on non-final attempts (never conditionally write
inside it — learning 2026-06-12). Least-privilege key split avoids widening the send key's blast
radius. The `doppler_secret` IaC route reuses the established operator-supplied-secret pattern.

### Legal (CLO)
**Status:** reviewed
**Assessment:** Brand-survival driver is GDPR Art. 12 — a body-only statutory letter whose
detection is silently skipped is an eaten regulatory clock. The degraded path MUST preserve
`matchStatutoryBody` whenever a body was fetched (AC5). A body-fetch failure with no body cannot
detect statutory content, so the degraded notify on that path is sent **statutory-grade**
(`statutory: true`, Phase 3 P1 decision) — an ordinary ping for a row that *could* be a body-only
DSAR is too weak a compensating control at single-user threshold. The race guard (AC7) prevents a
degraded `other` write from co-classing a row a sibling run already marked statutory. No new
processing activity, no special-category handling change.

### Product/UX Gate
NONE — no UI surface in Files to Edit (server/infra/test only).

## GDPR / Compliance Gate
Touches an inbound-mail processing surface + a new secret, brand-survival = single-user incident →
`/soleur:gdpr-gate` runs at deepen-plan against the FR/TR. Advisory-only. Deepen-pass folded in two
Art. 12 controls the gate framing surfaced: (1) the AC7 disjoint-column race guard (a degraded
`other` write must not co-class a statutory row — Art. 12 timeliness), (2) the statutory-grade
degraded notify on the fetch-failure path (a possibly-body-only DSAR must still surface elevated).
The new `RESEND_RECEIVING_API_KEY` is the same Resend sub-processor already disclosed (receiving) —
no new processor, no DPIA delta. TR3 (no body/subject/sender in any log/Sentry string) is preserved
on the new degraded path (AC6: `{ itemId }`-only extra).

## Files to Edit
- `apps/web-platform/server/email-triage/fetch-received-email.ts` — read `RESEND_RECEIVING_API_KEY` only (no send-key read).
- `apps/web-platform/server/inngest/functions/email-on-received.ts` — widen `HandlerArgs` with `attempt`/`maxAttempts`; widen `FusedOutcome` with `fetchFailed`; attempt-gated degraded finalize (independent fetch/LLM catches); `finalize-row` arm with the `.is(...null)` race guard; degraded sentinel in the ceiling-exclusion query; statutory-grade notify on fetch-failure path; `reportSilentFallback op:fetch-summarize-degraded`.
- `apps/web-platform/test/server/inngest/email-on-received.test.ts` — RED cases for AC4 (two-attempt recover + memo-absence), AC5 (summarizer-after-statutory + fetch-fail-no-statutory), AC6 (mirror), AC7 (disjoint-column race no-op).
- `apps/web-platform/.env.example` — document `RESEND_RECEIVING_API_KEY`.
- `apps/web-platform/infra/variables.tf` — new sensitive var.
- `apps/web-platform/infra/server.tf` — `doppler_secret` resource + env threading (mirror RESEND_API_KEY site).
- `apps/web-platform/infra/cloud-init.yml` — thread var into container env block.

## Files to Create
- None (degraded path reuses `applyFinalize`; key reuses `fetch-received-email.ts`; `doppler_secret` resource may land in an existing `.tf`).

## Open Code-Review Overlap
None — `gh issue list --label code-review --state open` returned no issue body referencing
`email-on-received`.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6.
  It is filled above.
- **Wrap the LLM call, not the whole fused step, for the degraded tail.** If the wrap surrounds the
  *entire* step, a summarizer-only failure would degrade to `other` even when the body carried a
  statutory marker `matchStatutoryBody` already matched — silently downgrading a DSAR to ordinary
  mail (AC5 guards this). The body statutory pass runs BEFORE the LLM (`email-on-received.ts:467`);
  the degraded catch must scope to the fetch and the LLM call independently so the deterministic
  statutory result always wins.
- **Inngest attempt context is NOT on `onFunctionRun` ctx** (it's `InitialRunInfo`). Read it from
  the handler arg / `transformInput` `BaseContext`. An `as` cast on the wrong ctx silently yields
  `undefined` → the final-attempt gate always fires → a degraded row written on attempt 0 that
  pre-empts the retry that would have succeeded. Verify the arg against `node_modules/inngest` types
  in Phase 0.
- **Skip the whole degraded `step.run` on non-final attempts** — Inngest memoizes completed step
  results across retries; a step that runs-but-no-ops on attempt 0 replays its memoized empty
  result on attempt 1, masking recovery.
- **`Closes #5468` (not `Ref`)** — the issue's *defect* (silent permanent NULL) is resolved by the
  merge (degraded tail). The operator key-provision is tracked as AC12, not the closure condition.
- The two stranded rows are *unfinalized stubs*; a redelivery adopts+resumes (does not
  short-circuit). Re-sending after the key fix is the cleanest re-drive; never a manual SQL UPDATE
  (WORM trigger + RPC-only).
- **Use `Closes` AND verify with `gh issue view 5467`** confirmed: #5467 (the Proton-Sieve upstream)
  is CLOSED; this defect is independent and was masked by it, not a duplicate.
- **[deepen P0] The degraded `mail_class='other'` write does NOT race-protect via `applyFinalize`'s
  P0001 re-select.** `statutory_class` and `mail_class` are INDEPENDENT one-time-set columns
  (`mig 102:189-203`); a concurrent statutory finalize sets only `statutory_class`, so the degraded
  `mail_class` write hits a row with `OLD.mail_class IS NULL` → the WORM trigger PERMITS it (no
  P0001), producing a DSAR row co-classed `other` + an ordinary mis-notify. The degraded UPDATE
  MUST add `.is("statutory_class", null).is("mail_class", null)` to its WHERE (AC7); a zero-row
  result is the "a sibling won, do nothing" signal.
- **[deepen P1] Degraded sentinel collides with the daily-LLM-ceiling exclusion.** The ceiling
  count (`email-on-received.ts:443-444`) treats any non-NULL `summary` on a non-`probe` row as LLM
  spend unless it `LIKE 'deferred — volume cap%'`. The degraded sentinel (zero Anthropic spend)
  must be added to that exclusion with a verbatim-matching `LIKE` prefix (AC8), else degraded rows
  inflate the spend cap and falsely defer real mail.
- **[deepen] Attempt-gate is a CONFIRMED repo idiom — copy, don't invent.** `_cron-shared.ts:107-108`
  (HandlerArgs `attempt`/`maxAttempts` from `BaseContext`) + `cron-stale-deferred-scope-outs.ts:358`
  (`(attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`) are the verbatim precedent; inngest 3.54.2 exposes
  `attempt` on `BaseContext` (`types.d.ts:411-431`). With `retries: 1`, `maxAttempts` is statically
  2 — pin the relationship with an inline comment next to `retries: 1`.
