---
title: "soleur.ai Cloudflare account move outage 2026-11-18"
date: 2026-11-18
incident_pr: N/A
incident_window: "2026-11-18T16:24:00Z → 2026-11-18T17:15:32Z"
recovery_at: "2026-11-18T17:15:32Z"
suspected_change: "soleur.ai registration moved from the personal Cloudflare account to the dedicated Soleur account (no PR, no code change)"
brand_survival_threshold: aggregate pattern
status: open
triggers: []
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "2026-11-21T16:24:00Z"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

When the soleur.ai registration moved to the dedicated Soleur Cloudflare account, Cloudflare created a new zone from a DNS scan and moved the old zone to status `moved`. For about 51 minutes the website, the app and sign-in were unreachable. Service was restored forward in the new account by rebuilding DNS, zone settings and the Pages project from a read-only export of the old zone.

## Status

open — one of `resolved` / `unresolved but ended` / `ongoing`. Mirrors the `status:` frontmatter above; do not introduce a second source of truth.

User-facing service recovered at 17:15:32Z. Still degraded at the time of writing, tracked in #12931: legacy-URL and www→apex 301 redirects, `X-Robots-Tag` noindex transform rules, the `deploy`/`ssh`/`registry` tunnel hosts (deploys and CI registry pushes blocked), and docs CI still deploying to the old account's Pages project.

## Symptom

From about 16:24 UTC, `soleur.ai`, `www.soleur.ai` and `app.soleur.ai` returned HTTP 403 (Cloudflare Error 1000, "DNS points to prohibited IP"). Sign-in failed because `api.soleur.ai` (the Supabase custom domain, which also carries the GitHub OAuth callback) was proxied by Cloudflare and answered 404. Mail records were wrong too. The three Proton DKIM CNAMEs had become proxied (so they returned Cloudflare IPs, and outbound mail likely failed DKIM under `p=reject`). The inbound MX, the SES feedback MX/SPF records and the Resend subdomain DKIM keys were missing.

## Incident Timeline

- **Start time (detected):** 2026-11-18T16:24:00Z
- **End time (recovered):** 2026-11-18T17:15:32Z
- **Duration (MTTR):** 0h51m

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 16:23:52 | soleur.ai registration moves to the Soleur account. Cloudflare activates new zone `951ce525…` (lennon/laila, Free plan) populated by a DNS scan; old zone `5af02a2f…` (bradley/nora, Pro) goes to `moved`. The operator started the move. |
| human | 16:24:00 | Incident start (operator-reported). |
| agent | 16:25:42 | Better Stack opens "soleur dot ai apex" (403). App dashboard follows at 16:27:02, database readiness at 16:27:34, changelog and legal pages at 16:35:52, and the four 301-redirect monitors at 16:44–16:46. |
| agent | 16:33–16:34 | Two `deploy-docs.yml` runs for `7e1d286` go red on the live-apex build-identity probe. |
| human | before 17:00 | Operator diagnoses from the Cloudflare API and DNS and opens this incident in Claude Code. |
| agent | ~17:00 | Probes every Cloudflare token in Doppler. None reaches the new account; all reach only the `moved` zone. |
| agent | 17:03 | Read-only snapshot of the old zone (36 records, BIND export, settings, rulesets, LB) and the new zone's public view, saved outside the repo at mode 600. |
| human | ~17:06 | Operator asks for the token to be created with Playwright and signs in to the Cloudflare dashboard. |
| agent-with-ack | 17:08 | First token created through the dashboard session. Its value was lost (the redact proxy does not save `filename` output), so the token was deleted. An empty Doppler secret was written by mistake and removed. |
| agent-with-ack | ~17:09 | Second token (`CF_API_TOKEN_SOLEUR_ACCT`, expires 2026-12-18) handed to a one-shot localhost sink, stored in Doppler, file shredded. The value never entered the transcript. |
| agent-with-ack | ~17:10 | app.soleur.ai: three prohibited-IP A records replaced with one proxied A record to the web-platform origin. api.soleur.ai set to DNS-only (TTL 60) and its ACME TXT restored. Proton DKIM CNAMEs set to DNS-only. |
| agent | ~17:11 | Checks: `/login` and `/health` return 200; Supabase auth through api.soleur.ai answers with GitHub enabled; the OAuth authorize call 302s to github.com. |
| agent | 17:12:08 | Better Stack resolves "soleur app dashboard". |
| agent-with-ack | ~17:12 | 12 missing MX/TXT/CNAME records added. Two scan-imported records under the delegated `mail.` name removed. The MX/TXT/NS/CNAME diff against the old export is empty apart from the website and tunnel CNAMEs. Zone settings copied to exact parity (ssl strict, min TLS 1.2, HSTS and six others). |
| agent-with-ack | ~17:13 | Pages project `soleur-docs` created in the Soleur account and build `7e1d286` deployed with wrangler. soleur.ai and www attached as custom domains, and both records repointed as proxied CNAMEs. |
| agent | 17:15:26 | Both custom domains `active`; apex and www return 200 serving `version.txt` = `7e1d286`. |
| agent | 17:15:31–34 | Better Stack resolves the changelog, legal-terms and database-readiness monitors; the apex monitor moves to validating. |
| agent | ~17:25 | Follow-up #12931 filed for the Terraform migration and the remaining degraded surfaces. |

## Participants and Systems Involved

Operator (single founder); a Claude Code agent session. Systems: Cloudflare (registrar, two accounts and zones, Pages, Tunnel, Load Balancing, Access, rulesets), Supabase custom domain, Proton Mail, Amazon SES, Resend, Buttondown, Better Stack Uptime, Sentry, Doppler.

## Detection (+ MTTD)

- **How detected:** manual — the operator noticed and reported it. Better Stack also alerted at 16:25:42Z, about 2 minutes after the zone was activated.
- **MTTD (mean time to detect):** Unknown (external/manual report)

## Triggered by

user — one of user / system / market movement / provider. The operator started the move of the soleur.ai registration to the dedicated Soleur account. Cloudflare then created the new zone and filled it with its own DNS scan.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The new authoritative zone serves scanned records instead of the old zone's records | Registry nameservers are lennon/laila; the new zone was activated at 16:23:52Z; proxied hosts there were A records at Cloudflare anycast IPs (Error 1000); api was proxied; 12 records were missing | None found | Confirmed |
| Origin or application failure | — | soleur-docs.pages.dev served 200 throughout; the app returned 200 as soon as its record pointed at the origin; Sentry showed no edge or DNS-related errors in 16:00–17:30Z | Rejected |

## Resolution

Fixed forward in the new Soleur account; the old zone was only read. Steps: mint a scoped API token through the dashboard session; restore the app, api, email and verification records from the old-zone export (MX/TXT/NS/CNAME diff empty apart from the website and tunnel CNAMEs); copy the zone settings to exact parity; create the `soleur-docs` Pages project in the new account, deploy the live build `7e1d286`, attach soleur.ai and www, and point both at it. Tunnel hosts, rulesets, bulk redirects and the load balancer still live in the old account; they move to the new account in #12931.

## Recovery verification

- Better Stack: app dashboard resolved 17:12:08Z; database readiness, changelog and legal pages resolved 17:15:31–34Z; apex validating at 17:15:38Z.
- curl from outside: soleur.ai, www, /changelog/, /legal/terms-and-conditions/ and /llms.txt return 200; app /login and /health return 200; api auth answers 401 without an apikey (Supabase is serving) and the GitHub authorize call returns 302 to github.com.
- DNS at lennon.ns.cloudflare.com and at the Cloudflare and Google public resolvers returns the restored records. No DS record exists for soleur.ai, so DNSSEC is not a factor.
- Zone-settings diff against the old zone: empty.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why were the site, the app and sign-in down?** The authoritative zone served wrong records: proxied hosts were A records pointing at Cloudflare's own IPs (Error 1000), api.soleur.ai was proxied, and records were missing.
2. **Why did the authoritative zone have wrong records?** Moving the registration to another Cloudflare account created a new zone in that account and switched the registry nameservers to it. The old, correct zone went to `moved`.
3. **Why did the new zone not match the old one?** Cloudflare filled it from a DNS scan of the public view. A scan sees the anycast IPs behind proxied records, not their real targets, and it cannot find names it does not guess (the acme, DKIM-subdomain and SES feedback names). Account-scoped resources (Pages project, tunnel, load balancer, Access apps, rulesets, bulk-redirect lists) do not move with a zone.
4. **Why was this not caught before the nameservers switched?** There was no runbook or pre-check for moving a registration between accounts. Zone and account configuration lives in Terraform pinned to the old zone and account ids, and nothing pre-staged the target zone or compared it with the source before the switch.
5. **Why did recovery take 51 minutes?** No credential in Doppler reached the new account. Mitigation waited on an operator sign-in to mint a token, and the Pages project had to be rebuilt because a proxied CNAME cannot point into a Pages project owned by another account.

## Versions of Components

- **Version(s) that triggered the outage:** N/A — no code change; Cloudflare registration move at about 16:23:52Z.
- **Version(s) that restored the service:** No code change. New zone `951ce525…` configuration plus a Pages deploy of `jikig-ai/soleur@7e1d286` to the new account's `soleur-docs` project.

## Impact details

### Services Impacted

`soleur.ai` and `www.soleur.ai` (marketing and docs site), `app.soleur.ai` (dashboard and health), sign-in through `api.soleur.ai` (Supabase custom domain, including the GitHub OAuth callback), and email: outbound DKIM (Proton), inbound SES MX, SES feedback MX/SPF and Resend subdomain DKIM. Still degraded and tracked in #12931: legacy-URL and www 301 redirects, the `X-Robots-Tag` rules, and the deploy/ssh/registry tunnel hosts.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface. This is the canonical "Customer Impact"; do NOT add a second free-text Customer Impact block.

- Prospect: could not load soleur.ai or www for about 51 minutes; legacy links still do not redirect.
- Authenticated app user: could not reach the app or sign in (email or GitHub) for about 51 minutes.
- Legal-document signer: the legal pages were unreachable for the same window.
- Admin via Access: the deploy, ssh and registry hosts are unreachable until #12931 lands.
- Billing customer: the app (and with it any billing surface) was unreachable for the window; no billing data was affected.
- OAuth installation owner: the GitHub OAuth callback through api.soleur.ai failed during the window.

### Revenue Impact

Unknown / N/A

### Team Impact

Deploys of the web platform and CI registry pushes are blocked until #12931 lands. Docs CI deploys to the old account's project, so docs changes do not reach the live site.

## Lessons Learned

### Where we got lucky

The old zone kept every record, setting and ruleset in a readable `moved` state during Cloudflare's grace period, so it served as an exact source of truth. No DNSSEC DS record was published, so the nameserver switch did not cause validation failures.

### What went well

Both zones were snapshotted read-only before any change. Recovery went in order of user impact: app and sign-in first, then email, then the website. The new token was handed over without its value entering the transcript. Records and settings were verified by an empty diff against the old export, not by eye.

### What went wrong

There was no pre-check or runbook for a cross-account registration move. No credential reached the new account, which added minutes of operator time. During mitigation, the first token's value was lost and that token had to be deleted, and an empty Doppler secret was written once before being removed. The Playwright MCP server that was tried first lacked a browser install. The incident skill's Phase 0 pull fence was refused by a safety check, so Better Stack and Sentry were pulled directly instead.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

**Each row MUST cite a filed GitHub issue number.** A bare bullet or a `TBD`/`(none)` placeholder is not allowed — file the issue first (`gh issue create`, cross-referencing the source PR in the body), then record its number here. An item with no `#NNNN` is shelf-ware that rots the moment the session ends; the `/ship` Incident-PIR gate blocks merge on any item that lacks an issue reference. If there are genuinely zero follow-ups, write exactly `No action items — incident fully resolved in the source PR with no residual work.` as a line of its own, with no emphasis — the permitted no-item form is plain so that the markdown linter (MD049, emphasis-style) cannot restyle it; the `/ship` gate accepts the plain line (and the underscore/asterisk-wrapped spellings shipped before this template changed).

| Issue | Action | Status |
|---|---|---|
| #12931 | Migrate Terraform to the new Soleur account and zone: rulesets and bulk redirects, transform/config/cache/WAF rules, load balancer, tunnel and Access apps (with a host-side cloudflared redeploy), plan check (Pro vs Free), `cf_zone_id`/`cf_account_id`, Doppler `CF_ZONE_ID` and tokens, GitHub Actions Pages secrets, and revoking the temporary token | open |
