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

## Status (dated; all times UTC; verified 2026-11-08 unless a row says otherwise)

| Act | State | Evidence |
|---|---|---|
| 0. Read-only preconditions | **DONE before act 3**, with three exceptions stated in "What was NOT run" below | the Act 0 table's expectations are the PRE-FLIP state (they are historical now; see "Act 0" for what holds today) |
| 1. `ORIGIN_TLS_REQUIRED=1` in Doppler `prd` | **DONE** about 20:55Z on 2026-11-07. Do NOT set it again | `doppler secrets --only-names -p soleur -c prd` lists `ORIGIN_TLS_REQUIRED` |
| 2. Restart both hosts on it | **DONE**: redeploy completed about 21:01Z (the 21:00:04Z / 21:01:04Z `soleur-web-platform` and 21:00:35Z / 21:01:32Z `soleur-web-2` `origin-tls: listening` pairs; web release v0.395.3 by publish order). It is NOT the last restart before the flip: see "Restarts before and after the flip" | `origin-tls-probe.sh --canary` exit 0 `TLS-ON-ORIGIN-HOP` TLSv1.3 at 21:22Z |
| 3. The flip | **DONE** on 2026-11-07: ruleset written at 23:43:43.9Z (Cloudflare `last_updated`), apply job ended 23:44:26Z, first passing probe 23:44:39Z. Do NOT dispatch it again while strict is live | see "Act 3 record" below |

### Act 3 record (dated facts only)

- `ENABLE_ORIGIN_TLS_STRICT` was set in Doppler `prd_terraform` (lowercase `true`) on 2026-11-07. The Doppler activity log shows a `prd_terraform` write ("1 added") at 23:41:47Z, 7 s before the flip dispatch was created (23:41:54Z); the log names the account (`ops@jikigai.com`), not the secret, so that match is consistent with, not proof of, the switch write.
- Merge apply, run 42425987199 (23:36:03Z to 23:38:12Z): added the strict rule DISABLED, 4 to 5 rules, no edge behaviour change.
- Entrypoint audit (`apply_target=entrypoint-audit`), run 42426216807 (23:39:13Z to 23:40:49Z): no dashboard-added rules reported. The audit prints a live rule count only; "declared 5" is the author's count of `seo-config-rules.tf`, so the audit alone does not prove live == declared. The better evidence is the flip's own plan, which changed exactly one thing.
- Flip apply, run 42426416266: apply job 23:42:34Z to 23:44:26Z; plan 0 to add, 1 to change, 0 to destroy (the `ORIGIN-TLS STRICT` rule's `enabled` false to true); the Terraform log line "cloudflare_ruleset.seo_config_settings: Modifications complete" is stamped 23:43:44.97Z; Cloudflare reports the live ruleset (version 7) `last_updated` 23:43:43.865Z.
- `origin-tls-probe.sh --require-tls`: **passed on the first poll, at 23:44:39Z** (TLSv1.3), 13 s after the apply run ended and about 55 s after the ruleset write. **There was no earlier poll, so about 55 s is an UPPER BOUND on the flip's time-to-effect**, not a measurement of when it took effect. Before 23:44:39Z the flip was not proven effective.
- Live ruleset, read 2026-11-08: 5 rules, 4 enabled ssl rules (flexible app, apex `full`, canary `strict`, strict), version 7 (`cloudflare-readonly.sh config-entrypoint`). Per its header, `enabled_ssl_rules` is 2 plus one per ORIGIN-TLS switch that is on (both are), hence 4.
- **What the probe proves.** `TLS-ON-ORIGIN-HOP` shows the hop used TLS for a request through the edge to web-1 (the only weighted origin; web-2 has weight 0). It would also pass under `full`, which does not validate the certificate. The stronger evidence that the mode is `strict` is the live rule itself: enabled, and last in the list (last match wins). The canary rule is still enabled, so `--canary` no longer discriminates anything.

#### Restarts before and after the flip

The flip survived full redeploys under `strict` and `ORIGIN_TLS_REQUIRED=1`. Restart pairs (`origin-tls: listening` rows, Better Stack, web-1 then web-2; the web release version is inferred from publish order, not read from `/health` at that time):

| Restart pair (web-1 / web-2) | Relative to the flip | Release (by publish order) |
|---|---|---|
| 20:32:54Z / 20:34:03Z, 20:53:47Z / 20:55:00Z | before act 2 | earlier |
| 21:00:04Z / 21:00:35Z, 21:01:04Z / 21:01:32Z | act 2 | v0.395.3 |
| 21:46:45Z / 21:47:57Z, 22:10:27Z / 22:11:42Z, 22:55:45Z / 22:56:58Z | between act 2 and the flip (not recorded earlier) | v0.395.4, v0.395.5, v0.395.6 (v0.395.6 was live when the flip was applied) |
| **23:48:28Z / 23:49:43Z** | **after the flip** | v0.395.7 |
| 00:13:58Z / 00:15:11Z | after the flip | v0.395.8 |

Release run 42426213123 (Web Platform Release) deployed v0.395.7: `deploy` job 23:47:12Z to 23:48:34Z, `verify-peer-deploy` 23:48:45Z to 23:49:53Z, i.e. 3 to 6 minutes AFTER the flip. Both hosts restarted and logged `origin-tls: listening` (23:48:28Z, 23:49:43Z), so the flip survived a full redeploy under `strict` with `REQUIRED=1`. The 00:13:58Z / 00:15:11Z pair coincides with the +30 min recheck.

#### Latency and error samples (small, client-side `GET /health`; each figure names its sample)

| Sample | n | non-200 | p50 | p90 |
|---|---|---|---|---|
| Pre-flip baseline, taken by the session that ran the flip, about 23:40Z on 2026-11-07 (before the flip dispatch at 23:41Z) | 30 | 0 | 0.190 s | 0.239 s |
| An earlier pre-flip sample taken by the CTO agent's session, about 21:2xZ on 2026-11-07 | 30 | 0 | 0.194 s | 0.245 s |
| Post-flip, right after the flip (the flip-running session, about 23:45Z) | 30 | 0 | 0.194 s | 0.332 s |
| +30 min recheck, 2026-11-08 00:15Z (the flip-running session) | 30 | 0 | 0.212 s | 0.393 s |
| Later sample, 2026-11-08 07:37Z, taken by a review seat (unpaired) | 30 | not stated | 0.225 s | 0.368 s |

Both pre-flip samples agree within 4 ms at p50 and 6 ms at p90. The value 0.194 s appears twice: as the earlier pre-flip p50 (CTO agent's session, about 21:2xZ) and as the p50 right after the flip (flip-running session, about 23:45Z); they are different samples. The 0.190 s / 0.239 s sample taken minutes before the flip is used as the baseline. p50 is essentially unchanged (0.190 to 0.194 to 0.212 s); **p90 rose from about 0.24 s to 0.33 s right after the flip and 0.39 s at the 00:15Z recheck, and the rise is unexplained.** Candidates, none established: the full redeploys after the flip (23:48 to 23:50Z and 00:14 to 00:15Z, with new Cloudflare-to-origin TLS connections after each restart), TLS termination CPU in the Node process, a longer handshake on new origin connections, or small-sample noise. "Fine" is not a finding: the +30 min recheck (p50 0.212 s, p90 0.393 s, the highest p90 so far) is a rise, not a recovery.

#### What was NOT run before the flip

- The local read-only plan (Act 0): not run. The flip plan itself (1 change) was read after the fact in the apply log.
- The Sentry `feature:origin_tls` read and the `pagerules-ssl` check: last read at about 19:58Z on 2026-11-07 (0 events; 0 active page rules; reported in PR #12341), not re-run immediately before the flip.
- Doppler activity log, `prd_terraform` writes in the window (account `ops@jikigai.com` for every entry, secret names not shown): 22:54:34Z (1 updated), 23:41:47Z (1 added, discussed above) and 00:13:25Z (1 updated). The 22:54:34Z and 00:13:25Z writes are **not attributed** here.

### Open checks (plainly)

| Check | Owner of the check | State |
|---|---|---|
| Signed-in WebSocket connects through the edge under `strict` (the upgrade path has never been exercised through the TLS hop by a probe) | **owner** (no probe exists) | open |
| +1 h and +24 h rechecks (the 30-request loop and the Sentry query), rollback kept armed for the whole window | whoever runs the soak | pending |
| Sentry `feature:origin_tls` | anyone with the read token | not re-read after the flip |
| Real 502/520 rate over a fixed window (Cloudflare analytics) | **owner** (no sanctioned reader) | open |
| Port 80 | stays OPEN until the bake passes (CLO condition 3); the post-flip probe passing is necessary, not sufficient | open |
| Rollback time-to-effect at the edge | | **unmeasured**: the apply run took 109 to 370 s on this workflow; the flip's own upper bound (about 55 s from the ruleset write to the first passing probe) is the only edge figure |

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

The startup line does not print whether `ORIGIN_TLS_REQUIRED` was in effect, so "REQUIRED is live" is proven by ORDERING (the Doppler write precedes a green redeploy,
which precedes fresh per-host lines), not read directly.

## Act 0 - read-only preconditions before act 3 (anyone; all runnable; the Expected column is the PRE-FLIP state)

| Check | Command | Expected |
|---|---|---|
| Doppler names only | `doppler secrets --only-names -p soleur -c prd \| grep ORIGIN_TLS` and `doppler secrets --only-names -p soleur -c prd_terraform \| grep ENABLE_ORIGIN_TLS` | `ORIGIN_TLS_CERT_B64`, `ORIGIN_TLS_KEY_B64`, `ORIGIN_TLS_REQUIRED`; and only `ENABLE_ORIGIN_TLS_CANARY_RULE` (strict absent). Never print values |
| Both hosts listening on the minted certificate | `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 6h --grep 'origin-tls: listening' --limit 300 \| jq -r '.raw \| fromjson \| select(has("CONTAINER_NAME")) \| select(tostring \| contains("origin-tls: listening")) \| "\(.SYSLOG_TIMESTAMP) host=\(.host)"' \| sort \| tail` | fresh lines for `soleur-web-platform` AND `soleur-web-2` after the act 2 redeploy; (the same rows carry `fingerprint256` 7B:E5:11:D0... and `daysLeft` about 5474 inside the pino message) |
| No origin-TLS errors in Sentry | see "Sentry check" below | 0 events (and the control query returns rows) |
| Canary still proves the strict handshake | `bash apps/web-platform/infra/origin-tls-probe.sh --canary` | exit 0, `mode=canary result=TLS-ON-ORIGIN-HOP`, TLSv1.3 |
| Normal traffic still plain | `bash apps/web-platform/infra/origin-tls-probe.sh` | `PLAIN-ORIGIN-HOP` (the pre-flip truth) |
| No page rule can override the Configuration Rule | `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh pagerules-ssl` | `active_rule_count` 0 |
| Live ruleset matches the code | `... cloudflare-readonly.sh config-entrypoint` | `rule_count` 5, `enabled_ssl_rules` 2 plus one per ORIGIN-TLS switch that is on (3 before the flip: flexible app, apex `full`, canary `strict`; 4 after it); the app-host strict rule present with `enabled` false once the merge apply has run |
| Dashboard-added rules would be deleted by the whole-list update | `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=entrypoint-audit -f reason="pre-flip entrypoint audit (ADR-321)"` then read the run and #6767 | no finding for `http_config_settings`. The audit prints a LIVE rule count only (it does not compare against the declared count), so also compare that count with the rule blocks in `seo-config-rules.tf`; the apply plan's single enabled change is the better evidence |
| The plan the flip will execute | local read-only plan, from `apps/web-platform/infra` with the init and variable set the apply job uses (`doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color -input=false -var="ssh_key_path=/tmp/ci_ssh_key.pub" -target=cloudflare_ruleset.seo_config_settings`), with `TF_VAR_enable_origin_tls_strict=true` set for that one command | exactly one in-place change to `cloudflare_ruleset.seo_config_settings`, `enabled` false to true on the `ORIGIN-TLS STRICT` rule, no `+`/`-` rule lines. **Not run by the author** (it needs the Tier-B loader's variables); the apply job AUTO-APPROVES its own plan, so this local plan is the only human look before the flip |
| Latency baseline | the 30-request loop below | record p50/p90 |
| Edge error baseline | the 30-request loop below (client-side) | 30 of 30 200 |

Latency and error loop (run before, right after, at +1 h and +24 h; the baseline measured minutes before the flip was non200=0, p50 0.190 s, p90 0.239 s):

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
applies took 109 to 370 s. For the FLIP the first passing probe came about 55 s after the ruleset write (an upper bound: it was the first poll); propagation of a ROLLBACK has not been timed. Plan on 2 to 6 minutes plus about a minute of propagation.
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
