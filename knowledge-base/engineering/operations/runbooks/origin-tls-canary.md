---
title: Origin-TLS canary rule (strict for one probe request)
category: operations
tags: [tls, cloudflare, canary, origin-ca]
date: 2026-11-07
---

# Origin-TLS canary rule (ADR-321, #10479)

A Configuration Rule that makes Cloudflare dial the origin in `strict` for ONE kind of request: `/health` on `app.soleur.ai` carrying
`x-origin-tls-probe: 1`. Everything else to the host stays `flexible`. It measures the real edge-to-origin handshake against the Origin CA
certificate before the host-wide strict flip. It is declared in `apps/web-platform/infra/seo-config-rules.tf` behind
`var.enable_origin_tls_canary_rule` (default false), so merging the code changes nothing at the edge.

## Preconditions (read-only)

- Both hosts logged `origin-tls: listening` after their last start (Better Stack, decoded per ADR-321); no `feature:origin_tls` Sentry events.
- The https LB monitor reports both origins healthy (it validates the certificate): `cf-lb-overlay.yml` run for `ga-monitor-https` green.
- Baseline: `bash apps/web-platform/infra/origin-tls-probe.sh --canary` exits 3 (`NO-TLS-ON-ORIGIN-HOP`, the rule is not applied yet).

## Turn it on (owner's go, two steps)

1. Doppler, prd_terraform: set `ENABLE_ORIGIN_TLS_CANARY_RULE` to `true` (the value is a boolean; the CLI prints every other secret unless
   its stdout is discarded, so redirect it: `doppler secrets set ENABLE_ORIGIN_TLS_CANARY_RULE=true -p soleur -c prd_terraform > /dev/null`).
2. `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason="ADR-321: enable the origin-TLS canary rule"`
   (the same apply path as a merge; the plan should show exactly one in-place change to `cloudflare_ruleset.seo_config_settings`, +1 rule).

## Read it

```bash
bash apps/web-platform/infra/origin-tls-probe.sh --canary ; echo "exit=$?"
```

| Exit | Line | Meaning |
|---|---|---|
| 0 | `mode=canary result=TLS-ON-ORIGIN-HOP` | The rule applied AND Cloudflare accepted the Origin CA certificate under strict (issuer, expiry, hostname). |
| 1 | `result=NOT-200` with `http=525` or `526` | The rule applied and Cloudflare REFUSED the certificate. Fix the certificate or its delivery before any flip. |
| 3 | `result=NO-TLS-ON-ORIGIN-HOP` | The rule did not apply (not propagated yet, not enabled, or the phase rejected the header field). Says nothing about the certificate. |
| 2 | `UNREACHABLE` | Could not check. |

Also read the Better Stack startup lines per host. The edge canary reaches the host that carries traffic (web-1); web-2 (weight 0) is
covered by the https LB monitor and its own `origin-tls: listening` line.

## Turn it off / rollback

Delete the Doppler secret (or set it to `false`) and dispatch the same apply again. The plan shows one in-place change (-1 rule); the
entrypoint is never destroyed. Time to take effect: the apply run (several minutes) plus edge propagation (seconds to about a minute).
Real traffic is never in the canary's scope, so there is no user-facing urgency. A `git revert` of the code PR after the canary is on is
also safe (it removes the dynamic block, the same in-place -1 rule), but it needs a merge to apply; the Doppler switch is the fast lever.
