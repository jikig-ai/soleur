---
feature: feat-one-shot-email-ingress-inbound-dead
plan: knowledge-base/project/plans/2026-06-17-fix-inbound-email-ingress-dead-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — Fix inbound email ingress pipeline (dead since 2026-06-12)

> Diagnosis-first plan: tasks 1.x are LIVE read-only diagnosis (L3→L7). The fix
> task set (2.x) is PRUNED to the confirmed hypothesis — do NOT do all of 2.x.

## Phase 0 — Preconditions

- [x] 0.1 Re-verify `route.ts` ack ordering — confirmed lines 176/292/315 (claimDelivery + sendInngestWithRetry awaited before 2xx).
- [x] 0.2 Pre-diagnosis sanity gate — probe self-check intact; AC8 short-circuit-after-insert invariant HOLDS. The 06:15 error is the assert-probe-row throw (steps 1-3 succeeded). Zero rows since 06-12 (not even 'other') rules out a classification-only false-negative.
- [x] 0.3 CPO sign-off carried forward (requires_cpo_signoff plan ran plan+deepen-plan; diagnosis read-only).

## Phase 1 — Live diagnosis (read-only, L3→L7 order)

- [x] 1.1 Sentry check-in history: status=error daily 06-13→06-17 (+ first error 06-12 19:39, expectedTime null = manual run). error = fired+asserted+row-absent → downstream of send.
- [x] 1.2 Empirical localization via the data plane (Resend mgmt key is send-only restricted): only 2 inbound webhooks ever (both direct-to-inbound diagnostics), zero Proton-routed probe webhooks → the dead hop is HOP A (Proton).
- [x] 1.3 **L3 egress (H1) — RULED OUT.** Skipped the nft/dig diff in favor of a STRONGER proof: Supabase claim-inserts succeed end-to-end through the firewall (processed_resend_events + email_triage_items writes land for direct mail). A successful write supersedes nft-set membership. No SSH needed.
- [x] 1.4 **L3 ingress — H2a ruled out, H2b CONFIRMED.** MX intact (dig → inbound-smtp.eu-west-1.amazonaws.com); webhook+receiving proven enabled by live svix POSTs; Proton Sieve forward = the broken hop (differential).
- [x] 1.5 **L7 tunnel (H3) — RULED OUT.** curl POST → 401 (route svix-header guard), server=cloudflare, not tunnel 502/404. GET → 405 (POST-only route).
- [x] 1.6 **L7 route (H4/H4b) — RULED OUT.** 401 (not 500) → RESEND_INBOUND_WEBHOOK_SECRET set; processed_resend_events claim-insert succeeds (msg_3FGK 06-17 11:30) → dedup write-health good.
- [x] 1.7 **L7 Inngest (H5) — RULED OUT.** email-on-received ran + claim-inserted for direct mail → function registered, 8288 listener alive. probe_tokens gains rows daily → scheduler alive.
- [x] 1.8 Confirmed **H2b** (Proton Sieve forward broken). Every layer verified/not-verified with an artifact (table in plan §Diagnosis Result). Opt-out: Inngest-cloud-egress only.
- [x] 1.9 Files-to-Edit pruned to the runbook only (operator-config cause, no code edits). No open code-review overlap (candidate set = runbook only).

## Phase 2 — Fix (PRUNED to the confirmed hypothesis — do only the matching arm)

- [ ] 2-H1 add Supabase data-plane host coverage to `cron-egress-allowlist.txt`/`cron-egress-resolve.sh` (auto-applies on merge); RED-first regression test: probe downstream-host set ⊆ allowlist.
- [ ] 2-H2a re-enable Resend receiving / recreate webhook (`resend-inbound-bootstrap.sh`) or fix `dns.tf` MX drift; RED-first: webhook-present-and-enabled probe / MX plan-shape test.
- [x] 2-H2b **CONFIRMED ARM.** Runbook documented (`inbound-email-ingress-dead.md`, guard N/A). Operator re-enables the Sieve forward post-merge (no Proton creds + MFA → not automatable here). Direct-to-inbound canary monitor recommended as a tracked follow-up (avoids speculative scope here).
- [ ] 2-H3 restore `/api/*` ingress in `tunnel.tf`; RED-first: tunnel ingress plan-shape test.
- [ ] 2-H4 restore `RESEND_INBOUND_WEBHOOK_SECRET` (stdin, never bang-prefix); one-row dedup release only if a specific wedged `svix_id` is identified (no bulk delete).
- [ ] 2-H4b fix `processed_resend_events` RLS/constraint regression; RED-first: fresh-claim-insert-succeeds test.
- [ ] 2-H5 merge restarts container (remediation); intermediate checkpoint asserts `email-on-received` registered post-restart; RED-first: registry parity test.

## Phase 3 — Verify (gates)

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (NOT `npm run -w`).
- [ ] 3.2 Regression test green via real runner: `./node_modules/.bin/vitest run <path>` (TS) or `bash apps/web-platform/infra/cron-egress-firewall.test.sh` (shell).
- [x] 3.3 Runbook created: `inbound-email-ingress-dead.md` (dedicated — cause is Proton Sieve, not egress) with the L3→L7 no-SSH diagnosis flow + fast differential.
- [ ] 3.4 PR body: `Ref #<N>` (NOT `Closes`) — ops-remediation class.

## Phase 4 — Post-merge (operator + automated)

- [x] 4.1 Fired probe via trigger.sh → HTTP 202 dispatched (token 739db236…, 13:36:27 UTC).
- [x] 4.2 **AC8 PASS** — `SOLEUR-PROBE-739db236…` landed as `mail_class='probe'` in `email_triage_items` at 13:36:38 (~11s, ≪ 15m SLA). Chain restored via the native Proton forward. Sentry monitor → `ok` at the run's 15m assert (~13:51).
- [ ] 4.3 AC8b: if probe still red → issue stays OPEN, re-enter diagnosis treating the applied fix as ruled-out; escalate H6+CPO on a second failure.
- [ ] 4.4 AC8c (only if probe short-circuits BEFORE the shared insert): operator forwards one real email; assert non-probe row lands.
- [ ] 4.5 AC9: next scheduled run (`0 6 * * *`) stays green (Sentry API, no dashboard).
- [ ] 4.6 AC10: `gh issue close <N>` only after AC8 (and AC8c if applicable) passes.
- [ ] 4.7 Deferred: file/confirm the `routine_runs` cron run-log observability tracking issue (OUT of scope here).
