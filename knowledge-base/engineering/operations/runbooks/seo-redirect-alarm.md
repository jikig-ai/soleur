---
title: A sampled SEO 301 redirect alarm fired
date: 2026-09-20
owners: engineering/ops
category: infrastructure
tags: [uptime, redirect, seo, better-stack, cloudflare, 301, bulk-redirects]
applies_to:
  - apps/web-platform/infra/uptime-alerts.tf
  - apps/web-platform/infra/seo-bulk-redirects.tf
  - apps/web-platform/infra/seo-rulesets.tf
related_issues: [8364, 7798, 7883]
---

# Runbook: a sampled SEO 301 redirect alarm fired

**TL;DR:** re-run the probe's assertion by hand —
`curl -s -o /dev/null --max-time 15 -w '%{http_code} %{redirect_url}' <probe-url>`.
If it prints `301`, the alarm is stale or was a transient; if it prints anything
else, the edge redirect for that class stopped firing — go to
[Diagnose](#diagnose).

## First: which alarm is this?

Three Better Stack monitors, one per independent edge-redirect mechanism
(#8364). The subject line is the `pronounceable_name` — it is the only thing
that distinguishes them in an inbox:

| Alert name | Resource | Probes | Means |
|---|---|---|---|
| `soleur pages agents redirect 301` | `betteruptime_monitor.seo_redirect_zone_ruleset` | `https://soleur.ai/pages/agents.html` | A `rules {}` block was lost from `cloudflare_ruleset.seo_page_redirects` (or the whole ruleset stopped applying). |
| `soleur legal privacy redirect 301` | `betteruptime_monitor.seo_redirect_bulk_item` | `https://soleur.ai/pages/legal/privacy-policy.html` | An explicit `item` vanished from `cloudflare_list.legal_redirects`, or the list/ruleset binding broke. |
| `soleur blog dated slug redirect 301` | `betteruptime_monitor.seo_redirect_blog_pair` | `https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/` | The generated `local.blog_redirect_pairs` expansion stopped producing list items end-to-end. |

They are **samples**, not coverage: three is the smallest set that separates
the three failure mechanisms. A red probe means that *class* of edge redirect
is suspect — other URLs on the same mechanism are likely affected too. It says
nothing by itself about the other two classes.

These are related to but distinct from `soleur dot ai www redirect 301`
(the www→apex canonicalizer alarm — runbook
[www-redirect-alarm.md](./www-redirect-alarm.md)): that one watches a
host-canonicalization redirect, these watch legacy-URL SEO redirects.

## What is actually being asserted

Each monitor requests its URL and requires HTTP **exactly 301**, with
`follow_redirects = false` so the pre-redirect response is what gets graded.
That is why they live on Better Stack: Sentry's uptime checker always follows
3xx and grades the *terminal* response, so `equals 301` is structurally
unsatisfiable there (#7798, ADR-204). `expected_status_codes = [301]` is exact
on purpose — a 302/307/308 is a different canonicalization contract to search
engines, and a 200 means the legacy URL is serving content again.

## Diagnose

1. **Reproduce** — the same assertion the monitor makes, from your machine:

   ```bash
   curl -sSI --max-time 15 <probe-url>   # e.g. https://soleur.ai/pages/agents.html
   ```

   | Observed | Meaning |
   |---|---|
   | `301` + `location:` to the documented target | Healthy. The alarm is stale or a transient. |
   | `200` | The edge redirect stopped firing and the origin is serving the URL (or a stale build is). |
   | `404` | The redirect is gone AND nothing serves the URL — the failure mode this alarm exists to catch. |
   | `302` / `307` / `308` | Something re-created the redirect with the wrong status code. |
   | `5xx` / timeout | Not a redirect problem — a reachability failure; expect the reachability monitors to fire too. |

2. **Read the alarm's own state, not just the URL.** This one needs a
   credential, unlike step 1. Same selector shape as the www-redirect runbook:

   ```bash
   curl -sS -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain -p soleur -c prd_terraform)" \
     https://uptime.betterstack.com/api/v2/monitors \
   | jq -r '.data[] | select(.attributes.pronounceable_name=="soleur pages agents redirect 301") | .attributes | {status, last_checked_at}'
   ```

   The vendor exposes the monitor's status but not the response code the
   failing check observed — recover that by re-running step 1.

   To read several recent check outcomes through the same credential path as CI:

   ```bash
   doppler run -p soleur -c prd_terraform --command '
     curl -sS --fail-with-body --max-time 30 \
       -H "Authorization: Bearer $BETTERSTACK_API_TOKEN_READONLY" \
       "https://uptime.betterstack.com/api/v2/monitors"' \
     | jq -r '.data[] | select(.attributes.pronounceable_name | test("redirect 301")) | .attributes | "\(.pronounceable_name)  \(.status)  \(.last_checked_at)"'
   ```

3. **A deploy or infra apply in the last ~25 minutes is the most likely benign
   cause.** `confirmation_period = 1200` absorbs transient windows (the same
   bound as the www monitor — a Pages rebuild can serve stale content past the
   15-minute mark). Check `gh run list --workflow=apply-web-platform-infra.yml
   -L 3` and `gh run list --workflow=deploy-docs.yml -L 3` before changing
   anything.

## Where the redirect is declared

- `apps/web-platform/infra/seo-rulesets.tf` —
  `cloudflare_ruleset.seo_page_redirects` (zone `http_request_dynamic_redirect`
  phase) carries the `/pages/<slug>.html` rules, including
  `seo_redirect_zone_ruleset`'s probe URL.
- `apps/web-platform/infra/seo-bulk-redirects.tf` —
  `cloudflare_list.legal_redirects` carries the explicit `source_url` items
  (including `seo_redirect_bulk_item`'s probe URL) and the `dynamic "item"`
  block expanding `local.blog_redirect_pairs` (which generates
  `seo_redirect_blog_pair`'s probe URL among its three shapes). The first
  `rules {}` block of `cloudflare_ruleset.bulk_redirects` binds the list — a
  list nothing binds is inert.
- Rule ordering in `bulk_redirects` is load-bearing (legal before
  `www_canonical`, first-match-wins) — see `www-apex-canonicalizer.test.sh`.

## Fix

The declared config is guarded at PR time, so a merged regression in the
Terraform is unlikely — the usual cause is a change made **outside** Terraform
(a dashboard edit, an emptied list, a token-scope loss).

1. **Read the scheduled drift run — do not plan by hand.**

   ```bash
   gh run list --workflow=scheduled-terraform-drift.yml -L 3
   gh run view <run-id> --log | grep -A5 'cloudflare_list.legal_redirects\|cloudflare_ruleset.seo_page_redirects\|cloudflare_ruleset.bulk_redirects'
   ```

   If the scheduled run is stale, dispatch it:

   ```bash
   gh workflow run scheduled-terraform-drift.yml
   ```

   A local plan is deliberately NOT offered: the root has an R2 backend and
   reads ~12 `TF_VAR_*` from Doppler — credentialed, and the answer comes from
   CI (`hr-no-ssh-fallback-in-runbooks`).

2. If there is drift, apply it — merge to `main` and let
   `apply-web-platform-infra.yml` converge. Do not hand-apply.
3. If there is **no** drift and the URL still does not 301, something outside
   this root is overriding it. Do NOT eyeball the dashboard — pull the live
   rulesets instead (`hr-no-dashboard-eyeball-pull-data-yourself`). The
   read-only, GET-only entrypoint audit covers both phases that carry these
   301s (`http_request_dynamic_redirect` and `http_request_redirect`):

   ```bash
   gh workflow run apply-web-platform-infra.yml -f apply_target=entrypoint-audit
   ```

   See `knowledge-base/engineering/operations/runbooks/cloudflare-whole-list-entrypoint-audit.md`.

   Any finding here belongs on
   [#7883](https://github.com/jikig-ai/soleur/issues/7883): these probes are the
   "a Cloudflare-side change reached prod un-applied" detection that issue's
   re-evaluation was gated on.

## What these alarms do NOT cover

They match the **status code only**. "The URL 301s, but to the wrong target" is
invisible to them — no uptime vendor can assert the `Location` target
(`expected_status_code` has no header assertion). That is #7883, still open.

They also do not cover *every* legacy URL: the three probes are a sample, one
per failure mechanism. Source-set completeness is guarded at PR time by the
drift guards and `seo-redirect-monitors.test.sh` (which pins these probes'
membership in the declared source set); runtime per-URL coverage is
deliberately rejected on unresolved free-tier quota.

## Related

- [ADR-204](../../architecture/decisions/ADR-204-redirect-health-moves-to-better-stack-because-sentry-cannot-express-it.md) — the capability grounds, and the #8364 amendment
- [www-redirect-alarm.md](./www-redirect-alarm.md) — the sibling www→apex alarm
- Issue [#8364](https://github.com/jikig-ai/soleur/issues/8364),
  [#7883](https://github.com/jikig-ai/soleur/issues/7883)
