# Runbook: Querying Better Stack logs (historical, programmatic)

**TL;DR:** Use [`scripts/betterstack-query.sh`](../../../../../scripts/betterstack-query.sh) under `doppler run -p soleur -c prd_terraform`. It queries the ClickHouse HTTP SQL API. The ingest token is write-only; reading historical logs needs a dedicated ClickHouse *connection* (already provisioned — creds in Doppler).

```bash
# Last 1h of app logs mentioning a cron, excluding host-metric noise:
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 1h --grep cron-roadmap-review --raw-only --limit 50

# Arbitrary SQL (write the literal token $BS_TABLE for the remote() arg):
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh \
  'SELECT count() AS n FROM remote($BS_TABLE) WHERE dt >= now() - INTERVAL 2 HOUR FORMAT JSONEachRow'
```

## Standing alarms over this source (log-content recurrence alarms)

A **log-*content* recurrence alarm** over this Better Stack Logs source is an **in-repo GitHub-Actions
cron poller**, NOT a native Better Stack alert — query via `betterstack-query.sh` → decode/threshold
in a `scripts/` checker → deduped `action-required` GitHub issue → Sentry self-liveness heartbeat.
This is the reusable **"Pattern: Better Stack log-content alarms"** recorded in
[`ADR-096` §Consequences](../../architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md)
(the `better-uptime` TF provider has no log-alert resource — the sibling `BetterStackHQ/logtail`
provider does, and [ADR-218](../../architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md)
uses it for the one signal class ADR-096 exempts: a pure stateless per-bucket count with an
email-acceptable surface; the Telemetry v2 SQL-alert route stays rejected for stateful/newest-scoped
signals + the operator-surface reasons documented there).

Live standing alarms over this source:

- **`logtail_exploration_alert.monitor_send_failed`** (#8097 / ADR-218, evaluated every 60 s over
  a 300 s window) — the one Terraform-managed native Better Stack Logs alert, `soleur-monitor-send-failed-prd`. Pages
  (team email; `betteruptime_policy.uptime` on the paid tier) on any PRIORITY-2 row whose message
  starts `SOLEUR_` and contains `_SEND_FAILED` or `_REFUSED` — a web-1 monitor unit's own Resend/
  Sentry send failed. `SOLEUR_*_SEND_SKIPPED` and `SOLEUR_*_HALT` never match by construction.
  Defined in `apps/web-platform/infra/betterstack-logs-alerts.tf`; verified through the real apply
  path by `terraform_data.send_failed_alert_probe` + `scripts/followthroughs/send-failed-alert-probe-8097.sh`;
  self-health via the `logs_alert` arm of `reconcile-live-heartbeats.ts`. Runbook:
  [`monitor-send-failed-alert.md`](./monitor-send-failed-alert.md). Readback (never
  `--grep PRIORITY=2`): the runbook's step-1 SQL with `JSONExtractString(raw,'PRIORITY') = '2'`.
- **`logtail_exploration_alert.inngest_luks_wrong_volume`** (#6894 / ADR-142, evaluated every 300 s
  over a 5400 s window) — `soleur-inngest-luks-wrong-volume-prd`. Pages when the dedicated Inngest
  host's hourly `SOLEUR_INNGEST_SERVER_PROBE` row reports `/mnt/data` backed by a by-id alias that
  is **not** the encrypted volume's — i.e. Redis is writing unencrypted again after the cutover
  (an on-host rollback, a reboot that took the pre-cutover arm, or a replace whose first boot
  resolved the plaintext volume). Nothing else notices: the scheduler is healthy in all three.
  **Armed.** It shipped paused, because before the cutover the plaintext alias was the CORRECT
  value and an armed rule would have paged continuously. Since #8296 the variable's declared
  default is `true`, so every apply arms it: the push apply of `b53173a04` did so, and the alert
  read back `paused=false` on 2026-09-21. No `-var` flag and no tfvars entry is involved. The watched alias is built from
  `hcloud_volume.inngest_redis_luks.id`, never a literal. Defined in
  `apps/web-platform/infra/betterstack-logs-alerts.tf`; drift guard
  `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` (6 mutation rows).
  Runbook: [`inngest-luks-cutover-6894.md`](./inngest-luks-cutover-6894.md). Readback:
  `--grep SOLEUR_INNGEST_SERVER_PROBE` and read `data_mount_devid` on the `host_role=dedicated` row.
- **Anthropic spend, three alerts** (#8611 / ADR-243; drift guard
  `apps/web-platform/test/infra/inngest-step-524-alert.test.sh`). All three are aggregates only,
  so the email names the condition, never a row:
  - **`logtail_exploration_alert.inngest_step_524`** (every 300 s over 900 s) —
    `soleur-inngest-step-524-prd`. Pages on any inngest-server journald row whose `message.error`
    contains one of three texts, all meaning "the server lost a step's response":
    `invalid status code: 524` (a step outlived Cloudflare's ~100 s origin timeout — should not
    recur under streaming), `error parsing stream: error reading response body` and
    `Your server reset the connection while we were reading the reply` (a STREAMED step response
    dropped mid-flight; both measured in the #8611 spike). **A web deploy that kills a running step
    also matches**, so check the deploy log for the page's window first. These rows are PRIORITY 6
    and ship only because `vector.toml`'s `inngest_journald` unit match admits them despite its
    PRIORITY 0..4 list (observed; #6551).
    Readback, no SSH, no pipe:
    1. `doppler run -p soleur -c prd_terraform -- bash scripts/probe-inngest-524-count.sh` prints
       `count=<n>` for the last 24 h and `unit_rows=<m>` on stderr. `unit_rows=0` exits 3: the
       inngest-server path is dark, so a quiet count means nothing.
    2. Was a second paid session started? The per-run cost marker's run id is the field **`id`**
       (not `run_id`, which is the filing-deny marker's). Over the page's window:

       ```sql
       SELECT JSONExtractString(raw, 'message', 'id') AS run, count() AS markers
       FROM (SELECT dt, raw FROM remote($BS_TABLE)
             UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
       WHERE dt > now() - INTERVAL 1 DAY
         AND raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
         AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'
       GROUP BY run HAVING count() > 1 FORMAT JSONEachRow
       ```

       Any row is a duplicate spawn. Then search Sentry for `inngest.run_id:<run>`.
    3. The Sentry ops that say what the single-flight guard did (feature `cron-claude-eval`):
       `claude-eval-singleflight-join` — a retry reached the live child (or its settled result),
       one marker, **the guard worked**; `claude-eval-singleflight-no-runid` — a spawn had no
       well-formed run id, **the guard was bypassed**, investigate. Feature `inngest-serve`, op
       `inngest-stream-consumer-cancel` — a step stream's consumer disconnected (one event per drop;
       its tags name the function, step and whether the request was signed).
  - **`logtail_exploration_alert.claude_cost_daily_burn`** (hourly, trailing 24 h) —
    `soleur-claude-cost-daily-burn-prd`. Pages when the cron `SOLEUR_CLAUDE_COST` markers' summed
    `cost_usd` exceeds **$25** (`local.claude_cost_daily_burn_usd`; recalibration on #8613). The sum
    is a FLOOR: a marker with a null `cost_usd` (a timeout, a no-result or parse-error exit, the
    HTTP-transport crons compound-promote / weekly-release-digest / the credit probe) sums as $0,
    and a run killed mid-flight emits no marker. Rank the spend with the per-source SQL under
    [Querying Anthropic cost markers](#querying-anthropic-cost-markers-soleur_claude_cost--_daily).
    A single source far above its `--max-budget-usd` cap (`server/inngest/cron-budgets.ts`), or two
    markers per run `id` (the query under the 524 alert above), is the lead.
  - **`logtail_exploration_alert.claude_cost_capture_dark`** (hourly, trailing 24 h) —
    `soleur-claude-cost-capture-dark-prd`. Pages when 24 h holds no cron cost marker with a
    non-null `cost_usd` AND no credit-probe RED row (`op=anthropic-credit-exhausted` /
    `anthropic-key-invalid`). The marker path is broken (the emitter, Vector, or the field moved
    again), so the burn alert above is blind. An out-of-credit day stays quiet: that page is the
    `anthropic-credit-exhausted` Sentry issue alert (the credit probe's own cron monitor is
    routed since #8630 but muted, #8704).
- **`scheduled-zot-restart-loop.yml`** (#6291; hourly, dispatched by the web-server watchdog clock since #8495 with a GHA-cron fallback — see `inngest-server.md` "How the external watchdogs are triggered") — the zot registry restart-loop
  recurrence alarm. Reads the `SOLEUR_ZOT_DISK` marker, fires a deduped `[ci/zot-restart-loop]`
  issue on a newest-`boot_id` OOM/crash-loop and a `[ci/zot-telemetry-silent]` issue if the
  reporter goes dark. Checker: `scripts/zot-restart-loop-alarm.sh` (shared parse helper
  `scripts/lib/zot-telemetry-parse.sh`); self-liveness `sentry_cron_monitor.zot_restart_loop_alarm`.
  Dry-run: `doppler run -p soleur -c prd_terraform -- bash scripts/zot-restart-loop-alarm.sh`.
  - **Also reads `SOLEUR_PRIVATE_NIC`** (#6415 / ADR-115) — the registry host's own assertion
    that its private IP (`10.0.1.30`) is configured. Carried as an **independent** verdict
    (`NIC_ALARM_VERDICT`, deliberately NOT in the exit code) and firing three deduped
    `[ci/registry-private-nic]` classes: *host has no private NIC* (terminal),
    *boot race self-healed* (advisory — a successful heal emits `nic_ok=true`, so the terminal
    branch structurally cannot see it), and *guard went dark* (absence).
    Query: `… --grep SOLEUR_PRIVATE_NIC`. Decode: `imds_rc!=0` → H1 (metadata-service blip);
    `imds_rc=0 && imds_nets=0` → H2 (the `hcloud_server_network` additive online-attach race);
    `imds_nets>0 && converged_by!=already` → the attach landed and the guest never configured it.
    **If zot is reported unreachable, rule the private NIC out FIRST** — #6400 was 14 days of
    "zot mysteriously down" that was actually a missing NIC, and a NIC-less host keeps public
    egress so every other signal here stays green.
- **`scheduled-followthrough-sweeper.yml`** — one-shot soak follow-throughs (e.g.
  `scripts/followthroughs/zot-restart-plateau-6288.sh`) recur the same query+decode shape.

## ⚠️ A "no creds" / TRANSIENT error is NOT "no access" (repeat misdiagnosis)

`betterstack-query.sh` does **not** read Doppler itself — it needs the query creds
**injected** via `doppler run`. Run it in a bare shell and it exits with
`BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not set`; a follow-through that wraps it
(e.g. `chardevice-wedge-nonrecurrence-5934.sh`) then reports `TRANSIENT: … auth/config/network`.

**Neither means this session lacks Better Stack access.** Both mean the call was not
wrapped in `doppler run`. The fix is always the same — re-run:

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh <args>
```

Do NOT conclude "I can't verify from here" and stop. This mistake has now happened
twice (the note below, and #5934); the script's error message itself now spells out
the correct invocation. See hard rule `hr-verify-repo-capability-claim-before-assert`
— a fail-safe/degraded probe output is *inconclusive*, never proof of a capability gap.

## Why this exists (the three-token trap)

Better Stack has **three** distinct credentials and it is easy to reach for the
wrong one (we initially skipped log-querying believing we lacked access — we did
not):

| Credential (Doppler `soleur`) | Scope | Use for |
|---|---|---|
| `BETTERSTACK_LOGS_TOKEN` (`prd`) | **ingest only** (write) | Vector → Better Stack shipping. CANNOT read. |
| `BETTERSTACK_API_TOKEN` (`prd_terraform`) | Telemetry mgmt API | sources, **connections**, metadata. NOT log content. |
| `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` (`prd_terraform`) | ClickHouse HTTP read | **reading historical logs/metrics via SQL** |

The query creds are a ClickHouse HTTP *connection* — a username/password pair
Basic-auth'd against a regional ClickHouse endpoint, separate from both tokens.

## Connection details (provisioned 2026-06-01)

- Source: `soleur-inngest-vector-prd` — id **2457081**, team **520508**, table_name `soleur_inngest_vector_prd_3`, `data_region` `eu-central-1a`, **90-day log retention**.
  **(#7772) CORRECTED 2026-09-04 — this line read `region eu-fsn-3, 3-day log retention` and both halves were wrong.** The region is a vendor RENAME, not a move (see the naming note below). The retention was a FREE-TIER value that predates the 2026-08-16 move to a paid plan; measured twice on two endpoint shapes (`GET /api/v2/sources` and `GET /api/v2/sources/<id>`), this source reports `logs_retention=90` and `metrics_retention=90`. The stale figure had propagated into the Art. 30 register and both published legal documents, all corrected in the same change. `logs_retention` is a PER-SOURCE attribute, not a billing field — so read it here rather than inferring it from the account tier, which genuinely cannot be pulled (`/sources/<id>/usage`, `/usage`, `/billing` all 404).
- Source: `soleur-git-data-prd` — id **2734275**, team **520508**, table_name `soleur_git_data_prd`, `data_region` `eu-central-1a`, **90-day log retention**, ingesting host `s2734275.eu-central-1a.betterstackdata.com`. git-data's OWN source since #7772. `remote()` identifier: `t520508_soleur_git_data_prd_logs`.
- **Region naming, so nobody re-derives it:** `eu-fsn-3` and `eu-central-1a` are the SAME cluster — the former is the vendor's earlier name, CNAMEs to the latter, and both resolve to an identical five-address A set (`195.63.225.49/.50/.53/.70/.72`, measured 2026-09-04). Query creds are region-scoped, not source-scoped, so ONE connection reaches BOTH sources.
- Query host: `eu-central-1a-connect.betterstackdata.com` (region-scoped — creds fail against other clusters).
  **(#7898) CORRECTED 2026-09-09 — this line named the stale `eu-fsn-3` connect hostname, with an explicit `:443`.** (The dead string is not reproduced here: a grep for it is an acceptance criterion, and a corrective note that keeps the token alive defeats the check.) Pulled read-only from the config the workflows actually inject (`doppler secrets get BETTERSTACK_QUERY_HOST -p soleur -c prd_terraform --plain`), the live value is `eu-central-1a-connect.betterstackdata.com`, with no explicit `:443`. This is a stale NAME, not a wrong cluster — per the naming note above, `eu-fsn-3` and `eu-central-1a` are the same cluster and the old name still resolves. Both values share the `betterstackdata.com` apex, which is what `scripts/betterstack-query.sh`'s allowlist pins.
- `remote()` table identifier: **`t<TEAM_ID>_<table_name>_logs`** → `t520508_soleur_inngest_vector_prd_3_logs`. The docs' `t123456_...` placeholder is the **team id**, not the source id. (Suffixes: `_logs`, `_metrics`, `_spans`.)

## Re-minting the query connection (if creds are lost/rotated)

Fully automated via the Telemetry API — **no dashboard click-path needed**:

```bash
TOK=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -sS -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  --data '{"client_type":"clickhouse","team_ids":[520508]}' \
  https://logs.betterstack.com/api/v1/connections
# → 201 {data:{attributes:{host,port,username,password,data_region}}}
```

Then store (never echo the password):

```bash
doppler secrets set BETTERSTACK_QUERY_HOST=<host>     -p soleur -c prd_terraform --no-interactive
doppler secrets set BETTERSTACK_QUERY_USERNAME=<user> -p soleur -c prd_terraform --no-interactive
printf '%s' "<password>" | doppler secrets set BETTERSTACK_QUERY_PASSWORD -p soleur -c prd_terraform --no-interactive
```

List existing connections: `GET https://logs.betterstack.com/api/v1/connections` (Bearer `BETTERSTACK_API_TOKEN`).

## Query mechanics

- Endpoint: `POST https://$BETTERSTACK_QUERY_HOST?output_format_pretty_row_numbers=0`, Basic auth, body = SQL, `Content-type: plain/text`.
- **(#7898) The destination is PINNED, and so are the table arguments.** `scripts/betterstack-query.sh` extracts the authority from `BETTERSTACK_QUERY_HOST` and refuses anything that is not `*.betterstackdata.com` (exit 2) before it attaches the credential — `curl -u` sends Basic auth preemptively on the first request, so an unpinned host hands the ClickHouse read credential to whoever set the variable. `BS_TABLE` / `BS_TABLE_S3` (env or `--table` / `--table-s3`) must match `^[A-Za-z0-9_]+$`, because they interpolate into `remote()` and `s3Cluster()` whose leading arguments are an address and a URL; `--limit` must be numeric.
  - **Consequence for a re-mint:** a connection minted in a region whose host falls outside that apex would be refused. Every observed value is under it; if the vendor ever changes the apex, the allowlist in `scripts/betterstack-query.sh` is the one place to update.
  - **Consequence for a test:** there is deliberately no host-override seam. A suite that needs to exercise the egress path shims `curl` — `run_sql()` is the sole egress site — and uses a synthetic vendor-shaped host. Worked examples: `tests/scripts/test-betterstack-query-archive.sh` (shell-function shim) and `tests/scripts/test-git-data-rung2-evidence-capture.sh` (shim on `PATH`).
  - **Read the residual plainly:** `*.betterstackdata.com` covers every Better Stack *tenant*, not just ours. The pin narrows the adversary set from anyone to any Better Stack customer; it does not close it (ADR-052).
- **(#8043 Guard 5) `--table` / `--table-s3` are honoured in BOTH modes — never silently dropped.** Until 2026-09-11, mode 1 (raw SQL) ran its query and exited before the mode-2 flag loop, so `betterstack-query.sh "SELECT … remote($BS_TABLE) …" --table t520508_soleur_git_data_prd_logs` silently read the DEFAULT (shared inngest) source with exit 0. Against a git-data host that is a plausible empty result — the false verdict "the boot was dark" — and it nearly produced exactly that on #8043. The script now pre-scans both table flags ahead of mode dispatch (see the `PRE-SCAN` comment block in `scripts/betterstack-query.sh`), so they work on either side of the SQL, `--table` derives the `_s3` name for `$BS_TABLE_S3` in mode 1 just as in mode 2, and an explicit `--table-s3` / `BS_TABLE_S3` env still wins regardless of order.
  - **Exit 64 from a table flag** means a USAGE error, the same code as an unknown flag: a bare trailing `--table` with no value, or a non-`_logs` table (`_metrics`, `_spans`) with no explicit archive at a point that needs one — mode 2 without `--no-archive`, or a raw query that spells `$BS_TABLE_S3`. It is never exit 2 (identifier refusal) or exit 3 (creds not injected); read the message, it names `BS_TABLE`.
  - **The canonical way to read git-data's own source is the environment, not the flag:** `export BS_TABLE=t520508_soleur_git_data_prd_logs` — which is what `scripts/followthroughs/git-data-rung2-evidence-capture.sh` does (its `PIN THE TABLE TO GIT-DATA'S OWN SOURCE` block), so every raw query it issues, and the derived `_s3` sibling, stay on one source by construction. Pinned by the `mode 1:` rows of `tests/scripts/test-betterstack-query-archive.sh`.
- Always end SELECTs with `FORMAT JSONEachRow` for line-delimited JSON.
- **(#8296) Three reads that report a false ABSENCE.** `--grep` is a literal `LIKE '%…%'` — `'a\|b'` matches the six-character string, never an alternation; run one grep per term. A tag read with `--limit` lets heartbeats scroll a rare transition row out of the window (the LUKS FSM `cutover-complete` row was "absent" for 30 min while present) — grep the transition REASON, not the tag. And an FSM row's `message` is a JSON OBJECT, so `.message[0:230]` errors and reads as no rows; test `type` before slicing. A negative read must also be bounded AFTER the action's own timestamp with slack: a window ending at `14:50:16` missed a write at `14:50:16.9`.
- Columns: `dt` (use for WHERE/ORDER), `raw` (the full log line as text/JSON). **What `dt` measures depends on the emitter.** For the Vector-shipped inngest source it is the warehouse's RECEIVE time, not the host's event time — measured 2026-09-24 (#8759): `dt` equals the `ingest_time` column byte-for-byte, sits ~1 s after the row's own journald `timestamp`, and one HTTP batch shares one `dt`. The host's own clock is inside `raw` (`timestamp`, `__REALTIME_TIMESTAMP`). Before treating `dt` as either clock for a new source, measure it: `SELECT dt, ingest_time, raw … LIMIT 5`.
- Recent logs: `remote(t520508_..._logs)`. Older than the hot window: `s3Cluster(primary, t520508_..._s3)` with `WHERE _row_type = 1`, `UNION ALL`-combined.

## App container pino lines (cron failures) — now queryable (#4773, 2026-06-02)

**Closed (was a coverage gap discovered 2026-06-01).** The Next.js app container's
pino stdout — including `spawnClaudeEval` cron output, `fn: cron-<name>` — now
ships to this source. The container starts with `--log-driver journald`
(cloud-init.yml + ci-deploy.sh, all 3 `docker run` sites), and Vector's
`app_container_journald` source ingests it filtered to pino **WARN+** (level ≥ 40)
via `app_container_warn_filter`, then through the same 3-stage `pii_scrub_*`
redaction as every other source.

Query cron pino lines in Better Stack by `source_kind`:

```sql
SELECT dt, raw FROM remote(t520508_..._logs)
WHERE raw LIKE '%"source_kind":"app_container"%'
  AND raw LIKE '%"fn":"cron-growth-audit"%'
ORDER BY dt DESC LIMIT 50 FORMAT JSONEachRow
```

Two deliberate trade-offs:

- **WARN+ only.** The filter parses the pino `level` field (NOT journald
  `PRIORITY` — Docker's journald driver maps all stdout to PRIORITY 6 regardless
  of pino level, so a PRIORITY filter would drop everything). INFO/DEBUG (the
  request-log firehose) is dropped for quota. A non-zero claude exit logs at
  error level → shipped. The INFO-level `claude --print` **max-turns notice**
  is NOT here — it reaches **Sentry** via the `scheduled-output-missing`
  `extra.stdoutTail` (#4773 PR-A), alongside `extra.stderrTail`/`extra.exitCode`.
- **Container log retention moved to journald.** Switching off `json-file`
  dropped its `max-size 10m/max-file 3` rotation; the container's `docker logs`
  and retention are now governed by journald — at its **default** `SystemMaxUse`
  (min(10% of /var, 4 GB)) unless an explicit bound is provisioned. Explicitly
  sizing `SystemMaxUse` + ensuring `Storage=persistent` (so the journal survives
  reboot and the redirected container volume can't evict the supervisor/system
  journal Sources 1/2 depend on) is tracked as a follow-up infra task — the
  journald storage config predates #4773 and applies equally to the two
  pre-existing journald sources.
- **Rollout on existing hosts (non-load-bearing order).** PR-C is fully active
  only after BOTH (a) an inngest-bootstrap deploy ships the new `vector.toml`,
  AND (b) a web-platform deploy re-creates the `soleur-web-platform` container
  with `--log-driver journald`. Either interleaving degrades gracefully: a
  journald source with no matching lines is benign, and a journald-logging
  container with no matching source just isn't shipped until the config lands.
  No operator action beyond a normal deploy of both components.

## Querying Anthropic cost markers (`SOLEUR_CLAUDE_COST` / `_DAILY`)

The production Claude fleet emits two structured cost-marker families at pino
**WARN** (so the same `app_container_warn_filter` ships them). Both ride the
existing app-container → journald → Vector → Better Stack path — **no
`betterstack-query.sh` change**; the `--grep` form already does `raw LIKE '%…%'`:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 48h --grep SOLEUR_CLAUDE_COST --limit 20
```

- **`SOLEUR_CLAUDE_COST`** — per-turn (sessions) + per-run (crons). Emitted from
  the `cost-writer` choke point (`source ∈ {agent-runner, cc-soleur-go,
  leader-loop}`), the `spawnClaudeEval` substrate (`source: "cron:<name>"`,
  `capture_status ∈ {ok, no-result-event, parse-error, timeout}`), and the
  `postAnthropicMessage` HTTP transport (`cron:<name>`, tokens-only). A
  `capture_status != "ok"` row is a *shipped* capture-failure event — NOT
  row-absence — so "capture broke" is distinguishable from "genuinely \$0".
- **`SOLEUR_CLAUDE_COST_DAILY`** — the once-a-day Admin cost-report cron
  (`cron-anthropic-cost-report`), carrying the org-total `cost_usd` + a per-model
  array. A `{status:"key-missing"}` row is the correct **dark** signal while
  `ANTHROPIC_ADMIN_KEY` is unprovisioned (do NOT triage its absence as a
  regression during the mint window).
  - **`days_since_first_dark`** — whole UTC days since the *first observed* dark
    fire (2026-07-10), present on `key-missing` rows only. It is **not** the age
    of the current dark window: it never resets, so after a mint-then-rotate it
    reads the full elapsed span on day one of a benign gap. Read it as "how long
    has this surface been unprovisioned at least once", never as "how long has it
    been broken right now". Nothing branches on it.
  - **Absent-vs-zero trap.** The field is *omitted* on `status:"ok"` rows, and
    `JSONExtractInt(raw,'days_since_first_dark')` returns **0** for a missing key.
    So a healthy `ok` row and a genuine day-0 dark row are indistinguishable by
    that extract alone. Any panel or query MUST filter `status='key-missing'`
    **first**.
  - **Field-isolate before trusting a match.** `--grep` is an unanchored
    `raw LIKE '%…%'` over the Better Stack source that host multiplexes into —
    `2457081` for the web, inngest and registry planes, `2734275` for git-data
    since #7772 — so a `--grep` sweep must name the source it is sweeping rather
    than assume there is only one. GitHub webhook payloads (issue and PR bodies) reach that source —
    so any issue/PR text quoting the marker name will match. A structural check
    is used rather than a `source_kind` filter because it holds regardless of
    which Vector source an echo arrives on. A trustworthy producer row has `component` =
    `claude-cost` (the pino base field from `claude-cost-marker.ts`) as a
    key of the decoded `raw`'s **`.message` object** (measured 2026-09-12: the
    app-container line is stored as `{"message": {…pino fields…}}`, so the
    fields are one level down, never at the top level), not as nested string
    content. Match structurally (decode `raw`, then check `.message.component`)
    rather than by substring;
    `scripts/followthroughs/run-report-exit-first-contact-8076.sh` is the
    worked example (its fixture suite pins the live shape and reds on a
    top-level reader); `anthropic-admin-key-6297.sh` reads `.message` first
    and falls back to the top level.
  - **Expect a permanently-dark surface until an account-tier decision is made.**
    The Admin API is unavailable to individual accounts, and the operator's org is
    one — `platform.claude.com/settings/admin-keys` returns "Page not found".
    Until the org is converted to a team organization, `key-missing` is the
    steady state, not a transient mint window. See ADR-108 §Consequences and
    issue #6297.

### `SOLEUR_CRON_FILING_DENY` — a cron run was denied a filing

Emitted by `apps/web-platform/server/cron-filing-deny-marker.ts` (called from
`_cron-claude-eval-substrate.ts` `finish()`) at pino **WARN** (same
`app_container_warn_filter`, same path as the cost markers, no
`betterstack-query.sh` change) when a cron run's result event carried
filing-shaped `permission_denials` — a `gh issue create` or
`gh api …/issues` create the containment hook refused (ADR-216 addendum, the
run-report population). The substrate reads `permission_denials[]` from the
result event itself; there is no hook-written deny log to look for.

Fields: `fn` (Inngest function id), `run_id` (the Inngest run id — the join
key below), `spawn_started_at` (the claude-eval child's spawn instant; NOT the
handler's memoized `runStartedAt`, which is minutes earlier), `count` (denied
filing commands in the run), `commands` (command HEADS — `gh issue create` or
`gh api <endpoint path>`, query string dropped, capped — never a title, a
body, or a credential), `capture_status` (`ok`, or `field-absent` when the
result event parsed but carried no `permission_denials` array: count 0 then
means "the deny channel went dark", not "no denials").

```bash
doppler run -p soleur -c prd_terraform -- \
  bash scripts/betterstack-query.sh --since 7d --grep SOLEUR_CRON_FILING_DENY \
  | jq -R -r 'fromjson? | .raw | fromjson? | .message | select(.component == "cron-filing-deny") | [.fn, .run_id, .count, .capture_status] | @tsv'
```

Three caveats before reading a zero as clean:

- **Row shape.** The pino payload sits under `.message` of the decoded `raw`
  (measured 2026-09-12: 38/40 live rows), so field-isolate on
  `.message.component`, never on top-level keys — a top-level reader returns
  nothing on every row and looks exactly like "no denials".
- **Capture.** A run killed at `maxTurnDurationMs`, OOM-killed, or whose
  stdout was truncated has NO result event and therefore no deny marker even
  if it was denied. Its `SOLEUR_CLAUDE_COST` row carries
  `capture_status != ok`; treat such a run's deny status as UNKNOWN.
- **Shape, not reason.** `permission_denials[]` carries the command, not the
  deny reason, so a filing-shaped command refused for another cause (a
  metachar, an allowlist miss) is counted too. The marker measures "a filing
  was refused", which is the operator question; it does not attribute the
  refusal to the filing gate specifically.

A deny alone does not say whether the run recovered. Discriminate the two
outcomes by joining the marker's `run_id` to the Sentry tag `inngest.run_id`
(set by `sentry-correlation.ts` on every event in the run):

- **Denied and vanished** — a Sentry `scheduled-output-missing` event exists
  for that `fn` with the same `inngest.run_id`: the cron never filed its
  run-report, the persistence handshake refused the artifacts, and the
  heartbeat reads the run as silence. This is the #8059 shape and the reason
  exit 0 exists. (`cron-legal-audit` is the exception: it is
  `resolveBestEffortEvalOk` and emits no `scheduled-output-missing`; its only
  backstop is the heartbeat's `maxGapDays`, so a deny-then-abandon there reads
  as "denied then complied" until the gap trips.)
- **Denied then complied** — no matching `scheduled-output-missing`: the agent
  retried under an exit (usually exit 1, `meta/machinery`) and the run-report
  landed. Check measurement line 1d for the residue and the sweeper for a
  mis-labelled report.

The marker is the deny-side half of that join; the Sentry event is the
outcome-side half. Neither alone is the answer.

### `SOLEUR_COMPOUND_PROMOTE_OUTCOME` — what the weekly self-improvement run DID

Emitted by `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
`emitOutcomeMarker()` at pino **WARN** (same `app_container_warn_filter`, same
path as the cost markers) on **every** terminal exit of the promoter — the
census guard `cron-compound-promote-outcome-census.test.ts` fails the build if
a return is added without one. Before #8281 the promoter had been silently dead
since 2026-07-06: every exit returned a `status` string that reached nowhere,
so the only signal was the Sentry heartbeat, which proves LIVENESS, not work
(measured: a completed 516,512-input-token Anthropic call producing nothing,
invisible for ten weeks).

Fields: `status` (closed union: `disabled` | `deduped` | `week-cap-reached` |
`empty-corpus` | `anthropic-truncated` | `no-qualifying-clusters` | `completed`
| `error` — eight values from seven return sites), `trigger` (`cron` for the
`0 0 * * 0` fire, `manual` for `cron/compound-promote.manual-trigger`; BOTH
dispatch the same handler, so this field is the only thing that distinguishes
them), `run_id` (join key to Sentry `inngest.run_id`), `corpus_count`,
`corpus_input_bytes`, `clusters_proposed`, `clusters_opened`, `refusals[]`
(one enum per refused cluster, capped at 20), `refusals_total` (the uncapped
count — compare it with `refusals | length` before reading a capped list as
complete), `refusal_detail[]` (capped at 20 — see below; #8427 widened it past
`{cluster_hash, reason}`), and on `error` only,
`error_class` + an `error_message` scrubbed by `redactGithubSourcedText`
(token / JWT / email / credential-URL shapes) and capped at 200 bytes. The
row carries `component: "compound-promote"` (emitter:
`server/compound-promote-marker.ts`, PR #8344).

```bash
doppler run -p soleur -c prd_terraform -- \
  bash scripts/betterstack-query.sh --since 30d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 50 \
  | jq -R -r 'fromjson? | . as $r | ($r.raw|fromjson?).message
              | select(type == "object" and .SOLEUR_COMPOUND_PROMOTE_OUTCOME == true and .fn == "cron-compound-promote")
              | [$r.dt, .trigger, .status, (.corpus_count//"-"), (.clusters_proposed//"-"),
                 (.clusters_opened//"-"), ((.refusals//[])|join(",")),
                 ((.refusal_detail//[])
                    | map("\(.cluster_hash[0:8]):\(.reason)"
                          + ":len=\(.diff_len//"-")"
                          + ":fenced=\(if .diff_fenced == null then "-" else .diff_fenced end)"
                          + ":hdr=\(if .diff_header_pair == null then "-" else .diff_header_pair end)"
                          + ":hunk=\(if .diff_hunk == null then "-" else .diff_hunk end)")
                    | join(" | "))] | @tsv'
```

Reading it:

- **Field-isolate, never substring.** GitHub webhook payloads (issue and PR
  bodies) reach this source, and every artifact of #8281 quotes the marker
  name. A `grep -c` over undecoded `raw` counted this PR's own description as
  an emission. The `select` on `.fn` is what makes a row an emission.
- **`completed` with `clusters_opened: 0` is the interesting case**, and
  `refusals[]` is what separates "the corpus had nothing to propose"
  (`no-qualifying-clusters`, or `completed` with empty refusals) from "every
  cluster was refused" — the two states #8281 was filed to distinguish. The
  refusal enums name the gate: `diff-structural-op` / `diff-path-refused` (the
  allowlist), `corpus-shrink-refused` (the post-apply floor),
  `skill-conflict-guard`, `byte-budget-overflow`, `not-committed-*`.
  `refusal_detail[].cluster_hash` recurring week over week is a cluster the
  proposer keeps producing and the gates keep refusing.
- **`diff-underivable` is no longer an emitted value (#8427).** It was ONE
  literal covering SIX structurally different conditions, so a refusal said
  derivation had failed and nothing about why. It is now one value per site:

  | reason | what actually happened |
  |---|---|
  | `diff-underivable-read-tree` | `git read-tree HEAD` failed — a broken or empty checkout, not a bad proposal |
  | `diff-underivable-apply` | `git apply --cached` rejected the patch — the model's diff is malformed |
  | `diff-underivable-diff-index` | `git diff-index` failed — a git output-format break |
  | `diff-underivable-empty-pathset` | the patch applied but derived NO paths — a proposal that nets to no change |
  | `diff-underivable-unparsable-record` | a `diff-index` record we could not parse |
  | `diff-empty` | the proposal was empty or whitespace-only |

  **`diff-empty` deliberately does NOT carry the `diff-underivable` prefix.**
  The five `underivable-*` values do, so a SUBSTRING or full-text query on
  `diff-underivable` keeps matching those — but it stops matching the
  empty-proposal rows, which is intended. An EXACT-match alert condition on
  `refusals[]` breaks on all six values, not just `diff-empty`; nothing in this
  repo has one, and a saved query outside it cannot be verified from here. An empty proposal was never a derivation failure; this is a
  reclassification, not a compatibility break to route around.
- **Do not write `.diff_fenced // "-"` in a jq projection.** jq's `//` yields
  its right-hand side when the left is `null` **or `false`**, so every `false`
  renders identically to an absent field — and `false` is a meaningful value for
  all three booleans. The recipe above uses an explicit `== null` test. (`//` is
  fine for `diff_len`: `0` is truthy in jq.)
- **The diff-SHAPE fields disambiguate the apply arm.** `git apply` emits
  `No valid patches in input (allow with "--allow-empty")` byte-identically for
  an empty string, a whitespace-only string, a markdown-fenced block, and a
  `---`/`+++` header pair with no `@@` hunk (measured, git 2.55.0), so
  `diff-underivable-apply` alone still cannot name the input. Every
  `refusal_detail[]` entry therefore carries `diff_len`, `diff_fenced`,
  `diff_header_pair` and `diff_hunk` — numbers and booleans only, never the
  diff body. `diff_fenced: true` is the high-value one: it means the proposer
  wrapped its diff in a markdown code fence, which is a PROMPT defect rather
  than a proposal-quality one.
- **`refusals` is derived from the step's RETURN VALUE**, so it is correct on
  a replayed run. An earlier revision pushed into a handler-scope array from
  inside the memoized step and emitted `[]` on every real run.
- **The `select(type == "object")` guard is load-bearing**: rows before
  2026-09-19 (PR #8344 — the marker went through the console-backed Inngest
  ctx logger and rendered as multi-line text) and any diagnostic `ctx.logger`
  line matched by the grep decode to a STRING `.message`, and `.SOLEUR_… ==
  true` on a string is a jq error, not a miss.
- **The marker carries NO free-text field, and that is deliberate (#8427).**
  An earlier revision of that change put git's `detail` string into
  `refusal_detail[]` behind a redact-then-classify-then-cap transform. Review
  falsified the control: the classifier only collapsed tokens containing `/`,
  so a proposal creating a file at the repository ROOT — a name the model picks
  freely, and which `git diff-index` emits unquoted, spaces included — passed
  through byte for byte. Measured against git 2.55.0, a diff creating
  `ALERT <arbitrary prose>.md` produced `detail = "A ALERT <arbitrary prose>.md"`
  in the row. At ~198 characters × 20 entries that is ~3,960 model-chosen
  characters per weekly run into this processor.

  Every repair for that is a denylist over a string the model writes, so the
  field was removed instead. What the row carries is decidable by construction:
  a closed `reason` enum chosen by our code, a sha256 `cluster_hash`, and the
  numeric/boolean `diff_*` shape fields.

  **Where the diagnostic went.** The full, unelided string reaches **Sentry**
  via `reportSilentFallback` (`feature: cron-compound-promote`,
  `op: diff-path-refused`, `extra.detail`), redacted by
  `redactGithubSourcedText` and capped by `safeDetail`. Read it with
  `scripts/sentry-issue.sh`, not from this source.

  Two things worth knowing when you go looking. The per-cluster
  `diff-path-refused` ctx-logger line DOES reach this source (measured
  2026-09-20 by recovering the 05:39Z run's `detail` from it) — it renders as
  multi-line `util.inspect` text, one journald row per line, so it is unpleasant
  to query rather than absent, and it no longer carries `detail`. And
  `reportSilentFallback` writes through the app's main pino instance, which also
  lands here — so "it only goes to Sentry" is false for that copy, which is why
  it is redacted rather than merely capped.
- **A dark channel reads as zero.** Before grading an absence, confirm
  `SOLEUR_CLAUDE_COST` rows exist in the same window — same emitter class,
  same path. The #8281 soak probe (`scripts/followthroughs/compound-promote-outcome-8281.sh`)
  does this and requires `trigger == "cron"`, so a manual fire cannot close it.

The manual trigger is agent-invocable on every harness: Claude Code `Skill
tool soleur:trigger-cron`, Grok `/trigger-cron`, Devin `/soleur:trigger-cron`,
Codex `$soleur:trigger-cron`; the event is derived from `EXPECTED_CRON_FUNCTIONS`
in `cron-manifest.ts`, not a second list.

### `SOLEUR_WATCHDOG_DISPATCH` — the watchdog dispatch clock (#8495, ADR-248)

Emitted by `server/watchdog-dispatch-clock.ts` through `emitWatchdogDispatch`
(`server/cron-liveness-marker.ts`, `component: "cron-liveness"`) at pino **WARN**, once at
boot (`outcome` `armed`/`disarmed`) and once per tick (`dispatched`, `skipped_slot_has_run`,
`failed`, `tick_escaped`). Fields: `host_id`, `workflow`, `slot` (ISO slot start), `outcome`,
and on a failure `op` (`mint`/`dedup-read`/`dispatch`), `reason` (`timeout`/`http`/`throw`),
`status`; a skip carries `run_id` + `run_event` of the run that already covered the slot.
Expect about five tick rows an hour per web host (`host_name` is Vector's, outside the marker).
`tick_escaped` must never appear. The
canary container's rows are not shipped (Vector matches the prod container name exactly).

```bash
doppler run -p soleur -c prd_terraform -- \
  bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_WATCHDOG_DISPATCH \
  | jq -R -r 'fromjson? | .raw | fromjson? | .host_name as $h | .message | select(type == "object" and .SOLEUR_WATCHDOG_DISPATCH == true) | [$h, .host_id, .workflow, .slot, .outcome, (.op // ""), (.reason // "")] | @tsv'
```

### `SOLEUR_RUN_REPORT_SWEEP` — the 12:00Z run-report arm changed state

Emitted by `cron-stale-deferred-scope-outs.ts` `sweepRunReports` through
`emitRunReportSweep` (`server/cron-liveness-marker.ts`, `component:
"cron-liveness"`) at pino **WARN** on any fire that CLOSED at least one
run-report or DEFERRED one past
the 25-per-run cap; a quiet fire (nothing closed, nothing deferred) is silent.
Fields: `total`, `closed`, `skipped`, `deferred`, `closedByLabel` (per
`scheduled-*` label), `skippedByReason` (`failed-report`, `human-triaged`,
`reopened-by-human`, `action-required`, kill-switch label, `too-young`,
`not-run-report-shape`, `not-open`, `triage-read-failed`), `dryRun`. A run
with `deferred > 0` has a backlog the next fire drains; a `closed` count on a
label whose reports are FAILED-bodied is the regression the FAILED guard
exists to stop and the follow-through for #8076 grades it from GitHub.

```bash
doppler run -p soleur -c prd_terraform -- \
  bash scripts/betterstack-query.sh --since 7d --grep SOLEUR_RUN_REPORT_SWEEP \
  | jq -R -r 'fromjson? | .raw | fromjson? | .message | select(type == "object" and .SOLEUR_RUN_REPORT_SWEEP == true) | [.closed, .deferred, (.closedByLabel | tojson)] | @tsv'
```

Rows before 2026-09-19 (PR #8344) decode to a STRING `.message`; the
`type == "object"` guard skips them — same cause as the compound-promote
decode above (measured dark on the 2026-09-14/15 fires).

Ranked SQL. Since #8344 (2026-09-19) pino fields nest under `raw.message`, so every marker field
is read as `JSONExtract*(raw, 'message', '<field>')`. The top-level form `JSONExtract*(raw, '<field>')`
returns 0/empty on every row and reads as "no spend" (#8611, measured: $0 top-level vs $159.81
nested over the same 356 cron markers). `remote(...)` alone is the hot table, which covers only
recent hours; for any longer window, union it with the S3 archive as below.

```sql
-- Per-source spend over a window (per-run marker; cron sources only)
SELECT JSONExtractString(raw, 'message', 'source') AS source,
       count() AS runs,
       round(sum(JSONExtractFloat(raw, 'message', 'cost_usd')), 2) AS cost_usd,
       countIf(JSONExtractBool(raw, 'message', 'is_error')) AS failed_runs,
       countIf(JSONExtractString(raw, 'message', 'subtype') = 'error_max_budget_usd') AS cap_hits
FROM (SELECT dt, raw FROM remote($BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 30 DAY
  AND raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
  AND JSONExtractString(raw, 'message', 'component') = 'claude-cost'
  AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'
GROUP BY source ORDER BY cost_usd DESC FORMAT JSONEachRow

-- Per-model spend attribution (per-run marker; operator-key cron sources only)
SELECT JSONExtractString(raw, 'message', 'model') AS model,
       count() AS turns,
       round(sum(JSONExtractFloat(raw, 'message', 'cost_usd')), 2) AS cost_usd
FROM (SELECT dt, raw FROM remote($BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 30 DAY AND raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
  AND JSONExtractString(raw, 'message', 'component') = 'claude-cost'
  AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'
GROUP BY model ORDER BY cost_usd DESC FORMAT JSONEachRow

-- Daily authoritative org total (Admin report)
SELECT dt, JSONExtractString(raw, 'message', 'date') AS day,
       JSONExtractFloat(raw, 'message', 'cost_usd') AS org_cost_usd
FROM (SELECT dt, raw FROM remote($BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE raw LIKE '%"SOLEUR_CLAUDE_COST_DAILY":true%'
ORDER BY dt DESC LIMIT 30 FORMAT JSONEachRow
```

The `"SOLEUR_CLAUDE_COST":true` key match (with `:true`) keeps the `SOLEUR_CLAUDE_COST_DAILY`
org-total rows out of a per-run sum. Rows before #8344 carry `message` as a string and read 0 here.
Since #8611 the per-run marker also carries `is_error`, `subtype` (e.g. `error_max_budget_usd`)
and `num_turns` for cron claude-eval runs. **Is a cron's cap too tight?** A source whose `cap_hits`
is a large share of its `runs` in the per-source query is being cut off before finishing (wasted
partial sessions); compare its `cost_usd / runs` against its `CLAUDE_BUDGET_USD` entry in
`server/inngest/cron-budgets.ts` and recalibrate on #8613. Without the `component` + `cron:` guards
these queries also sum founder BYOK session spend (`agent-runner`, `cc-soleur-go`, `leader-loop`),
which is not the operator key's.

The markers carry `conversationId`/`runId`, token counts, cost, model, and
`source` — no PII, and the daily marker is field-allowlisted so `api_key_id`/
`workspace_id` never reach Better Stack.

Two further blind spots surfaced by the cron-workspace ENOSPC incident
(#4684/#4689): (a) the `_metrics` table stores **empty** `AggregateFunction`
values — the actual metric numbers live as JSON in the `_logs` `raw` column, so
query `_logs`, not `_metrics`, for metric values. (b) The Vector host-metrics
source reports only **HOST** filesystems (the root volume), **not** the
container's `/tmp` tmpfs. That is why the 256 MB-tmpfs clone ENOSPC was invisible
here while the host root showed ~56 GB free — host metrics are structurally blind
to the per-container tmpfs the crons clone into. Disk-pressure on a cron
workspace surfaces via Sentry (`op=cron-workspace-low-disk` WARN, and the
`scheduled-output-missing` `extra.stderrTail`/`extra.exitCode`), not here.

Region scope of the query connection (#5105 session): the minted ClickHouse
connection only reaches the cluster of the data region it was provisioned
around (ours: eu-fsn-3). `remote(t<TEAM>_<table>_logs)` for a source in a
DIFFERENT region (e.g. the eu-nbg-2 onboarding demo source) fails with
`CLUSTER_DOESNT_EXIST` — use the Telemetry API (`GET /api/v1/sources`) for
metadata on out-of-region sources, or mint a second connection. Also note:
metric events shipped through the generic HTTP sink count against the LOGS
ingestion quota (3 GB/mo free tier), so quota math must include host metrics
(see knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md).

Nested-tag extraction (#5110 second-pass session): metric rows store tags as a
nested JSON object — `JSONExtractString(raw, 'tags.mountpoint')` (dotted
single-arg path) silently returns empty strings. Use the multi-key form
`JSONExtractString(raw, 'tags', 'mountpoint')` to descend into the `tags`
object. When a tag extraction unexpectedly groups everything under one empty
key, sample one raw row (`SELECT raw ... LIMIT 1`) before trusting the path.

## Querying the zot CONTAINER log channel (`SOLEUR_ZOT_LOG`) — registry, #7440 / ADR-184

> **⚠️ THIS CHANNEL IS LIVE as of 2026-08-12. Zero rows here is now a FAULT, not a
> not-yet — read this box before following the queries below mid-incident.** The
> `soleur-registry` host is cloud-init-only (ADR-096), so the shipper was **merged inert**
> and stayed inert until the host was next re-provisioned. That happened at
> **2026-08-12T20:54:12Z** via a dedicated `registry-host-replace`
> ([run 31639782781](https://github.com/jikig-ai/soleur/actions/runs/31639782781)) — **not**
> the step-6 replace of the zot-pin ordered path this box previously named, which had
> already fired ~45h before the shipper merged and therefore carried nothing. The first
> PASS was read back out of the warehouse at 2026-08-12T21:03:51Z (37 envelope rows against
> a floor of 7), which is what flipped ADR-184 to `accepted`.
>
> **So if the queries below return zero rows, do not reflexively read it as a not-yet.** Start with
> the enrolled probe — `scripts/followthroughs/zot-log-channel-7440.sh` — and read its `reason=`;
> it discriminates cases a bare query cannot:
>
> - **Your own read is broken** — `credentials_unset`, `query_tool_missing`, `query_failed`. In all
>   three your manual query below ALSO returns zero, for a read-side reason. Check these first:
>   they point at your Doppler credential, not at the registry host.
> - **The channel answered and was empty** — `channel_dark` (zero envelope AND zero control rows:
>   the read path is not answering at all), `delivered_but_silent` (**act now** — the host is
>   provisioned and the shipper is not emitting), `shipper_state_unreadable` / `shipper_post_failing`
>   (the unit runs; its state file or its POSTs are failing), `not_delivered` (**post-delivery this
>   means a REGRESSION**, not a not-yet — see the boot-id bullet below).
> - `credential_shape_in_channel` is the sole `exit 1`, but it is computed from shipped rows, so it
>   **cannot** occur on a zero-row window. It is not a candidate for the case this box is about.
>
> **Zeros that are still legitimate**, and the probe will not save you from either: any window whose
> start predates **2026-08-12T20:54:12Z** (the channel did not exist yet), and any `--no-archive`
> query reaching outside the ~40-minute hot window. Check your `--since` before concluding anything.

**What changed.** Before #7440 the only registry telemetry was the 5-minute
`SOLEUR_ZOT_DISK` heartbeat, which samples **one** `docker logs` line per interval into
its `zot_last_err` field. Every count derived from that channel was therefore a **lower
bound**, not a measurement. Measured over 6h on 2026-08-11: 72 rows mentioned the host,
all 72 were heartbeats, and zero genuine zot log lines had ever reached the warehouse.

### The discriminator: a positive, host-isolated envelope

Every line the shipper POSTs is prefixed:

```text
SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry <sanitized zot line>
```

**Match that prefix at offset 0. Do not grep `zotregistry.dev`.** That string returns
53 rows over a 6h window *today, with no shipper in existence* — every one of them the
heartbeat echoing its own `zot_last_err`. It is the canonical false green for this
channel. And `host_name` does not exist on these rows: that field is Vector-populated
and this host runs no Vector, so the in-message `host=` token is the only isolation
available on a source every host ships to.

### Grep encoding-safe, THEN decode, THEN field-isolate

ClickHouse stores `raw` **double-encoded**: real zot JSON `"caller":"zotregistry.dev/…"`
is stored as `\"caller\":\"zotregistry.dev`. A grep containing a quote or a colon-joined
field name becomes a `LIKE` that matches **nothing, ever**. Use the quote-free,
colon-free token:

```bash
# Genuine zot rows in the last 30 min (hot window; --no-archive is correct at this span).
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 30m --no-archive --limit 400 --grep SOLEUR_ZOT_LOG \
  | jq -R -r 'fromjson? | .raw // empty' \
  | jq -R -r 'fromjson? | .message // empty' \
  | grep -F 'SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry '
```

`zotregistry.dev/zot/v2/pkg/api` is the zot-only substring to confirm the content really
came from zot — it carries no quote and no colon, so it survives the double encoding.

### The four evidence classes, and why the gc RATIO is the point

These four are **cap-exempt** in the shipper, so they survive the rate cap during exactly
the flood (crash-loop / pull storm) that accompanies disk growth:

| String | What it answers |
|---|---|
| `executing gc` | the **denominator** — gc started |
| `gc successfully completed` | gc finished |
| `garbage collected blobs` | gc actually reclaimed |
| `PatchBlobUpload` | orphaned `.uploads/` evidence (i/o timeouts) |

`gc` runs hourly (`"gc": true`, `gcDelay`/`gcInterval` 1h). **A stalled gc emits a start
with no completion**, so the start/complete *ratio* is the discriminator — which is why
the channel admits starts at all. If only completions were shipped, "gc never ran", "gc
ran fine" and "the shipper filtered it" would be indistinguishable: the lower-bound
defect reproduced one layer up.

### Is it delivered? (check this before reading any zero as a fault)

```bash
# 1. The one-shot boot marker, fired once from runcmd at provision time.
… --grep SOLEUR_ZOT_LOG_BOOT     # boot_id=, shipper_cron=<present|absent>

# 2. The reporter's INDEPENDENT path — it survives a totally dead shipper egress.
… --grep SOLEUR_ZOT_DISK | … | grep -oE 'log_shipper_post_fail=[^ ]+|log_shipper_last_ok_age_s=-?[0-9]+|log_shipper_dropped_cum=[^ ]+|log_shipper_drop_seq=[^ ]+|boot_id=[0-9a-f-]+'

`log_shipper_post_fail=` takes `unknown` when the shipper's state file is unreadable — that is
**not** zero. The previous `[0-9]+` form could not match it, so a never-run shipper read as "no
POST failures", which is the inverted root cause. `log_shipper_last_ok_age_s=-1` means no row has
ever shipped. Drop reasons on `SOLEUR_ZOT_LOG_DROPPED` rows are `rate_cap`, `exempt_cap`,
`redact_failed`, `sanitized_empty` and `cursor_invalidated`; the last carries `n=unknown` because
the lost span between a rotated-past cursor and the bounded restart is genuinely unbounded.
```

- **No boot marker AND `boot_id` still `bc135d5b-…`** → **since 2026-08-12 this is a FAULT, not a
  wait.** It previously read "not delivered. Expected; wait", which was correct until delivery.
  `bc135d5b-…` is the PRE-shipper boot; the host delivered on 2026-08-12T20:54:12Z is
  `93c52405-5fd2-462d-8051-fa68b8ab327f`. Seeing the old boot now means the host regressed to a
  pre-shipper image — investigate rather than wait. Prefer the `log_shipper_post_fail=` presence
  test in the next bullet as the positive/negative proof; it does not depend on remembering which
  boot is current.
- **`log_shipper_post_fail=` present on a `SOLEUR_ZOT_DISK` row but zero envelope rows** →
  *delivered and dead*. **This is the state that means act, not wait.** The cron tick is
  failing, its journald match is wrong, or `jq` is missing on the host.

  **`boot_id` drift is NOT evidence of delivery on this host** and must not be used as one.
  The private-NIC guard calls `reboot` as a convergence primitive and cloud-init's `runcmd` is
  per-instance, so a plain reboot of the current, un-replaced host drifts `boot_id` while
  delivering nothing — reading that as "delivered" starts the 90-day escalation clock against
  a host that was never replaced. The `log_shipper_post_fail=` key exists only in the reporter
  this change ships, so its presence is positive proof and its absence is positive proof of the
  opposite. There is no systemd unit, no `failed` state and no start-limit to reset: the shipper
  is an `/etc/cron.d` one-shot.
- **`log_shipper_post_fail` climbing** → the unit runs but its POSTs fail; an egress or
  token fault, not a dead unit. That counter deliberately rides the 5-min reporter rather
  than the shipper's own channel, because a counter surfaced on the channel it monitors is
  unobservable exactly when it is non-zero.
- **`SOLEUR_ZOT_LOG_DROPPED n=… reason=rate_cap`** → volume exceeded the 5,000/day cap.
  `n` is scoped to the interval that row closes; `boot_id` + `seq` are what let you detect
  a counter discontinuity across a replace or a crash replay.

### Expected volume

`zot-liveness-heartbeat.timer` fires every **60s** and zot logs every request at info, so
~**1,440 rows/day** arrive by construction before any real pull traffic. A window
returning far fewer is a measurable shortfall, not a judgement call — the probe reports it
as `reason=below_expected_floor`.

## Verifying disk-fullness / write-health on a deny-all host WITHOUT SSH (registry, #6122 session)

> **⚠️ Correction (#6240/#6244, 2026-07-08): triangulation does NOT prove a disk is
> *not* full.** Source 1 (Hetzner Volume API) reports the **block-device** size — NOT
> the guest **filesystem** size; these diverge if `resize2fs` failed. Source 3 ("the
> last push succeeded") does **not** prove `<85%` — zot dedups blobs and a partial
> write can still fit, so a push can succeed on a nearly-full fs. In the follow-up
> incident the disk **was** full: the volume was grown to 30 GB but `resize2fs` had
> silently failed (`|| true`), leaving the ext4 fs at ~10 GB. **For a "disk full?"
> question you MUST see the guest `df%`** — ship it as telemetry
> (`betterstack-query.sh --grep SOLEUR_ZOT_DISK` → `pcent`, `fs_size_gb`,
> `block_size_gb`), never infer fullness from the provider API. The triangulation
> below is still valid for *host-down vs cron-not-installed vs full*, but corroborate
> genuine fullness with the shipped `df%` marker. Full write-up:
> [../../../project/learnings/best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md](../../../project/learnings/best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md).

A disk-gated **missed-heartbeat** (e.g. `soleur-registry-disk-prd`, which pings only
while `/var/lib/zot < 85%`) is **ambiguous** on a deny-all-public host with no SSH: it
means *either* the cron isn't installed yet (benign false positive — common right after a
host `-replace`) *or* the disk genuinely crossed 85%. You cannot `df` the box. Triangulate
from three SSH-free sources instead of eyeballing a dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`):

1. **Hetzner Volume API** — `GET /v1/volumes?name=soleur-registry-store` → block-device size
   (30 GB) + attach status (the "percent full" denominator).
2. **Hetzner server disk metrics** — `GET /v1/servers/{id}/metrics?type=disk` → write activity;
   near-idle = not actively filling.
3. **The last CI release run's zot-mirror step logs** — many `pushed blob: sha256:...` with
   NO `500 no space left on device` = the disk **accepted writes** = not full. The
   success/failure of the **last real write attempt** is the most decisive SSH-free signal.

A never-pinged disk-gated heartbeat (`last_event_at` absent → cron not installed) is **NOT**
proof of disk-full — corroborate with an independent write-success signal (source 3) before
concluding either way. Read liveness from `attributes.status ∈ {paused,pending,up,down}`
(only `up` proves a ping arrived); the heartbeat API has **no `last_event_at` field**. Full
write-up: [2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md](../../../project/learnings/2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md).

## Verifying disk-fullness / write-health on a deny-all host WITHOUT SSH

A **disk-gated missed-heartbeat** (e.g. `soleur-registry-disk-prd` — pings only
while `/var/lib/zot < 85%`) is **ambiguous**: cron-not-installed false positive
vs genuine disk-full. On a deny-all-public host with no SSH you cannot `df`.
Do NOT conclude from the heartbeat alone — triangulate three SSH-free sources:

1. **Hetzner Volume API** — `GET /v1/volumes?name=<store>` → block-device size +
   attach status (the "percent full" denominator; rules out a detached volume).
2. **Hetzner server disk metrics** — `GET /v1/servers/{id}/metrics?type=disk` →
   write activity; near-idle = not actively filling.
3. **The last CI release run's zot-mirror step logs** — many `pushed blob:
   sha256:...` with **no** `500 no space left on device` = the disk **accepted
   writes** = not full. The last real write attempt's outcome is the most
   decisive SSH-free signal.

A never-pinged heartbeat (`last_event_at` absent → cron simply not installed) is
**NOT proof of disk-full** — corroborate with the independent write-success
signal (3) before concluding either way. Serves
`hr-no-dashboard-eyeball-pull-data-yourself`.

**Heartbeat liveness = `attributes.status`, not a ping timestamp.** The Better
Stack heartbeat API exposes `attributes.status ∈ {paused,pending,up,down}` and
has **no `last_event_at` field**; only `status == "up"` proves a ping arrived.
Full write-up:
[2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md](../../../project/learnings/2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md).

## Querying host CPU / memory / load (`host_metrics`) — right-sizing a host WITHOUT SSH

Vector's `host_metrics` source (`vector.toml [sources.host_metrics]`, collectors
cpu/memory/disk/filesystem/load, 300s scrape) ships each datapoint to this same
Better Stack Logs table. This is how you read a host's real CPU/RAM utilisation
over weeks with no SSH — e.g. to right-size `var.web_hosts` (#6459 web-2 → `cx23`
was decided on 30 days of web-1 memory/load pulled this way).

**GOTCHA that wastes a session (it wasted one — 2026-07-25): metric events ship
in NATIVE Vector shape, NOT the `tag_metrics`-flattened log shape.** So:

- The host is under **`tags.host`** (e.g. `soleur-web-platform`), NOT the top-level
  `host` field that log rows use.
- The metric name is at **top-level `name`** (`memory_available_bytes`,
  `memory_total_bytes`, `load1/load5/load15`, …), NOT `metric.name`.
- The value is **`gauge.value`**, NOT `metric.value`.
- **`source_kind` is unset** on these rows — a filter `source_kind='host_metrics'`
  returns ZERO and looks like "metrics don't ship." They do; you filtered wrong.
  (The repo's `tag_metrics` remap that would add those fields is not reflected in
  shipped data — tracked in #6944 separately; query by `tags.host` + `name` and it just works.)

Memory utilisation distribution for one host over 30 days (min available =
worst-case peak usage; subtract from total for GB used):

```sql
SELECT count() AS samples,
  round(anyIf(v, n='memory_total_bytes')/1073741824,2)                          AS total_gb,
  round(minIf(v, n='memory_available_bytes')/1073741824,2)                      AS min_avail_gb,
  round(quantile(0.50)(if(n='memory_available_bytes',v,NULL))/1073741824,2)     AS p50_avail_gb,
  round(avgIf(v, n='memory_available_bytes')/1073741824,2)                      AS avg_avail_gb
FROM (
  SELECT JSONExtractString(raw,'name') AS n, JSONExtractFloat(raw,'gauge','value') AS v
  FROM ( SELECT raw FROM remote($BS_TABLE)
           WHERE dt > now() - INTERVAL 30 DAY
             AND JSONExtractString(raw,'tags','host')='soleur-web-platform'
             AND JSONExtractString(raw,'name') IN ('memory_available_bytes','memory_total_bytes')
         UNION ALL
         SELECT raw FROM s3Cluster(primary, $BS_TABLE_S3)
           WHERE _row_type=1 AND dt > now() - INTERVAL 30 DAY
             AND JSONExtractString(raw,'tags','host')='soleur-web-platform'
             AND JSONExtractString(raw,'name') IN ('memory_available_bytes','memory_total_bytes') )
) FORMAT JSONEachRow
```

Swap `load%` for the `name` filter (and `maxIf(v,n='load15')`) to read sustained
CPU pressure. After web-2 is born, re-run with `tags.host='soleur-web-2'` to
confirm it emits metrics and to drive the resize-or-keep-`cx23` decision
(ADR-143 D1). Serves `hr-no-dashboard-eyeball-pull-data-yourself`.
