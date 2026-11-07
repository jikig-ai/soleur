---
title: Origin-TLS strict flip for app.soleur.ai (ordered acts, proof, rollback)
category: operations
tags: [tls, cloudflare, strict, origin-ca]
date: 2026-11-07
---

# Origin-TLS strict flip (ADR-321 decision 3, #10479)

Makes Cloudflare validate the Origin CA certificate on EVERY request to `app.soleur.ai` (`strict`) instead of dialing it unvalidated over
plain HTTP (`flexible`). The code is merged inert: `var.enable_origin_tls_strict` defaults to false, so the merge changes nothing at the edge.
The flip is the owner's three ordered acts below. **The order is the safety property.** Do not set the switch in act 3 before act 2 is proven.

## Why this order

`ORIGIN_TLS_REQUIRED=1` makes absent or invalid certificate material FATAL at startup (ADR-321 decision 6). It is read only when a container
starts. If it is live on both hosts BEFORE the edge flips, a bad deploy fails its canary container, the redeploy fails and the OLD container keeps
serving while the edge is still `flexible`: nobody sees anything. If the edge flips first, the same bad deploy is a 525/526 for every user.

## Act 0 - read-only preconditions (anyone)

| Check | Command or source | Expected now |
|---|---|---|
| Both hosts listening on the minted certificate | `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 12h --grep 'origin-tls: listening'`, decoded: keep rows with `CONTAINER_NAME`, `host`, and the pino message | one fresh line per host (`soleur-web-platform`, `soleur-web-2`), `fingerprint256` 7B:E5:11:D0..., `daysLeft` about 5474 |
| No origin-TLS errors | Sentry Discover, `query=feature:origin_tls`, `statsPeriod=24h` (token name `SENTRY_ISSUE_RO_TOKEN`, Doppler `soleur/prd`; GET only) | 0 events |
| Canary still proves the strict handshake | `bash apps/web-platform/infra/origin-tls-probe.sh --canary` | exit 0, `mode=canary result=TLS-ON-ORIGIN-HOP`, TLSv1.3 |
| Normal traffic still plain | `bash apps/web-platform/infra/origin-tls-probe.sh` | `PLAIN-ORIGIN-HOP` (the pre-flip truth) |
| LB monitor green on https/443 for both origins | the `ga-monitor-https` run summary (42376594967), and no `web_lb_health` "Unhealthy" mail since | green |
| No page rule can override the Configuration Rule | `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh pagerules-ssl` | `active_rule_count` 0 (Configuration Rules also take precedence over Page Rules) |
| Live ruleset is what the code expects | `... cloudflare-readonly.sh config-entrypoint` | 4 rules while the canary is on: flexible app, obfuscation, apex `full`, canary `strict`; no strict app-host rule yet |
| Edge baseline | 30 sequential `GET https://app.soleur.ai/health?x=<n>` | 30 of 30 return 200 |
| Doppler | names only: `ORIGIN_TLS_KEY_B64`, `ORIGIN_TLS_CERT_B64` present in `prd`; `ORIGIN_TLS_REQUIRED` absent; `ENABLE_ORIGIN_TLS_STRICT` absent | as stated |

## Act 1 - REQUIRED in Doppler prd (owner's go; no effect until a restart)

```bash
doppler secrets set ORIGIN_TLS_REQUIRED=1 -p soleur -c prd > /dev/null
```

## Act 2 - restart both hosts on it, same image (owner's go)

web-1 swaps first (canary container, drain, swap), then fans out to web-2. A failure leaves the old container serving.

```bash
WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11 REDEPLOY_TIMEOUT_S=4800 \
 doppler run -p soleur -c prd_terraform --only-secrets WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET \
 -- bash .github/actions/dispatch-web-redeploy/track.sh
```

Proof before act 3 (all must hold): `track.sh` exits 0 with a terminal frame `reason=ok`; each host logs a NEW `origin-tls: listening` line (timestamp after the
Doppler write of act 1 and after the redeploy start); no `feature:origin_tls` Sentry events; `--canary` probe still exit 0. If the redeploy FAILS, the
edge is untouched: read the failure reason, fix, and do not proceed; to undo act 1 delete the name and redeploy.
Gap: the startup line does not print whether `ORIGIN_TLS_REQUIRED` was set, so "REQUIRED is live" is proven by this ordering, not read directly.

## Act 3 - the flip (owner's go)

```bash
doppler secrets set ENABLE_ORIGIN_TLS_STRICT=true -p soleur -c prd_terraform > /dev/null
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason="ADR-321: strict flip for app.soleur.ai"
```

The apply plan must show exactly one in-place change to `cloudflare_ruleset.seo_config_settings`, +1 rule.

Proof after: `bash apps/web-platform/infra/origin-tls-probe.sh --require-tls` exits 0 with `result=TLS-ON-ORIGIN-HOP` and `transport=TLSv1.3` (NOT the canary mode:
normal traffic now crosses a validated TLS hop); the 30-request baseline still 30 of 30; no 525/526; Sentry `feature:origin_tls` quiet; Better Stack has no
`origin-tls: a client failed the TLS handshake` burst; the pool is still healthy; open a signed-in session and confirm the WebSocket connects (the upgrade path has
not been exercised through the edge under strict before). Port 80 stays open until these pass (CLO condition 3).

## Rollback (roll forward only: never `git revert` the resource)

Delete `ENABLE_ORIGIN_TLS_STRICT` from Doppler `prd_terraform` (or set it `false`) and re-run the same apply dispatch. One in-place change, -1 rule; the app host returns
to the adopted `flexible` rule and the entrypoint is never destroyed. Time to effect: the apply run (several minutes) plus edge propagation (seconds to about a minute).
Break-glass if the apply path is unavailable: `GET` the `http_config_settings` entrypoint, remove the rule whose description starts `ORIGIN-TLS STRICT`, and `PUT` the full
list back (the owner's go; a whole-list PUT is error-prone under pressure, so prefer the apply). Also unset the Doppler switch afterwards or the next apply re-adds the rule.

What users see if the flip goes wrong: Cloudflare error pages on every page, API call and WebSocket of `app.soleur.ai`: 525 (SSL handshake failed) or 526 (invalid SSL
certificate). Browser-to-edge TLS is unaffected. Act 2 exists so this state is unreachable through a bad deploy.

## After the flip has baked

A cleanup change edits the `flexible` rule to `strict`, removes both dynamic blocks and variables, and the owner deletes `ENABLE_ORIGIN_TLS_CANARY_RULE` and
`ENABLE_ORIGIN_TLS_STRICT` from Doppler `prd_terraform`.
