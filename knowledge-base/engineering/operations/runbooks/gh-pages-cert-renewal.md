---
title: GitHub Pages certificate renewal (apex 526)
date: 2026-08-19
owners: engineering/ops
category: infrastructure
tags: [tls, certificate, github-pages, cloudflare, acme, apex, 526]
applies_to:
  - apps/web-platform/infra/seo-config-rules.tf
  - apps/web-platform/infra/dns.tf
  - apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts
  - apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts
related_issues: [6691, 6698, 6657, 7539]
related_prs: [7584, 7620]
---

# GitHub Pages certificate renewal (apex 526)

Covers `soleur.ai` / `www.soleur.ai` — the marketing + docs site served by GitHub
Pages behind Cloudflare. **`app.soleur.ai` is a different origin (Hetzner) and is
never affected by anything on this page.**

> **Superseded 2026-08-20 (#7640) — read this before running anything below.** The
> marketing/docs site is migrating off GitHub Pages to Cloudflare Pages (ADR-194, accepted
> 2026-08-20; plan
> `knowledge-base/project/plans/2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`).
> This page is **retained deliberately**, not by oversight — a DNS-only revert to GitHub Pages
> is the migration's rollback, so the procedure has to survive. But once the apex cutover
> (PR3 of #7640) has landed, **this procedure no longer works and two of its steps are actively
> harmful**:
>
> - **The scripted path refuses to run, by design.** `cron-gh-pages-cert-reissue` is gated on the
>   live apex record type still being `A`; post-cutover it is a `CNAME`, and the routine returns a
>   non-benign terminal outcome instead of half-running. This is the correct behaviour: against a
>   CNAME apex, `listToggleRecords()` matches only the **www** record and flips *it* to
>   `proxied = false` — dropping HSTS, Rule 10's HTTPS upgrade, WAF and bot management on a host
>   `domains.md` mandates be proxied — and `restoreStateInner` then refuses to restore a subset,
>   making that de-proxying one-way. Do **not** work around the gate.
> - **Step 8 — *"After a successful renewal, remove the `ssl = "full"` rule"* — is void.**
>   `ssl = "full"` must **stay** for as long as the rollback window is open: the GitHub Pages
>   origin certificate is expired by construction, and under `strict` a rollback would serve
>   **526** — the exact outage this rule was added to end. Its removal is tracked on the #7640
>   deferred-cleanup issue, not here.
> - **The manual path cannot succeed either.** Eligibility requires the hostname to resolve to
>   GitHub's anycast IPs; post-cutover it resolves to Cloudflare Pages, and repointing it to make
>   a certificate issue *is* the rollback, not a renewal.
> - `cron-gh-pages-cert-state`'s daily `0 3 * * *` trigger is **removed** (manual-trigger arm
>   retained), so the `[cert-poll]` issue that used to instruct a reader to fire the routine no
>   longer files itself. If you arrived here from an old one, stop.
>
> **How to tell which side of the cutover you are on**, without a dashboard:
> `dig +short soleur.ai` returning the four `185.199.x` GitHub anycast addresses means pre-cutover
> and everything below applies. Anything else means the migration has landed. Current state and the
> rollback procedure are in
> `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`.

## The one thing to understand first

**GitHub Pages will not issue OR renew a certificate while the hostname is
Cloudflare-proxied.** It is not a bug, a wedge, or a support case:

```
$ gh api repos/jikig-ai/soleur/pages/health
is_https_eligible              false     <- the blocker
is_proxied                     true
is_cloudflare_ip               true
is_pointed_to_github_pages_ip  false
caa_error                      null
reason                         null
```

Because renewal needs the same eligibility as issuance, the origin cert **expires
every 90 days by construction** and cannot self-heal. Everything below follows
from that.

> **Do not open a GitHub Support ticket for this.** The 2026-08-16 incident
> concluded — wrongly — that the ACME authorization was wedged server-side and
> needed Support. It was not. `bad_authz` read back instantly after a domain
> re-add is *stale state*, not a fresh rejection.

## Symptom

`https://soleur.ai/` returns **HTTP 526** (Cloudflare "Invalid SSL certificate").

Distinguish it from its neighbours — they have different causes and different
runbooks:

| Code | Meaning | Not this runbook |
|---|---|---|
| **526** | Origin cert invalid/expired | ← you are here |
| 521 | Origin refused the connection | origin down |
| 522 | Origin timed out | origin/network |
| 502 | Cloudflare could not get a valid response | app-layer |

## Triage (60 seconds, no SSH)

```bash
# 1. Is it actually the cert, and is the app also down?
curl -sSo /dev/null -w "apex=%{http_code}\n" https://soleur.ai/
curl -sSo /dev/null -w "app=%{http_code}\n"  https://app.soleur.ai/   # expect 307

# 2. What does GitHub itself say? THIS IS THE AUTHORITATIVE READ.
gh api repos/jikig-ai/soleur/pages/health | jq '{
  apex: .domain      | {is_https_eligible, is_proxied, caa_error, reason},
  www:  .alt_domain  | {is_https_eligible, is_proxied, caa_error, reason}
}'

# 3. Cert state + expiry
gh api repos/jikig-ai/soleur/pages | jq '.https_certificate | {state, expires_at, description}'

# 4. The origin cert as actually served (bypasses Cloudflare)
echo | openssl s_client -servername soleur.ai -connect 185.199.108.153:443 2>/dev/null \
  | openssl x509 -noout -dates
```

The endpoint in step 2 intermittently returns `{}`. **Retry it** — an empty body
is a failed read, not a negative answer.

Read the result:

| `is_https_eligible` | `caa_error` | Meaning | Action |
|---|---|---|---|
| `false` | `null` | Proxied. Normal, expected state. | Renewal window (below) |
| `false` | set | Zone forbids the issuing CA | Fix CAA first — no window will help |
| `true` | `null` | Eligible; GitHub just hasn't run yet | Wait — it is on GitHub's schedule |

## Restore service NOW (if the site is down)

Already in place as of 2026-08-16 — verify before doing anything else:

```bash
curl -sS "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/rulesets/phases/http_config_settings/entrypoint" \
  -H "Authorization: Bearer $CF_API_TOKEN_RULESETS" \
  | jq '.result.rules[] | {description, expression, action_parameters}'
```

Expect a rule `(http.host in {"soleur.ai" "www.soleur.ai"})` → `{"ssl": "full"}`.
It is declared in `apps/web-platform/infra/seo-config-rules.tf`. `full` still
encrypts the origin leg; it only skips certificate *validation*, which is exactly
what `strict` was rejecting.

If it is missing, the site serves 526 until it is applied. It is in the
merge-apply `-target` allow-list, so merging the Terraform change is normally
enough — but **check that main's web-platform apply is green first** (#7539 has
had it red for extended periods; a merge-apply that fails leaves the rule
unapplied and the site down).

## Renew the certificate

### Timing is the whole trick

The renewal window requires apex+www to be **DNS-only** so GitHub can see its own
IPs. What that costs depends entirely on *when* you run it:

| When | What visitors see during the window | Cost |
|---|---|---|
| **Cert still valid (~day 60)** | GitHub Pages serves the still-valid cert directly | **Zero downtime** ✅ |
| Cert already expired | Browser TLS interstitial | Real outage ❌ |

**Run it while the current certificate is still valid.** This is the single most
important operational fact on this page. The 2026-08-16 outage was painful only
because the window was attempted *after* expiry — same mechanism, opposite user
impact.

### Procedure

1. **Snapshot the records you are about to change** so restore is unconditional:

   ```bash
   for t in A CNAME; do
     curl -sS "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=$t&per_page=100" \
       -H "Authorization: Bearer $CF_API_TOKEN_DNS_EDIT" \
     | jq -r '.result[] | select(.name=="soleur.ai" or .name=="www.soleur.ai")
              | [.id,.type,.name,.content,(.proxied|tostring)] | @tsv'
   done | tee /tmp/toggle-records.tsv
   ```

   Expect **exactly 5** rows (4 apex A + 1 www CNAME). Fewer means a failed read —
   stop, do not proceed on a partial set.

2. **Confirm the zone has no AAAA records.** Let's Encrypt prefers IPv6 and will
   not fall back from a proxied AAAA that answers with the wrong content, so one
   surviving AAAA defeats validation at any window length:

   ```bash
   curl -sS "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=AAAA" \
     -H "Authorization: Bearer $CF_API_TOKEN_DNS_EDIT" | jq '.result | length'   # expect 0
   ```

3. **Flip all 5 records to `proxied: false`** (`PATCH .../dns_records/<id>` with
   `{"proxied": false}`).

4. **Wait for GitHub to agree** — not merely for DNS to propagate. Public
   resolvers converge in well under a minute; GitHub re-evaluates on its **own
   background schedule** and is the slow half:

   ```bash
   # poll until BOTH report true — this can take far longer than DNS suggests
   gh api repos/jikig-ai/soleur/pages/health \
     | jq '{apex: .domain.is_https_eligible, www: .alt_domain.is_https_eligible}'
   ```

   Both must be `true`. The certificate covers apex **and** www as one order, so
   an ineligible `www` fails issuance behind a perfect apex.

5. **Only if the cert is genuinely stuck** (state in `bad_authz`, `errored`,
   `authorization_revoked`) toggle the Pages custom domain to force a fresh
   order. **Skip this for an ordinary renewal of a healthy cert** — toggling a
   healthy in-flight order can *manufacture* a `bad_authz`:

   ```bash
   echo '{"cname":null}'          | gh api -X PUT repos/jikig-ai/soleur/pages --input -
   sleep 60
   echo '{"cname":"soleur.ai"}'   | gh api -X PUT repos/jikig-ai/soleur/pages --input -
   ```

6. **Poll for issuance** until `state` is `approved`/`issued` with a future
   `expires_at`. Be patient — this is GitHub's background job, not an API call
   you can force.

7. **Restore `proxied: true` on all 5 records.** Do this on *every* exit path,
   including failure. Verify 5/5 succeeded; a partial restore leaves the origin
   exposed and Cloudflare's WAF bypassed.

8. **After a successful renewal, remove the `ssl = "full"` rule** from
   `seo-config-rules.tf` and re-run the guard test (it pins the rule count and
   the `TEMPORARY` marker). Retiring it at any other time re-arms the 526.

   > **VOID from the #7640 cutover — do not perform step 8.** `ssl = "full"` must stay in
   > place for as long as the ADR-194 rollback window is open: rollback repoints DNS at a
   > GitHub Pages origin whose certificate is expired by construction, and `strict` would
   > serve **526**. Its removal is tracked on the #7640 deferred-cleanup issue. See the
   > banner at the top of this page.

### The scripted path

`cron-gh-pages-cert-reissue` automates steps 1–7 and emits
`SOLEUR_CERT_REISSUE` markers to Better Stack, including
`httpsEligibleApex` / `httpsEligibleWww` / `healthCaaError` per attempt. Fire it
with `soleur:trigger-cron`:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/trigger-cron/scripts/trigger.sh" \
  --event cron/gh-pages-cert-reissue.manual-trigger
```

**Known limitations at time of writing:**

- Its DNS-only window is budgeted at ~15 minutes total, which is **too short**
  for GitHub's provisioning cadence. Expect `poll_timeout` and re-run, or do
  steps 3–7 by hand with a longer window.
- It is manual-trigger only. Proactive day-60 scheduling is **not** built.
- It requires the Inngest control plane; if `POST /api/internal/trigger-cron`
  returns 502, check for `ECONNREFUSED 10.0.1.40:8288` and see
  [inngest-server.md](./inngest-server.md).

## Detection

> **Superseded 2026-08-20 (#7640):** the daily `0 3 * * *` trigger described in this
> section was REMOVED by the ADR-194 substrate PR; `cron-gh-pages-cert-state` is
> manual-trigger-only, and its Sentry monitor carries `enabled = false`. Read the
> steps below as the pre-cutover behaviour. Fire it with
> `cron/gh-pages-cert-state.manual-trigger` via POST /api/internal/trigger-cron.

`cron-gh-pages-cert-state` ran daily at 03:00 UTC (schedule now disarmed) and:

- files/updates a `[cert-poll]` issue below **21 days** to expiry (a log), and
- **pages via Sentry** below **7 days** when the cert is wedged in a state ACME
  cannot self-heal (`SOLEUR_CERT_CRITICAL`).

The escalation tier exists because detection alone was never the problem: #6691
was filed 28 days early and commented **every single day** — "expires in 2 days",
"1 days", "0 days", "-1 days" — and the site still went down. A daily issue
comment is a log, not an alert.

## Post-incident checks

```bash
curl -sSo /dev/null -w "apex=%{http_code}\n" https://soleur.ai/          # 200
curl -sSo /dev/null -L -w "www=%{http_code} hops=%{num_redirects}\n" \
     https://www.soleur.ai/                                             # 200, 1 hop
curl -sSo /dev/null -w "app=%{http_code}\n" https://app.soleur.ai/       # 307
dig +short soleur.ai A @1.1.1.1                                          # Cloudflare IPs (re-proxied)
```

And confirm the zone default was never disturbed:

```bash
curl -sS "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/settings/ssl" \
  -H "Authorization: Bearer $CF_API_TOKEN_ZONE_SETTINGS" | jq -r .result.value   # strict
```

## History

- **2026-05-18** — Zone-level *Always Use HTTPS* 301'd the HTTP-01 challenge path.
  Fixed by the ACME carve-out in Rule 10 of `seo_page_redirects`. Necessary, but
  not sufficient, and `domains.md` recorded it as a complete fix — which is part
  of why the next failure went unescalated.
- **2026-07-19** — Cert entered `bad_authz`; #6691 filed. Two reissue attempts
  (#6698) toggled successfully but never validated.
- **2026-08-16** — Cert expired 13:53 UTC; apex served 526 for ~8h15m. Restored
  with the scoped `ssl = "full"` rule. The hand-run remediation was
  mis-diagnosed as a server-side wedge requiring GitHub Support.
- **2026-08-19** — `pages/health` finally consulted; `is_https_eligible: false`
  identified as the real and permanent blocker. Diagnosis corrected in #6698 and
  the reissue gate now reads GitHub's own verdict (#7620).
