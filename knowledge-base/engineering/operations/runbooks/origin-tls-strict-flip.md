---
title: Origin-TLS strict flip for app.soleur.ai (ordered acts, proof, rollback)
category: operations
tags: [tls, cloudflare, strict, origin-ca]
date: 2026-11-07
---

# Origin-TLS strict flip (ADR-321 decision 3 and item 10, #10479)

Makes Cloudflare validate the Origin CA certificate on EVERY request to `app.soleur.ai` (`strict`) instead of dialing it unvalidated over plain HTTP
(`flexible`). The code is merged inert: the strict rule is ALWAYS in the ruleset but `enabled = var.enable_origin_tls_strict`, which defaults to false, so
merging adds one disabled rule and changes no edge behaviour. The flip is the owner's three ordered acts. **The order is the safety property.**

## Status (dated; re-verify before relying on it)

| Act | State | Evidence (read-only, 2026-11-07 21:22Z) |
|---|---|---|
| 1. `ORIGIN_TLS_REQUIRED=1` in Doppler `prd` | **DONE** about 20:55Z. Do NOT set it again | `doppler secrets --only-names -p soleur -c prd` lists `ORIGIN_TLS_REQUIRED` |
| 2. Restart both hosts on it | **DONE**, redeploy of v0.395.3 completed about 21:01Z | `/health` version 0.395.3; fresh `origin-tls: listening` lines 21:00:04Z / 21:01:04Z (`soleur-web-platform`) and 21:00:35Z / 21:01:32Z (`soleur-web-2`); `origin-tls-probe.sh --canary` exit 0 `TLS-ON-ORIGIN-HOP` TLSv1.3 |
| 3. The flip | **NOT DONE** | `ENABLE_ORIGIN_TLS_STRICT` absent from Doppler `prd_terraform`; only `ENABLE_ORIGIN_TLS_CANARY_RULE` is present |

## Why this order

`ORIGIN_TLS_REQUIRED=1` makes absent or invalid certificate material FATAL at startup (ADR-321 decision 6). It is read only when a container starts. With it live
on both hosts BEFORE the edge flips, a deploy whose certificate material is bad fails its candidate (canary) container, the redeploy fails and the old container
keeps serving while the edge is still `flexible`: nobody sees anything.

**Scope of that guarantee (read this before calling the flip safe).** It covers certificate-MATERIAL failures caught at the candidate container. It does not cover:

- A **production-start failure** after the candidate passes (for example the `-p 0.0.0.0:443:3443` publish failing): ADR-321 decision 7 accepts that the previous
  image is not restored and the host is left down until a human intervenes. Under `strict` that is a user-visible outage on that host regardless of the order.
- An **older image** (before the TLS listener) deployed after the flip: it has nothing on :443, so every request is a 525/526 under `strict`.
- A **later Doppler change** to the certificate material (rotation, deletion) that takes effect at the next restart: REQUIRED makes that restart fail at the candidate
  (good), but a host that restarts for another reason (reboot, crash loop) with bad material and no candidate gate can come up unable to serve TLS.
- The **WebSocket upgrade path**, which has never crossed the edge-to-origin TLS hop under `strict` (the canary exercises `GET /health` only).

Until the image with the 2026-11-08 hardening is deployed, the startup line does not print whether `ORIGIN_TLS_REQUIRED` was in effect, so "REQUIRED is live" is proven by ORDERING (the Doppler write precedes a green redeploy,
which precedes fresh per-host lines), not read directly. From that image on, the `origin-tls: listening` line carries `required: true|false`, a direct per-host read.

## Act 0 - read-only preconditions before act 3 (anyone; all runnable)

| Check | Command | Expected |
|---|---|---|
| Doppler names only | `doppler secrets --only-names -p soleur -c prd \| grep ORIGIN_TLS` and `doppler secrets --only-names -p soleur -c prd_terraform \| grep ENABLE_ORIGIN_TLS` | `ORIGIN_TLS_CERT_B64`, `ORIGIN_TLS_KEY_B64`, `ORIGIN_TLS_REQUIRED`; and only `ENABLE_ORIGIN_TLS_CANARY_RULE` (strict absent). Never print values |
| Both hosts listening on the minted certificate | `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 6h --grep 'origin-tls: listening' --limit 300 \| jq -r '.raw \| fromjson \| select(has("CONTAINER_NAME")) \| select(tostring \| contains("origin-tls: listening")) \| "\(.SYSLOG_TIMESTAMP) host=\(.host)"' \| sort \| tail` | fresh lines for `soleur-web-platform` AND `soleur-web-2` after the act 2 redeploy; (the same rows carry `fingerprint256` 7B:E5:11:D0... and `daysLeft` about 5474 inside the pino message) |
| No origin-TLS errors in Sentry | see "Sentry check" below | 0 events (and the control query returns rows) |
| Canary still proves the strict handshake | `bash apps/web-platform/infra/origin-tls-probe.sh --canary` | exit 0, `mode=canary result=TLS-ON-ORIGIN-HOP`, TLSv1.3 |
| Normal traffic still plain | `bash apps/web-platform/infra/origin-tls-probe.sh` | `PLAIN-ORIGIN-HOP` (the pre-flip truth) |
| No page rule can override the Configuration Rule | `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh pagerules-ssl` | `active_rule_count` 0 |
| Live ruleset matches the code | `... cloudflare-readonly.sh config-entrypoint` | `rule_count` 5, `enabled_ssl_rules` 3 (flexible app, apex `full`, canary `strict`); the app-host strict rule present with `enabled` false once the merge apply has run |
| Dashboard-added rules would be deleted by the whole-list update | `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=entrypoint-audit -f reason="pre-flip entrypoint audit (ADR-321)"` then read the run and #6767 | no drift finding for `http_config_settings` (a read-only enumeration; it posts its findings to #6767) |
| The plan the flip will execute | local read-only plan, from `apps/web-platform/infra` with the init and variable set the apply job uses (`doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color -input=false -var="ssh_key_path=/tmp/ci_ssh_key.pub" -target=cloudflare_ruleset.seo_config_settings`), with `TF_VAR_enable_origin_tls_strict=true` set for that one command | exactly one in-place change to `cloudflare_ruleset.seo_config_settings`, `enabled` false to true on the `ORIGIN-TLS STRICT` rule, no `+`/`-` rule lines. **Not run by the author** (it needs the Tier-B loader's variables); the apply job AUTO-APPROVES its own plan, so this local plan is the only human look before the flip |
| Latency baseline | the 30-request loop below | record p50/p90 |
| Edge error baseline | the 30-request loop below (client-side) | 30 of 30 200 |

Latency and error loop (run before, right after, at +1 h and +24 h; the baseline measured in the author's session was non200=0, p50 0.194 s, p90 0.245 s):

```bash
for i in $(seq 1 30); do curl -s -o /dev/null -w '%{time_starttransfer} %{http_code}\n' --max-time 10 "https://app.soleur.ai/health?l=$i-$RANDOM"; sleep 1; done > /tmp/lat.$$
awk '$2!=200{b++} END{print "non200=" b+0}' /tmp/lat.$$; cut -d' ' -f1 /tmp/lat.$$ | sort -n | awk '{a[NR]=$1} END{print "n=" NR " p50=" a[int(NR*0.5)] "s p90=" a[int(NR*0.9)] "s max=" a[NR] "s"}'; rm -f /tmp/lat.$$
```

This is a client-side sample of `/health`, not the real 502/520 rate: no sanctioned reader of Cloudflare edge analytics exists in the repo tooling, so the true rate over a fixed
window is an **owner act** (Cloudflare dashboard, Analytics, status codes 502 and 520-526 for `app.soleur.ai`, same window before and after).

Sentry check (GET only; token NAME `SENTRY_ISSUE_RO_TOKEN`, Doppler `soleur/prd`; `scripts/sentry-issue.sh` has no feature-search mode, so this is the exact call):

```bash
doppler run -p soleur -c prd -- bash -c 'curl --disable --noproxy "*" -s --max-time 30 -G "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/" \
  --data-urlencode "field=timestamp" --data-urlencode "field=message" --data-urlencode "field=host_name" --data-urlencode "query=feature:origin_tls" \
  --data-urlencode "statsPeriod=24h" --data-urlencode "dataset=errors" --data-urlencode "per_page=20" \
  --config - < <(printf "header = \"Authorization: Bearer %s\"\n" "$SENTRY_ISSUE_RO_TOKEN") | jq -c "{n:(.data|length), err:(.detail // null)}"'
# control (must return rows, or the zero above means nothing): swap the query for "has:feature"
```

Owner acts (no probe exists): the `web_lb_health` "Unhealthy" notification mail (inbox), pool health (the sanctioned Cloudflare reader has no pool-health subcommand; the
`ga-monitor-https` run summary is the existing instrument), and the signed-in WebSocket connect.

## Act 3 - the flip (owner's go)

```bash
doppler secrets set ENABLE_ORIGIN_TLS_STRICT=true -p soleur -c prd_terraform > /dev/null
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason="ADR-321: strict flip for app.soleur.ai"
```

**The value must be the lowercase string `true`.** Terraform converts the env value to a bool; `True`, `1` or `yes` fail the conversion and abort the WHOLE root's plan,
not just this rule. After the apply, read the plan in the run log (`gh run view <id> --log | grep -E 'Plan:|will be updated'`): it must say one in-place change.

Proof after (and record the time-to-effect: poll the probe every 10 s from the moment the apply ends until it passes):

- `bash apps/web-platform/infra/origin-tls-probe.sh --require-tls` (NOT `--canary`) exits 0 with `result=TLS-ON-ORIGIN-HOP`, `transport=TLSv1.3`.
- The 30-request loop: still 30 of 30, p50/p90 compared with the baseline.
- Sentry `feature:origin_tls` quiet; no `origin-tls: a client failed the TLS handshake` burst in Better Stack; the pool still healthy; the signed-in WebSocket connects (owner act).
- Re-check at **+1 h and +24 h** with the loop and the Sentry query, and keep the rollback below armed for that whole window. Port 80 stays open until these pass (CLO condition 3).

## Rollback (an in-place update; never `git revert` the resource)

The strict rule is always present and only `enabled` toggles, so the rollback is an in-place attribute update with the rule count constant. This was **measured, not asserted**:
real `terraform plan` + `terraform show -json` documents replayed through the real destroy-guard filter (`tests/scripts/test-destroy-guard-counter-web-platform.sh`, T65)
give `nested_deletes` 0 for flip-on, rollback, canary-off and canary-off-while-strict-on, so the apply job does not refuse them on a `workflow_dispatch` (where
`github.event.head_commit.message` is empty and `[ack-destroy]` cannot be supplied). The first design (a rule that came and went) planned a rule REMOVAL (`nested_deletes` 1)
that the same dispatch path refuses.

```bash
doppler secrets delete ENABLE_ORIGIN_TLS_STRICT -p soleur -c prd_terraform --yes > /dev/null     # or set it to the lowercase string false
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason="ADR-321: roll back the strict flip"
```

Time to effect: the apply run. Measured on this workflow in this repository: the canary enabling dispatch (run 42407585597) took 302 s wall clock with the apply job 111 s; recent push
applies took 109 to 370 s. Edge propagation after the apply is **not measured** (record it at the flip with the 10-second poll above). Plan on 2 to 6 minutes plus propagation.
Real traffic is never in the canary's scope, but a bad flip hits every user until this lands.

What users see if the flip goes wrong: Cloudflare error pages on every page, API call and WebSocket of `app.soleur.ai`, 525 (SSL handshake failed) or 526 (invalid SSL
certificate). Browser-to-edge TLS is unaffected.

**Break-glass (OWNER ONLY, not agent-runnable, not tested).** If the apply path itself is unavailable, the ruleset can be edited at the Cloudflare entrypoint
(`PUT /zones/<zone>/rulesets/phases/http_config_settings/entrypoint`, with `CF_API_TOKEN_RULESETS`, which carries Config Rules:Edit). This runbook does not give a runnable
procedure on purpose: the sanctioned reader (`cloudflare-readonly.sh config-entrypoint`) returns a summary, not a PUT body; a whole-list PUT can silently drop the apex `full`
rule (an HTTP 526 on the HSTS-preloaded apex) or reorder the adopted `flexible` rule (last match wins); and nothing here verifies the read-back. Use the dashboard to
disable the `ORIGIN-TLS STRICT` rule instead, then unset the Doppler switch so the next apply does not re-enable it.

## After the flip has baked: the cleanup change

A cleanup PR edits the adopted `flexible` rule to `strict`, removes both ORIGIN-TLS rules and both variables, and the owner deletes `ENABLE_ORIGIN_TLS_CANARY_RULE` and
`ENABLE_ORIGIN_TLS_STRICT` from Doppler. That change REMOVES rules (replayed: `nested_deletes` 2), so it must be merged to main with a line containing exactly `[ack-destroy]` in the
merge commit message (a push apply; the dispatch path cannot ack). That is the right friction for a deliberate removal, and it is never an emergency path.

## Act 2 reference (done 2026-11-07; for a repeat)

web-1 swaps first (candidate container, drain, swap), then fans out to web-2. The deploy-webhook credentials are read from the Tier-B project (they also still exist in
`prd_terraform`, which is Tier-A readable until #9294 closes; do not use that copy):

```bash
WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11 REDEPLOY_TIMEOUT_S=4800 \
 doppler run -p soleur-infra-privileged -c prd --only-secrets WEBHOOK_DEPLOY_SECRET,CF_ACCESS_CLIENT_ID,CF_ACCESS_CLIENT_SECRET \
 -- bash .github/actions/dispatch-web-redeploy/track.sh
```

An agent session can run this only if its Doppler login can read `soleur-infra-privileged/prd` (the author's could); the act is production-mutating and needs the owner's own go.
Proof: exit 0 with a terminal frame `reason=ok`, fresh per-host `origin-tls: listening` lines, no `feature:origin_tls` Sentry events, `--canary` probe exit 0.
web-2 (weight 0) is covered only by the https LB monitor with certificate validation and its own listening line; the edge canary reaches web-1 only.
