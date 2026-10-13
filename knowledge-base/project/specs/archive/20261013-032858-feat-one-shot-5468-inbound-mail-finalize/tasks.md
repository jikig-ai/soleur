---
feature: feat-one-shot-5468-inbound-mail-finalize
issue: 5468
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-17-fix-inbound-mail-finalize-tail-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — fix inbound mail finalize tail (#5468)

Derived from the finalized, deepened plan. Two-pronged fix: (1) least-privilege
`RESEND_RECEIVING_API_KEY` for the inbound body GET (root cause = Resend
`restricted_api_key`, Sentry WEB-PLATFORM-35), (2) final-attempt-gated degraded
finalize so a body-fetch/summarizer egress drop never strands a row at NULL.

## Phase 0 — Preconditions (verify, do not code)

- [ ] 0.1 Re-confirm WEB-PLATFORM-35 is the only `inngest.fn_id:email-on-received` Sentry issue (Doppler `prd_terraform` `SENTRY_AUTH_TOKEN`).
- [ ] 0.2 Confirm attempt-context shape: inngest `BaseContext.attempt`/`maxAttempts` (`node_modules/inngest/types.d.ts:411-431`), precedent `_cron-shared.ts:107-108` + `cron-stale-deferred-scope-outs.ts:358`.
- [ ] 0.3 Read `cfo-on-payment-failed.ts` (retries:1 + deadletter precedent) and `infra/github-app.tf:40-80` (operator-supplied `doppler_secret` pattern).

## Phase 1 — Resend receiving key (config root cause)

- [ ] 1.1 `fetch-received-email.ts`: read `RESEND_RECEIVING_API_KEY` ONLY; throw the retriable "must be set" error keyed on the new var if unset. No `RESEND_API_KEY` read (AC1).
- [ ] 1.2 `.env.example`: document `RESEND_RECEIVING_API_KEY` + receiving/full-access scope comment; dev sets it equal to `RESEND_API_KEY` (AC2).

## Phase 1b — IaC threading (Infrastructure)

- [ ] 1b.1 `infra/variables.tf`: `variable "resend_receiving_api_key"` (string, sensitive, no default).
- [ ] 1b.2 New `doppler_secret "resend_receiving_api_key"` resource, `config = "prd"`, name `RESEND_RECEIVING_API_KEY`.
- [ ] 1b.3 `infra/server.tf` + `infra/cloud-init.yml`: thread `${resend_receiving_api_key}` into the container env (mirror the `RESEND_API_KEY` site at server.tf:59).

## Phase 2 — RED tests (cq-write-failing-tests-before)

- [ ] 2.1 AC4: two-attempt sequence — attempt 0 throw re-throws + row NULL + degraded `step.run` ABSENT from step memo; attempt 1 recovers → recovered classification wins.
- [ ] 2.2 AC5a: summarizer-only failure after a statutory body → finalizes `statutory_class` (NOT degraded `other`).
- [ ] 2.3 AC5b: body-fetch failure → degraded `other`, explicit assert NO `statutory_class` written.
- [ ] 2.4 AC6: degraded finalize fires `reportSilentFallback op:fetch-summarize-degraded` with only `{ itemId }` extra.
- [ ] 2.5 AC7: row already `statutory_class='dsar'` + degraded write attempt → zero-row no-op, statutory_class preserved, NO ordinary notify.
- [ ] 2.6 All RED first (fail before Phase 3).

## Phase 3 — Degraded-finalize tail (code resilience defect)

- [ ] 3.1 Widen `HandlerArgs` (`email-on-received.ts:89`) with `attempt?: number; maxAttempts?: number`.
- [ ] 3.2 Widen `FusedOutcome` with a single `fetchFailed` variant.
- [ ] 3.3 Independent catches around the body fetch AND the LLM call (NOT the whole step) so the statutory body pass wins (AC5).
- [ ] 3.4 Final-attempt gate: `const isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1)`; skip the whole degraded `step.run` on non-final attempts (re-throw); pin the `retries: 1` → maxAttempts=2 relationship in a comment.
- [ ] 3.5 `finalize-row` arm for `fetchFailed`: degraded UPDATE guarded `.is("statutory_class", null).is("mail_class", null)` (AC7 race guard) writing `mail_class='other'` + fixed sentinel summary.
- [ ] 3.6 Add the degraded sentinel `LIKE` prefix to the daily-ceiling exclusion query (`email-on-received.ts:443-444`) — verbatim match with the sentinel literal (AC8).
- [ ] 3.7 Notify: statutory-grade (`statutory: true`) on the fetch-failure path (possible body-only DSAR); ordinary on summarizer-only degraded.
- [ ] 3.8 `reportSilentFallback op:fetch-summarize-degraded`, `{ itemId }`-only extra (TR3).

## Phase 4 — Green + exhaustiveness

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — widen every `switch (fused.kind)` arm tsc surfaces (AC10/AC11).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/email-on-received.test.ts` green (AC9).

## Phase 5 — Ship + post-merge (operator)

- [ ] 5.1 PR body: `Closes #5468`. Split AC into Pre-merge (PR) / Post-merge (operator).
- [ ] 5.2 AC12: mint receiving/full-access key in Resend dashboard → set `TF_VAR_resend_receiving_api_key` via Doppler `prd_terraform` → `terraform apply -target=doppler_secret.resend_receiving_api_key` (canonical triplet). Verify `doppler secrets get RESEND_RECEIVING_API_KEY -p soleur -c prd --plain | head -c 4`.
- [ ] 5.3 AC13: read-only — `email_triage_items` NULL-class rows for fresh mail trend to zero; re-send the two diagnostic subjects to re-drive (adopt+resume); never manual SQL UPDATE.

## Notes
- CPO sign-off required (single-user incident threshold) before /work begins.
- `user-impact-reviewer` will run at review time (review/SKILL.md conditional-agent block).
