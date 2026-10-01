# Phase 0 re-spike — Inngest v1.19.4 → v1.45.1 (#7463)

Re-verification of every load-bearing claim that was originally measured against
v1.19.4 in `feat-inngest-dedicated-host/phase0-empirical-spike.md`, re-run against the
**bump target** `v1.45.1` (`1.45.1-9059f14a7`, published 2026-09-17T20:51:40Z).
Harness date: 2026-09-29. Harness: the same topology as the original spike —
`inngest` binary v1.45.1 running natively on 127.0.0.1:18288, external Postgres
(`rspike-pg-a` :15432 / `rspike-pg-b` :15433, postgres:16-alpine), external Redis
(`rspike-redis` :16379, redis:7-alpine), two SDK app instances on :13000/:13001
sharing app id `spike-app` (`inngest@3.54.2`, the version prod pins — the SDK major
is deliberately out of scope, #8628). SDK env: `INNGEST_SIGNING_KEY` (64-hex),
`INNGEST_EVENT_KEY` (32-hex), `INNGEST_BASE_URL=http://127.0.0.1:18288`.

## Release resolution + delta (never restate the issue's figures)

- `gh api repos/inngest/inngest/releases/latest` → `v1.45.1`, 2026-09-17T20:51:40Z,
  `prerelease=false draft=false`.
- Tag-ordered walk: `gh api 'repos/inngest/inngest/releases?per_page=100' --paginate`,
  filtered to `prerelease==false && draft==false && tag =~ ^v\d+\.\d+\.\d+$` → 242
  stable tags; `v1.19.4` sits at position **30** → the bump spans **29 stable
  releases**. Command recorded so the number is reproducible; the issue's 22/27
  discrepancy is neither confirmed nor restated.

## Checksum verification (one `checksums.txt`, both arches, re-hashed)

Fetched `https://github.com/inngest/inngest/releases/download/v1.45.1/checksums.txt`
once; extracted the `linux_amd64` and `linux_arm64` rows; downloaded both tarballs and
`sha256sum -c`'d them against the extracted rows:

| Arch | checksums.txt row | tarball re-hash |
|---|---|---|
| amd64 | `52c07d837088a6712acd15b8edd4191f961b69884541f468a3c1b9bb4348a4e5` | OK |
| arm64 | `58db59dbe39afd7472c7c59bd7cc9f82f5da5810dabdac40b2bde3a8338aa7b5` | OK |

(The checksums file is a plain sha256sum manifest shipped in the release — it is
release-shipped, not GPG-signed. The reviewed embed in `inngest.tf` is the trust
anchor, per the checksum-verification learning.)

## Flag surface — `inngest start --help` diff v1.19.4 → v1.45.1

The ONLY differences are **additions**: four `--connect-*-grpc-*` flags.
Every flag the repo passes still exists: `--host`, `--port`, `--sqlite-dir`,
`--postgres-uri`, `--redis-uri`, `--sdk-url`/`-u`, `--signing-key`, `--event-key`,
`--poll-interval`, `--tick`, `--postgres-max-open-conns`, `--postgres-max-idle-conns`,
`--postgres-conn-max-idle-time`. No flag was removed or renamed.

```
+ --connect-executor-grpc-ip string  (default: "127.0.0.1")
+ --connect-executor-grpc-port int   (default: 50053)
+ --connect-gateway-grpc-ip string   (default: "127.0.0.1")
+ --connect-gateway-grpc-port int    (default: 50052)
```

### Units — verified against `cmd/start` SOURCE at tag v1.45.1 (not docs)

| Flag | v1.45.1 declaration | Multiplier in source | Verdict |
|---|---|---|---|
| `--postgres-conn-max-idle-time` | `cli.IntFlag`, `Value: 5`, "in minutes" (`cmd/start/cmd.go`) | `* time.Minute` (`pkg/devserver/devserver.go:202`) | **MINUTES — holds** (repo passes `1` = 1 min) |
| `--postgres-conn-max-lifetime` | `cli.IntFlag`, `Value: 30` | `* time.Minute` (`devserver.go:203`) | **MINUTES** (not passed by repo; recorded so nobody "fixes" it wrongly) |
| `--postgres-max-open-conns` | `cli.IntFlag`, `Value: 100` | conns | **holds**; NEW validations on v1.45.1: `must be greater than 1`, and `max-idle-conns <= max-open-conns` (`cmd/start/start.go:100-104`) — repo's `5`/`2` pass both |
| `--postgres-max-idle-conns` | `cli.IntFlag`, `Value: 10` | conns | holds |
| `--poll-interval` | `cli.IntFlag`, `Value: 0` | `* time.Second` (`service.go:295`) | **seconds — holds** (repo passes 60) |
| `--tick` | `cli.IntFlag`, `Value: DefaultTick` | milliseconds ("in milliseconds") | **ms — holds** |

### The `--postgres-max-open-conns` durable-detection sentinel — HOLDS

The flag exists on v1.45.1 and remains in `BACKEND_FLAGS` only in the durable-backend
form (`inngest-bootstrap.sh` writes it iff Redis is verifiably external). The
detection contract (`ci-deploy.sh`, `cloud-init-inngest.yml`'s
`--postgres-max-open-conns` grep on the emitted ExecStart) still binds to a flag that
exists and is passed only in the durable shape.

### `signkey-prod-` strip — STILL REQUIRED

`./inngest start --signing-key signkey-prod-<64hex>` →
`Error: signing-key must be hex string with even number of chars`. Bare 64-hex boots
(migrations ran, server bound). The systemd unit's `INNGEST_SIGNING_KEY#signkey-prod-`
expansion is still correct on v1.45.1.

### `inngest pause` — absent on BOTH endpoints (pre-existing dead call)

`./inngest pause --help` → `No help topic for 'pause'` on v1.19.4 AND v1.45.1. The
call at `inngest-bootstrap.sh` (the `|| warn`-guarded drain attempt before binary
replace) is dead on both — not an upgrade regression; filed as a micro follow-up.

### Poll semantics (`Opts.Poll`) — IDENTICAL on both versions

`cmd/start/start.go` on both tags sets `PollInterval` but **never sets `Opts.Poll`**
(only `cmd/devserver` sets `Poll: !noPoll`). `pollSDKs`'s skip —
`if !d.Opts.Poll && len(app.Error.String) == 0 { continue }` — is byte-identical on
both tags: in prod `start` mode the loop re-pings only ERRORED apps. The #5159
"`--poll-interval` self-heal" mechanism is therefore **unchanged by the bump**
(whatever re-arm it provided on v1.19.4 it provides identically on v1.45.1).

## ADR-100 Finding 1 — route-once fan-out: HOLDS

Two `--sdk-url`s (13000 + 13001), same app id `spike-app`: server stores ONE app,
URL = last-writer-wins. 4/4 `test/hello` events executed on instance A only, 0 on B;
one run per event in `runs`. Route-once confirmed on v1.45.1.

## ADR-100 Finding 2 + follower-claim set — mostly holds, ONE change

| Claim | v1.45.1 verdict |
|---|---|
| `runs(first, filter: RunsFilterV2!, orderBy)` enumerates runs, no run ids needed | **HOLDS** — real data returned, `startedAt`/`queuedAt` present on every node |
| `scheduled_tick` field absent | **HOLDS** — still not in `FunctionRunV2` |
| `eventName` null on cron runs | **HOLDS** |
| `cronSchedule` null on run nodes | **CHANGED** — v1.45.1 returns `"* * * * *"` on `cron-tick` runs. The doublefire probe's `(functionID, floor(startedAt/cron_period))` bucketing remains correct and version-agnostic; the prose claim needs re-stamping (populated since some v1.4x) |
| `FunctionRunV2` field set | superset: adds `deferredFrom`, `defers`, `isDeferred`, `siblingDefers`; `RunsFilterV2` adds `isDeferred` |
| Epoch bound rejected as out-of-range `Time!` | **HOLDS** — now a clearer error: "time should be RFC3339Nano formatted string" |
| `GET /v1/functions` unauthenticated → 404 | **HOLDS** (404, unregistered route) |
| `eventsV2` envelope (`inngest/scheduled.timer` + nested `runs`, `inngest/function.finished`) | **HOLDS** — identical shape observed |
| `inngest/function.cancelled` event + ULID run ids | **HOLDS** — `FnCancelledName` still in `pkg/consts/events.go:9`; observed run ids `01M3PH…` are ULIDs |

## ADR-100 Finding 3 — Postgres swap with retained Redis: FLUSHALL mandate HOLDS

Exact replay: `sleeper` triggered on PG-A, `SLEEPER_STARTED` logged, mid-90s-sleep;
server killed; restarted on **empty PG-B** + **same Redis** (migrations ran on B at
boot). Result on v1.45.1:

- `SLEEPER_STARTED` re-emitted and `SLEEPER_RESUMED_AFTER_SLEEP` — the Redis-held
  continuation replayed a run PG-B had never heard of to completion.
- `CRON_TICK` fired at the next two minute boundaries against PG-B from the stale
  Redis schedule.
- 8 `{cs}:a:*` idempotency keys survived the flip; DBSIZE 74.

Verdict identical to v1.19.4: **gated `FLUSHALL` + `DBSIZE == 0` before the
Postgres flip remains mandatory.**

## Listeners — UNCHANGED bind set; the NEW flags are advertise-only (corrected in review)

Measured `ss -tln` on BOTH endpoints booted locally: v1.19.4 and v1.45.1 bind the SAME
three sockets — `*:50052` (connect-gateway gRPC), `*:50053` (connect-executor gRPC),
`*:8289` (connect-gateway HTTP), plus the `--host`-bound API listener. What v1.45.1
actually adds is the four `--connect-*-grpc-ip/-port` **advertise** flags ("IP address
other instances use to reach") — they are NOT bind addresses; the sockets stay
wildcard on both versions. An earlier draft of this section claimed the listeners
were new in v1.45.1; that was wrong — the flags are new, the binds are not.

Exposure: `cloud-init-inngest.yml`'s nftables input chain is `policy accept` with
targeted drops only on `:8288`/`:8289` (web-IP allowlist + drop). So `:50052`/`:50053`
are reachable from every private-net peer on BOTH versions — not default-deny, and not
a new exposure introduced by this bump. ADR-100 Decision 3's ":8289 binds loopback if
Connect is unused" is likewise stale (it binds wildcard regardless). Correcting the
posture is tracked; this bump neither widens nor narrows it.

## Migration census — goose, v1.19.4 → v1.45.1 (`pkg/db/postgres/migrations`)

5 new Postgres migrations, applied automatically on `start`:

| Migration | Class |
|---|---|
| `000006_apps_unique_active_name` | **DESTRUCTIVE cleanup** — force-archives same-name duplicate `apps` rows and renames losers `name || ' (id:<id>)'` before adding the unique index (upstream release notes call this out; tiebreaks: active > archived, most functions, newest, id) |
| `000007_spans_is_deferred` | `ALTER TABLE spans DROP COLUMN is_deferred` |
| `000008_add_spans_run_inner_lookup_index` | `DROP INDEX CONCURRENTLY` + recreate |
| `000009_reconcile_prod_spans_indexes` | 4× `DROP INDEX CONCURRENTLY IF EXISTS` + recreates |
| `000010_add_trace_runs_list_indexes` | 3× `DROP INDEX CONCURRENTLY IF EXISTS` + recreates |

(sqlite migrations delta: 2 files — not our path.)

## Changelog walk — 29 releases, flags/schema/log-text

- **API V2 strictness (v1.4x):** unsupported query params and unexpected request
  bodies now return HTTP 400 instead of silently ignoring. Our probes POST to
  `/v0/gql` (GraphQL, unaffected) and GET `/v1/functions` (a 404 route on both —
  unaffected).
- **AI metadata renames:** `.model` → `.request_model`, `.system` → `.provider` in
  extracted AI metadata. No repo code consumes those fields (grep: none).
- **Update notifier added:** suppressed under non-TTY/`CI`/`DO_NOT_TRACK`/
  `INNGEST_NO_UPDATE_NOTIFIER` — the systemd unit is non-TTY; inert. Our monitor is
  the only operative freshness signal.
- **Queue/GQL internals** (`deferredFrom`, `isDeferred`, connect-gateway surface) —
  additive; no flag the repo passes was renamed or removed (see flag diff above).

## Alert-needle survival (`betterstack-logs-alerts.tf` `inngest_step_524`)

All three step-524 needles still exist in v1.45.1 source: `invalid status code: %d`
(`checkpoint.go`, `httpdriver.go`, `httpv2.go`), `error parsing stream: %w` +
`error reading response body to check for status code` (`httpdriver.go:438` +
`parse.go:107` compose the observed message), `Your server reset the connection
while we` (`exechttp.go`). Boot strings `initialized database`,
`ran database migrations`, `using external redis`, `starting event stream` all still
emitted verbatim (observed in this spike's logs).

## Drift-signal precondition (plan P4)

`scheduled-terraform-drift.yml` run 36539255971 (2026-09-29) ALREADY reports a pending
`hcloud_server.inngest` replace (`Plan: 4 to add, 0 to change, 4 to destroy` —
inngest server + network + 2 volume attachments, from earlier merged cloud-init work).
The pin bump adds to the same pending `user_data` diff; nothing new is armed.

## Harness cleanup

`rspike-pg-a`, `rspike-pg-b`, `rspike-redis` containers and the native `inngest`/node
processes are reaped at end of Phase 0 work (cleanup-on-failure convention); scratch
under `/var/tmp/inngest-bump-7463/` and `~/inngest-bump-7463/`.
