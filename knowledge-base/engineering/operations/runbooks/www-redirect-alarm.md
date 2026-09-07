---
title: The www→apex 301 alarm fired
date: 2026-09-07
owners: engineering/ops
category: infrastructure
tags: [uptime, redirect, www, canonical, better-stack, sentry, cloudflare, 301]
applies_to:
  - apps/web-platform/infra/uptime-alerts.tf
  - apps/web-platform/infra/sentry/uptime-monitors.tf
  - apps/web-platform/infra/seo-bulk-redirects.tf
  - apps/web-platform/infra/cutover-verify.sh
related_issues: [7798]
---

# Runbook: the www→apex 301 alarm fired

**TL;DR:** run `bash apps/web-platform/infra/cutover-verify.sh --check-www-redirect`.
It needs no credentials. If it prints `CUT3 PASS`, the alarm is stale and will
clear itself; if it prints `FAIL`, the Cloudflare Bulk Redirect stopped firing —
go to [Diagnose](#diagnose).

## First: which alarm is this?

Two monitors watch `www.soleur.ai` and they mean different things. Read the
subject line before anything else — they are the only thing that distinguishes
them in an inbox.

| Alert name | Vendor | Means | Time to page |
|---|---|---|---|
| `soleur dot ai www redirect 301` | Better Stack | www stopped 301-ing to the apex. The site is UP; canonicalization is broken. | ~20 min (180s cadence, 1200s confirmation) |
| `soleur-ai-www-reachability` | Sentry | www is unreachable, TLS-broken, or 5xx. | ~15 min (300s interval, 3 failures) |

They are independent. Both firing at once means www is down; only the first
firing means www is serving something, just not a redirect.

## What is actually being asserted

`betteruptime_monitor.soleur_www_redirect` (`uptime-alerts.tf`) requests
`https://www.soleur.ai/` and requires HTTP **exactly 301**, with
`follow_redirects = false` so the pre-redirect response is what gets graded.

That last part is the whole point, and it is why this monitor is on Better Stack
rather than beside its four siblings in Sentry. Sentry's uptime checker always
follows 3xx and evaluates assertions against the *final* response, so on this URL
it grades the apex's 200 — an `equals 301` assertion there is unsatisfiable. It
was configured exactly that way from 2026-05-29 to 2026-09-07 and failed 100% of
its checks (#7798, ADR-204).

## Diagnose

1. **Reproduce.** `bash apps/web-platform/infra/cutover-verify.sh --check-www-redirect`

   This is the same assertion the monitor makes, run from your machine against
   the public URL. It reads no token and exits before any credentialed path.

2. **Read what came back.** The bare `curl` is
   `curl -sSI https://www.soleur.ai/`, and the three outcomes are distinct:

   | Observed | Meaning |
   |---|---|
   | `301` + `location: https://soleur.ai/` | Healthy. The alarm is stale or was a transient. |
   | `200` | **The Bulk Redirect stopped firing.** www is serving the site directly — duplicate content, and the canonical signal splits. |
   | `302` / `307` / `308` | Something re-created the redirect with the wrong status. Search engines treat these differently from a 301. |
   | `522` / `526` / timeout | Not a redirect problem. This is a reachability failure; `soleur-ai-www-reachability` should be firing too. |

3. **A deploy in the last ~20 minutes is the most likely benign cause.** During a
   Cloudflare Pages rebuild, www transiently serves its own 200 (~15 min
   observed). `confirmation_period = 1200` exists to absorb exactly that, so a
   page during a rebuild means the window was exceeded, not that the window is
   wrong. Check `gh run list --workflow=deploy-docs.yml -L 3` before changing
   anything.

## Where the redirect is declared

The 301 is an **account-level Cloudflare Bulk Redirect**, not a DNS record and
not a Pages setting:

- `apps/web-platform/infra/seo-bulk-redirects.tf` —
  `cloudflare_list.www_canonical` holds the `www.soleur.ai/` item, and the second
  `rules {}` block in `cloudflare_ruleset.bulk_redirects` is what binds it. A list
  nothing binds is inert.
- Rule ORDER matters: that rule is declared after `legal_redirects`, and rules
  evaluate first-match-wins. A reordering silently changes which redirect wins for
  the ten legacy `/pages/legal/<slug>.html` paths, which match both lists on the
  www host.
- `apps/web-platform/infra/dns.tf` — www stays a **proxied CNAME at the Pages
  project** (Camp B; CTO ruling). Cloudflare's own recipe parks www at a black-hole
  IP instead; the divergence is deliberate, and it is why a failed redirect
  degrades to "serves the site" rather than a 522 on an HSTS-preloaded host.

## Fix

The declared config is guarded at PR time by
`apps/web-platform/infra/www-apex-canonicalizer.test.sh`, so a merged regression
in the Terraform is unlikely — the usual cause is a change made **outside**
Terraform (a dashboard edit, or an account-level Bulk Redirect touched by hand).

1. `cd apps/web-platform/infra && terraform plan` and look for drift on
   `cloudflare_list.www_canonical` or `cloudflare_ruleset.bulk_redirects`.
2. If there is drift, apply it — merge to `main` and let
   `apply-web-platform-infra.yml` converge. Do not hand-apply.
3. If there is **no** drift and www still does not 301, the redirect is being
   overridden by something not in this root. Check for a Page Rule or a
   Configuration Rule added via the dashboard, and record what you find on #7798's
   successor — a Cloudflare-side change reaching production without a Terraform
   apply is the named re-evaluation trigger for building a runtime target
   assertion (ADR-204, Residual Gap).

## What this alarm does NOT cover

It matches the **status code only**. "www 301s, but to the wrong host" and "the
301 is served by a stale origin" are invisible to it, and to every uptime vendor —
neither Better Stack nor Sentry can assert the redirect's target.

Those are covered at PR time by `www-apex-canonicalizer.test.sh` (source and
target hosts, `status_code = 301`), and on demand by `cutover-verify.sh` CUT3/CUT4,
which additionally reject a correct 301 that still carries a GitHub/Fastly origin
marker. Reaching that state requires a change made outside Terraform. See ADR-204.

## Related

- [ADR-204](../../architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md)
- [ADR-194](../../architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md) — the Pages cutover that made www a Pages custom domain
- Issue [#7798](https://github.com/jikig-ai/soleur/issues/7798)
