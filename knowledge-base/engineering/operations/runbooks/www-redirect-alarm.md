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
| `soleur dot ai www redirect 301` | Better Stack | www stopped 301-ing to the apex. The site is UP; canonicalization is broken. | ~23 min (up to 180s to observe + 1200s confirmation) |
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

3. **Read the alarm's own state, not just the URL.** Step 1 answers "what does www
   return now"; it does not answer "is the alarm still firing, or am I chasing a
   stale page". Same selector `cutover-verify.sh` uses:

   ```bash
   curl -sS -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain -p soleur -c prd_terraform)" \
     https://uptime.betterstack.com/api/v2/monitors \
   | jq -r '.data[] | select(.attributes.pronounceable_name=="soleur dot ai www redirect 301") | .attributes | {status, last_checked_at}'
   ```

   This one DOES need a credential, unlike step 1. Note the vendor exposes the
   monitor's status but not the response code the failing check observed — recover
   that by re-running step 1, not from the API.

   **The Sentry half — `soleur-ai-www-reachability` — is a different vendor and a
   different path shape.** Two details are load-bearing, and each returns `404` on
   its own if you get it wrong — which reads exactly like "no such monitor" rather
   than "wrong URL":

   - the org slug is **`jikigai-eu`** (`doppler secrets get SENTRY_ORG -p soleur -c
     prd_terraform --plain`), not `soleur`. A wrong slug answers
     `404 {"detail":"Project does not exist"}`, which invites you to go looking for
     a missing project rather than a wrong org.
   - per-check rows live under the **project**, not the organization.
     `organizations/<org>/uptime/<id>/checks/` is a `404`, even though
     `organizations/<org>/uptime/` (the LIST) is the correct org-scoped call. The
     two sit one path segment apart and only one of them is org-scoped.

   The **host is not** one of them, and this is worth stating because it looks like
   it should be: the org is EU-resident and the sibling Better Stack call is
   region-specific. Measured 2026-09-07, `sentry.io` and `de.sentry.io` BOTH return
   `200` for the org-scoped list and the project-scoped checks path — Sentry routes
   the org either way. The examples below use plain `sentry.io` to match
   `cutover-verify.sh`, which is the in-repo caller of these same two endpoints.
   (`scripts/sentry-issue.sh` carries a comment recording that an earlier
   "de.sentry.io 404s" claim was also false, measured 2026-09-02 — this is the
   second time the host has been blamed for someone else's 404.)

   ```bash
   # 1. resolve the monitor id AND its project slug (this call IS org-scoped).
   #    --fail-with-body: without it an expired token exits 0 with a JSON error
   #    body, and jq renders that as an unhelpful blank -- indistinguishable from
   #    "no such monitor", which is the confusion this whole section exists to end.
   read -r MON PROJ < <(doppler run -p soleur -c prd_terraform --command '
     curl -sS --fail-with-body --max-time 30 \
       -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
       "https://sentry.io/api/0/organizations/jikigai-eu/uptime/"' \
     | jq -r '[.[] | select(.name=="soleur-ai-www-reachability")][0]
              | "\(.id) \(.projectSlug)"')

   # Fail loudly rather than building a URL with an empty id: `.../uptime//checks/`
   # is a 404, i.e. the exact "no such monitor" false signal again.
   [ -n "${MON:-}" ] && [ "$MON" != "null" ] || { echo "monitor not found"; return 1 2>/dev/null || exit 1; }

   # 2. read the check rows (PROJECT-scoped).
   MON="$MON" PROJ="$PROJ" doppler run -p soleur -c prd_terraform --command '
     curl -sS --fail-with-body --max-time 30 \
       -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
       "https://sentry.io/api/0/projects/jikigai-eu/$PROJ/uptime/$MON/checks/"' \
     | jq -r '.[] | "\(.timestamp[0:19])  \(.checkStatus)  http=\(.httpStatusCode)"'
   ```

   `$MON`/`$PROJ` are passed as ENVIRONMENT, not spliced into the command string —
   that string is evaluated by a shell holding the whole `prd_terraform` secret set,
   so a vendor-supplied value with a quote in it does not belong in it.

   **There is no time-window parameter on the checks endpoint.** Measured
   2026-09-07: no query, `?statsPeriod=24h`, `?statsPeriod=14d` and
   `?statsPeriod=90d` all return the same 10 rows. It is a fixed rolling
   collection, which is why `cutover-verify.sh` bounds it CLIENT-side with
   `CUTOVER_SINCE` in jq rather than asking the API to. Do not add a
   `statsPeriod=` and believe you are reading a window.

   Unlike Better Stack, Sentry DOES expose the observed status code per check —
   and it is the code of the **first hop**, while the assertion is graded against
   the **terminal** response. That distinction is the whole of #7798: rows reading
   `failure ... http=301` are not a contradiction, they are a `301` first hop whose
   followed terminal `200` failed an `equals 301` assertion. If you ever see that
   shape again, the assertion is wrong, not the redirect.

   To LOOK UP the alarm issue by short-id (a GET; this does not close anything):

   ```bash
   doppler run -p soleur -c prd_terraform --command '
     curl -sS --fail-with-body --max-time 30 \
       -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
       "https://sentry.io/api/0/organizations/jikigai-eu/shortids/WEB-PLATFORM-11/"' \
     | jq -r '.group | "\(.shortId) status=\(.status) lastSeen=\(.lastSeen)"'
   ```

   Closing it is a different call — `PUT {"status":"resolved"}` on the issues
   endpoint — and `scripts/sentry-issue.sh` already wraps that; prefer it over
   hand-rolling the write.

4. **A deploy in the last ~25 minutes is the most likely benign cause.** During a
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

1. **Read the scheduled drift run — do not plan by hand.**

   ```bash
   gh run list --workflow=scheduled-terraform-drift.yml -L 3
   gh run view <run-id> --log | grep -A5 'cloudflare_list.www_canonical\|cloudflare_ruleset.bulk_redirects'
   ```

   That job already plans this root on a schedule, with the credentials it needs.
   A local plan is deliberately NOT offered here: the root has an R2 backend and
   reads ~12 `TF_VAR_*` from Doppler, so it is a credentialed operation, and
   `hr-no-ssh-fallback-in-runbooks` / the no-human-infra-steps gate both say the
   answer comes from CI. If the scheduled run is stale, dispatch it rather than
   reproducing it locally:

   ```bash
   gh workflow run scheduled-terraform-drift.yml
   ```

2. If there is drift, apply it — merge to `main` and let
   `apply-web-platform-infra.yml` converge. Do not hand-apply.
3. If there is **no** drift and www still does not 301, something outside this root
   is overriding it. Do NOT go and look in the dashboard — pull the live rulesets
   instead (`hr-no-dashboard-eyeball-pull-data-yourself`). The read-only,
   GET-only entrypoint audit already exists and covers the exact phase that carries
   the www 301 (`accounts/<acct>/rulesets/phases/http_request_redirect/entrypoint`):

   ```bash
   gh workflow run apply-web-platform-infra.yml -f apply_target=entrypoint-audit
   ```

   See `knowledge-base/engineering/operations/runbooks/cloudflare-whole-list-entrypoint-audit.md`.

   Any finding here belongs on [#7883](https://github.com/jikig-ai/soleur/issues/7883).
   That issue's re-evaluation trigger is evidence of a Cloudflare-side change reaching
   production out-of-band, which is exactly what this step surfaces.

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
