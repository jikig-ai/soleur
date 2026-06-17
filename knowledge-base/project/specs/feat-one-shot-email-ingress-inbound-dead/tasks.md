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

- [ ] 0.1 Re-verify `route.ts` ack ordering (dedup + inngest.send awaited before 2xx; lines 176/292/315) — the L3→L7 discriminator depends on it.
- [ ] 0.2 Pre-diagnosis sanity gate: confirm the probe's OWN self-check is intact (read `cron-email-ingress-probe.ts` assert + `probe_tokens` record/match) — rule out a false-negative on a live chain BEFORE concluding the chain is dead.
- [ ] 0.3 CPO sign-off recorded (single-user-incident threshold) before /work proceeds.

## Phase 1 — Live diagnosis (read-only, L3→L7 order)

- [ ] 1.1 Pull Sentry `cron-email-ingress-probe` Crons check-in history; classify the 06-17 06:15 failure as `error` (fired, assert failed → break downstream of send) vs `missed`. [artifact]
- [ ] 1.2 Pull the **Resend delivery log** for the probe's outbound→inbound round-trip: delivered-2xx vs non-2xx vs no-delivery → localizes the dead hop empirically.
- [ ] 1.3 **L3 egress (H1):** MANDATORY `nft list set ip filter soleur_egress_allow` vs `dig +short <ref>.supabase.co` (all A records) diff — assert the data-plane IP the route dials NOW ∈ set. Corroborate with Sentry `egress-blocked` op-tag events (IP→host via ipinfo). [artifact = the diff]
- [ ] 1.4 **L3 ingress (H2a/H2b):** Resend `email.received` webhook present+enabled (`resend-inbound-bootstrap.sh` GET steps); `dig MX inbound.soleur.ai` vs `dns.tf`; Proton Sieve forward active.
- [ ] 1.5 **L7 tunnel (H3):** `curl -sI https://app.soleur.ai/api/webhooks/resend-inbound` → expect route 4xx (svix-header guard), NOT tunnel 502/404; check `tunnel.tf` ingress block. [artifact = curl -Iv headers]
- [ ] 1.6 **L7 route (H4/H4b):** confirm `RESEND_INBOUND_WEBHOOK_SECRET` set in Doppler `soleur/prd`; `processed_resend_events` write-health (recent successful inserts vs route Sentry dedup-step errors); disambiguate dedup-poison from H1-on-HOP-E (function ran-and-threw vs silently egress-dropped).
- [ ] 1.7 **L7 Inngest (H5):** if send-step ok but assert fails + other functions stalled → desync; if send-step fails → dead 8288 listener. Distinguish in the artifact.
- [ ] 1.8 Record the confirmed hypothesis (H1/H2a/H2b/H3/H4/H4b/H5) OR H6 (none-of-the-above → Resend-log localization + CPO escalation, NO speculative fix). Mark every layer verified/not-verified (only sanctioned opt-out: Inngest-Cloud-egress).
- [ ] 1.9 Prune `## Files to Edit` to the confirmed hypothesis subset; run the open-code-review-overlap query against the pruned list.

## Phase 2 — Fix (PRUNED to the confirmed hypothesis — do only the matching arm)

- [ ] 2-H1 add Supabase data-plane host coverage to `cron-egress-allowlist.txt`/`cron-egress-resolve.sh` (auto-applies on merge); RED-first regression test: probe downstream-host set ⊆ allowlist.
- [ ] 2-H2a re-enable Resend receiving / recreate webhook (`resend-inbound-bootstrap.sh`) or fix `dns.tf` MX drift; RED-first: webhook-present-and-enabled probe / MX plan-shape test.
- [ ] 2-H2b re-enable Proton Sieve forward (operator) + synthetic forward monitor if automatable; runbook-document (guard N/A).
- [ ] 2-H3 restore `/api/*` ingress in `tunnel.tf`; RED-first: tunnel ingress plan-shape test.
- [ ] 2-H4 restore `RESEND_INBOUND_WEBHOOK_SECRET` (stdin, never bang-prefix); one-row dedup release only if a specific wedged `svix_id` is identified (no bulk delete).
- [ ] 2-H4b fix `processed_resend_events` RLS/constraint regression; RED-first: fresh-claim-insert-succeeds test.
- [ ] 2-H5 merge restarts container (remediation); intermediate checkpoint asserts `email-on-received` registered post-restart; RED-first: registry parity test.

## Phase 3 — Verify (gates)

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (NOT `npm run -w`).
- [ ] 3.2 Regression test green via real runner: `./node_modules/.bin/vitest run <path>` (TS) or `bash apps/web-platform/infra/cron-egress-firewall.test.sh` (shell).
- [ ] 3.3 Runbook updated (`cron-egress-blocked.md` or new `inbound-email-ingress-dead.md`) with the L3→L7 no-SSH diagnosis flow.
- [ ] 3.4 PR body: `Ref #<N>` (NOT `Closes`) — ops-remediation class.

## Phase 4 — Post-merge (operator + automated)

- [ ] 4.1 Fire probe: `/soleur:trigger-cron cron/email-ingress-probe.manual-trigger`.
- [ ] 4.2 AC8: `mail_class='probe'` row lands in `email_triage_items` within 15m + Sentry monitor → `ok` (query via Supabase MCP + Sentry check-in API).
- [ ] 4.3 AC8b: if probe still red → issue stays OPEN, re-enter diagnosis treating the applied fix as ruled-out; escalate H6+CPO on a second failure.
- [ ] 4.4 AC8c (only if probe short-circuits BEFORE the shared insert): operator forwards one real email; assert non-probe row lands.
- [ ] 4.5 AC9: next scheduled run (`0 6 * * *`) stays green (Sentry API, no dashboard).
- [ ] 4.6 AC10: `gh issue close <N>` only after AC8 (and AC8c if applicable) passes.
- [ ] 4.7 Deferred: file/confirm the `routine_runs` cron run-log observability tracking issue (OUT of scope here).
