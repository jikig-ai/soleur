---
title: "fix: inbound email ingress pipeline dead since 2026-06-12"
date: 2026-06-17
type: bug
classification: ops-remediation + code/config fix (root cause TBD by live diagnosis)
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
status: diagnosed
---

## Diagnosis Result (2026-06-17) — H2b CONFIRMED (Proton Sieve forward broken)

> Live read-only diagnosis complete. **Root cause = H2b: the Proton Sieve
> auto-forward `ops@soleur.ai → <x>@inbound.soleur.ai` (HOP A) is broken.**
> The egress firewall was a red herring — egress-only and proven healthy.
> This explains the load-bearing fact (probe still failed after #5413): no
> egress fix can repair a Proton-side forward.

**Decisive differential:** direct-to-inbound diagnostics (bypassing Proton)
land end-to-end; Proton-routed daily probes never produce a Resend webhook
despite clean daily outbound sends. The only differing hop is Proton.

| Layer | Verdict | Artifact |
|---|---|---|
| L3 egress (H1) | ruled out | Supabase claim-inserts succeed for direct mail (`processed_resend_events` msg_3FGK 06-17; `email_triage_items` rows) — end-to-end egress write through the firewall (stronger than nft-set membership) |
| L3 ingress MX (H2a-MX) | ruled out | `dig MX inbound.soleur.ai` → `inbound-smtp.eu-west-1.amazonaws.com` |
| L3 ingress webhook (H2a-webhook) | ruled out | live svix POSTs (msg_3FGK, msg_3F39) prove Resend receiving + `email.received` webhook enabled |
| **L3 ingress Proton Sieve (H2b)** | **CONFIRMED** | direct-to-inbound mail arrives (06-12, 06-17); Proton-routed probes never produce a webhook (probe_tokens clean daily 06-13→06-17) |
| L7 tunnel (H3) | ruled out | `curl POST` → route 401 (svix-header guard), `server=cloudflare`, not tunnel 502/404 |
| L7 secret (H4) | ruled out | 401 not 500 → `RESEND_INBOUND_WEBHOOK_SECRET` set |
| L7 dedup blocker (H4b) | ruled out | `processed_resend_events` claim-insert succeeds (msg_3FGK 06-17 11:30) |
| L7 Inngest (H5) | ruled out | email-on-received ran + claim-inserted for direct mail → registered, 8288 listener alive |
| Inngest-cloud-egress | opted out | topology (ADR-030 self-hosted loopback) |

**Precise mechanism (confirmed in the live mailbox):** the Sieve filter
`ops@ → inbound triage (forward-and-keep, #5103)` is **enabled** and its
condition matches; every daily probe sits in the `ops@soleur.ai` **inbox**
(NOT spam, so the spam-guard isn't firing). The `redirect :copy
"triage@inbound.soleur.ai"` action **does not deliver** — forwarding breaks
SPF/DMARC alignment (apex soleur.ai SPF authorizes only Proton), so Resend's
inbound MX drops the forwarded copy.

**Fix shape:** H2b is operator-owned Proton config — **no code regression in
this repo → regression guard N/A** (plan §"diagnosis-driven fix"). Remediation
= replace the fragile Sieve `redirect` with Proton's **native auto-forward**
(SRS-based, survives SPF); the one-time confirmation link emailed to
`triage@inbound.soleur.ai` is read via the Resend dashboard. Rule creation
needs the operator's Proton password (true human gate). Repo deliverable =
runbook only (AC3 forbids speculative edits to unconfirmed-hypothesis files).

**Secondary discovered defect (separate follow-up #5468):** non-probe inbound
mail finalizes `mail_class=null`/`summary=null`. Root cause found during this
diagnosis: the prod `RESEND_API_KEY` is **send-only**, so `fetchReceivedEmail`
(`resend.emails.receiving.get`) throws → the HOP F summarizer tail fails. Fix
= read-capable Resend key in Doppler + redeploy. Does not affect the probe
path (probe finalizes before HOP F).
---

# 🐛 Fix: inbound email ingress pipeline is dead (operator-inbox email-triage chain)

## Overview

Zero inbound emails have landed in `email_triage_items` (prod) since **2026-06-12 19:32 UTC** (latest row; `mail_class=null`). The daily liveness probe `cron-email-ingress-probe` (`apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts`) **FAILED 2026-06-17 06:15 UTC** with `ingress probe row absent after 15m — email ingress chain is broken`. The outbound Resend send step does not throw, so the break is on the **inbound** side.

The break window overlaps the cron egress-firewall rollout (DOCKER-USER default-drop, #5089 merged 2026-06-10 13:43 UTC) and the route's own go-live (#5125 merged 2026-06-11 11:01 UTC). A grace-window IP-retention fix (#5413) merged **2026-06-16 13:17 UTC** to stop LB-rotation egress drops — **yet the probe still failed at 2026-06-17 06:15 UTC, AFTER that fix**. That single fact is load-bearing: the generic LB-rotation explanation the grace-window fix addresses is **not a complete root cause**, so this plan must **diagnose against live prod state first** (L3→L7) and let the diagnosis drive the fix — it must NOT pin a single cause from code-reading alone.

**Goal:** root-cause the inbound break, fix it, verify a probe round-trips end-to-end (a `mail_class='probe'` row lands within the 15m SLA), and add a regression guard if the cause is a code/config regression.

**Explicitly OUT of scope (separate follow-up PR):** the cron run-log observability gap (heavy claude-spawning crons not writing `routine_runs` rows). `public.routine_runs` was newly deployed 2026-06-16 and is too young to answer historical windows — for this investigation, pull Sentry cron check-in history directly (per `hr-no-dashboard-eyeball-pull-data-yourself`). A deferral tracking issue is filed (see Deferred Items).

## The inbound topology (verified hop-by-hop)

```
ops@soleur.ai (Proton)
  └─ Proton Sieve auto-forward  →  <x>@inbound.soleur.ai
       └─ Resend receiving MX (eu-west-1 AWS SMTP, inbound.soleur.ai)   [HOP A: external/MX]
            └─ svix-signed POST  →  https://app.soleur.ai/api/webhooks/resend-inbound   [HOP B: INGRESS via Cloudflare tunnel]
                 └─ route.ts: svix verify → dedup insert into processed_resend_events   [HOP C: EGRESS → Supabase data-plane]
                      └─ inngest.send(EMAIL_INBOUND_RECEIVED_EVENT)                       [HOP D: loopback 127.0.0.1:8288, self-hosted]
                           └─ email-on-received.ts: claim-insert into email_triage_items   [HOP E: EGRESS → Supabase data-plane, SHARED by probe + real mail]
                                ├─ probe path: probe_tokens lookup → finalize mail_class='probe' (NO LLM)   [diverges AFTER the shared HOP E insert]
                                └─ real mail: fetch-sanitize-summarize (LLM, Anthropic)                      [HOP F: real-mail-only tail, probe never exercises this]
```

> **Verified (verify-the-negative pass):** the probe and real mail **share** the HOP E `claim-insert` into `email_triage_items` (`email-on-received.ts:234,291-310`); they diverge AFTER it — probe does a `probe_tokens` lookup (`:378`) + `mail_class='probe'` finalize (`:391-394`), real mail goes on to the LLM summariser (HOP F, `:425`). So the probe round-trip proves HOPS A→E but does NOT exercise the real-mail HOP F summariser tail or the deadline-repin. AC8's "short-circuit-after-insert" invariant HOLDS (good); AC8c covers the residual real-mail tail. The earlier loose phrasing "probe short-circuits before the LLM, Supabase-only" was misleading — corrected here.

Evidence: `apps/web-platform/infra/resend-inbound-bootstrap.sh:43-47` (domain `inbound.soleur.ai`, webhook endpoint `https://app.soleur.ai/api/webhooks/resend-inbound`); `apps/web-platform/app/api/webhooks/resend-inbound/route.ts:81-316`; `apps/web-platform/server/inngest/client.ts` (`baseUrl: http://127.0.0.1:8288`, self-hosted per ADR-030); `apps/web-platform/server/inngest/functions/email-on-received.ts:233-341` (claim-insert).

**Firewall direction (decisive):** the nftables DOCKER-USER chain filters **EGRESS only** (FORWARD hook). It **cannot drop the inbound svix POST itself** (HOP B arrives via Cloudflare tunnel → host INPUT, never FORWARD/DOCKER-USER — `apps/web-platform/infra/cron-egress-nftables.sh` header). It **can** drop the route handler's and the Inngest function's **downstream Supabase egress** (HOPS C, E). The Supabase data-plane host (`<ref>.supabase.co`) is a **dynamic env-resolved** host in `cron-egress-resolve.sh:149` (`NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_URL`), NOT the static `api.supabase.com` line in the allowlist — `api.supabase.com` is the Management API, a different host.

## User-Brand Impact

**If this lands broken, the user experiences:** statutory/legal emails the operator forwards to `ops@soleur.ai` silently vanish — they never appear in the operator inbox, never get a summary, and the statutory-deadline backstop (`deadline-repin`) never fires because no row exists to re-pin. The operator believes a GDPR/legal deadline is tracked when it is not.

**If this leaks, the user's data / workflow is exposed via:** N/A for the break itself (no exposure). The *diagnosis* must stay read-only on prod (Sentry check-in API, `nft list set` read, DNS/curl probes) — no synthetic rows written to PROD via integration suites (`hr-dev-prd-distinct-supabase-projects`). The probe's own synthetic `mail_class='probe'` rows are sanctioned (synthetic content from our own outbound address; learning 2026-05-16).

**Brand-survival threshold:** single-user incident. A single missed statutory email is a brand-survival event for a compliance-adjacent product. CPO sign-off required at plan time; `user-impact-reviewer` invoked at review time.

## Research Reconciliation — Spec vs. Codebase

| Claim (feature description) | Reality (verified) | Plan response |
|---|---|---|
| "Break coincides with cron egress firewall rollout (#5413 grace-window merged 2026-06-16 13:17)" | #5413 merged **2026-06-16 13:17 UTC** ✓. But the firewall **default-drop** went live earlier: #5089, **2026-06-10 13:43 UTC**. The route went live #5125, **2026-06-11 11:01 UTC**. | Hypotheses span the full firewall timeline, not just #5413. |
| "Investigate whether firewall/infra severed the inbound webhook path" | Firewall is **egress-only**; it cannot sever the inbound POST (HOP B). It CAN sever HOP C/E (Supabase egress). | L3 firewall hypothesis is scoped to the **egress** hops; a separate INGRESS hypothesis (tunnel/MX/webhook config) is required because the firewall does not explain an ingress break. |
| "Grace-window fix should have restored it" | Probe **still failed 2026-06-17 06:15**, AFTER #5413 merged 2026-06-16 13:17. | Generic LB-rotation is NOT a complete cause. The plan diagnoses live state; the fix is determined by the diagnosis, not assumed. |
| "`api.supabase.com` is allowlisted (static)" (implied safe) | `api.supabase.com` (Management API) ≠ the data-plane `<ref>.supabase.co` the route actually dials. Data-plane host is dynamic-env-resolved. | Diagnosis confirms the **data-plane** host's IPs are in `@soleur_egress_allow`, not just the static apex. |
| Inngest egress to a cloud host could be blocked | Inngest is **self-hosted** in-container (`127.0.0.1:8288`, ADR-030); HOP D is loopback, not egress. | Inngest-cloud-egress hypothesis ruled OUT by topology. |

## Hypotheses (L3 → L7 — unverified layers FIRST, per network-outage checklist)

The break manifests as a multi-hop chain failure. Per `hr-ssh-diagnosis-verify-firewall`, verify the lower layers before any service-layer hypothesis.

**Route ack ordering (cited, not assumed — the discriminator depends on it):** `route.ts` `await`s the dedup `claimDelivery` (HOP C, line 176) AND `await`s `sendInngestWithRetry` (HOP D, line 292) BEFORE returning `{ received: true }` (line 315). So a **2xx response means HOPS C and D both succeeded** → a break despite 2xx is at **HOP E** (the `email-on-received` insert into `email_triage_items`). A **5xx** localizes to HOP C (dedup-insert 500, line 186) or HOP D (inngest.send failed, line 312). This ordering is what makes the next inference sound — re-verify it at /work Phase 1 if `route.ts` has changed.

**Critical ingress/egress straddle (HOP C does BOTH):** a Resend non-2xx is NOT cleanly "ingress". HOP C runs svix-verify (secret-dependent, H4/ingress-framed) AND the Supabase dedup egress (H1/egress-framed) in the SAME handler. An egress failure inside HOP C returns 500 and shows as Resend non-2xx — masquerading as ingress. **Sub-classify any Resend non-2xx by the route's OWN Sentry event at the same timestamp:** a 4xx-at-svix-guard (op=`secret`/`signature` → true ingress/secret, H4) vs a 5xx-after-svix with an egress-blocked breadcrumb (egress inside HOP C, H1). "Resend non-2xx → ingress" is too coarse and can misroute an egress cause to the do-not-touch-allowlist branch.

**Absence of a lower-layer signal is itself a signal** — Resend *delivered 2xx* ⟹ break at HOP E (per ack ordering above); Resend *no delivery / non-2xx with NO route Sentry event* ⟹ break at HOP A/B (ingress, H2/H3); Resend *non-2xx WITH a route Sentry event* ⟹ break inside HOP C (sub-classify by op-tag per the straddle rule).

1. **L3 — egress firewall drops Supabase data-plane (HOPS C/E).** The dynamic data-plane host `<ref>.supabase.co` rotated to an IP absent from `@soleur_egress_allow`, default-dropping the dedup/claim insert. *Verification (read-only, no SSH where possible):*
   - Pull the Sentry `cron-email-ingress-probe` Crons monitor check-in history (`/monitors/<slug>/checkins/`) — `missed` vs `error` distinguishes "never fired" from "fired and assertion failed" (the 06-17 06:15 failure is an *error* = it fired, sent the probe, and the row never landed → downstream-of-send break).
   - **MANDATORY confirming step (asserts the invariant, not a proxy):** `nft list set ip filter soleur_egress_allow` and diff against `dig +short <ref>.supabase.co` (ALL current A records) — a data-plane IP the route resolves to NOW that is missing from the set is the smoking gun. The invariant is "the IP the route dials at fire time ∈ allowlist", NOT "some Supabase IP once appeared in egress-blocked". [verification artifact: paste the diff]
   - *Corroborating (not confirming):* search Sentry for `egress-blocked` / `egress_blocked` events (op-tag) in the break window; `extra.sample` carries a dropped DST IP. Map IP→host via `curl -s https://ipinfo.io/<ip>/json`. A Supabase IP here proves *a* Supabase egress was dropped — possibly a stale rotation already healed — so it corroborates but does not confirm without the `nft`/`dig` diff above.
   - Inspect `cron-egress-resolve` OK log line for `retained=M` vs `allow=N` (grace-window working ⟺ `retained > allow`).
2. **L3 — INGRESS break: MX / Resend receiving / webhook endpoint config (HOPS A/B).** The firewall does NOT explain an ingress break, so this is a parallel, independent hypothesis. Split by sub-cause because the fix + guard differ sharply:
   - **H2a (Resend webhook disabled / MX drift — CODE/CONFIG regression, guard MANDATORY).** Resend API: is the `email.received` webhook for `https://app.soleur.ai/api/webhooks/resend-inbound` still present and **enabled**? Did a change disable receiving on `inbound.soleur.ai`? (`resend-inbound-bootstrap.sh` GET steps are idempotent/read-only.) `dig MX inbound.soleur.ai` — does it still point at `inbound-smtp.*.amazonaws.com`? Compare against `apps/web-platform/infra/dns.tf` (drift = code regression).
   - **H2b (Proton Sieve forward broken — OPERATOR config, guard N/A).** Is the Sieve forward `ops@soleur.ai → <x>@inbound.soleur.ai` still active? This is operator-owned mailbox config — the one genuinely operator-checkable step (automatable up to the Resend/DNS edge only). If automatable, add a synthetic monitor for the forward; otherwise document in the runbook.
3. **L7 — TLS / Cloudflare tunnel ingress for `/api/webhooks/resend-inbound` (HOP B).** `curl -sI https://app.soleur.ai/api/webhooks/resend-inbound` (expect a 4xx from the route's own svix-header guard, NOT a tunnel 502/404). A tunnel ingress regression or `app.soleur.ai` cert/SNI break would return non-route errors. [artifact: paste `curl -Iv` headers: `Server`, `CF-Ray`]. Cross-check the tunnel ingress block in `apps/web-platform/infra/tunnel.tf` for a recent change to the catch-all/`/api/*` rule.
4. **L7 — route handler: secret / dedup poison / dedup-blocker (HOP C application layer).** Three distinct sub-modes:
   - **Secret:** confirm `RESEND_INBOUND_WEBHOOK_SECRET` is set in Doppler `soleur/prd` (rotated/unset → every POST fails Step 1/Step 2 with `secret`/`signature` Sentry op-tag events — search those).
   - **Dedup poison:** `processed_resend_events` row present for the window but no `email_triage_items` row. **Caution — observationally identical to H1-on-HOP-E** (the dedup insert at HOP C succeeded, the `email_triage_items` insert at HOP E was egress-dropped). To distinguish: H4 dedup-poison requires the `email-on-received` function to have *run and thrown* on the insert (Sentry function error), whereas H1 shows the egress *silently dropped* before the insert with NO function error. Same evidence → two fixes, so this disambiguation is load-bearing.
   - **Dedup blocker (H4b):** the dedup insert at HOP C itself fails-closed (a unique-constraint/RLS regression on `processed_resend_events`), so the route aborts at HOP C and never calls `inngest.send` — NO `email_triage_items` row AND NO function execution. Check `processed_resend_events` *write health* (recent successful inserts in the window vs route Sentry errors at the dedup step), not just stale-row presence.
5. **L7 — Inngest function desync OR dead listener (HOP D/E).** Did the `email-on-received` function lose registration after a container restart (#5159/#5188 serveHost re-registration class)? Check `cron-email-ingress-probe` monitor: if its OWN send step succeeds but the assert fails, and OTHER Inngest functions are also stalled, suspect a function-registry desync. A **dead `127.0.0.1:8288` listener** (Inngest process crashed) presents differently — as a *send-step failure* (distinct from desync's send-success-but-assert-fail). Both are remediated by the `web-platform-release.yml` container-restart path on merge (NOT an SSH step), but they MUST be distinguished in the recorded artifact so the cause is logged correctly. *Confirm via:* post-restart, query the self-hosted Inngest function-list endpoint and assert `email-on-received` is present (an intermediate checkpoint BETWEEN the restart and the AC8 probe, so a desync is caught before the downstream-conflated probe).
6. **H6 — none-of-the-above (residual).** The load-bearing fact (probe STILL failed after #5413) is precisely the signal the cause may be outside H1–H5. This is a **valid, documented outcome**, not a dead end. *Procedure:* (a) pull the **Resend delivery log** for the probe's own outbound→inbound round-trip to localize the dead hop empirically (delivered-2xx vs not); (b) if Resend shows delivery but NO route Sentry event at all, the break sits between tunnel and route registration (a hop H1–H5 only partially cover); (c) escalate to CPO with the full artifact bundle rather than shipping a speculative fix. AC1 references H6 so "no hypothesis confirmed" is a documented terminal state.

**Pre-diagnosis sanity gate (run BEFORE concluding the chain is dead):** confirm the probe's OWN self-check path is intact — read `cron-email-ingress-probe.ts` assert logic and the `probe_tokens` record/match path. A regression in token-recording or the classification short-circuit's token-match would make the probe fail (`error` check-in) while the inbound chain is actually ALIVE — a false-negative that would send the operator chasing H1–H5 for nothing. Rule this out first.

**Opt-out (the ONLY sanctioned one):** Inngest-Cloud-egress is opted out — topology proves Inngest is self-hosted loopback (ADR-030, `client.ts` baseUrl), so HOP D is not egress. Every OTHER layer requires a positive verified/not-verified artifact (AC2); no other opt-out is permitted.

## Diagnosis-driven fix (the fix shape is determined by which hypothesis confirms)

This is the load-bearing structure: **diagnose first, then apply the matching fix.** Each confirmed hypothesis maps to a concrete remediation:

- **H1 confirmed (Supabase data-plane egress drop):** add the data-plane host coverage to the egress mechanism. Two sub-cases:
  - If `<ref>.supabase.co` is resolving but grace-window isn't accumulating its rotation pool → raise `GRACE_WINDOW_SECS` or confirm the dynamic-host loop actually resolves it (the `extract_host` of `NEXT_PUBLIC_SUPABASE_URL`). Fix lands in `cron-egress-allowlist.txt` and/or `cron-egress-resolve.sh`; **auto-applies on merge** via `terraform_data.cron_egress_firewall` + `apply-web-platform-infra.yml` (no SSH step).
  - If the data-plane host is genuinely missing from the dynamic loop → add it explicitly with an evidence comment. **Regression guard:** extend `cron-egress-firewall.test.sh` to assert the Supabase data-plane host is covered, AND add a test asserting `cron-email-ingress-probe`'s downstream-host set ⊆ allowlist.
- **H2a confirmed (Resend webhook disabled / MX drift — code/config):** re-run `resend-inbound-bootstrap.sh` (idempotent) to re-enable receiving / recreate the webhook; or fix `dns.tf` MX drift and let `apply-web-platform-infra.yml` re-apply. **Regression guard MANDATORY:** a synthetic-check or scheduled probe asserting the Resend `email.received` webhook exists + is enabled (extends the existing daily probe rationale); MX plan-shape test for `dns.tf`.
- **H2b confirmed (Proton Sieve forward broken — operator config):** re-enable the Sieve forward (operator mailbox). **Guard N/A** (operator-owned); add a synthetic forward monitor if automatable, else runbook-document.
- **H3 confirmed (tunnel ingress regression):** restore the `/api/*` ingress rule in `tunnel.tf`; auto-applies on merge. **Regression guard MANDATORY:** assert the tunnel ingress block contains the catch-all/`/api/*` route (Terraform plan-shape test).
- **H4 confirmed (secret unset / dedup poison):** restore `RESEND_INBOUND_WEBHOOK_SECRET` in Doppler `soleur/prd` (via `resend-inbound-bootstrap.sh` step 4, never via `!` bang-prefix per `hr-never-paste-secrets-via-bang-prefix`). Dedup poison: targeted read-only confirm, then a one-row release only if a specific wedged `svix_id` is identified (no bulk delete, `hr-bulk-delete-per-item-live-infra-role-check`). **Guard:** route already fail-closes on unset secret (`route.ts:99-110`); add a startup/probe assertion if the secret can silently become unset (secret-rotation = transient, guard N/A).
- **H4b confirmed (dedup-insert blocker — RLS/constraint regression on `processed_resend_events`):** fix the constraint/RLS regression. **Regression guard MANDATORY:** test asserting a fresh `svix_id` claim-insert succeeds (the write-health invariant).
- **H5 confirmed (Inngest desync / dead listener):** the merge itself restarts the container (`web-platform-release.yml` path-filtered on `apps/web-platform/**`) — a PR merge IS the remediation. Intermediate checkpoint: post-restart, assert `email-on-received` present in the Inngest function-list endpoint BEFORE the AC8 probe. **Regression guard MANDATORY:** confirm `email-on-received` is in `EXPECTED_CRON_FUNCTIONS`/the function registry parity test.
- **H6 confirmed (none of the above):** NO speculative fix ships. Document the Resend-delivery-log localization + the full artifact bundle, escalate to CPO. The issue stays open.

> If the diagnosis confirms a **code/config regression** (H1 missing-host, H2a webhook/MX, H3 tunnel rule, H4b dedup-blocker, H5 registry gap), the regression guard is **mandatory** (`wg-when-a-workflow-gap-causes-a-mistake-fix`). If it is a **transient/operator-config** cause (H2b Sieve, H4 rotated-secret) with no code regression, document the cause + remediation in the runbook and note "no code regression → guard N/A" with a one-line justification.

## Files to Edit (candidate set — pruned by diagnosis)

- `apps/web-platform/infra/cron-egress-allowlist.txt` — (H1) add Supabase data-plane host with evidence comment, IF missing from the dynamic loop.
- `apps/web-platform/infra/cron-egress-resolve.sh` — (H1) only if the dynamic-host resolution or grace-window logic needs a fix for the data-plane host.
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — (H1 regression guard) assert probe's downstream-host coverage.
- `apps/web-platform/infra/dns.tf` — (H2) MX drift correction.
- `apps/web-platform/infra/tunnel.tf` — (H3) restore `/api/*` ingress rule.
- `apps/web-platform/test/server/inngest/cron-email-ingress-probe.test.ts` — regression test for the confirmed cause (downstream-host-set assertion or registration assertion).
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` (or a new `inbound-email-ingress-dead.md` runbook) — document the diagnosis + remediation for next time.

> NOTE: the actual Files-to-Edit set is **pruned to the confirmed hypothesis** at /work Phase 1. Editing all of the above would be wrong — the diagnosis selects the subset.

## Files to Create

- `knowledge-base/engineering/operations/runbooks/inbound-email-ingress-dead.md` — (likely) a dedicated runbook for the inbound-chain diagnosis flow (L3→L7 order, the Sentry check-in queries, the `nft`/`dig` diff, the Resend webhook re-check). Only if `cron-egress-blocked.md` doesn't already cover the inbound chain.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returns no scope-outs touching the candidate files (`route.ts`, `cron-egress-*`, `email-on-received.ts`, `cron-email-ingress-probe.ts`). [Verify the exact two-stage `gh --json` + standalone `jq --arg` query at /work Phase 1 against the live file list once pruned.]

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Root cause named with live evidence (or H6 documented).** The PR body states which hypothesis (H1, H2a, H2b, H3, H4/H4b, H5) is confirmed — OR records H6 (none-of-the-above) as a valid terminal outcome with the Resend-delivery-log localization + CPO escalation. Either way the **verification artifact** is pasted (Sentry check-in history showing the `error`/`missed` pattern; the mandatory `nft list set` vs `dig` data-plane diff; the Resend webhook-enabled state; the tunnel/cert curl headers; or the Resend delivery log for H6). A code-reading-only conclusion is NOT acceptable.
- [x] **AC2 — L3→L7 order honored.** Diagnosis verified the egress-firewall (L3) AND the ingress MX/webhook/tunnel (L3/L7) layers before any application-layer conclusion; each layer marked verified/not-verified with an artifact. The ONLY permitted opt-out is Inngest-Cloud-egress (topology-justified per the Hypotheses opt-out); every other layer requires a positive verified/not-verified artifact.
- [x] **AC3 — Fix matches the confirmed cause.** The diff edits ONLY the file subset the confirmed hypothesis requires; no speculative edits to unconfirmed-hypothesis files. If H6 (none-of-the-above) is the outcome, NO speculative fix ships — the PR documents the artifact bundle and escalates to CPO.
- [x] **AC4 — Regression guard (conditional).** H2b is operator-owned config — **no code regression → guard N/A, runbook updated** (per plan §diagnosis-driven fix). The existing daily probe already alarms on recurrence. IF the cause is a code/config regression (H1, H2a, H3, H4b, H5), a test asserts the invariant that was violated (e.g., probe's downstream-host set ⊆ egress allowlist; Resend `email.received` webhook present+enabled; tunnel `/api/*` ingress present; `processed_resend_events` write-health; `email-on-received` registered). Test runs green via the package's real runner: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (TS) or `bash apps/web-platform/infra/cron-egress-firewall.test.sh` (shell). IF transient/operator-config (H2b Sieve, H4-secret-rotation) with no code regression, the PR body records "no code regression → guard N/A, runbook updated" with a one-line rationale.
- [x] **AC5 — Runbook updated.** New `inbound-email-ingress-dead.md` (dedicated — the cause is Proton Sieve, not egress, so `cron-egress-blocked.md` is the wrong home). `cron-egress-blocked.md` (or new `inbound-email-ingress-dead.md`) carries the inbound-chain L3→L7 diagnosis flow with no-SSH queries (`hr-no-ssh-fallback-in-runbooks`).
- [ ] **AC6 — Typecheck clean:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`).
- [x] **AC7 — Issue link uses `Ref #N`** (not `Closes #N`) in the PR body — this is an ops-remediation class fix whose verification completes post-merge (the probe must round-trip green in prod). Actual closure happens in the post-merge step after the green probe.

### Post-merge (operator + automated)

- [x] **AC8 — End-to-end probe round-trips green. VERIFIED 2026-06-17 13:36 UTC.** After activating the native Proton forward, a manual-trigger probe (token `739db236…`) landed as `mail_class='probe'` in `email_triage_items` in ~11s (≪ 15m SLA). The probe traverses the SAME `email-on-received` claim-insert as real mail; the `mail_class='probe'` short-circuit happens AFTER that shared insert (invariant holds) — so AC8c is NOT required for the ingress proof. Fire the probe on demand via `/soleur:trigger-cron cron/email-ingress-probe.manual-trigger` (reads the trigger secret read-only from Doppler; no SSH). Within the 15m SLA, a `mail_class='probe'` row lands in `email_triage_items` and the `cron-email-ingress-probe` Sentry Crons monitor transitions to `ok`. [Automatable: `mcp__plugin_supabase_supabase__*` read query for the new row + Sentry check-in API for the `ok` transition.] **Probe ≡ real-mail invariant:** confirm the probe traverses the SAME `email-on-received` claim-insert into `email_triage_items` that real operator mail uses (`email-on-received.ts:233-341`), and that the `mail_class='probe'` short-circuit happens AFTER that shared insert — not before it. If the short-circuit precedes the shared write, the probe is a proxy and AC8 MUST be supplemented by AC8c (one real-forward test), because the probe cannot cover the divergent real-mail tail.
- [ ] **AC8b — AC8-red is NOT a dead end.** If the probe row does NOT land within 15m after the merged fix, AC8 fails and the issue stays OPEN (AC10 blocked). Re-enter the L3→L7 diagnosis treating the applied fix as a now-ruled-out hypothesis (a red AC8 means the confirmed hypothesis was wrong/incomplete, NOT that the SLA window was too short — `retries:0` and the 15m window are pinned by design). Escalate to H6 + CPO if a second pass also fails to confirm.
- [ ] **AC8c — Real-mail tail (only if AC8's short-circuit-after-insert invariant does NOT hold).** Operator forwards ONE real email to `ops@soleur.ai`; assert it lands as a non-probe `email_triage_items` row within the SLA. (Automatable up to the Proton Sieve edge; the forward itself is the one operator action — `Automation: not feasible because the source mailbox send is operator-owned`.)
- [ ] **AC9 — Monitor stays green on the next scheduled run** (`0 6 * * *`). Confirm via Sentry check-in API, not dashboard eyeballing (`hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] **AC10 — Close the incident issue** (`gh issue close <N>`) only AFTER AC8 (and AC8c if applicable) passes (the `Ref #N` → manual-close sequence for ops-remediation).

## Test Scenarios

1. **Regression test (if H1):** synthesize the probe's downstream host list and assert each is covered by `cron-egress-allowlist.txt` static entries OR the dynamic-env-resolved host set. (Test fixtures synthesized only — `cq-test-fixtures-synthesized-only`.)
2. **Regression test (if H3):** parse `tunnel.tf` and assert the ingress rule set routes `/api/*` (or catch-all) to the container.
3. **Regression test (if H5):** assert `email-on-received` ∈ the function registry / `EXPECTED_CRON_FUNCTIONS` parity set.
4. **End-to-end (post-merge):** manual-trigger probe → assert `mail_class='probe'` row within 15m (the existing probe IS this test; the AC is that it goes green).

## Observability

```yaml
liveness_signal:
  what: cron-email-ingress-probe Sentry Crons monitor (daily 06:00 UTC + manual-trigger)
  cadence: daily; on-demand via /soleur:trigger-cron
  alert_target: Sentry Crons monitor cron-email-ingress-probe (RED on missed/error)
  configured_in: apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts:62,274-289
error_reporting:
  destination: Sentry (sentry-correlation middleware Layer 1 captures the terminal throw with the assert-probe-row breadcrumb); egress drops surface via cron-egress-resolve.sh sentry_event op=egress_blocked
  fail_loud: true (retries:0 pinned so a late row cannot convert a failed assert into a retry-then-green)
failure_modes:
  - {mode: Supabase data-plane egress dropped (H1), detection: egress-blocked Sentry event sample IP→Supabase; probe assert error, alert_route: cron-egress-resolve Sentry event + cron-email-ingress-probe monitor}
  - {mode: Resend webhook disabled / MX drift (H2), detection: Resend delivery log non-2xx + probe assert error with send-step success, alert_route: cron-email-ingress-probe monitor error}
  - {mode: tunnel ingress / cert regression (H3), detection: curl app.soleur.ai/api/webhooks/resend-inbound returns tunnel 502/404, alert_route: cron-email-ingress-probe monitor}
  - {mode: webhook secret unset / dedup poison (H4), detection: route Sentry op=secret/op=signature events, alert_route: Sentry issue}
  - {mode: Inngest function desync (H5), detection: probe send-step ok + multiple Inngest functions stalled, alert_route: cron-email-ingress-probe monitor missed}
logs:
  where: Sentry (probe assert + egress events); Better Stack (Vector journald, host-scoped); cron-egress-resolve OK log line on host
  retention: Sentry default; Better Stack per plan
discoverability_test:
  command: "curl -s -H 'Authorization: Bearer $SENTRY_API_TOKEN' 'https://sentry.io/api/0/organizations/$SENTRY_ORG/monitors/cron-email-ingress-probe/checkins/?per_page=15' | jq -r '.[] | \"\\(.dateCreated) status=\\(.status)\"'"
  expected_output: a green (status=ok) check-in within 15m of a manual-trigger fire; no ssh
```

## Infrastructure (IaC)

This plan MAY touch infra (egress allowlist, DNS, tunnel) depending on the confirmed hypothesis. All confirmed-infra fixes route through the existing Terraform/auto-apply path — **no SSH, no manual provisioning** (`hr-all-infrastructure-provisioning-servers`).

### Terraform changes
- `apps/web-platform/infra/cron-egress-allowlist.txt` (H1) — folded into `terraform_data.cron_egress_firewall.triggers_replace` via file hash; a merged edit auto-applies.
- `apps/web-platform/infra/dns.tf` (H2) — MX record correction (additive to apex Proton MX; never touches `soleur.ai` apex).
- `apps/web-platform/infra/tunnel.tf` (H3) — Cloudflare tunnel ingress rule restore.
- Required vars / state: drift-remediation invocation against `apps/web-platform/infra/` uses the canonical triplet (AWS R2 backend creds raw-exported, `terraform init -input=false`, `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan/apply`). But the **default apply path here is auto-apply-on-merge** (`apply-web-platform-infra.yml`), not a manual runbook.

### Apply path
Cloud-init + auto-apply-on-merge (the egress firewall + DNS + tunnel all re-apply via `apply-web-platform-infra.yml`'s push-to-main trigger). Expected blast radius: none beyond restoring the dropped host/rule. If a manual `terraform apply` is ever needed, re-run `terraform plan` against live state immediately before (drift snapshots go stale).

### Distinctness / drift safeguards
`dev != prd` (distinct Supabase projects, `hr-dev-prd-distinct-supabase-projects`). The egress allowlist + grace-window store live on the prod host's `StateDirectory` (not tmpfs); a reboot does not wipe the pool.

### Vendor-tier reality check
Resend Pro tier already provisioned (expense recorded #5xxx, 2026-06-16). Cloudflare tunnel / Supabase: no free-tier resource-creation gate relevant here.

## Architecture Decision (ADR/C4)

**Skip — no architectural decision.** This is a bug fix on the existing ADR-055 (Resend inbound) + ADR-052 (egress firewall) + ADR-030 (self-hosted Inngest) surfaces. A competent engineer reading the existing ADRs is not misled by this fix. If the diagnosis reveals the egress firewall's dynamic-host coverage was an *unstated* invariant (data-plane vs management host), amend ADR-052's `## Consequences` with a one-line note rather than a new ADR — but only if a genuine decision gap is found.

## Domain Review

**Domains relevant:** Engineering (infra/observability), Product (operator-inbox brand-survival), Legal/Compliance (statutory-deadline backstop depends on this chain).

### Engineering (CTO)
**Status:** carry-forward from research. **Assessment:** the break is a multi-hop chain failure; the egress-firewall is one candidate but the post-fix probe failure proves it is not the *whole* story. The plan correctly forces live L3→L7 diagnosis over code-reading. Inngest self-hosted topology rules out the cloud-egress hypothesis. Primary risk: pinning H1 prematurely and shipping an allowlist edit that doesn't fix an ingress-side cause.

### Product/UX Gate
**Tier:** none — no UI surface created or edited (infra/server/runbook only). No file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`. Skip.

### Legal / Compliance
**Status:** relevant. **Assessment:** the dead chain means statutory-deadline emails are untracked — a compliance exposure for a compliance-adjacent product. GDPR gate (Phase 2.7) ran — **CLEAN, no Critical findings**: the diagnosis touches `email_triage_items` (regulated-data surface) but is **read-only** on prod, introduces no new schema column / FK / vendor / processing activity, and restores an existing pipeline whose lawful-basis / retention (`purge_email_triage_items()`) / Art. 17 anonymisation machinery is already in place. Two advisory (Important) notes: (1) **Art. 5(1)(e) retention is NOT starved by the break** — the `retention-purge` step runs FIRST in the probe cron (`cron-email-ingress-probe.ts:131-140`), independent of broken ingress; the diagnosis must not regress that ordering. (2) **Chapter V** — the summariser calls Anthropic under the existing DPA, but the probe path short-circuits before the LLM, so verification transits no real PII; diagnosis writes no synthetic PII to prod (`hr-dev-prd-distinct-supabase-projects`).

## Deferred Items

- **Incident issue:** #5467 (work target; PR uses `Ref #5467`, closed post-merge after AC8 green).
- **Cron run-log observability gap** (heavy claude-spawning crons not writing `routine_runs` rows): OUT of scope per the feature description. Filed **#5469** (`domain/engineering` + `priority/p2-medium`). Re-evaluation criterion: after the inbound fix ships and the durable run-log (`routine_runs`, deployed 2026-06-16) accumulates ≥14 days of data.
- **HOP F summarizer-tail defect** (discovered during diagnosis — non-probe inbound mail leaves `mail_class`/`summary` NULL): filed **#5468** (`type/bug` + `priority/p2-medium`). Separate subsystem; masked while the chain is dead.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **Do NOT run any integration/e2e suite that writes synthetic `auth.users` / conversation / billing rows against PROD** during diagnosis (`hr-dev-prd-distinct-supabase-projects`). Diagnosis is read-only: Sentry check-in API, `nft list set` read, `dig`/`curl` probes, Resend GET endpoints, read-only Supabase queries. The ONLY sanctioned prod write is the probe's own synthetic `mail_class='probe'` marker (designed for exactly this).
- The probe failure at 06-17 06:15 is an `error` check-in (it fired, sent, and the assert failed), NOT `missed`. Do not misread it as an Inngest scheduler desync — the send step succeeded, so the break is downstream of the send (HOP C/E or the inbound-side HOP A/B that prevents the marker arriving back).
- `api.supabase.com` in the allowlist is the **Management API**, not the data-plane `<ref>.supabase.co` the route dials. Confirming `api.supabase.com` is present proves nothing about the data-plane host's coverage.
- Firewall is **egress-only**. If the diagnosis shows the inbound svix POST never reached the route (Resend delivery log non-2xx, no route Sentry events at all), the firewall is NOT the cause — pivot to H2/H3 (MX/webhook/tunnel) and do not edit the allowlist.
