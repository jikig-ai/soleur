---
title: Inbound email ingress dead — L3→L7 diagnosis
date: 2026-06-17
owners: engineering/ops
applies_to: apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts
related_pr: 5465
related_adr: ADR-055 (Resend inbound), ADR-052 (egress firewall), ADR-030 (self-hosted Inngest)
---

# Inbound email ingress dead — L3→L7 diagnosis

The operator-inbox email-triage chain has gone silent: the
`cron-email-ingress-probe` Sentry Crons monitor is RED (`status=error`)
and no new rows are landing in `email_triage_items`. This runbook is the
**no-SSH** diagnosis flow (`hr-no-ssh-fallback-in-runbooks`,
`hr-no-dashboard-eyeball-pull-data-yourself`).

> **First instinct trap (read this before you touch the firewall).** This
> chain spans an *operator-owned* hop (Proton Sieve forward) that no Soleur
> infra change can fix. The egress firewall / LB-rotation is the *loudest*
> recent change but it is **egress-only** — it cannot sever the inbound
> svix POST, and it cannot explain a break that survives an egress fix. Run
> the **fast differential** below FIRST; it localizes the dead hop in one
> step and stops you editing the allowlist for an ingress cause.

## Topology (hop-by-hop)

```
ops@soleur.ai (Proton mailbox, apex MX = protonmail.ch)
  └─ HOP A: Proton Sieve auto-forward  ops@ → <x>@inbound.soleur.ai   [OPERATOR-OWNED]
       └─ HOP B: Resend receiving MX (inbound-smtp.eu-west-1.amazonaws.com)
            └─ svix-signed POST → https://app.soleur.ai/api/webhooks/resend-inbound  [Cloudflare tunnel → host INPUT]
                 └─ HOP C: route.ts dedup claim → processed_resend_events  [Supabase egress]
                      └─ HOP D: inngest.send (127.0.0.1:8288, self-hosted, ADR-030)  [loopback, NOT egress]
                           └─ HOP E: email-on-received claim-insert → email_triage_items  [Supabase egress, SHARED probe+real]
                                ├─ probe: probe_tokens lookup → mail_class='probe' (NO LLM)   [finalize AFTER the shared HOP E insert]
                                └─ HOP F: real mail → fetch-sanitize-summarize (Resend body GET + Anthropic LLM)
```

The firewall (DOCKER-USER, FORWARD hook) filters **egress only** — it can
drop HOP C/E (Supabase) but never the inbound POST at HOP B (arrives via
the Cloudflare tunnel → host INPUT).

## Fast differential (run this FIRST — it localizes the dead hop in one step)

The daily probe traverses **HOP A (Proton)**. A direct-to-inbound test email
**bypasses Proton** and exercises only HOP B→E. Compare the two:

1. **Send a direct-to-inbound canary** — an email from a Resend-verified
   sender straight to `<x>@inbound.soleur.ai` (the receiving local-part),
   bypassing `ops@soleur.ai`/Proton entirely. (The 2026-06-17 incident used
   ad-hoc diagnostic sends with subjects `SOLEUR-INGRESS-DIAG-<uuid>` /
   `INBOUND-LEG-DIAGNOSTIC direct-to-inbound (bypasses Proton)`.)
2. **Read the data plane** (read-only, service-role over REST — no SSH):

   ```bash
   SB=$(doppler secrets get SUPABASE_URL -p soleur -c prd --plain)
   KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
   hdr=(-H "apikey: $KEY" -H "Authorization: Bearer $KEY")
   # HOP C write-health (did Resend POST a webhook the route claimed?):
   curl -sS "${hdr[@]}" "$SB/rest/v1/processed_resend_events?select=*&order=received_at.desc&limit=10"
   # HOP E (did email-on-received claim-insert?):
   curl -sS "${hdr[@]}" "$SB/rest/v1/email_triage_items?select=id,created_at,mail_class,subject,resend_email_id,claim_key&order=created_at.desc&limit=10"
   # probe outbound health (is the cron sending + recording tokens daily?):
   curl -sS "${hdr[@]}" "$SB/rest/v1/probe_tokens?select=*&order=created_at.desc&limit=7"
   ```

3. **Read the verdict:**

   | Direct-to-inbound canary | Proton-routed probe | Dead hop | Fix |
   |---|---|---|---|
   | **arrives** (processed_resend_events + email_triage_items rows appear) | does NOT arrive (no probe svix_id / no `SOLEUR-PROBE-*` row) | **HOP A — Proton Sieve forward (H2b)** | operator re-enables the Sieve forward; infra is healthy, **do not touch the allowlist** |
   | does NOT arrive | does NOT arrive | HOP B–E (infra) | continue the L3→L7 checklist below |
   | arrives, but `mail_class`/`summary` stay NULL | n/a | HOP F summarizer tail | investigate `fetch-sanitize-summarize` (Resend body GET / Anthropic) — does NOT break the probe path |

If `probe_tokens` shows clean daily rows but no probe ever lands in
`email_triage_items`, and a direct-to-inbound canary DOES land → the outbound
send works, the inbound infra works, and the only differing hop is Proton.
**That is H2b.**

## L3→L7 checklist (run only if the canary did NOT arrive)

Verify lower layers before any application-layer conclusion
(`hr-ssh-diagnosis-verify-firewall`). Mark each verified/not-verified with
an artifact.

- **L7 tunnel + secret (H3/H4) — no SSH:**
  ```bash
  curl -sS -o /dev/null -w "HTTP=%{http_code} server=%header{server}\n" \
    -X POST https://app.soleur.ai/api/webhooks/resend-inbound
  ```
  Expect **401** (route's own svix-header guard) with `server=cloudflare`.
  - 401 (not 500) ⟹ tunnel + route reachable AND `RESEND_INBOUND_WEBHOOK_SECRET`
    is set (an unset secret returns 500 at Step 1, `route.ts:100`).
  - tunnel 502/404 ⟹ H3 (tunnel/cert) — check `apps/web-platform/infra/tunnel.tf`.
- **L3 ingress MX (H2a) — no SSH:**
  ```bash
  dig +short MX inbound.soleur.ai   # expect: 10 inbound-smtp.eu-west-1.amazonaws.com.
  ```
  Drift ⟹ compare against `apps/web-platform/infra/dns.tf`. Resend
  receiving + the `email.received` webhook being enabled is **proven** by any
  live svix POST landing in `processed_resend_events` — a webhook delivery
  IS the receiving-enabled artifact.
- **L3 egress (H1) — prefer the end-to-end proof over the nft set read:**
  A successful `processed_resend_events` / `email_triage_items` write *is* a
  Supabase egress write through the firewall — it proves egress works more
  strongly than nft-set membership (the membership check is one necessary
  condition; the write succeeding proves all of them). Only if claim-inserts
  are *failing* do you need the host read:
  `nft list set ip filter soleur_egress_allow` vs
  `dig +short ifsccnjhymdmidffkzhl.supabase.co` (data-plane host from
  `SUPABASE_URL`; note `NEXT_PUBLIC_SUPABASE_URL`=`api.soleur.ai` is the same
  host behind Cloudflare). `api.supabase.com` in the allowlist is the
  Management API — **not** the data-plane host the route dials.
- **L3 egress corroboration (H1):** Sentry `egress-blocked` op-tag events in
  the window (`extra.sample` carries the dropped DST IP; map via
  `curl -s https://ipinfo.io/<ip>/json`). A Supabase IP here proves *a* drop
  occurred, possibly already healed — corroborating, not confirming.
- **L7 Inngest (H5):** if a probe lands in `email_triage_items` but assert
  fails (row present, `mail_class` never 'probe') and other Inngest functions
  are stalled → desync; a container restart (merge to `apps/web-platform/**`)
  re-registers. If `probe_tokens` stops gaining rows → the cron scheduler /
  8288 listener is down, not ingress.
- **Sentry monitor history (no SSH, Crons-scoped token):**
  ```bash
  T=$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
  curl -sS -H "Authorization: Bearer $T" \
    "https://sentry.io/api/0/organizations/jikigai-eu/monitors/cron-email-ingress-probe/checkins/?per_page=20" \
    | python3 -c "import sys,json;[print(c['dateCreated'],c['status']) for c in json.load(sys.stdin)]"
  ```
  `status=error` (fired, asserted, row absent → downstream of send) vs
  `status=missed` (scheduler never fired → Inngest desync).

## Root-cause → remediation

| Confirmed | Remediation | Regression guard |
|---|---|---|
| **H2b Proton Sieve forward** | Operator re-enables the Sieve forward in Proton webmail (Settings → Filters / Forwarding: `ops@soleur.ai → <x>@inbound.soleur.ai`). Confirm Proton has not spam-foldered/blocked the `notifications@soleur.ai` sender. | N/A (operator-owned). The existing daily probe already alarms on recurrence; see *Recommended hardening*. |
| H1 egress drop | add the data-plane host coverage in `cron-egress-allowlist.txt` / `cron-egress-resolve.sh` (auto-applies on merge) | `cron-egress-firewall.test.sh` host-coverage assertion |
| H2a webhook/MX | re-run `resend-inbound-bootstrap.sh` (idempotent) / fix `dns.tf` MX | webhook-enabled probe / MX plan-shape test |
| H3 tunnel | restore `/api/*` ingress in `tunnel.tf` (auto-applies) | tunnel ingress plan-shape test |
| H4/H4b secret/dedup | restore `RESEND_INBOUND_WEBHOOK_SECRET` (stdin, never `!` bang-prefix); one-row dedup release only for a named wedged `svix_id` | fresh-claim-insert-succeeds test |
| H5 Inngest | merge restarts the container (the remediation); assert `email-on-received` registered post-restart | function-registry parity test |

## 2026-06-17 incident record

- **Symptom:** `cron-email-ingress-probe` RED daily 06-13→06-17; last
  `email_triage_items` row 2026-06-12 19:32. Probe still failed 06-17 06:15
  **after** the #5413 grace-window egress fix.
- **Root cause: H2b — Proton Sieve forward `ops@soleur.ai → inbound.soleur.ai`
  broken (HOP A).** The egress firewall was a red herring — egress-only and
  proven healthy.
- **Evidence:** direct-to-inbound diagnostics landed (processed_resend_events
  `msg_3FGK…` 06-17 11:30, `msg_3F39…` 06-12 19:32; email_triage_items rows
  `5de15f49`, `361908db`); Proton-routed daily probes never produced a Resend
  webhook despite clean daily outbound sends (probe_tokens 06-13→06-17 at
  06:00). Route POST → 401 (tunnel + secret healthy). MX intact. Supabase
  claim-inserts succeed (egress healthy).
- **Secondary defect (separate follow-up):** both landed diagnostics are
  `mail_class=null`/`summary=null` — the non-probe HOP F summarizer tail
  fails. Does not affect the probe path.

## Recommended hardening

The daily probe alarms when this chain breaks but cannot self-localize
Proton-vs-infra — the 2026-06-17 diagnosis needed a manual direct-to-inbound
canary. Adding a **direct-to-inbound canary step** to
`cron-email-ingress-probe` (send a 2nd marker straight to
`<x>@inbound.soleur.ai`, assert both) would make a future break self-report
"Proton forward broken" vs "inbound infra broken" without a manual
differential. Tracked as a post-incident follow-up.
