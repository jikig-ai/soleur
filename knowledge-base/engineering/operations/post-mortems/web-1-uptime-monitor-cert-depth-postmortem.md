---
title: "web-1 per-host uptime monitor dark — Cloudflare Universal SSL wildcard depth"
date: 2026-07-06
incident_pr: 6128
incident_window: "since the per-host detector was introduced (#5933) until 2026-07-06"
recovery_at: "on the merge-triggered apply-web-platform-infra.yml run (automatic)"
suspected_change: "#5933 Item 1 — per-host uptime absence detector added with a two-level probe hostname (web-<n>.app.soleur.ai)"
brand_survival_threshold: none
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability-monitoring gap, no personal-data exposure"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

Better Stack auto-paused the uptime monitor **"soleur uptime web-1"** with a "down for too long" notice. Investigation showed the **web platform itself was healthy the entire time** (`app.soleur.ai/health` → 200); what was non-functional was the *per-host uptime monitor* for web-1. Its probe URL, `https://web-1.app.soleur.ai/health`, is a two-level subdomain that Cloudflare's free Universal SSL wildcard (`*.soleur.ai`, one label deep) cannot serve, so every HTTPS probe failed the TLS handshake at the CF edge (SSL alert 40). The monitor could never have gone green — per-host availability alerting for web-1 was effectively dark from the moment the detector was introduced.

## Status

resolved — the code fix (renaming the probe hostname to the single-label `web-1.soleur.ai`, covered by `*.soleur.ai`) is complete in PR #6128 and re-enables the monitor via the merge-triggered `terraform apply` (`paused = false` reconciles Better Stack's auto-pause in the same run).

## Symptom

Better Stack "monitor paused — down for too long" email; per-host web-1 uptime detection produced only failures and was auto-paused. No customer-facing symptom (apex + Sentry monitors stayed green because the origin was healthy).

## Incident Timeline

- **Start (latent):** since the per-host detector (#5933 Item 1) shipped with the two-level probe hostname — the monitor was never able to succeed.
- **Detected:** 2026-07-06, via Better Stack auto-pause email to the operator.
- **Recovered:** on merge + auto-apply of PR #6128 (Cloudflare record rename + monitor URL change, in-place).

## Detection (+ MTTD)

- **How detected:** Better Stack auto-pause notification (monitoring system), forwarded by the operator.
- **MTTD:** effectively the full latent window — a permanently-failing monitor surfaces only when the vendor's auto-pause threshold trips, not at the moment coverage went dark. This is the core lesson (see below).

## Root Cause(s) — 5-Whys

1. **Why did the monitor pause?** Better Stack recorded sustained failures on `https://web-1.app.soleur.ai/health`.
2. **Why did every probe fail?** The CF edge returned a TLS handshake failure — no certificate for that hostname.
3. **Why no certificate?** Cloudflare Universal SSL covers `soleur.ai` + the one-label wildcard `*.soleur.ai`; `web-1.app.soleur.ai` is two labels deep and is not covered.
4. **Why was a two-level probe hostname chosen?** The per-host detector named the probe record `${each.key}.app` (`web-<n>.app.soleur.ai`), diverging from the single-label convention every other proxied record in `dns.tf` uses.
5. **Why did it ship?** No pre-merge check verified that a new proxied HTTPS probe hostname was within Universal SSL wildcard depth; `terraform fmt`/`validate` and unit tests are blind to edge-cert coverage.

## Impact details

### Services Impacted

Per-host uptime monitoring for web-1 only. The web platform (`app.soleur.ai`) had **zero downtime**; apex reachability stayed covered by `betteruptime_monitor.soleur_apex` + four Sentry uptime monitors.

### Customer Impact (by role)

None. No user-facing surface was degraded; no data was exposed.

### Revenue Impact

None.

## Lessons Learned

### What went well

- The diagnosis correctly rejected the "web-1 is down" reading by probing the origin directly (`app.soleur.ai/health` → 200) and isolating the failure to the CF edge TLS layer before touching any host/firewall/service.

### What went wrong

- A per-host monitor shipped in a permanently-failing state and stayed dark until the vendor's auto-pause tripped — the monitoring gap was itself unmonitored.
- A proxied HTTPS probe hostname was created two labels deep, outside free Universal SSL coverage, with no gate to catch it.

### Prevention

- The fix aligns `web_host` with the single-label convention (`web-1.soleur.ai`), and the plan's Phase 3 guard grep (`\.app\.soleur\.ai/health` / `${each.key}.app`) is a cheap regression brake against re-introducing a two-level probe hostname.
- Broader learning captured in `knowledge-base/project/learnings/2026-07-06-cloudflare-universal-ssl-wildcard-depth-breaks-two-level-proxied-probe.md`: any CF-proxied HTTPS hostname must stay ≤1 label under the apex to ride free Universal SSL, or budget a paid cert.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
