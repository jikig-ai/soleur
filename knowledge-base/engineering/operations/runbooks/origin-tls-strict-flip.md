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

#### /health p90 after the strict flip: evidence and isolation procedure

**Status: unexplained.** The p90 rise after the flip is not explained, and the effect of `strict` on user-facing latency is **unmeasured**. A flat p50 is not evidence that users are unaffected: do not read "fine" into it. Everything below is a procedure and a list of candidates, not a finding. Every claim not measured in the dated samples is marked UNVERIFIED.

##### Evidence (client-side unless a row says otherwise; 2026-11-08 unless stated; names, counts and timestamps only)

| Evidence | n | Measure | Result |
|---|---|---|---|
| Pre-flip baseline, 2026-11-07 about 23:40Z (table above) | 30 | `GET /health`, `time_starttransfer` | p50 0.190 s, p90 0.239 s |
| All post-flip samples in the table above, plus the two below | 30 each | same | p50 0.193 to 0.225 s, p90 0.318 to 0.393 s |
| Pair 1, about 16:35Z | 30 | same | p50 0.218 s, p90 0.359 s |
| Pair 2, about 16:35Z | 30 | same | p50 0.193 s, p90 0.318 s |
| Server wait (`time_starttransfer` minus `time_pretransfer`) for `app.soleur.ai/health`, about 16:37Z, interleaved with the apex | 30 | server wait | p50 0.154 s, p90 0.285 s |
| Server wait for the apex `soleur.ai/` (a different origin), about 16:37Z, interleaved with the row above | 30 | server wait | p50 0.082 s, p90 0.111 s |
| `origin-tls: listening` restart pairs, `soleur-web-platform` and `soleur-web-2` | 11 pairs | Better Stack rows between 01:05Z and 16:17Z (count and range only; the restart table above lists pairs only through 00:15Z, and no per-pair times are recorded here) | 11 |
| Better Stack handshake-failure (`a client failed the TLS handshake`) or unexpected-close lines | 00:20Z to 16:00Z on 2026-11-08 | line search | none found |
| Same line search, 2026-11-08 16:00Z to 23:46Z (read at the +24h re-check) | 17 warn lines (`code=ECONNRESET`) on web-1 only, between 21:41Z and 22:07Z; none on web-2; none outside that window | line search; the line is rate-limited to one per minute with a suppressed count | about 3,700 resets in about 26 minutes, peak 589 in one minute (21:55Z to 21:57Z), plus 2 `ERR_TLS_HANDSHAKE_TIMEOUT`; a container restart at 21:49:32Z did not stop it. The log carries no source address; whether any user saw a 525/526/502/520 in that window is **unknown** (needs the Cloudflare analytics reader, #12441). No alert covers this signal. |
| `origin-tls-probe.sh --require-tls`, about 16:35Z | 1 | exit and transport | passes, TLSv1.3 |

No pre-flip server-wait decomposition exists, so the 0.154 s cannot be split into before and after.

##### Reading the evidence honestly

- With n=30, p90 is roughly the third-slowest value, so run-to-run spread is large: the two 16:35Z samples, taken minutes apart, already differ by 0.04 s at p90 (0.359 versus 0.318).
- p50 moved little (0.190 s before; 0.193 to 0.225 s after). The movement is in the tail, which is exactly what n=30 measures worst.
- The apex control is a different origin. It shares only the client network with `app.soleur.ai`. It does not share the Node process, the Supabase leg or the Cloudflare-to-origin hop, so 0.154 s versus 0.082 s is **not a TLS number**.
- The p90 rise is therefore not attributed to the flip. The post-flip samples are consistently above the pre-flip baseline (five of five p90 values at or above 0.318 s, against 0.239 s and 0.245 s before), but they are small, were taken by several sessions, and the baseline pair is itself only two samples.

##### Candidates and what each predicts (all UNVERIFIED)

| # | Candidate | Predicts | Status |
|---|---|---|---|
| 1 | Redeploys: a cold Cloudflare-to-origin connection pool and a cold Supabase leg right after each restart (`/health` makes one Supabase round trip per request, so a cold connection right after a restart adds to the first requests; how long that lasts is UNVERIFIED) | The slow tail clusters in the minutes after an `origin-tls: listening` pair and recovers between restarts | UNVERIFIED |
| 2 | TLS termination CPU in the Node process | p50 and CPU move together. Judged unlikely at sub-millisecond per keep-alive request, but that figure is an estimate, not a measurement | UNVERIFIED |
| 3 | Handshakes on new Cloudflare-to-origin connections: under `flexible` a new origin connection costs a TCP handshake; under `strict` it adds a TLS 1.3 handshake and certificate validation (about one extra round trip between the Cloudflare colo and the origin) | A step at 23:43Z that is stable across restarts, present on every path to the same origin (including the Supabase-free control), and visible per Cloudflare colo | UNVERIFIED |
| 4 | `/health` awaits one PostgREST round trip on every request (`users?select=id&limit=1`, 2 s abort, `checkSupabase()` in `server/health.ts`), so its server wait contains a database call whose variance is independent of TLS. The original brief omitted this candidate | The tail follows Supabase latency, the same shape appears on any other path that also calls Supabase, and a Supabase-free same-origin path stays flat regardless of TLS | UNVERIFIED |

##### Isolation procedure (read-only, in order)

Steps A and B need no Cloudflare token. Step C is blocked until the token and subcommand below exist. Nothing here changes production, and no step may be answered by borrowing another token.

**Step A: interleaved A/B against a Supabase-free same-origin control (no token).** At least 100 requests per path over at least 10 minutes, alternating the two paths. The control candidate is `/robots.txt?cb=<rand>`; it is served through Next, so it also passes the Next middleware (an imperfect control), and it is UNVERIFIED that it makes no Supabase call. The control is valid only when `cf-cache-status` is not `HIT` (the random query string is meant to prevent that; check, do not assume). `%header{}` in `curl -w` needs curl 7.84 or newer. **Run time:** 100 requests at one per 6 s take about 11 minutes, longer than one foreground shell call: write the loop to a script, run it in the background and read the output file once it exits (the file, not stdout, is the artifact; do not delete it before the summary step has run).

```bash
OUT=$(mktemp)
FMT='%{http_code}|%{time_connect}|%{time_appconnect}|%{time_pretransfer}|%{time_starttransfer}|%header{cf-ray}|%header{cf-cache-status}\n'
for i in $(seq 1 100); do
  for p in health robots; do
    case $p in health) u="https://app.soleur.ai/health?l=$i-$RANDOM";; robots) u="https://app.soleur.ai/robots.txt?cb=$i-$RANDOM";; esac
    printf '%s|' "$p" >> "$OUT"
    curl --disable --noproxy "*" -s -o /dev/null --max-time 10 -w "$FMT" "$u" >> "$OUT"
  done
  sleep 6
done
# fields: 1 path, 2 status, 3 connect, 4 appconnect, 5 pretransfer, 6 starttransfer, 7 cf-ray, 8 cf-cache-status
for p in health robots; do
  awk -F'|' -v p="$p" '$1==p && $2==200 && $8!="HIT"{print $6-$5}' "$OUT" | sort -n | awk -v p="$p" '{a[NR]=$1} END{print p " server-wait n=" NR " p50=" a[int(NR*0.5)] "s p90=" a[int(NR*0.9)] "s p99=" a[int(NR*0.99)] "s"}'
  awk -F'|' -v p="$p" '$1==p{n=split($7,r,"-"); print r[n]}' "$OUT" | sort | uniq -c | sort -rn | head
done
awk -F'|' '$2!=200{b[$1]++} END{for(k in b) print k " non200=" b[k]}' "$OUT"
rm -f "$OUT"
```

Record `time_connect`, `time_appconnect`, `time_pretransfer`, `time_starttransfer`, the `cf-ray` colo suffix (the second command's counts) and the status; report p50, p90 and p99 per path and per colo. At n=100 the p99 is the second-slowest value, so it is a spread indicator, not a stable estimate.

**Step B: the Supabase leg alone, from a client, over the same hours (no Cloudflare token).** It uses the public anon key, never the service-role key, and the key and the URL go through curl's stdin config so neither appears in argv. The variable NAMES `SUPABASE_URL` (preferred by the server over the custom domain, see `serverUrl()`), `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` come from `apps/web-platform/.env.example` and the server code; that they exist in Doppler `soleur/prd` is UNVERIFIED (check with `doppler secrets --only-names -p soleur -c prd`, names only). It is also UNVERIFIED that `/rest/v1/` answers 200 for the anon key; if it does not, record the status and stop, do not escalate to another key. This measures the client-to-Supabase path, not the origin-to-Supabase path that `/health` actually uses, so it bounds how variable the database leg can be; it does not measure the leg inside `/health`.

```bash
OUT_B=$(mktemp)
doppler run -p soleur -c prd -- bash -c 'for i in $(seq 1 100); do
  printf "url = \"%s/rest/v1/?l=%s\"\nheader = \"apikey: %s\"\n" "${SUPABASE_URL:-$NEXT_PUBLIC_SUPABASE_URL}" "$i" "$NEXT_PUBLIC_SUPABASE_ANON_KEY" \
    | curl --disable --noproxy "*" -s -o /dev/null --max-time 10 --config - -w "%{http_code} %{time_connect} %{time_appconnect} %{time_pretransfer} %{time_starttransfer}\n"
  sleep 6
done' > "$OUT_B"
# fields: 1 status, 2 connect, 3 appconnect, 4 pretransfer, 5 starttransfer
awk '$1!=200{b++} END{print "non200=" b+0}' "$OUT_B"
awk '$1==200{print $5-$4}' "$OUT_B" | sort -n | awk '{a[NR]=$1} END{print "supabase server-wait n=" NR " p50=" a[int(NR*0.5)] "s p90=" a[int(NR*0.9)] "s p99=" a[int(NR*0.99)] "s"}'
rm -f "$OUT_B"
```

**Step C: Cloudflare analytics by hour (needs the token below; blocked until it exists). The block below is the REQUEST SHAPE for the future subcommand, not a command to run: it wraps `bash -c` in `doppler run`, which the wrapper script's contract forbids, and the token and subcommand do not exist yet. It is an HTTP POST that only reads (an analytics query).** A GraphQL POST to `https://api.cloudflare.com/client/v4/graphql` with `Authorization: Bearer`, dataset `httpRequestsAdaptiveGroups`, filter `datetime_geq` and `datetime_lt`, `clientRequestHTTPHost: "app.soleur.ai"`, `clientRequestPath: "/health"`, `requestSource: "eyeball"`, `orderBy: [datetimeHour_ASC]`, dimension `datetimeHour`, and quantiles of the origin response duration. The dataset and those filter keys are documented; the **exact origin-duration quantile field names are UNVERIFIED**, and so is the **per-plan time-range cap** (slice requests to at most 24 h and treat even that as unverified). The `count` selection and the variable type names are likewise UNVERIFIED. First run a schema-discovery query and take the field names from its output, never from this page. The request shape below is what the future subcommand must send; until it exists, running it by hand is not the sanctioned path.

```bash
# 1. Schema discovery (no secret in the query). The jq filter prints type and field NAMES only.
QF=$(mktemp); BF=$(mktemp); export QF BF
echo '{ __schema { types { name fields { name } } } }' > "$QF"
jq -n --rawfile q "$QF" '{query:$q}' > "$BF"
doppler run -p soleur -c prd_terraform -- bash -c 'curl --disable --noproxy "*" -s --max-time 30 --config - < <(printf "url = \"https://api.cloudflare.com/client/v4/graphql\"\nheader = \"Content-Type: application/json\"\nheader = \"Authorization: Bearer %s\"\ndata-binary = \"@%s\"\n" "$CF_API_TOKEN_ANALYTICS_READ" "$BF") \
  | jq -c "{types:[.data.__schema.types[]? | select(.name|test(\"httpRequestsAdaptiveGroups\";\"i\")) | {type:.name, fields:[.fields[]?.name | select(test(\"origin|quantile|duration\";\"i\"))]}], err:(.errors // null)}"'

# 2. The hourly read, after replacing <FIELDS_FROM_DISCOVERY> with names printed above.
cat > "$QF" <<'EOF'
query ($zone: String!, $from: Time!, $to: Time!) {
  viewer { zones(filter: {zoneTag: $zone}) {
    httpRequestsAdaptiveGroups(limit: 100, orderBy: [datetimeHour_ASC],
      filter: {datetime_geq: $from, datetime_lt: $to, clientRequestHTTPHost: "app.soleur.ai", clientRequestPath: "/health", requestSource: "eyeball"}) {
      dimensions { datetimeHour }
      count
      <FIELDS_FROM_DISCOVERY>
    }
  } }
}
EOF
export FROM=2026-11-07T12:00:00Z TO=2026-11-07T23:43:00Z
doppler run -p soleur -c prd_terraform -- bash -c 'jq -n --rawfile q "$QF" --arg z "$CF_ZONE_ID" --arg f "$FROM" --arg t "$TO" "{query:\$q,variables:{zone:\$z,from:\$f,to:\$t}}" > "$BF"
  curl --disable --noproxy "*" -s --max-time 30 --config - < <(printf "url = \"https://api.cloudflare.com/client/v4/graphql\"\nheader = \"Content-Type: application/json\"\nheader = \"Authorization: Bearer %s\"\ndata-binary = \"@%s\"\n" "$CF_API_TOKEN_ANALYTICS_READ" "$BF") \
  | jq -c "(.errors // empty), (.data.viewer.zones[0].httpRequestsAdaptiveGroups[]? | {hour:.dimensions.datetimeHour, n:.count})"'
rm -f "$QF" "$BF"
```

The zone identifier is an identifier, not a credential, so passing it to `jq --arg` is acceptable; the bearer token only ever travels through curl's stdin config, response headers and the request config are never printed, and the discovery `jq` prints names only. Run the hourly read for the windows 2026-11-07T12:00Z to 23:43Z (pre-flip) and 23:44Z to now (post-flip), once for `/health` and once for a Supabase-free path (the Step A control), and compare the quantile fields hour by hour.

**Token prerequisite (a separate change, tracked in #12441).** Step C needs a new token, `CF_API_TOKEN_ANALYTICS_READ` (permissions Analytics:Read and Zone:Read), bound to a **new subcommand** of `plugins/soleur/scripts/cloudflare-readonly.sh`, with **no fallback to any other token** (CTO ruling). State this plainly: the wrapper is a closed, **GET-only** subcommand set, and GraphQL analytics is a **POST** endpoint, so the new subcommand needs a **documented read-only-POST exception** to the wrapper's GET-only contract. Neither the token nor the subcommand exists in this change; creating the token is a credential change that belongs to the owner. The commands above are the request shape the subcommand must reproduce, not a sanctioned manual path.

##### Interpretation (what each outcome would mean; none has been observed)

| Observation | Reads as | Supports |
|---|---|---|
| Step A: the control's p90 is also elevated against its own earlier sample, while `/health` is elevated too | An edge or connection effect shared by every path to this origin | Candidate 3 (or 1, if the tail clusters after restarts) |
| Step A: only `/health` is elevated and the control is flat | App-side or Supabase variance | Candidate 4 |
| Step A re-run now: neither path differs from the pre-flip baseline | Small-sample noise (n=30 spread) | None; close the item |
| Step A: the tail clusters in the minutes after an `origin-tls: listening` pair | Post-restart warm-up | Candidate 1 |
| Step B: the Supabase leg alone shows the same tail shape as `/health` | The database leg dominates the tail regardless of TLS | Candidate 4 |
| Step C: a step in origin duration at 23:43Z, stable across restarts and across colos | The flip itself | Candidate 3 (or 2 if it tracks CPU) |
| Step C: no step at 23:43Z, but the tail follows restarts | Redeploy warm-up | Candidate 1 |
| Step C: a `/health`-only step with a flat control path | App-side or Supabase variance | Candidate 4 |

Step A cannot prove the flip caused anything: no pre-flip control sample exists, so it localizes the effect (edge versus app) rather than attributing it. The only decisive test of the strict-mode effect would be a controlled flip-back, which is production-mutating, is the owner's decision, and is not proposed here.

##### Marker ruling: no in-app `SOLEUR_HEALTH_TIMING` marker now

Ruled by the CTO agent, 2026-11-08: the procedure above answers the question without a code change, so no timing marker is added in the follow-ups PR. Revive the marker if any one of these happens: (1) the Supabase-free control also regresses by more than 50 ms at p90; (2) Cloudflare origin duration shows a step change aligned with the flip; (3) a user-facing latency complaint arrives.

If revived, the shape is: a `warn`-level line (Vector drops INFO, so an info marker would never reach Better Stack) named `SOLEUR_HEALTH_TIMING` with the fields `total_ms`, `supabase_ms`, `tls` and `protocol`; emitted AFTER the response is written, inside try/catch; only when `total_ms > 500`, plus a 1-in-50 sample; at most 6 lines per minute; the response body and status unchanged (`health-keyword-monitor-contract.test.ts` pins the body the monitors read).

##### Still unverified (do NOT record as verified)

- The cause of the p90 rise after the flip; whether it is a regression at all rather than n=30 noise.
- That `strict` changes user-facing latency in either direction.
- Every candidate in the table: redeploy warm-up, TLS CPU in Node, new-connection handshakes under `strict`, and the per-request Supabase round trip in `/health`.
- That `/robots.txt` makes no Supabase call and is never served from the Cloudflare cache; that it is a fair Supabase-free control.
- That `/rest/v1/` answers 200 for the public anon key, and that the three variable names exist in Doppler `soleur/prd`.
- The exact origin-duration quantile field names, the `count` selection, the variable type names, and the per-plan time-range cap of the Cloudflare GraphQL analytics API; that schema introspection is permitted for the future token.
- That the sub-millisecond-per-request TLS CPU figure holds on these hosts.
- Per-colo behaviour: no per-colo data has been collected.
- Whether the 11 restart pairs between 01:05Z and 16:17Z coincide with any tail samples (no per-pair times are recorded here).
- That the token `CF_API_TOKEN_ANALYTICS_READ` and its wrapper subcommand will be accepted (the POST exception is a design change, not yet reviewed).

##### Addendum 2026-11-09: origin response time for /health (Cloudflare analytics)

Read this first: this addendum supersedes the "Token prerequisite" paragraph, the Step C text that says the token and subcommand do not exist, and the "Real 502/520 rate" row of the open-checks table below. Those rows are left as written (additions-only: this addendum is inserted in the p90 section ahead of "What was NOT run before the flip", and no earlier line of the file was edited); what changed is stated at the end of this addendum. It is conditioned on the merge of the change that adds the subcommands (Ref #12441, #10479, #10205). No cause is claimed for anything below.

Every figure in the first two lists is **owner-supplied, not re-derived by this wrapper**: the owner ran the first query live against Cloudflare GraphQL `httpRequestsAdaptiveGroups` (path filter `/health`, hourly groups) before this change; nothing here was re-read by an agent.

**Origin response time for `/health`, hourly rows (owner-supplied, not re-derived)**

- Window: 217 hourly rows, 2026-10-31T20Z to 2026-11-09T20Z.
- Before the flip (171 h): median hourly p50 332 ms, median hourly p90 477 ms.
- After the flip (45 h): median hourly p50 269 ms, median hourly p90 855 ms.
- Daily median hourly p90: 462 to 645 ms for each day from 11-01 to 11-07 (11-02 was the highest, 645 ms), then 851 ms on 11-08 and 859 ms on 11-09.
- The step coincides with the strict flip at 2026-11-07T23:43Z.
- p50 did not rise; only the tail did (about +385 ms).
- The tail clusters near 850 ms and 1390 ms.

**Figures that do not agree with each other (recorded, not fixed, not reconciled)**

- 171 h + 45 h is 216, against the 217 rows stated for the window. The hour 2026-11-07T23Z straddles the flip and the owner's split does not say where it went.
- The difference of the stated p90 medians is 855 - 477 = 378 ms, against "about +385 ms". The owner's figure was not re-derived, so which pairing gives +385 ms is not known.

**What the code on this branch says about keep-alive (read by this change, not measured)**

- The plain `:80` server (`apps/web-platform/server/index.ts`) and the `:443` TLS listener (`apps/web-platform/server/origin-tls.ts`) both assign `keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS` (905000 ms, defined once in `origin-tls.ts`). A shorter keep-alive on `:443` than on `:80` is therefore ruled out as a configuration difference today. It was not always equal: the `:80` server ran Node's 5 s default until PR #12181 (merged 2026-11-06, commit `08a57c642a`) added the assignment, and this file does not record when that change deployed, so the pre-flip window of 171 h (from 2026-10-31T20Z) may span both `:80` settings.
- The remaining candidates are NOT separated by anything in this addendum: candidates 1, 2, 3 and 4 of the table above, in particular a new-connection TLS handshake on the Cloudflare-to-origin hop, redeploy restarts, TLS CPU and (candidate 4) the `/health` PostgREST round trip. The tail clusters above are a description of the data, not evidence for any one of them. A controlled flip-back is the owner's production decision and is not proposed here.

**5xx histogram (502, 520, 525, 526 and the other 5xx statuses)**

| Row | Status |
|---|---|
| Edge 5xx counts by hour and status, 216-hour window | `not yet read; first sanctioned read after merge` |

The exact command, run from a fresh checkout where `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` is empty:

```text
doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh analytics-edge-errors 216
```

The matching `/health` read is the same command with `analytics-health 216`. No wrapper run is recorded in this addendum; a result is recorded in a second dated addendum after the first sanctioned read, and the `not yet read` row above is then left as written. Both reads are `Unverified:` records, never `Checked:`, and `rows: 0` is never recorded as "no errors".

**Caveats that apply to any figure read with the new subcommands**

- Counts are sampled estimates (adaptive sampling); never compute an exact error rate from `count`.
- The dataset may under-report edge-generated blank 502/503/504 pages.
- The `/health` query is filtered by path only: it is not scoped to a host or to `requestSource`.
- Complete hours only, so the series lags by up to one hour.
- The window maximum is 216 hours, so it cannot reproduce the owner's 217-row window.
- The status dimension, the status range operators, `_DESC` ordering and the quantile field names for this dataset are not documented publicly; they are unverified until the first sanctioned read returns `ok`.

**Median of the hourly p90, to reproduce the owner's before/after comparison.** The input is the stored second output line of `analytics-health 216` (the evidence file `knowledge-base/engineering/operations/runbooks/evidence/<UTC date>-analytics-health-216h.json`, which is created by the post-merge follow-up and does not exist in this change). `--arg lo` is the first hour included, `--arg hi` the first hour excluded, both as `YYYY-MM-DDTHH:MM:SSZ` strings that sort as text. Run once for the hours before the flip and once for the hours after it (record the row count each median used: the 216-hour window ends before the read, so the earliest hours of the owner's range may fall outside it), and exclude the straddling 2026-11-07T23Z hour from both medians (state that in the record). Default pairs: before `--arg lo 2026-10-31T20:00:00Z --arg hi 2026-11-07T23:00:00Z`, after `--arg lo 2026-11-08T00:00:00Z --arg hi <the first hour after the last row>`:

```bash
jq --arg lo "<first hour included>" --arg hi "<first hour excluded>" \
  '[.series[] | select(.hour >= $lo and .hour < $hi and .p90_ms != null) | .p90_ms] | sort
   | length as $n | if $n == 0 then null elif $n % 2 == 1 then .[($n - 1) / 2] else (.[$n / 2 - 1] + .[$n / 2]) / 2 end' \
  <evidence file>
```

**Handoff for the post-merge read (ready to paste)**

Authority: the two reads are Class R and need no typed go from the owner; merging a wrapper fix PR (if the first read fails) is not Class R and does.

1. Preflight, from a checkout rebased onto the merged main: `git fetch origin main`, then `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` must print nothing. If it does, rebase onto `origin/main` and repeat; if it is still non-empty record `other: wrapper-drift` and stop.
2. Run both reads and keep an output only when the exit code is 0, line 1 is exactly `cloudflare-readonly: <subcommand> ok` and line 2 parses with `jq -e .`; never store stderr or an `unverified` line. The not-kept line is for the terminal only: record the reason token in the second addendum, never the parenthetical:

```bash
d=knowledge-base/engineering/operations/runbooks/evidence; mkdir -p "$d"
for sub in analytics-health analytics-edge-errors; do
  err=$(mktemp); out=$(doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh "$sub" 216 2>"$err"); rc=$?
  line1=$(printf '%s\n' "$out" | sed -n 1p); f="$d/$(date -u +%F)-$sub-216h.json"
  if [ "$rc" -eq 0 ] && [ "$line1" = "cloudflare-readonly: $sub ok" ] && printf '%s\n' "$out" | sed -n 2p | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "$out" | sed -n 2p > "$f" && echo "kept $f"
  else
    echo "$sub: not kept, rc=$rc, stdout line 1: ${line1:-none}, stderr line 1: $(sed -n 1p "$err")"
  fi
  rm -f "$err"
done
```

3. Record each result as an `Unverified:` line in a second dated addendum (keys `Cloudflare analytics-health (F) #12441` and `Cloudflare analytics-edge-errors (G) #12441`), then act on the table below. At most two fix PRs in total across both queries.

| Wrapper output | Meaning | Next action |
|---|---|---|
| `unverified - api-error (graphql: unknown field ...)` | a field or filter name in a fixed query is wrong for this dataset | a fix PR to the wrapper (cap two in total across both queries); record `other: api-error` only, the parenthetical is data and is never copied |
| `unverified - api-error` (plain) | the vendor message did not pass the message gate | re-run once; if it repeats it counts as a fix PR (same cap) |
| `unverified - bad-response (shape)` or `(jq exit n)` | the vendor shape differs from the query's assumptions | a fix PR to the wrapper (same cap) |
| `unverified - upstream-error (...)` | 429, 5xx or a curl failure | one re-run after a pause, then record `other: upstream-error`; not a fix PR |
| `unverified - not-found` or plain `unverified - bad-response` | HTTP 404, or a non-numeric status | re-run once; if it repeats record `other: not-found` or `other: bad-response`; not a fix PR |
| `unverified - token-lacks-scope` | HTTP 403: the token lacks the zone scope | the owner's credential change; record `other: token-lacks-scope`; never answer with another token |
| `unverified - no-zone-access` | the zone is not visible to the token, or the zone id is wrong (not told apart) | check the zone id and the token's zone |
| `unverified - token-invalid` | the token is expired or revoked (it expires 2027-02-07) | rotation is the owner's credential change |
| `unverified - no-credential (<name>)` | the Doppler config lacks that variable | add it to the config; never borrow another token |
| `unverified - no-tool (jq or date)` | the host lacks the tool | record `no-tool` |
| no wrapper line on stdout | the wrapper wrote one fixed line to stderr only (exit 64 or 78), or doppler itself failed | read the printed `stderr line 1` and `rc`: rc 64 with a refused source or token shape is `other: refused-source` (a usage error records nothing, re-run correctly); rc 78 is `other: xtrace`; a doppler login or config error is `Unverified: no-credential` |

**Reconciliation with Step C and the token description above**

- Step C's request shape listed `clientRequestHTTPHost` and `requestSource: "eyeball"`. The owner-proven first query drops both and filters on the `/health` path only, so the `/health` series is not host- or `requestSource`-scoped.
- The "Token prerequisite" paragraph says Analytics:Read and Zone:Read. The owner-supplied description of the minted token is Analytics:Read on one zone, expiring 2027-02-07.

**Other results recorded 2026-11-09 (owner-supplied, not re-derived by this change)**

- Live-verify against production passed on 2026-11-09, as reported by the owner: `RESULT: PASS fresh conversation persisted and appeared in the rail via=reload elapsed=48s checks=33`. This change did not re-derive it: the CI log was searched and the line was not found. Search snapshot (the set of runs moves as new runs land): the 20 newest runs of `web-platform-release.yml`, by `gh run view <id> --log` limited to the first matching line per run. First pass on 2026-11-09 (newest run 42693428412): `RESULT: PASS` matched only the workflow's own script text in 8 of 20 runs, and `appeared in the rail via=` over those found no line. Re-run at about 2026-11-09T23:30Z (newest run 42717430338, created 23:04Z): script-text matches in 7 of 20 runs, no `appeared in the rail via=` line. This is not a failure of the check; it means the line was not located.
- WebSocket upgrade through the strict hop returned `101` (unauthenticated; not a signed-in check). The owner's brief puts it at 2026-11-08T14:49:20Z. The comment on #10479 (issuecomment-6725639019, an agent session, posted 2026-11-08T18:54:17Z) reports the same unauthenticated `101 Switching Protocols` result in its bake re-check at 16:35-16:37Z. The two times conflict and neither was re-derived; this change claims neither as the probe time. It shows an upgrade through the strict hop only: the signed-in WebSocket run is not done.

**What changed in the status tables above.** As of the merge of this change, the token `CF_API_TOKEN_ANALYTICS_READ` exists (per the owner; this change did not read Doppler) and `plugins/soleur/scripts/cloudflare-readonly.sh` has the subcommands `analytics-health` and `analytics-edge-errors` (fixed read-only GraphQL queries sent as a POST; see ADR-289 and `standing-delegation.md` section 9), so Step C is runnable through the wrapper after the merge, from a checkout that matches `origin/main`. Until a sanctioned read is recorded, the "Real 502/520 rate" row stays open and every analytics figure above is the owner's, not the wrapper's.

#### What was NOT run before the flip

- The local read-only plan (Act 0): not run. The flip plan itself (1 change) was read after the fact in the apply log.
- The Sentry `feature:origin_tls` read and the `pagerules-ssl` check: last read at about 19:58Z on 2026-11-07 (0 events; 0 active page rules; reported in PR #12341), not re-run immediately before the flip.
- Doppler activity log, `prd_terraform` writes in the window (account `ops@jikigai.com` for every entry, secret names not shown): 22:54:34Z (1 updated), 23:41:47Z (1 added, discussed above) and 00:13:25Z (1 updated). The 22:54:34Z and 00:13:25Z writes are **not attributed** here.

##### Verify `origin-tls-event` is live (read-only; run after the merge-triggered apply)

1. `gh run list --workflow apply-sentry-infra.yml --branch main --limit 3 --json databaseId,conclusion,headSha,createdAt`. Expected: a run whose `headSha` is the merge commit of PR #12434 or a later one on `main`. A `conclusion: success` alone is not enough: the kill switch (`[skip-sentry-apply]` on its own line of the merge commit message) skips the apply steps and the run can still end green.
2. `gh run view <databaseId> --json jobs --jq '.jobs[] | select(.name | test("apply"; "i")) | .steps[] | select(.name | test("Terraform apply|live fidelity")) | {name, conclusion}'`. Expected: both steps, `Terraform apply (cron + uptime monitors)` and `sentry_alert live fidelity (AC19/AC20)`, with `conclusion: success`. `skipped` on either, or no output at all (the kill switch skips the whole `apply` job), means nothing was applied or compared, so the rule is still **DECLARED**. The fidelity step compares every declared `sentry_alert` field by field against live Sentry and fails the run on a divergence; a pass is the evidence the rule exists live as declared.
3. After the next scheduled `Sentry Alert Drift Detection` run (`scheduled-sentry-alert-drift.yml`): `gh issue list --label ci/sentry-alert-drift --state open --json number,title`. Expected: no open issue. That probe compares live Sentry with the committed `alert-reference.json`, which this PR extends with `origin-tls-event`. Optionally read the org workflows endpoint (README section "Audit") and look for the rule named `origin-tls-event`; the fidelity step in 2 already checks its fields, so this read is a convenience, not a gate.

If step 1 shows no run for the merge commit, or step 2 shows `skipped`, `failure` or no output, the state stays **DECLARED**. Do not write "live" anywhere until steps 1 and 2 pass.

### Open checks (plainly)

| Check | Owner of the check | State |
|---|---|---|
| Signed-in WebSocket connects through the edge under `strict` (the upgrade path has never been exercised through the TLS hop by a probe) | **owner** (no probe exists) | open |
| +1 h and +24 h rechecks (the 30-request loop and the Sentry query), rollback kept armed for the whole window | whoever runs the soak | pending |
| Sentry `feature:origin_tls` | anyone with the read token | not re-read after the flip. The alert rule `origin-tls-event` (any `feature=origin_tls` event, `frequency_minutes` 47) is **DECLARED** in the follow-ups PR; it is live only after the merge-triggered `apply-sentry-infra.yml` run has been read (see "Verify the rule is live" below). Until then the pull-based query in "Sentry check" is the only check |
| Real 502/520 rate over a fixed window (Cloudflare analytics) | **owner** mints the token, then the **agent** runs it (no sanctioned reader until then) | open. A read-only reader needs the `CF_API_TOKEN_ANALYTICS_READ` token and a `cloudflare-readonly.sh` subcommand (with a documented read-only-POST exception), tracked in `#12441`; see "/health p90 after the strict flip" Step C |
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

Until the release carrying PR #12388 is deployed, the startup line does not print whether `ORIGIN_TLS_REQUIRED` was in effect, so "REQUIRED is live" is proven by ORDERING (the Doppler write precedes a green redeploy,
which precedes fresh per-host lines), not read directly. From that release on, the `origin-tls: listening` line carries `required: true|false` (read it with the `required=` command below; production rows that predate it print `required=null`).

**Listener events after the bind (ADR-321 item 11, ruled 2026-11-08).** Before the bind, a listener `error` is fatal under REQUIRED (the candidate container fails). After it: an unexpected `close` of the https server is reported
(`tags.reason=unexpected-close`) and is fatal under REQUIRED, so `--restart unless-stopped` restarts the container; a server `error` is reported at most once a minute (`extra.suppressed` counts the rest) and the process keeps serving.
**A dead :443 that raises neither event** (a docker-proxy or iptables failure, a rejected certificate) is not detected in-process. The detectors are the Better Stack `app`/`app_health` monitors (a page after roughly 4 to 6 minutes) and the
https LB monitor (an "Unhealthy" email only; web-1 is never drained). **No Sentry alert rule for `feature:origin_tls` is live**: the rule `origin-tls-event` is DECLARED in the follow-ups PR and is live only after the merge-triggered `apply-sentry-infra.yml` run is read, so a Sentry event is a pull-based check until then. Recovery for a dead
:443 is a redeploy.

## Act 0 - read-only preconditions before act 3 (anyone; all runnable; the Expected column is the PRE-FLIP state)

| Check | Command | Expected |
|---|---|---|
| Doppler names only | `doppler secrets --only-names -p soleur -c prd \| grep ORIGIN_TLS` and `doppler secrets --only-names -p soleur -c prd_terraform \| grep ENABLE_ORIGIN_TLS` | `ORIGIN_TLS_CERT_B64`, `ORIGIN_TLS_KEY_B64`, `ORIGIN_TLS_REQUIRED`; and only `ENABLE_ORIGIN_TLS_CANARY_RULE` (strict absent). Never print values |
| Both hosts listening on the minted certificate, and `required` per host | `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 6h --grep 'origin-tls: listening' --limit 300 \| jq -r '.raw \| fromjson \| select(has("CONTAINER_NAME")) \| select(tostring \| contains("origin-tls: listening")) \| "\(.SYSLOG_TIMESTAMP) host=\(.host) required=\(.message.required)"' \| sort \| tail` (the pino fields are an OBJECT at `.message`, verified against production rows on 2026-11-08; rows from before PR #12388 print `required=null`) | fresh lines for `soleur-web-platform` AND `soleur-web-2` after the act 2 redeploy, and `required=true` on both once the release carrying PR #12388 is live; (the same rows carry `fingerprint256` 7B:E5:11:D0... and `daysLeft` about 5474 inside the pino message) |
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
window is an **owner act** (Cloudflare dashboard, Analytics, status codes 502 and 520-526 for `app.soleur.ai`, same window before and after) until `#12441` lands, after which the agent reads it through the subcommand.

Sentry check (GET only; token NAME `SENTRY_ISSUE_RO_TOKEN`, Doppler `soleur/prd`; `scripts/sentry-issue.sh` has no feature-search mode, so this is the exact call):

```bash
doppler run -p soleur -c prd -- bash -c 'curl --disable --noproxy "*" -s --max-time 30 -G "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/" \
  --data-urlencode "field=timestamp" --data-urlencode "field=message" --data-urlencode "field=host_name" --data-urlencode "field=phase" --data-urlencode "query=feature:origin_tls" \
  --data-urlencode "statsPeriod=24h" --data-urlencode "dataset=errors" --data-urlencode "per_page=20" \
  --config - < <(printf "header = \"Authorization: Bearer %s\"\n" "$SENTRY_ISSUE_RO_TOKEN") | jq -c "{n:(.data|length), err:(.detail // null)}"'
# control (must return rows, or the zero above means nothing): swap the query for "has:feature"
```

Reading a Sentry event: `feature=origin_tls`, `op` is `load`, `create` or `listen`; `tags.reason` names the cause; `tags.phase` (listen events only) is `startup` (the bind failed: fatal under REQUIRED, the candidate container
fails) or `runtime` (after the bind). A `phase:runtime` event means the listener was up and then raised a server `error` (reported at most once a minute; the process continues) or closed unexpectedly (`reason=unexpected-close`; fatal under
REQUIRED, so the container restarts): look at the host's restart count and its `origin-tls: listening` rows. The query `feature:origin_tls phase:runtime` and `field=phase` were accepted by the API (HTTP 200) on 2026-11-08, but
**no event carrying `phase` exists yet, so the tag path is not verified against a real event** (a `has:phase` control returned 0).

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
