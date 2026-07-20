---
title: "Cloudflare Universal SSL wildcard depth breaks two-level proxied probe hostnames"
date: 2026-07-06
category: integration-issues
module: apps/web-platform/infra
tags: [cloudflare, universal-ssl, tls, betterstack, uptime-monitor, dns, terraform]
---

# Learning: Cloudflare Universal SSL wildcard is one label deep — a two-level proxied hostname has no edge cert

## Problem

Better Stack auto-paused the uptime monitor **"soleur uptime web-1"** with "down for
too long". The knee-jerk read is "the web-1 host is down" — but the host was healthy the
whole time.

The monitor (`betteruptime_monitor.web_host`) probed `https://web-1.app.soleur.ai/health`
with `verify_ssl = true`. Its CF-proxied DNS record (`cloudflare_record.web_host`) was
named `${each.key}.app` → `web-1.app.soleur.ai` — a **two-level** subdomain.

Live evidence that isolated the layer:
- `curl https://app.soleur.ai/health` → **200** (app is up).
- `curl https://web-1.app.soleur.ai/health` → **HTTP 000**, and `openssl s_client` showed
  `TLS alert, handshake failure (SSL alert 40)` at the Cloudflare **edge** — the request
  never reached the origin.
- `openssl s_client -connect app.soleur.ai:443` → edge cert SAN = `soleur.ai, *.soleur.ai`.

## Root cause

Cloudflare **Universal SSL** (the free tier cert) covers only the apex and a **one-label**
wildcard: `soleur.ai` + `*.soleur.ai`. A DNS wildcard matches **exactly one** subdomain
label, so `*.soleur.ai` covers `app.soleur.ai` and `web-1.soleur.ai` but **NOT** the
two-level `web-1.app.soleur.ai`. With no edge certificate for that hostname, every proxied
HTTPS request fails the TLS handshake at the edge. The monitor recorded sustained failures
and Better Stack auto-paused it. **It could never have gone green** with that URL.

Covering a two-level hostname requires a paid **Advanced Certificate Manager / Total TLS**
cert (~$10/mo) — none exists in the repo.

## Solution

Rename the probe hostname **down one label** to `web-1.soleur.ai`, which the existing free
`*.soleur.ai` wildcard already covers:

- `dns.tf` — `cloudflare_record.web_host`: `name = each.key` (was `"${each.key}.app"`).
- `uptime-alerts.tf` — `betteruptime_monitor.web_host`: `url = "https://${each.key}.soleur.ai/health"`.

The `betteruptime_monitor.web_host.url` change is in-place, but **the `cloudflare_record.name`
change is NOT** — the Cloudflare provider treats `name` as **ForceNew**, so renaming the record
**destroys and recreates it** (`# forces replacement` in the plan). That trips the
`apply-web-platform-infra` destroy-guard, which halts the auto-apply unless the merge commit
contains a line `[ack-destroy]`. The replacement is safe (it is the monitoring *probe* record,
not the app ingress `cloudflare_record.app`, and carries no user traffic) — but the merge commit
MUST acknowledge it. This was the miss on PR #6128: the plan predicted an "in-place UPDATE", the
apply was blocked, and a follow-up PR carrying `[ack-destroy]` was needed to land it. Lesson: any
`cloudflare_record` attribute change that the provider marks ForceNew (name, type, zone) is a
destroy, and an infra PR that renames one must ship `[ack-destroy]` in its PR body.

`paused = false` is unchanged, so the (acknowledged) `terraform apply` reconciles Better Stack's auto-pause and
re-enables the monitor in the same run. The record stays `proxied = true`, preserving the
CF-IP-only origin firewall.

## Resolution superseded — the per-host probe was the wrong tool

Fixing the cert depth (single-label rename) got the TLS handshake to succeed, but the probe
then returned **CF 521**: `web-1.soleur.ai` and `app.soleur.ai` share one origin IP, and the
origin's web server accepts the `app.soleur.ai` Host but **closes the connection for the
`web-1.soleur.ai` Host/SNI**. So the per-host probe was *doubly* broken — the cert bug masked an
origin-vhost gap. Making the per-host probe green would require every host's origin to serve its
own `web-<n>.soleur.ai` vhost/cert.

The operator's call (correct): **retire the per-host external HTTP probe entirely and monitor
`app.soleur.ai` instead.** For an LB-fronted multi-host cluster, "is a specific host dead" is the
job of the load balancer's origin health checks + host-level metric emails (`resource-monitor.sh`
→ ops@), NOT an external per-host HTTP monitor that has to be told every host's hostname and
needs per-host origin vhosts. Removed `betteruptime_monitor.web_host` + `cloudflare_record.web_host`
+ the dead `monitored` flag; added `betteruptime_monitor.app` probing `https://app.soleur.ai/`
(307→/login→200, `follow_redirects = true`). **Broader lesson: before fixing a monitor's probe
URL, ask whether the monitor's *target layer* is right at all — an external HTTP probe of a
specific backend host is usually the wrong altitude when a load balancer fronts the pool.**

## Key Insight

**A paused/red uptime monitor is not proof the target is down — verify the probe URL is
certificate-servable first.** For any CF-proxied HTTPS hostname, the subdomain depth must be
≤ 1 label under the apex to ride free Universal SSL. Every other proxied record in `dns.tf`
(`app`, `deploy`, `ssh`, `www`) is single-label for exactly this reason; the two-level
`web-<n>.app` was the sole outlier. When adding a proxied probe/serving hostname, keep it
single-label or budget for ACM/Total TLS.

Diagnostic shortcut: `openssl s_client -connect <apex>:443` prints the edge cert SAN — if the
hostname you're probing isn't matched by a SAN entry (remember wildcards are one label deep),
the handshake fails at the edge before any origin/firewall/service layer is even reached.

## Session Errors

1. **Fabricated a GitHub issue reference (`#6127`).** The work trigger was a Better Stack
   email, not a filed issue, but the commit message and both `.tf` comments cited `#6127` —
   which is an unrelated open PR. **Recovery:** a `gh issue view 6127` / `gh pr view 6127`
   existence check before marking the PR ready surfaced the mismatch; removed via edits +
   `git commit --amend`. **Prevention:** when the work trigger is a non-GitHub source
   (email, alert, dashboard), never synthesize a `#N` reference — describe the incident in
   prose ("Better Stack auto-pause incident") or file a real tracking issue and cite that.
   A fabricated `#N` silently mis-links the git history to unrelated work.
2. **`grep -c '${each.key}.soleur.ai/health'` returned 0** (false negative) because BRE
   treats the leading `$` oddly and the pattern didn't match as intended. **Recovery:**
   re-ran with `grep -F` (fixed-string). One-off; note for future AC-grep authoring: use
   `grep -F` when the pattern contains `${...}` / regex metacharacters you mean literally.
