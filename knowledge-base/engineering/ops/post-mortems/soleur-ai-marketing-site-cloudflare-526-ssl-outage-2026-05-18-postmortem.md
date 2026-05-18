---
title: "soleur.ai marketing site cloudflare 526 ssl outage 2026-05-18"
date: 2026-05-18
incident_pr: 3986
incident_window: "2026-05-18T09:36:00Z → 2026-05-18T16:55:00Z (~7h19m)"
suspected_change: "NONE introduced the regression — natural Let's Encrypt cert expiry surfaced a pre-existing latent IaC defect (zone-level 'Always Use HTTPS' force-redirect + GH-Pages CNAME-only origin). Recovery PRs: #3986 (fix-forward), #3974 (initial IaC)."
brand_survival_threshold: aggregate pattern
status: resolved
triggers: []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no Art. 33 trigger (advisory window would have been 2026-05-21T09:36:00Z)"
classification_override:
  advisory: none
  chosen: aggregate pattern
  reason: "Computed advisory was `none` because data_categories_breached=[] and risk_to_subjects=none (LE HTTP-01 nonces are RFC-8555 public-by-design; marketing site only — app.soleur.ai authenticated app on separate origin unaffected). Operator overrode to `aggregate pattern` because every visitor to soleur.ai apex+www over the 7h19m window saw a 526; concrete count unknown (no marketing analytics integration) but brand impact is aggregate. Latent IaC defect surface was cross-subdomain HTTPS-upgrade collapse — would have been single-user-incident if it had shipped past review without the prior fix; the actual outage was aggregate."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.



## Symptom

soleur.ai (apex + www) returned Cloudflare 526 ("Invalid SSL certificate at origin") to every visitor from 2026-05-18T09:36Z through 2026-05-18T16:55Z (~7h19m). app.soleur.ai (authenticated app, separate origin) was healthy throughout.

Root surface: GitHub Pages Let's Encrypt certificate for soleur.ai expired 2026-05-17. ACME HTTP-01 renewal failed (bad_authz) because the Cloudflare zone-level "Always Use HTTPS" toggle force-redirected the LE validator's plaintext-HTTP request to `/.well-known/acme-challenge/<token>` to HTTPS before GitHub Pages could serve the validator token on port 80 — breaking the RFC 8555 §8.3 HTTP-01 challenge precondition that the validator server be reachable over HTTP.

## Root-cause hypothesis

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Zone-level "Always Use HTTPS" toggle (CF dashboard, not IaC-managed) shadowed the GH-Pages HTTP-01 validator path. | CF dashboard showed `always_use_https=on` zone setting; LE staging probe to `http://soleur.ai/.well-known/acme-challenge/<probe>` returned 301→https; GH Pages domain-config UI displayed "DNS check successful but unavailable to your site" with cert-issuance error referencing HTTP redirect. | None. CF support ticket and LE staging trace concur. | Confirmed |
| Pre-existing IaC defect: redirect rule scope in `seo_page_redirects` did not carve out the `/.well-known/acme-challenge/*` path. | Initial IaC PR #3974 inherited the zone toggle without converting to a path-scoped redirect ruleset. PR #3986 replaced the zone toggle with an inline ACME-aware HTTPS-upgrade rule inside `seo_page_redirects`. | None. | Confirmed |
| Three additional latent defects caught only at recovery-apply time (see Follow-ups). | (1) CF proxy hides origin IPs from GH Pages' domain-config dig check; (2) `skip` action invalid on `http_request_dynamic_redirect` phase (CF API 20016); (3) CF allows only ONE user-defined `cloudflare_ruleset` per (zone, phase). | None — verified empirically during recovery. | Confirmed |

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-05-17 (approx) | Let's Encrypt cert for soleur.ai expires; first ACME renewal attempt fails (bad_authz). GH Pages auto-retries on its renewal schedule. |
| human | 2026-05-18T09:36:00Z | Incident detected — visitors to soleur.ai see CF 526. |
| human | 2026-05-18T09:36Z–~12:00Z | Diagnosis: confirmed expired LE cert at GH Pages origin; reproduced bad_authz via LE staging; identified zone-level "Always Use HTTPS" as the redirect culprit. |
| human | 2026-05-18T~12:00Z–~14:00Z | Authored PR #3986 (fix-forward) — inline ACME-aware HTTPS upgrade rule inside `seo_page_redirects`. Caught at apply time: `skip` action rejected on `http_request_dynamic_redirect` phase; reworked as negative-match clause in redirect expression. |
| human | 2026-05-18T~14:00Z–~16:00Z | Encountered second blocker: new `cloudflare_ruleset` for `acme_aware_https_upgrade` collided with `seo_page_redirects` (one user-defined ruleset per zone/phase). Inlined into existing ruleset. |
| human | 2026-05-18T~16:00Z–~16:30Z | Encountered third blocker: GH Pages domain-config check failed because CF proxy returned 104.x/172.x anycast IPs instead of GH's expected 185.199.108-111.153. Temporarily disabled CF proxy on the 5 records (proxied=false). |
| human | 2026-05-18T~16:55:00Z | GH Pages re-issued LE cert successfully; 526 cleared; CF proxy re-enabled. Recovery verified. |
| agent | 2026-05-18 | Recovery learning captured: `knowledge-base/project/learnings/2026-05-18-cloudflare-zone-toggle-replacement-must-cover-all-proxied-hosts.md`. Recovery issue #3976 closed. |

## Recovery verification

- PR #3986 merged and applied; `seo_page_redirects` ruleset now contains inline `(http.request.uri.path matches "^/\\.well-known/acme-challenge/")` negative-match clause so plaintext ACME validator requests reach GH Pages on port 80 unredirected.
- Live probe: `curl -I http://soleur.ai/.well-known/acme-challenge/probe-recovery` returns GH Pages 404 (not CF 301→https) — validator path reachable.
- Live probe: `curl -vI https://soleur.ai/` returns 200 with valid LE cert (issuer `R3` or successor) post-recovery.
- Recovery issue #3976 closed against PR #3986 merge SHA.

## Follow-ups

- [x] Capture session learning: CF proxy hides origin IPs from GH Pages domain-config check — `integration-issues/2026-05-18-cloudflare-proxy-hides-origin-ip-from-gh-pages-domain-check.md`
- [x] Capture session learning: `skip` action NOT valid on `http_request_dynamic_redirect` phase — `integration-issues/2026-05-18-cloudflare-dynamic-redirect-skip-action-invalid.md`
- [x] Capture session learning: CF allows only ONE user-defined `cloudflare_ruleset` per (zone, phase) — `integration-issues/2026-05-18-cloudflare-one-user-defined-ruleset-per-zone-phase.md`
- [ ] Add LE cert-expiry monitor (T-14d alert) — #4008
- [ ] Add CI guard for CF zone/ruleset PRs requiring ACME validator-path reachability — #4007
- [ ] Evaluate marketing-site migration from GH Pages to CF-native origin — #4009
- [ ] Decide on privacy-preserving marketing analytics (or accept aggregate-pattern PIR phrasing) — #4010
- [ ] Route-to-definition: `terraform-architect` Sharp Edges (3 CF gotchas) — #4004
- [ ] Route-to-definition: `infra-security` GH Pages wire recipe cert-renewal note — #4005

## Who was affected (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface:

- Prospect: AFFECTED. Every visitor to soleur.ai apex or www during the 7h19m window saw a Cloudflare 526 error page. Concrete count unknown — no marketing analytics integration. Brand-impact surface only; no credential or data exposure.
- Authenticated app user: NOT AFFECTED. app.soleur.ai runs on a separate origin with independent TLS chain; healthy throughout.
- Legal-document signer: NOT AFFECTED (signing flows run under app.soleur.ai).
- Admin via Access: NOT AFFECTED (Access protected hosts on separate origin).
- Billing customer: NOT AFFECTED (Stripe flows under app.soleur.ai).
- OAuth installation owner: NOT AFFECTED (callback hosts on separate origin).
