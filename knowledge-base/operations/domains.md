---
last_updated: 2026-08-20
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

## Addendum — 2026-08-20 (#7640): how the conflict is actually resolved

This section **supersedes the framing** of *"How the conflict is currently resolved"* in
`## Apex TLS: the proxy/certificate conflict (2026-08-16)` above. That section is left intact
because it is an accurate record of the state between 2026-08-16 and the cutover; what it does
not say is that `ssl = "full"` is a **mitigation, not the resolution**.

**The resolution is architectural: the docs site moves off GitHub Pages onto Cloudflare Pages**
([ADR-194](../engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md),
accepted 2026-08-20; implemented under #7640, plan at
`knowledge-base/project/plans/2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`).
Cloudflare serves the site, so **there is no origin leg and no origin certificate**. The conflict
this page records does not get managed better — it stops existing. The two requirements that were
in direct conflict are both satisfied afterwards: apex and www stay `proxied = true` for the HSTS
preload commitment, and no certificate has to be issued to a proxied origin, because nothing is
behind the proxy.

**What is still true, and stays true through this change:**

- The `## HSTS Preload Commitment` mandate is unchanged. Both hosts remain `proxied = true`;
  Universal SSL's one-label wildcard `*.soleur.ai` covers www.
- Rule 10 of `cloudflare_ruleset.seo_page_redirects` — **including its ACME carve-out clause** —
  is **not** retired by the migration. `## Always Use HTTPS exception (2026-05-18)` above stands
  verbatim, as does `always_use_https = "off"`. Retiring the carve-out was expected to free a
  ruleset slot; it does not, because the carve-out is a clause of Rule 10 rather than a rule of
  its own, so nothing about the 10-rule cap changes (see the ADR's `## Decision`, superseded note
  of 2026-08-20).
- `ssl = "full"` in `apps/web-platform/infra/seo-config-rules.tf` **stays in place** through the
  migration and for as long as the rollback window is open. Rollback is a DNS revert to GitHub
  Pages, whose certificate is expired by construction — under `strict` that rollback would serve
  **526**. Do not "clean up" this rule as part of the migration; its removal is on the
  deferred-cleanup issue with an explicit re-evaluation criterion.
- Cloudflare is already a sub-processor and already holds the zone. No new vendor, no new
  registrar or nameserver change, no DPA change. `## Domains` above is unaffected.

**What changes, and when — the `## DNS Records` table above describes the pre-cutover topology.**
The migration ships as three sequenced PRs; the table stays accurate until the third lands:

| Record | Today (as tabled above) | After the cutover |
|---|---|---|
| `soleur.ai` | four proxied `A` records on GitHub Pages anycast (`185.199.10[89].153`, `185.199.11[01].153`) | one proxied `CNAME` to the Cloudflare Pages project, flattened at the apex; the `MX` and `TXT` records at the apex are unaffected — CNAME flattening is what makes that legal |
| `www.soleur.ai` | proxied `CNAME` to `jikig-ai.github.io`; the `www -> apex` **301 is GitHub-Pages-owned** | proxied `CNAME` to the same Pages project, with the 301 rebuilt as a **Cloudflare Bulk Redirect** (account-level, `http_request_redirect` phase — *not* a rule in `seo_page_redirects`) running in front of the project |
| `_github-pages-challenge-jikig-ai.soleur.ai` | `TXT`, unproxied, domain verification | retained; GitHub Pages configuration is left in place but DNS-detached, because that is what makes the rollback a DNS-only revert |

`apps/web-platform/infra/dns.tf` remains the source of truth for all of it, and the cutover is a
single-hunk change to that file — deliberately, so the rollback is one revert.

**The GitHub Pages certificate-reissue routine is disarmed, not deleted.** Post-cutover it would
otherwise flip **`www` to `proxied = false`** — dropping HSTS, Rule 10's HTTPS upgrade, WAF and
bot management on a host this page mandates be proxied — and it structurally cannot restore that
flip. It is gated on the apex still being an `A` record and its daily detector cron is removed;
`gh-pages-cert-renewal.md` is retained but documents a routine that now refuses to run. See ADR-194
`## Addendum — 2026-08-20 (#7640)` §2 and AP-019's note in
[`principles-register.md`](../engineering/architecture/principles-register.md).
