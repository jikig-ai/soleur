---
last_updated: 2026-05-18
---

# Domains

| Domain | Registrar | Renewal Date | Nameservers | Notes |
|--------|-----------|--------------|-------------|-------|
| soleur.ai | Cloudflare | 2028-02-16 | ns1.cloudflare.com, ns2.cloudflare.com | Primary brand domain |

## DNS Records

**Source of truth: `apps/web-platform/infra/dns.tf` (Terraform-managed).** The table below mirrors that file for at-a-glance ops reference; edits to records MUST be made in `dns.tf` and applied via the operator runbook, not the Cloudflare dashboard.

| Type | Name | Content | Proxied | Notes |
|------|------|---------|---------|-------|
| A | soleur.ai | 185.199.108.153 | Yes | GitHub Pages |
| A | soleur.ai | 185.199.109.153 | Yes | GitHub Pages |
| A | soleur.ai | 185.199.110.153 | Yes | GitHub Pages |
| A | soleur.ai | 185.199.111.153 | Yes | GitHub Pages |
| CNAME | <www.soleur.ai> | jikig-ai.github.io | Yes | GitHub Pages |
| TXT | _github-pages-challenge-jikig-ai.soleur.ai | 8fcc2ac37a5abcac6cd2c71556053f | No | Domain verification |

## Security Configuration

| Setting | Value |
|---------|-------|
| SSL Mode | Full (Strict) |
| Always Use HTTPS | Off (zone toggle); path-aware via Rule 10 of `cloudflare_ruleset.seo_page_redirects` — see "Always Use HTTPS exception" below |
| Minimum TLS Version | 1.2 |
| HSTS | max-age=63072000; includeSubDomains; preload (source of truth: `apps/web-platform/infra/cloudflare-settings.tf` + `apps/web-platform/lib/security-headers.ts`) |
| HSTS Preload | Submitted 2026-03-20 — pending inclusion in Chromium preload list |
| DNSSEC | Enabled (pending DS propagation to .ai registry — expected active by 2026-04-12) |
| X-Content-Type-Options | nosniff |

## HSTS Preload Commitment

The domain `soleur.ai` was submitted to the [HSTS preload list](https://hstspreload.org) on 2026-03-20. This means:

- All subdomains must serve HTTPS. Creating an HTTP-only subdomain will be unreachable for browsers using the preload list.
- Removal from the list takes months (requires removing the `preload` directive from headers, submitting a removal request at hstspreload.org, and waiting for a Chromium release cycle).
- New subdomains created via Terraform must have Cloudflare proxy enabled (`proxied = true`). The zone-wide HTTPS-upgrade rule (Rule 10 of `cloudflare_ruleset.seo_page_redirects` — `expression = "(not ssl) and not ACME exception"`) covers every proxied host in the zone automatically. The zone-level `Always Use HTTPS` toggle is off (see "Always Use HTTPS exception" below).

## Always Use HTTPS exception (2026-05-18)

Cloudflare's zone-level **Always Use HTTPS** toggle is **off**. Edge-level HTTPS upgrade is instead provided by Rule 10 of `cloudflare_ruleset.seo_page_redirects` in `apps/web-platform/infra/seo-rulesets.tf` — a single redirect rule with expression `(not ssl) and not (http.host in {"soleur.ai" "www.soleur.ai"} and starts_with(http.request.uri.path, "/.well-known/acme-challenge/"))`. The negative-match clause carves out plain-HTTP `/.well-known/acme-challenge/*` requests on apex+www so an HTTP-01 challenge is not 301'd away; everything else 301s to HTTPS for every proxied host in the zone (apex, www, app, deploy). The previous zone-toggle configuration broke that path — see 2026-05-18 incident PIR.

> **⚠️ This carve-out is NECESSARY BUT NOT SUFFICIENT, and an earlier revision of this page said otherwise.** It used to read "so GitHub Pages can complete Let's Encrypt HTTP-01 renewal", which implies renewal works once the rule is in place. **It does not.** While apex+www are Cloudflare-proxied, GitHub never *orders* a certificate at all — `GET /repos/{owner}/{repo}/pages/health` returns `is_https_eligible: false` because the hostname resolves to Cloudflare rather than GitHub's anycast IPs. The challenge path being open is irrelevant if no challenge is ever issued. See **[GitHub Pages certificate renewal](../engineering/operations/runbooks/gh-pages-cert-renewal.md)** for the real mechanism and the renewal procedure. Correcting this mattered: the 2026-08-16 apex outage ran a 28-day countdown to expiry (#6691) while this page said renewal was handled.

**Why inlined into `seo_page_redirects` and not a separate ruleset:** Cloudflare allows only one user-defined ruleset per `(zone, phase)` combination (PR #3974 first attempt failed with `A similar configuration with rules already exists`). The `skip` action is also not valid on the `http_request_dynamic_redirect` phase (CF API error 20016), so the ACME bypass is expressed as a NEGATIVE match in Rule 10's expression rather than as a sibling skip rule. To fit the 10-rule Free-tier cap, `/blog/what-is-company-as-a-service/index.html` was dropped from the SEO redirects (canonical `/company-as-a-service/` is in the sitemap; Google will recrawl).

The toggle-off is codified in IaC at `apps/web-platform/infra/cloudflare-settings.tf` via `cloudflare_zone_settings_override.soleur_ai.settings.always_use_https = "off"`. If a future operator re-enables it through the dashboard, the next scheduled drift detector (`scheduled-terraform-drift.yml`) flags the drift and an apply restores the codified value. Re-enabling it would re-break the HTTP-01 challenge path — one of several preconditions for renewal, not the only one (see the warning above).

<!-- Corrected 2026-08-19: this sentence used to end "…the next ACME cert renewal
     (every ~60 days) would fail again", which asserted a renewal cadence that has
     never actually run. Let's Encrypt certificates are valid 90 days, not 60, and
     renewal has never succeeded while apex+www are proxied. -->

## Apex TLS: the proxy/certificate conflict (2026-08-16)

Two requirements on this page are in **direct conflict**, and nothing used to say so:

- The **HSTS preload commitment** above requires new hosts to be `proxied = true`.
- **GitHub Pages will not issue or renew a certificate for a proxied host** (`is_https_eligible: false`).

So the apex origin certificate expires every 90 days by construction and cannot self-heal. This is not a bug to fix in this repo; it is a property of putting GitHub Pages behind Cloudflare's proxy.

How the conflict is currently resolved:

| Leg | Certificate | Status |
|---|---|---|
| Visitor → Cloudflare | Cloudflare edge cert (Google Trust Services) | Valid, auto-renewed |
| Cloudflare → GitHub Pages | GitHub Pages cert (Let's Encrypt) | Expired; validation skipped |

A Configuration Rule scoped to `soleur.ai` + `www.soleur.ai` sets `ssl = "full"` (see `apps/web-platform/infra/seo-config-rules.tf`), so the edge accepts the expired origin cert instead of serving **HTTP 526**. `full` still encrypts the origin leg — it only skips certificate *validation*. The zone default stays `strict`, and `app.soleur.ai` is unaffected (it carries its own `flexible` rule).

This is acceptable **only** because the apex origin is a public static site: no auth, no cookies, no PII, and nothing a tampered response could escalate. Do **not** copy that rule to a host serving authenticated or user-submitted data.

**Renewal procedure — and why timing is the whole trick — is in [gh-pages-cert-renewal.md](../engineering/operations/runbooks/gh-pages-cert-renewal.md).**
