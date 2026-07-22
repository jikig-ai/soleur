# Runbook: Inngest server (self-hosted on Hetzner)

Operator-facing runbook for the self-hosted Inngest server provisioned by `apps/web-platform/infra/inngest.tf` and `inngest-bootstrap.sh` (PR-F follow-up, #3960).

Per ADR-030 the Inngest server runs as a single-host SQLite-backed durable trigger layer bound to `127.0.0.1:8288` (event ingestion) and `:8289` (admin API) on the same Hetzner host that runs the Web Platform. The CFO autonomous-draft pipeline (#3940) emits events to this server via `apps/web-platform/server/inngest/client.ts`.

## Quick reference

| Concern | Procedure |
|---|---|
| First-time bootstrap | [§ Fresh-host bootstrap](#fresh-host-bootstrap) |
| Heartbeat-miss alert | [§ Heartbeat triage](#heartbeat-miss-triage) |
| Key rotation (signing or event) | [§ Key rotation](#key-rotation) |
| Inngest CLI version bump | [§ Version bump](#cli-version-bump) |
| FR5 flag flip | [§ FR5 flip](#fr5-flag-flip) |
| Unpause heartbeat after first ping | [§ Unpause heartbeat](#unpause-heartbeat) |
| Cron bug-fixer manual trigger | [§ Cron bug-fixer](#cron-bug-fixer) |
| Fire any cron on demand | [§ On-demand cron trigger (HTTP)](#on-demand-cron-trigger-http--primary) |
| Dedicated-host cutover (#6178) | [§ Dedicated-host cutover](#dedicated-host-cutover-phase-2-opexecute-gated-sequence--ref-6178) |

## On-demand cron trigger (HTTP — PRIMARY)

To fire any allowlisted `cron/<name>.manual-trigger` event on demand, POST to the
internal trigger route — **no SSH to the Hetzner box required** (#4734, #4742):

```bash
TOKEN=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -sS -X POST https://app.soleur.ai/api/internal/trigger-cron \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"event":"cron/workspace-sync-health.manual-trigger"}' \
  -w '\n%{http_code}\n'
unset TOKEN
# → 202 {"dispatched":"cron/workspace-sync-health.manual-trigger","trigger":"manual-api"}
```

**Optional per-cron `data`** — crons that read `event.data` (e.g. `cron-bug-fixer`
reads `event.data.issue_number`) accept a `data` object. Route-controlled keys
(`trigger`, `at`) are stamped server-side and CANNOT be overridden by `data`:

```bash
  -d '{"event":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'
```

The allowlist is derived from `EXPECTED_CRON_FUNCTIONS`
(`apps/web-platform/server/inngest/cron-manifest.ts`) — a non-allowlisted event
returns 400. Non-plain-object `data` returns 400; the per-cron field validation
(e.g. `issue_number` positive-integer) lives in each cron, not the route.

**Agent/operator wrapper:** the `/soleur:trigger-cron` skill wraps this POST
(reads the secret read-only, lists allowlisted events, supports `--dry-run`):

```bash
plugins/soleur/skills/trigger-cron/scripts/trigger.sh --list
plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  --event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}' --dry-run
```

## Fresh-host bootstrap

After `terraform apply` against a fresh `hcloud_server.web`, the inngest-server is NOT yet running on the host. The bootstrap is decoupled from cloud-init by design (the OCI image is the sole delivery path). Steps:

1. Verify the GHA workflow `.github/workflows/build-inngest-bootstrap-image.yml` has published an OCI image:
   ```
   gh api repos/jikig-ai/soleur/actions/workflows/build-inngest-bootstrap-image.yml/runs --jq '.workflow_runs[0]'
   ```
   If no run exists, release a bootstrap image — see [§ Bootstrap-image release](#bootstrap-image-release-tag--build--deploy--verify) below for the canonical 4-step tag→build→deploy→verify flow.
2. Deploy the published image (NO SSH — `deploy-inngest-image.yml` is
   `workflow_dispatch`-only; it POSTs the deploy webhook → on-host `ci-deploy.sh`
   `case "inngest")` runs the bootstrap):
   ```
   gh workflow run deploy-inngest-image.yml -f tag=<TAG>   # e.g. tag=v1.1.16
   ```
3. Verify via the deploy-status webhook (NO SSH) — see [§ Bootstrap-image release](#bootstrap-image-release-tag--build--deploy--verify) step 4. Expect `{component:"inngest", tag:"<TAG>", reason:"success"}`.
4. [§ Unpause heartbeat](#unpause-heartbeat) once you've confirmed the heartbeat timer is firing.

## Heartbeat-miss triage

BetterStack emails `ops@jikigai.com` when the heartbeat is silent past the 30-second grace period. Triage:

1. **Confirm the alert is real** — `curl https://uptime.betterstack.com/api/v2/heartbeats/460830 -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)" | jq '.data.attributes.status'` should return `"paused"` (planned) or `"down"` (alert state).
2. **Check the service:**
   ```
   ssh root@<host> 'systemctl status inngest-server.service inngest-heartbeat.timer'
   ```
   - Both inactive → the bootstrap never completed. Re-fire the deploy webhook.
   - `inngest-server` active, `inngest-heartbeat.timer` inactive → restart the timer:
     ```
     ssh root@<host> 'systemctl restart inngest-heartbeat.timer'
     ```
   - Both active → check journalctl for the heartbeat service:
     ```
     ssh root@<host> 'journalctl -u inngest-heartbeat.service -n 20'
     ```
     Typical failure: missing `INNGEST_HEARTBEAT_URL` in Doppler prd, or Doppler CLI auth on the host expired.
3. **Confirm the URL is fresh:**
   ```
   terraform -chdir=apps/web-platform/infra output -raw inngest_heartbeat_url
   ```
   should match what `doppler secrets get INNGEST_HEARTBEAT_URL -p soleur -c prd --plain` returns.

## Session-pool pressure / exhaustion (`[ci/inngest-pool]`) — #5562

The external watchdog (`.github/workflows/scheduled-inngest-health.yml`) runs a
pool-utilization probe every 15 min: it reads `pg_stat_activity` on the dedicated
inngest Supabase project (ref `pigsfuxruiopinouvjwy`) via the Management API and
files a `[ci/inngest-pool]` issue + Sentry `error` when **inngest-attributable**
client connections cross ~80% of inngest's worst-case TOTAL footprint
(`INNGEST_CLIENT_CAP` = P × per-pool cap 5 ≤ 20; #6258, ADR-105)
— `pool_pressure`, the leading indicator — or `EMAXCONNSESSION` fires (`pool_exhausted`,
the cliff). It counts ONLY inngest's own connections (role `postgres`, minus the
pooler's Supavisor warm connections + the probe), NOT total `pg_stat_activity` (which
is dominated by Supabase infra baseline and false-fires — #5563). These modes are
**excluded from the auto-restart gate** — a restart re-opens all of inngest's
pooler connections at once and DEEPENS exhaustion (#5558). **Do NOT restart
inngest-server for a `[ci/inngest-pool]` alert.** Triage (no-SSH first):

1. **Read the alert** (no SSH) — `gh issue view "$(gh issue list --state open --search 'in:title \"[ci/inngest-pool]\"' --json number --jq '.[0].number')" --comments`. The body carries the inngest-attributable connection count vs the client cap; the full per-backend breakdown is in the run log (`Inngest client backends: …`).
2. **Re-read the live pool** (no SSH, read-only) — confirm via the same filtered query the probe uses (per-backend breakdown; inngest = role `postgres` minus Supavisor + the probe):
   ```
   SUPA=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
   curl -s --max-time 15 -X POST \
     https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query \
     -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' \
     -d '{"query":"select coalesce(application_name,'\''(none)'\'') as app, usename, state, count(*)::int as n from pg_stat_activity where backend_type = '\''client backend'\'' and query not ilike '\''%pg_stat_activity%'\'' group by 1,2,3 order by 4 desc"}' | jq .
   ```
3. **Clear stale sessions** (no SSH, read-only client cap is the real fix) — if `idle` / `idle in transaction` sessions are climbing, terminate them via the same `/database/query` path (still no host login):
   ```
   curl -s --max-time 15 -X POST \
     https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query \
     -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' \
     -d '{"query":"select pg_terminate_backend(pid) from pg_stat_activity where state = '\''idle'\'' and state_change < now() - interval '\''10 minutes'\''"}'
   ```
   The durable fix (#6258, ADR-105): inngest-server runs `--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1` (idle-time in MINUTES). `--postgres-max-open-conns` is PER-POOL, not total — inngest opens ~P separate Postgres pools (queue/state/history/api), so worst-case total = P × 5 ≤ 20; the idle-conns cap + 1-min idle drain release pinned Supavisor sessions so cutover-probe scans cannot ratchet the pool. The probe's leading indicator tracks this worst-case total (`INNGEST_CLIENT_CAP=20` in the workflow), not the pooler `default_pool_size` — so a `pool_pressure` alert means inngest's OWN connections approach the total ceiling (a stuck/looping function holding pooled connections, or more pools than expected). `default_pool_size` stays 30 — the #5562 30→15 revert is SUPERSEDED (its premise was falsified by the per-pool model; a 15-slot upstream would worsen exhaustion; see `apps/web-platform/infra/inngest.tf` + `decision-challenges.md`).
4. **`pool_probe_unavailable`** (401/403/non-JSON) is a *soft* mode — the probe itself is degraded, not the pool. Check the printed response body in the run log; a Supabase Management-API 401 is often a validation/scope signal, not pure auth (verify the PAT in Doppler `prd` and the `SUPABASE_ACCESS_TOKEN` GH secret).

### Cutover pre-flight-hang triage (`op=inventory` / `op=verify` `HTTP 000`) — #6258, ADR-106

An `op=inventory` / `op=verify` hook that returns **`HTTP 000` (empty body)** is a pre-flight scan
that ran past its budget — a distinct failure from the `[ci/inngest-pool]` `EMAXCONNSESSION` (500)
two-writer topology above. Since ADR-106 the scans are bounded (wall-clock deadline + page ceiling)
and **abandon-safe** (on timeout they emit a LOUD marker and `exit 1`, releasing the pool instead of
orphaning the scan). Triage off-box (no SSH):

1. **Query the in-surface marker** (the pre-flight path is now observable):
   ```
   scripts/betterstack-query.sh --grep 'SOLEUR_INNGEST_PREFLIGHT' --since 1h
   ```
   Read the discriminator fields on the `START` / `TIMEOUT` line for the run:
   - **No `SOLEUR_INNGEST_PREFLIGHT_START` for the run** → transport/host-down (the hook never
     executed) — check the Cloudflare tunnel + `webhook.service`, not the scan.
   - `TIMEOUT reason=deadline` with a progressing `pages=N`, `last_curl_exit=0` → a legitimately
     slow scan hit the wall-clock budget. Raise `PREFLIGHT_DEADLINE_S` (and the outer curl
     `--max-time`, keeping the sum bound) or the `INNGEST_MAX_PAGES` ceiling; do NOT narrow the window.
   - `TIMEOUT` with `last_curl_exit=28` / `pages_timed_out>0` → a **pool-pressure STALL** (the
     `HTTP 000` shape), NOT a slow scan — triage as `[ci/inngest-pool]` above (the durable fix is
     #6178, gated by #6230). `reason=gql_error` with `last_curl_exit=28` is the same stall surfacing
     via the `.data` guard.
2. **A fast LOUD error ≠ a hang.** Since ADR-106 the correct behaviour on an over-budget scan is a
   quick `exit 1` → webhook **non-200** with a `SOLEUR_*_TIMEOUT` cause in the run log's `::error::`.
   That is the fix working (it releases the pool), not a regression — re-run; the bounded transport
   retry (2 attempts) absorbs a transient two-writer 500.
3. **`op=verify` verdict ≠ transport-200.** A green op=verify sub-probe **transport** (no 000/500 on
   registry-probe / doublefire) is the ADR-106 success signal. The op=verify **JOB** still
   legitimately halts at its `registry_empty` precondition on the dark pre-cutover host
   (`cutover-inngest.yml:628-631`) — that is a verdict, not a transport hang, and a green op=verify
   job is a post-#6178 concern. Do NOT read a `registry_empty` halt as a pre-flight hang.

### Last-resort (host login)

Only after the three no-SSH steps above fail to resolve the pressure, inspect
inngest-server's own connection count on the host:
```
ssh root@<host> 'journalctl -u inngest-server.service -n 50 | grep -i "conn\|pool\|EMAXCONN"'
```
A host-level restart is the WRONG lever here (it worsens `EMAXCONNSESSION`); the
host login is for log inspection only, not remediation.

## External watchdog: functions-query degraded + restart `lock_contention` — #6407

Two soft/benign states the external inngest health watchdog handles WITHOUT paging or
churning a restart. Both are no-SSH — read Better Stack + the GitHub issue, never the host.

### `[ci/inngest-functions-degraded]` — `/v0/gql functions` transiently degraded (SOFT, NO restart)

**What it means.** The watchdog's cheap `/v0/gql functions` liveness read transiently failed
(a curl transport blip → the `__FETCH_FAILED__` envelope), but the on-host probe corroborated
the SAME loopback server's `/health` and got **HTTP 200** — inngest-server is UP and processing
events; only the functions read blipped. The classifier maps this to the soft mode
`functions_query_degraded`: **NO restart is dispatched, NO `[ci/inngest-down]` P1 is filed, and
the Sentry heartbeat stays `ok`** (no page). This is the #6407 false-positive class (the FATAL
sentinel used to fire `inngest_down` → restart even though inngest was healthy).

**Expected resolution.** Self-heals on the next `*/15` tick (the issue auto-closes on recovery).

**Persistence-escalation ceiling.** If the degraded state PERSISTS for ≥ ~45 min (3 `*/15`
cycles — the `/health`-ok-but-functions-permanently-wedged residual), the watchdog reclassifies
the verdict to `inngest_down`: it dispatches a restart AND flips the heartbeat to `error` (page).
First occurrence is soft; a sustained one is never masked forever.

**How to see it (no-SSH).** Query Better Stack for the verdict marker (tag `inngest-inventory`):
```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_INNGEST_LIVENESS_VERDICT
```
A `mode=degraded health_code=200` line confirms inngest is serving (soft); a `mode=down
health_code=<000|5xx>` line is a genuine down (the classifier routes it to `inngest_down` →
restart). No SSH — the marker rides Vector Source 4 → Better Stack Logs source 2457081. For a
second no-SSH signal, a GET of `https://deploy.soleur.ai/hooks/deploy-status` (HMAC + CF-Access)
shows `services.inngest_server`.

### Restart `reason=lock_contention` is BENIGN (not a restart failure)

When the watchdog dispatches `restart-inngest-server.yml` and the restart's verify poll reads
`reason=lock_contention` for `component=inngest`, it means **another deploy/restart already
holds the `ci-deploy.sh` critical section** (FD-200 `flock -n 200` loser) and will bring inngest
current — benign, not a failure. Per ADR-079 amendment #5960 (applied to the restart poll in
#6407), the poll treats it as NON-TERMINAL: it keeps polling for a fresh `component=inngest`
terminal success, and at budget expiry does a FINAL STATE re-read (`/hooks/deploy-status` for a
fresh inngest success, or `/hooks/inngest-liveness` healthy) before exiting benign — an
unconfirmed state fails loud (`UNVERIFIED`, exit 1). Marker (tag `ci-deploy`):
```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_INNGEST_RESTART_LOCK_CONTENTION
```

## Key rotation

Both `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` are TF-generated via `random_id` resources.

> **Secret delivery (#5560).** inngest-server reads `INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`, `INNGEST_SIGNING_KEY`, and `INNGEST_EVENT_KEY` from the doppler-run **environment** (owner-only `/proc/<pid>/environ`), never the `inngest start` argv (world-readable `/proc/<pid>/cmdline`). A rotated value loads on the next inngest-server restart/redeploy **without** being re-exposed on argv. **Ordering matters:** when rotating because a value leaked, deploy the env-delivery build FIRST (verify `ps -eo args | grep inngest` shows no secret), THEN rotate — rotating while an old argv-form image is still running would re-leak the new value immediately. After rotation, NEVER roll back to a pre-#5560 (argv-form) image.

<!-- lint-infra-ignore start -->

**⚠ The ONLY supported rotation path is the `terraform taint` flow below.** Do NOT rotate via the Doppler UI — every `doppler_secret` carries `lifecycle.ignore_changes = [value]`, so out-of-band Doppler-side changes are INVISIBLE to subsequent `terraform plan` runs. The provider skips the value read-back when `ignore_changes` is set; you'd get silent dashboard ↔ tfstate divergence. If you've accidentally rotated via the UI, run `terraform apply -replace=doppler_secret.<key>` to force TF to re-converge.

1. Identify which key to rotate. Replace `<KEY>` with `inngest_signing_key_prd` (or `_dev`, or `inngest_event_key_{prd,dev}`).
2. Taint the random_id so the next apply regenerates it:
   ```
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra taint random_id.<KEY>
   ```
3. Apply:
   ```
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra apply
   ```
   The companion `doppler_secret.<KEY>` ignores `value` changes via lifecycle; force a refresh:
   ```
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra apply -replace=doppler_secret.<KEY>
   ```
4. Restart the application + inngest-server so they pick up the new value:
   ```
   ssh root@<host> 'systemctl restart soleur-web-platform inngest-server.service'
   ```

<!-- lint-infra-ignore end -->

## CLI version bump

Inngest CLI version is pinned in `apps/web-platform/infra/inngest.tf` `locals` block. Bump procedure:

1. Find the new version + SHA256 at `https://github.com/inngest/inngest/releases`. The linux_amd64 SHA256 lives in the release's `checksums.txt` file.
2. Edit `inngest.tf`:
   ```
   inngest_cli_version = "vX.Y.Z"
   inngest_cli_sha256  = "<64-hex>"
   ```
3. Release the new bootstrap-image semver (N.N.N — separate from the embedded
   inngest-cli version) via the canonical flow below
   ([§ Bootstrap-image release](#bootstrap-image-release-tag--build--deploy--verify)):
   annotated tag → build → cloud-init pin bump → `workflow_dispatch` deploy →
   verify. On deploy, `inngest-bootstrap.sh` detects the version mismatch,
   pauses → drains → restarts → resumes (~5s downtime on loopback).

## Bootstrap-image release (tag → build → deploy → verify)

Releasing a new `soleur-inngest-bootstrap` image (changed `inngest-bootstrap.sh`,
`inngest-redis.*`, or bumped `inngest_cli_version`) is a **4-step coordinated
flow — the image build does NOT auto-deploy**. None of these steps use SSH
(`hr-no-ssh-fallback-in-runbooks`). Full context + gotchas:
`knowledge-base/project/learnings/workflow-patterns/2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md`.

1. **Push an ANNOTATED `vinngest-vX.Y.Z` tag** on the commit carrying the change
   (the repo forces annotated tags — a bare `git tag <name> <sha>` fails
   `fatal: no tag message?`):
   ```
   git tag -a vinngest-v1.1.16 <main-sha> -m "inngest-bootstrap v1.1.16: <what>"
   git push origin vinngest-v1.1.16
   ```
   Fires `build-inngest-bootstrap-image.yml` → builds + SHA-verifies + pushes the
   image. It does NOT deploy.
2. **Bump the cloud-init pin in lockstep** — `apps/web-platform/infra/cloud-init.yml`
   (the 3 `soleur-inngest-bootstrap:vX.Y.Z` refs) → `v1.1.16` in a PR. AC6 of
   `cloud-init-inngest-bootstrap.test.sh` asserts pin == the semver-max published
   `vinngest-v*` tag, so the tag in step 1 MUST exist first (else the bump PR's CI
   fails AC6); pushing the tag without bumping turns `main` red until this PR merges.
3. **Dispatch the deploy** (workflow_dispatch-only; the build never chains into it):
   ```
   gh workflow run deploy-inngest-image.yml -f tag=v1.1.16
   ```
4. **Verify via the deploy-status webhook (NO SSH)** — single authenticated GET:
   ```
   WS=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
   CID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
   CSEC=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
   HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WS" | sed 's/.*= //')
   curl -fsS -H "X-Signature-256: sha256=${HMAC}" \
     -H "CF-Access-Client-Id: ${CID}" -H "CF-Access-Client-Secret: ${CSEC}" \
     "https://deploy.soleur.ai/hooks/deploy-status" | jq '{component, tag, reason, exit_code}'
   ```
   Expect `{component:"inngest", tag:"v1.1.16", reason:"success"}` (durable backend
   live). `reason:"success_degraded_durability"` = the SQLite fail-safe fired
   (Redis not ready, #5547). Use the literal host `deploy.soleur.ai` — do NOT
   interpolate `$(doppler secrets get APP_DOMAIN_BASE …)` (reads empty / races).

## FR5 flag flip

`SOLEUR_FR5_ENABLED` gates PR-G (#3947) cohort exposure of the autonomous-draft trigger surface. NOT Terraform-managed (one-time human decision, not a credential). Flip procedure:

1. Confirm current state:
   ```
   doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain
   ```
2. Decide explicitly: this flips a production user-facing feature from gated to open. Confirm with `${USER}`.
3. Flip:
   ```
   echo 'true' | doppler secrets set SOLEUR_FR5_ENABLED -p soleur -c prd --no-interactive
   ```
4. Restart the web platform so it re-reads:
   ```
   ssh root@<host> 'systemctl restart soleur-web-platform'
   ```

## Unpause heartbeat

The BetterStack heartbeat is created with `paused = true` to avoid false alerts during the post-apply / pre-bootstrap gap. After [§ Fresh-host bootstrap](#fresh-host-bootstrap) succeeds and the first heartbeat ping is received, choose one of:

**Option A — UI (one-off):** Visit `https://uptime.betterstack.com/team/520508/heartbeats` → find `soleur-inngest-server-prd` → toggle pause off.

**Option B — API (agent-driveable):**
```
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -X PATCH https://uptime.betterstack.com/api/v2/heartbeats/460830 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"paused": false}'
unset TOKEN
```

<!-- lint-infra-ignore start -->

The `lifecycle { ignore_changes = [paused] }` on `betteruptime_heartbeat.inngest_prd` ensures future `terraform apply` runs do NOT revert the unpause regardless of which option you used.

Confirm pings are flowing:
```
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -s https://uptime.betterstack.com/api/v2/heartbeats/460830 \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.attributes | {status, last_ping_at}'
unset TOKEN
```

<!-- lint-infra-ignore end -->

## SQLite event-store retention

The Inngest SQLite store at `/var/lib/inngest/main.db` grows over time with retained events. There is no built-in rotation. At alpha-internal volume (~1k events/day × ~2KB avg), the store grows ~60MB/month — benign for ~1 year, then unbounded.

**Cleanup procedure** (when `du -sh /var/lib/inngest/` exceeds ~500MB OR before the host's volume usage triggers `disk-monitor.sh` alerts):
```
ssh root@<host> 'systemctl stop inngest-server.service && \
  sqlite3 /var/lib/inngest/main.db "DELETE FROM events WHERE ts < datetime(\"now\",\"-30 days\"); VACUUM;" && \
  systemctl start inngest-server.service'
```
Stopping inngest-server before VACUUM is required (SQLite write lock). Downtime ~5s for typical store sizes; longer for stores >1GB.

**Automation deferred:** the operator runs this manually for now. If event volume increases to where monthly manual cleanup becomes a chore, file a follow-up issue to wire a weekly systemd timer alongside `inngest-heartbeat.timer`.

## Durable backend (Supabase Postgres + self-hosted Redis) — #5450

> Migrating Inngest off bundled SQLite + in-memory Redis (ephemeral root disk) onto
> **Supabase Postgres** (`--postgres-uri`, dedicated EU project, session pooler :5432) +
> **self-hosted Redis** (`--redis-uri`, AOF on `/mnt/data`). Closes the silent-loss gap where a
> host re-provision drops every HTTP-armed `event-scheduled-reminder`. Executes the Postgres
> migration ADR-030 deferred. Plan: `knowledge-base/project/plans/2026-06-17-feat-inngest-durable-backend-supabase-postgres-plan.md`.

### Host-rebuild durability matrix (per mechanism)

"Dies with session?" (process restart) is distinct from "Survives host re-provision?" (fresh root disk).
The bug is the **host-rebuild** column, not the session column.

| Mechanism | Re-arms on web redeploy? | Survives process restart? | Survives host re-provision (pre-migration) | Survives host re-provision (post-migration) |
|---|---|---|---|---|
| `cron-*` (recurring) | Yes (registered every deploy) | Yes | Yes (re-armed on next deploy) | Yes |
| `oneshot-*` (first-arm) | n/a | Yes | Yes (boot-arm re-arms, ADR-046 I4) | Yes |
| `oneshot-*` (conditional re-arm, diverged ts) | n/a | Yes | **No — silent loss** | Yes (durable queue) |
| `event-scheduled-reminder` (HTTP-armed future `ts`) | No | Yes (queue in Redis) | **No — silent loss** | **Yes (durable Redis AOF)** |

### Phase 0 spike verdicts (2026-06-17, inngest v1.19.4, local docker harness — the Phase 1 gate)

CLI semantics (`inngest start --help`): `--postgres-uri` = "configuration and history persistence
(defaults to SQLite)"; `--redis-uri` = "external **queue and run state** (defaults to self-contained
**in-memory Redis** with periodic snapshot backups)". The armed-event **queue lives in Redis**, not Postgres.

- **0.2 FR1 durability boundary — durable Redis is MANDATORY.** Wiped-volume restart (recreate the
  inngest container = fresh root disk; Postgres + external-Redis volumes persist):
  - Postgres-only (default in-memory Redis): armed future-`ts` event **LOST** (did not fire).
  - Postgres + external durable Redis (AOF, `appendfsync everysec`): armed event **SURVIVED**, fired at its `ts`.
  - → Configure **both** Postgres and durable Redis (since #5560 both are delivered via the doppler-run **environment** — `INNGEST_POSTGRES_URI` + a constructed `INNGEST_REDIS_URI` — NOT on argv; see § Secret delivery). Postgres alone does NOT persist the queue.
- **0.3 Fail-closed vs silent fallback — Inngest FAILS CLOSED.** With a reachable-but-refused backend
  it exits non-zero (`failed to connect … connection refused`); `/health` never returns 200; **no**
  silent degrade to a healthy SQLite state. → The existing `/health` 200 gate already catches an
  *unreachable* backend. The residual silent-non-durable risk is **sentinel-absent** (ExecStart drops the
  durable config → defaults to SQLite **while** `/health`=200). The hard gate therefore asserts: (a) the
  running inngest cmdline contains the non-secret `--postgres-max-open-conns` durable sentinel (**#5560**:
  the postgres/redis URIs + signing/event keys are delivered via the doppler-run **environment**, never
  argv — `/proc/<pid>/cmdline` is world-readable, so detection keys on the sentinel, not `--postgres-uri`),
  (b) `inngest-redis` unit active + Redis ping, (c) Postgres reachable — NOT a "fail-open post-start assertion".
- **0.4 Cutover-recovery — enumeration is FEASIBLE; no app-side ledger required.** The server's GraphQL
  (`/v0/gql` `eventsV2(filter:{from!,until,eventNames,query,includeInternalEvents})`) returns received
  events by time window, including future-dated `reminder.scheduled`. Cutover recovery = quiesce arming →
  enumerate the OLD server's future-dated, not-yet-fired `reminder.scheduled` events → re-arm on the new
  Postgres+Redis server (cross-ref `runs` to exclude already-fired → avoid double-posting a comment).
  Dual-run-drain (run old SQLite server until armed reminders fire) is the simpler fallback. **No
  `scheduled_reminders` Supabase migration / boot reconciler is needed** (removes that conditional Phase-1 scope).
- **0.5 Pooler mode — session :5432 only (LIVE-confirmed).** Inngest uses sqlc prepared statements;
  Supabase **transaction pooler :6543 breaks them** (PgBouncer transaction mode). Use **Supavisor
  session pooler :5432**. **Live-verified 2026-06-17**: inngest v1.19.4 connected to the dedicated EU
  project (`soleur-inngest-prd`, ref `pigsfuxruiopinouvjwy`, `aws-0-eu-west-1.pooler.supabase.com:5432`,
  user `postgres.<ref>`) and **ran its migrations** cleanly (`ran database migrations db=postgres`).
  The dedicated project IS the isolation boundary, so the connection uses the project's `postgres` role
  via the pooler (verified) rather than a custom role (custom-role-via-Supavisor routing is the
  unverified part; a dedicated role inside an already-isolated project adds pooler-auth risk for
  marginal benefit — so the planned `inngest-supabase-bootstrap.sql` role bootstrap is intentionally
  dropped). `INNGEST_POSTGRES_URI` is set out-of-band in Doppler prd (see inngest.tf).

### Availability coupling (permanent, post-migration)

Post-cutover Inngest **cannot start** without Supabase + Redis reachable (the in-memory fallback is
gone — proven fail-closed in 0.3). Pre-migration it survived a Supabase outage on local SQLite; it no
longer will. Knowingly traded for durability + PITR + ADR-030 closure. The dedicated Inngest Supabase
project + co-located Redis keep the blast radius off the main app's project.

### Cutover procedure (Phase 2 — low-traffic window, rollback-ready)

**Before any cutover, consult:** [Destructive datastore migration safety pattern](../../../project/learnings/best-practices/2026-06-18-destructive-datastore-migration-backup-inventory-after-diff.md) — every destructive datastore migration takes (a) a recovery backup, (b) a full inventory BEFORE, (c) an after-inventory + diff. Steps 0.5 and 5 below are this runbook's instance of that pattern.

The KEYSTONE risk (plan §Sharp Edges): armed `reminder.scheduled` events live ONLY in Inngest state —
there is no app-side reminder store. A fresh-Postgres cutover loses them unless they are enumerated and
re-armed. Run these steps in order, **starting with Step 0** (the secret-provisioning precondition —
`INNGEST_REDIS_PASSWORD` is not created at merge time); the connection string is set out-of-band in
Doppler prd (`INNGEST_POSTGRES_URI`, see inngest.tf) and must be **URL-safe** (the provisioned value is
hex — no percent-encoding needed; if rotated to a password with reserved chars, URL-encode before
setting).

0. **Provision the Redis secret** (one-time precondition — `INNGEST_REDIS_PASSWORD` is NOT created at
   merge time; the `apply-web-platform-infra.yml` allow-list now reconciles it on the next infra merge,
   but for an immediate cutover run, apply it explicitly here). `INNGEST_POSTGRES_URI` is already present
   (set out-of-band, see inngest.tf). From the repo root:
   ```bash
   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID  -p soleur -c prd_terraform --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
   terraform -chdir=apps/web-platform/infra init -input=false
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform -chdir=apps/web-platform/infra apply \
       -target=random_password.inngest_redis_password_prd \
       -target=doppler_secret.inngest_redis_password_prd
   # Confirm the secret now exists (read-only, no SSH):
   doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd --plain   # → 48-char URL-safe value
   ```
   If the value is already present (a prior auto-apply or manual run minted it), this is a clean no-op —
   proceed to step 0.5.
0.5. **Pre-cutover safety gates (MANDATORY — #5509).** Before quiescing, capture a recovery point and a
   full-state baseline so this destructive cutover is reversible and verifiable (no SSH):
   ```bash
   gh workflow run cutover-inngest.yml --field op=backup      # Hetzner server snapshot (full root disk incl. /var/lib/inngest); logs the image id
   gh workflow run cutover-inngest.yml --field op=inventory   # BEFORE baseline: {functions, event_names, armed_reminder_ids}
   ```
   Record the backup **image id** (the run logs `DELETE /v1/images/<id>` to free it after the cutover is
   confirmed) and save the BEFORE inventory block from the run log — both feed step 5's correctness check.
   Do NOT proceed to quiesce until the `op=backup` snapshot action reports `success`.
1. **Quiesce arming** (no reminder armed into the doomed old SQLite mid-cutover):
   ```bash
   doppler secrets set INNGEST_CUTOVER_QUIESCE=1 -p soleur -c prd --no-interactive
   # POST /api/internal/schedule-reminder now returns 503 + Retry-After: 120.
   ```
2. **Reminder survival — DEFAULT: dual-run-drain; FALLBACK: no-SSH enumerate + re-arm.** Armed
   `reminder.scheduled` events live ONLY in Inngest state (verdict 0.4 — no app-side ledger). A
   fresh-Postgres cutover drops any still-armed reminder unless it is allowed to fire first OR is
   enumerated and re-armed. There is **no operator shell step** here — both paths are no-SSH.
   - **DEFAULT — dual-run-drain (simplest, no re-arm risk):** with arming quiesced (step 1), let the
     OLD SQLite server keep running until its already-armed reminders fire on their own. When the
     soonest pending fire-time has passed, proceed to deploy (step 4). No enumeration, no re-arm, no
     double-fire window. Best when only a few near-term reminders are armed.
   - **FALLBACK — capture + re-arm (when draining is not viable):** when too many reminders are armed
     or they fire too far out to wait, **persist the still-armed set ON-HOST BEFORE the deploy** — a
     post-deploy `op=rearm` self-enumerate would query the NEW (empty) Postgres+Redis backend and
     silently lose every reminder (#5542):
     ```bash
     gh workflow run cutover-inngest.yml --field op=enumerate   # OPTIONAL visibility: logs count + reminder_ids
     gh workflow run cutover-inngest.yml --field op=capture     # MANDATORY: persists records on-host pre-deploy
     ```
     `op=capture` drives `/hooks/inngest-rearm-reminders` with `mode=capture`: the host script queries
     the OLD server's `eventsV2`, reconstructs the FULL re-armable payload from each event's `raw`
     envelope (the legacy `id name receivedAt` query was payload-incomplete), drops already-fired events
     via the `runs` cross-ref, paginates to exhaustion, and writes the records to
     `/var/lib/inngest/cutover-capture.json` — under the `--sqlite-dir` volume, which survives the
     cutover's systemd restart (a config change, not a host re-provision). Records stay on-host
     (P2-sec-a) — only counts + `reminder_id`s surface in the run log. Then re-arm AFTER the deploy +
     quiesce-clear in step 6 (`op=rearm`), which **consumes the capture file** (NOT a post-deploy
     self-enumerate) and deletes it on full success. The re-arm routes back through `schedule-reminder`,
     which recomputes the Inngest dedup `id`/`ts` so an event that ALSO survived in state dedups instead
     of double-firing.
3. **Drain in-flight runs** — confirm zero `Running` status for ~60s (or accept-and-document that
   in-flight runs are abandoned; the reminder `post-comment`/`run-check` steps are not idempotent on
   replay, so a re-arm of an already-fired reminder would double-post).
4. **Deploy** via the release pipeline (no SSH): `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.14`.
   The deploy arg is the OCI **image tag** `v1.1.14` (space-separated, matching the CLI-version-bump
   step) — NOT `vinngest-v1.1.14`: the build workflow strips the `vinngest-` GIT-tag prefix and publishes
   the image as `v1.1.14` (GHCR has `v1.1.14`; `vinngest-v1.1.14` does not exist and would fail to pull).
   The `verify_inngest_health` HARD gate fails the deploy if `--postgres-uri` is set but `--redis-uri`
   is absent OR `inngest-redis.service` is inactive.
5. **Verify durability.**
   - **DEFAULT (non-destructive):** the deploy's own `verify_inngest_health` HARD gate (step 4) already
     asserts `--postgres-uri` ⇒ `--redis-uri` present + `inngest-redis` active + `/health` 200 +
     `/v1/functions` ≥1 cron. Combined with the spike-0.2 evidence (a wiped-volume restart survived on
     durable Redis), this is sufficient proof for a normal cutover — no extra step needed.
   - **OPT-IN (destructive, end-to-end proof):** to exercise the real wiped-volume invariant in prod
     shape with no remote shell:
     ```bash
     gh workflow run cutover-inngest.yml --field op=verify-wiped-volume   # async; polls verify-status
     ```
     This drives `/hooks/inngest-wiped-volume-verify`, which **aborts loudly unless the armed set is
     empty** (the real safety gate — it will NOT wipe with a real reminder pending), arms an
     unregistered-`named-check` throwaway that fires a run but posts **zero** comments, wipes
     `/var/lib/inngest`, restarts, and asserts `/health` + `/v1/functions` + the throwaway fired. Only
     run it once the armed set is drained/re-armed.
   - **Correctness diff (MANDATORY — #5509):** re-run `op=inventory` (the AFTER baseline) and diff it
     against the BEFORE block from step 0.5:
     ```bash
     gh workflow run cutover-inngest.yml --field op=inventory   # AFTER baseline
     ```
     Expected: `functions` identical (re-registered every deploy by construction) and `event_names`
     identical. `armed_reminder_ids` MUST be re-present after re-arm (FALLBACK path, step 6) OR
     empty-by-design (DEFAULT dual-run-drain, where the armed set fired on the old server pre-cutover).
     Any unexplained drop in `functions`/`event_names`, or a missing `armed_reminder_id` after re-arm,
     is a cutover defect — restore from the step 0.5 backup image before clearing quiesce.
6. **Re-open arming + re-arm recovered work** (no remote shell):
   ```bash
   doppler secrets set INNGEST_CUTOVER_QUIESCE= -p soleur -c prd --no-interactive  # clears the flag
   # FALLBACK path only: re-arm from the on-host capture persisted in step 2 (op=capture).
   gh workflow run cutover-inngest.yml --field op=rearm
   ```
   Run `op=rearm` ONLY after the quiesce flag is cleared — the host script aborts loud (does not
   silently drop) if it gets a 503 because quiesce is still set. `op=rearm` (mode `rearm-from-capture`)
   consumes `/var/lib/inngest/cutover-capture.json` from step 2 and deletes it on FULL success; a
   missing/corrupt capture is FATAL (non-200), never a silent self-enumerate of the empty new backend.
   - **Retry window (re-arm is replay-on-full-set).** On a partial failure the capture is RETAINED and a
     re-run re-POSTs the entire set; `schedule-reminder` recomputes the dedup `id`/`ts` so a
     still-pending reminder dedups instead of double-arming — but a reminder that *fires* between attempts
     is non-idempotent (it double-posts its comment, same hazard as step 3). So retry `op=rearm` promptly
     and only while quiesce is cleared; do not let hours pass between a partial re-arm and its retry.
   - **Aborted cutover leaves a landmine.** If you run `op=capture` then ABORT before `op=rearm`, the
     capture file persists on-host. A steady-state `op=rearm` (mode `rearm`, the default) deliberately
     IGNORES it (self-enumerates the live backend), so it will not hijack a routine re-arm — but it is
     stale clutter. After an aborted cutover, re-run the cutover from `op=capture` (which overwrites it),
     or let the next successful cutover `op=rearm` consume it.
7. **Rollback tripwire** — reverting ExecStart to `--sqlite-dir` is data-safe ONLY before any *real*
   (non-throwaway) reminder is armed against Postgres. After that the stale SQLite is missing those
   reminders AND could double-fire ones Postgres recorded → **forward-fix only**. On a committed
   cutover, wipe the old `/var/lib/inngest` SQLite so an accidental SQLite boot cannot replay dead
   reminders.

## Dedicated-host cutover (Phase 2, `op=execute` gated sequence) — Ref #6178

> **This is the ADR-100 dedicated-host extraction cutover** (move Inngest off the
> co-located web host onto the singleton `hcloud_server.inngest` at `10.0.1.40`),
> distinct from the same-host durable-backend cutover above. It flips the dedicated
> host from its **dark, non-prod Postgres** backend to **prod Postgres**, gated behind a
> Redis `FLUSHALL` + `DBSIZE==0` assertion (ADR-100 Decision 6/6a). **Every operator
> action here is a Doppler write, a `workflow_dispatch`, or a Better Stack read — there is
> NO `ssh`/host-shell step** (`hr-no-ssh-fallback-in-runbooks`; the dedicated host is
> deny-all-public). Only counts + `reminder_id`s / `function_id`s ever surface in a run
> log — never reminder bodies, actors, or connection strings.

**Precondition (do this DURING the dark window, well before the maintenance window):** the
flip oneshot (`inngest-cutover-flip.sh` + `.service`/`.timer` + `inngest-server-flip-guard.sh`)
must already be baked into the OCI image and installed on the dark host. Installing it is a
cloud-init/OCI change that **force-replaces the singleton** — zero prod-downtime by
construction (the host is on the non-prod dark backend serving zero prod crons; the AOF
Redis volume survives the replace). Never run that force-replace inside the maintenance
window. The poll timer ships **enabled and stays enabled for the host's whole life** — the
FSM flag (`INNGEST_CUTOVER_FLIP`) is the sole gate, so arming is pure Doppler writes with no
`systemctl` step.

### Op order (the gated sequence)

`op=execute` → **`op=arm` (no-SSH flip arm)** → **operator app-repoint (2.4)** → `op=rearm` →
`op=verify`. `op=execute` automates the web-host-expressible spine (2.0 → 2.2) and then
**withholds a SEAM**. As of #6369 the flip arm (2.2b/2.3) is **no longer an operator Doppler
write** — it is the no-SSH **`op=arm`** dispatch (a prod-write behind explicit dispatch + the
`inngest-cutover` GitHub Environment required-reviewer gate, which satisfies
`hr-menu-option-ack-not-prod-write-auth`: the dispatch + approval IS the ack). The remaining true
operator seams are **2.2a** (web-2 freeze/recreate lifecycle) and **2.4** (app-repoint, a code
merge) — both printed in the SEAM as an out-of-band hand-off.

> **`op=quiesce-web` (#6178) — the no-SSH remediation when the 2.2 gate reports STILL
> RUNNING.** The `op=execute` 2.2 gate only CHECKS (inventory non-200 = quiesced); it has no
> path to actually STOP the old co-located scheduler. When the gate fails with
> `2.2 QUIESCE HARD GATE FAILED / STILL RUNNING`, run `op=quiesce-web` (below) to
> stop+disable inngest across the host-set over the private net (HMAC + CF-Access, **no
> SSH**), then re-run `op=execute`. Operators have no SSH — this replaces the old operator
> host-shell stop-and-disable step (`hr-no-ssh-fallback-in-runbooks`). op=quiesce-web POLLS
> `/hooks/deploy-status` for each host's synchronous `quiesced` verdict (not-serving AND
> unit-inactive AND not-enabled) — it does NOT immediate-probe (the unit's
> `TimeoutStopSec=180` means the async stop can lag the 202). Its own failure verdicts each
> print a no-SSH forward action: `inngest_still_serving`/`inngest_still_enabled` (persistent
> = the unit is being RESURRECTED → pull `reason=` from `/hooks/deploy-status` + Better Stack
> `logger -t ci-deploy` and investigate what restarts/re-enables it — do **not** SSH);
> `quiesced_peer_fanout_unaccepted` (a peer 202 was not accepted → check the peer host + the
> web→web:9000 firewall + re-dispatch); UNKNOWN/000 (webhook unreachable → check
> CF-Access/HMAC + re-dispatch). NB the two "quiesce" meanings differ:
> `INNGEST_CUTOVER_QUIESCE` (Doppler arming-quiesce, blocks new reminders into the old
> SQLite — the same-host cutover above) vs `op=quiesce-web` (stop-and-disable the scheduler
> **process**).
>
> ```bash
> gh workflow run cutover-inngest.yml --field op=quiesce-web   # no-SSH stop+disable across the host-set; poll deploy-status for reason=quiesced
> ```

> **Pre-flight scans are bounded + observable (#6258, ADR-106).** The `op=inventory` /
> `op=verify` sub-probe scans (`inngest-inventory`, `inngest-registry-probe`,
> `inngest-doublefire-probe`) now enforce a wall-clock deadline + page ceiling and are
> abandon-safe (on timeout they emit `SOLEUR_INNGEST_PREFLIGHT_TIMEOUT` and `exit 1` →
> webhook non-200, releasing the pool). If a pre-flight op returns `HTTP 000`/`500`, use the
> **[Cutover pre-flight-hang triage](#cutover-pre-flight-hang-triage-opinventory--opverify-http-000--6258-adr-106)**
> above — a fast LOUD `SOLEUR_*_TIMEOUT` error is the fix working, NOT a hang, and an
> `op=verify` halt at its `registry_empty` precondition is a legitimate verdict on the dark
> pre-cutover host, NOT a transport failure.

1. **`op=execute`** (pre-flip orchestrator — no prod-write):
   ```bash
   gh workflow run cutover-inngest.yml --field op=execute
   ```
   It runs: **2.0** empty-registry pre-flight (aborts if the dark registry is non-empty — see
   remediation below); **2.1** capture of still-armed reminders (records persist on-host;
   `Σcaptured` + `reminder_id`s only in the log); **2.2** quiesce followed by a **QUIESCE HARD
   GATE** that re-inventories the **LB-reachable host** and **fails loud + withholds the SEAM**
   if inngest still serves there. If the gate fails (`STILL RUNNING`), run **`op=quiesce-web`**
   (the no-SSH stop+disable across the host-set — see the op-order note above) and re-run
   `op=execute`; the gate is a CHECK, `op=quiesce-web` is the ACT. When the gate passes it
   prints the SEAM with the exact operator steps below, then exits 0. Read the SEAM from the
   run log:
   ```bash
   gh run view <op=execute run id> --log | grep -E '::notice::|::error::|::warning::'
   ```

   > **DI-C3 LIMITATION — web-2 is NOT auto-verified (tracked #6227).** Both 2.1
   > capture and the 2.2 gate reach inngest via a web-host webhook that resolves over the **load
   > balancer** to `127.0.0.1:8288` on **whichever host the LB routed to** — there is no
   > host-targeting mechanism today (no firewall rule for web→web:8288 + no host-targeting
   > inventory/capture hook; that per-host fan-out infra is DEFERRED, see the tracking issue).
   > So `op=execute` positively confirms only the **LB-reachable** host. The **weight-0 warm-
   > standby web-2 (10.0.1.11)** self-arms oneshots into its **own** Redis independent of LB
   > weight, and is **neither captured nor quiesce-verified** by CI. **Step 1a below (web-2
   > quiesce) is MANDATORY, not advisory** — skipping it can (a) silently drop a reminder that
   > web-2 self-armed into its local Redis, and (b) leave a surviving web-2 scheduler
   > double-firing against prod Postgres that `op=verify` cannot detect (it reads only the
   > dedicated host's runs).

> **SUPERSEDED (#6538, 2026-07-17): web-2 was retired and destroyed; `var.web_hosts` is now
> web-1 only.** There is no warm-standby scheduler left to self-arm reminders or double-fire, so
> step 1a and the DI-C3 limitation above are **historical** — the cutover now runs against a
> single-host web set (web-1, `10.0.1.10`), which `op=execute` fully captures + quiesce-verifies.
> Skip 1a unless a second self-arming web host is ever re-provisioned before the cutover. (#6230
> — the web-2 quiesce action-required — was closed as obviated by this retirement.)

1a. **[HISTORICAL — web-2 retired #6538] Quiesce web-2 (was MANDATORY — DI-C3, before arming the flip).** `op=quiesce-web` (when run)
   now stop+disables web-2's SCHEDULER too (an ACT over the private net — a real improvement
   over operator-only web-2 handling), **but the freeze/recreate lifecycle STILL REMAINS
   MANDATORY**: CI cannot VERIFY web-2 (LB-scoped) AND web-2's local reminders were never
   captured (2.1 capture is also LB-scoped) — a fan-out stop does not capture/re-arm them, and
   web-2 self-arms oneshots into its OWN Redis independent of LB weight. So do **not** read a
   green `op=quiesce-web` as "web-2 handled." Recreate web-2 per the plan's **web-2
   freeze/recreate lifecycle** (§Bounded-outage / Downtime): take web-2 **out of the warm-standby
   rotation and recreate it onto the post-cutover config** so no surviving web-2 scheduler
   self-arms a reminder into its local Redis. This is a lifecycle action (freeze → recreate),
   **not** an `ssh`/host-shell step (`hr-no-ssh-fallback-in-runbooks`). Do **not** proceed to
   step 2 until web-2 is recreated. Tracks #6227 (real per-host web→web fan-out to auto-verify
   web-2).

2. **Arm the flip (2.2b/2.3) — dispatch the no-SSH `op=arm` verb (#6369).** This REPLACES the
   former three manual Doppler writes. `op=arm` performs all three writes on
   **`soleur-inngest/prd`** itself and confirms the on-host FSM reached `done` via Better Stack,
   with **no secret value ever echoed** (AC-NOBODY):
   ```bash
   gh workflow run cutover-inngest.yml --field op=arm
   ```
   Then **approve the `inngest-cutover` GitHub Environment required-reviewer gate** on the run —
   that approval IS the prod-write ack (`hr-menu-option-ack-not-prod-write-auth`; the dispatch +
   approval replace the old Doppler-console write). What `op=arm` does, in order:
   - **G1 pre-write FSM-state guard (DI-C2):** refuses to arm over a non-safe
     `INNGEST_CUTOVER_FLIP` state (armed/flipping/flushed/done) — a second arm would re-`FLUSHALL`
     the now-PROD Redis and wipe the live cron queue.
   - **G2 read-through sources (ADR-100 6b):** reads `INNGEST_POSTGRES_URI` +
     `INNGEST_HEARTBEAT_URL` **from `prd_terraform`** via the existing read-only `DOPPLER_TOKEN`
     (the canonical prod values already live there — **no operator seed**), masking each value.
   - **G3 positive prod-URI assertion (DI-C3):** asserts the value differs from the current dark
     `soleur-inngest/prd` URI, uses the `:5432` session pooler (never `:6543`), and targets the
     prod host — all value-silent.
   - **G4/G5 writes:** `INNGEST_POSTGRES_URI` → `INNGEST_HEARTBEAT_URL` → `INNGEST_CUTOVER_FLIP`
     set to `armed` (last), each via **stdin** (never argv), exit-gated. The enabled 30s poll
     timer then drives the forward FSM **stop → `FLUSHALL` → assert `DBSIZE==0` → start → `done`**.
   - **G6 confirm:** polls Better Stack for the `logger -t inngest-cutover-flip` line, time-bounded
     to the arm moment (so a stale prior terminal line cannot false-succeed), requiring `"flag":"done"`
     / `"exit_code":0` (the FSM state lives in the `flag` field; `reason` is a cause string like
     `flip-complete`); it FAILS LOUD on `aborted`/`rolled-back`/timeout (**do NOT proceed to 2.4**
     in that case — see aborted-state recovery below).

   > **No operator secret-seed (#6369 / ADR-100 Decision 6b).** The prod `INNGEST_POSTGRES_URI`
   > already lives in `prd_terraform` (canonical, `:5432`, distinct from the dark value), so op=arm
   > reads it **read-through** — there is **no `INNGEST_POSTGRES_URI_PROD` seed and no pre-window
   > human write**. The only new credential is the TF-provisioned read/write token
   > (`doppler_service_token.inngest_arm_write`) published as the `inngest-cutover` **environment**
   > secret `DOPPLER_TOKEN_INNGEST_ARM` (required-reviewer gated).

3. **Independent confirm / troubleshooting (optional — op=arm already gates on this).** op=arm
   only exits 0 after Better Stack shows the FSM `done`. To re-read the line yourself
   (`hr-no-dashboard-eyeball-pull-data-yourself`), or if op=arm failed loud at G6:
   ```bash
   doppler run -p soleur -c prd_terraform -- \
     scripts/betterstack-query.sh --since 30m --grep inngest-cutover-flip --raw-only --limit 20
   ```
   A clean flip surfaces a `"flag":"done"` line (with `"reason":"flip-complete"`) within a single 30s poll of arming. A
   `"reason":"dbsize-nonzero"` line means the DBSIZE gate tripped; a `"reason":"unexpected-exit(...)"`
   line means a flag-write/systemctl failure drove the flag to terminal `aborted` (the ERR-trap
   loud-fail) → either way see **aborted-state recovery** below. Do **NOT** `ssh`/`cat` the
   deny-all-public host to read state — `cat-inngest-cutover-state.sh` exists on-host as a **debug
   aid only**, never the operator gate. (These tags are on the `vector.toml` Source 4 allowlist —
   see the `vector-pii-scrub.test.sh` drift-guard — so they are guaranteed to ship off-box.)

3b. **Post-cutover: revoke the arm-write token (#6369, security F4/D6 — after AC17).** Once
   `op=verify` confirms exactly-once on the dedicated host, `DOPPLER_TOKEN_INNGEST_ARM` is a
   **standing read+write handle to the now-armed prod `INNGEST_POSTGRES_URI`** on
   `soleur-inngest/prd`. Rotate + revoke it (no-SSH); there is **no seed to delete** (reads are
   read-through):
   ```bash
   # (a) mint a fresh key + orphan the old one (propagates to the env secret in the same apply):
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform -chdir=apps/web-platform/infra apply -replace=doppler_service_token.inngest_arm_write
   # (b) revoke the orphaned key so no standing prod-DSN read handle survives:
   doppler configs tokens revoke --project soleur-inngest --config prd --slug <orphaned-token-slug> --yes
   ```
   The next per-merge apply keeps a fresh `inngest-cutover` env secret available for a future
   cutover; the required-reviewer gate means it cannot be used without an approved dispatch.

4. **App-repoint (2.4).** Merge the `ci-deploy.sh` `INNGEST_BASE_URL` → `http://10.0.1.40:8288`
   change (both the canary and prod sites) and redeploy the web app so the functions re-sync
   (register) onto the dedicated host. `op=rearm`/`op=verify` precondition-check that this
   landed (registry-non-empty).

5. **`op=rearm`** (re-arm the captured reminders after the flip):
   ```bash
   gh workflow run cutover-inngest.yml --field op=rearm
   ```
   It precondition-checks 2.4 (registry non-empty), consumes the on-host capture, and
   reconciles `Σcaptured == rearmed`; a delta **fails loud** with the missing `reminder_id`s and
   offers a retry (in-window ticks are not auto-backfilled).

6. **`op=verify`** (exactly-once):
   ```bash
   gh workflow run cutover-inngest.yml --field op=verify
   ```
   It reaches the dedicated GQL over the private net via `/hooks/inngest-doublefire-probe`
   (P1-12 — the runner cannot curl `10.0.1.40` directly), buckets every run by
   `(functionID, floor(startedAt / cron_period))`, and fails if any bucket has >1 run
   (double-fire). It also auto-emits the missed-tick `soleur:trigger-cron` list for ticks that
   fell in the quiesce→register gap (P2-16). Re-fire that list via `soleur:trigger-cron`.

   > **`op=verify` caveats — read before trusting the verdict:**
   > - **NOT a web-2 double-fire detector (P2-a / DI-C3).** The doublefire-probe reads **only the
   >   dedicated host's** (`10.0.1.40`) run history. A surviving weight-0 web-2 scheduler fires
   >   against prod Postgres via its **own loopback backend PRE-repoint**, whose runs never appear
   >   on the dedicated host — so `op=verify` cannot see a web-2 double-fire. The **operator's
   >   mandatory web-2 quiesce (step 1a)** is the control; `op=verify` does not substitute for it.
   > - **Single global `CRON_PERIOD` (P2-c).** One `CUTOVER_CRON_PERIOD_SECONDS` (default 3600)
   >   buckets **every** function. The exactly-once verdict is sound **only if every registered
   >   cron period ≥ `CRON_PERIOD` and hour-aligned**; a cron firing faster than the period yields
   >   >1 run/bucket (false-positive, blocks verify — safe) or a boundary-straddling double-fire
   >   reads clean (false-negative — unsafe). If any cron is sub-hourly, re-run with
   >   `CUTOVER_CRON_PERIOD_SECONDS` set to the **shortest** registered cron period.
   > - **Non-empty registry ≠ fully synced (P3-c).** The precondition only proves the re-sync
   >   **started**. Set `CUTOVER_REGISTRY_BASELINE` to the pre-cutover `op=inventory` `functions`
   >   count so `op=rearm`/`op=verify` enforce `function_count ≥ baseline` (a half-sync otherwise
   >   passes); without it, confirm the count matches the pre-cutover inventory manually.

### 2.0 registry-non-empty remediation (P1-6)

If `op=execute` aborts at 2.0 with `registry-probe: dark registry NON-empty`, the dark host has
functions registered against it — flipping now would carry stray state onto prod Postgres. To
empty the dark registry and re-run (all no-SSH):
1. Confirm `INNGEST_POSTGRES_URI` on `soleur-inngest/prd` still points at the **non-prod dark**
   backend (it must NOT be the prod URI yet — that is only written at step 2 above).
2. Stop whatever dev/test backend is re-syncing functions into the dark server (typically a
   stray `--sdk-url` pointing at the dark host), so nothing re-registers after you clear it.
3. Clear the dark registry (re-provision the dark host via the
   `apply_target=inngest-host-replace` dispatch, which force-replaces onto the empty dark
   backend), then re-dispatch `op=execute`. The 2.0 probe must report `registry_empty:true`
   before the SEAM is reachable.

### nftables web-host allowlist parity (#6608)

`inngest-host.tf` `local.web_host_private_ips` is rendered into the dedicated host's nftables
`ip saddr { … }` allowlist for the `:8288`/`:8289` control API (SEC-H2). It must equal the live
web-host roster (`var.web_hosts` `private_ip` set). web-2 (`.11`) was retired 2026-07-17 (#6538),
so the roster is web-1 (`10.0.1.10`) only; the literal was corrected to match (#6608) and is now
**drift-guarded** by `inngest-host.test.sh` §6b (the allowlist IP set must byte-equal the
`var.web_hosts` private_ip set — the edge to `var.web_hosts` the roster previously lacked, so a
future roster change red-lines CI until the allowlist follows).

**Apply path — the literal is baked into `user_data`, so the edit force-replaces the host.**
`hcloud_server.inngest` deliberately carries **no** `lifecycle.ignore_changes=[user_data]`
(ADR-100), and its resources are **excluded from the per-PR CI `-target`**, so the corrected
literal is **inert at merge** — nothing applies. Deliver it by folding into the HELD Phase-2
cutover re-provision (the same `apply_target=inngest-host-replace` dispatch above that delivers the
#6197 arm64-Vector wiring), which is scoped, AOF-volume-preserving, and menu-ack authorized. Do
**not** fire a separate gratuitous replace: during Phase-1 the host is dark/inert (zero prod crons),
so there is no urgency unless a read-only check shows `10.0.1.11` reallocated to a live host before
Phase-2.

**Post-apply verification (no-SSH).** Confirm the rendered nftables set no longer contains `.11`
and the `:8288`/`:8289` control API still accepts from web-1 (`10.0.1.10`) via the Vector
journald→Better Stack boot marker / registry-probe class check — never `ssh` (the host is
deny-all-public; `hr-no-ssh-fallback-in-runbooks`). Then `gh issue close 6608`.

### Rollback sequence (P1-13) — mirrors the forward gate, stop the dedicated host FIRST

1. **Dispatch `op=rollback` (no-SSH — it now does BOTH halves, #6369).** As of #6369 `op=rollback`
   first writes `INNGEST_CUTOVER_FLIP=rollback` on `soleur-inngest/prd` itself (the still-enabled
   timer then stops `inngest-server` on its next poll), confirms `"flag":"rolled-back"` /
   `"exit_code":0` via Better Stack (time-bounded), and THEN runs the web re-enable fan-out
   (step 3 below) **only after that confirm** — so the dedicated scheduler is proven stopped before
   the web schedulers come back (no two-live-scheduler double-fire; on an unconfirmed rolled-back it
   fails loud and withholds the web re-enable). Half (A) writes `rollback` when the forward flip is
   armed or progressing (`armed`/`flipping`/`flushed`/`done`), behind the same `inngest-cutover`
   environment required-reviewer gate; it writes ONLY the flip value (never re-writes
   POSTGRES_URI/HEARTBEAT). For a non-forward state (`aborted`/`unset`) there is nothing to reverse
   and it proceeds straight to the web re-enable (the documented aborted-state / P0-3 recovery):
   ```bash
   gh workflow run cutover-inngest.yml --field op=rollback   # then APPROVE the inngest-cutover environment gate
   ```
   There is **no separate operator Doppler write** — the dedicated-host stop is now folded into
   this single dispatch.
2. **Repoint the app back to loopback** — revert the `ci-deploy.sh` `INNGEST_BASE_URL` change
   (back to the loopback `host.docker.internal:8288`) and redeploy.

<!-- lint-infra-ignore start -->

3. **Re-enable web inngest — Half (B) of the SAME `op=rollback` dispatch from step 1** (it runs
   automatically after the `rolled-back` confirm; no second dispatch needed). `op=rollback` issues
   a SINGLE no-SSH `enable inngest _ _` fan-out (enable + start + verify-serving-and-enabled in ONE
   flock-held ci-deploy.sh handler, #6178) across the `$CUTOVER_HOSTS` set, then POLLS
   `/hooks/deploy-status` for the terminal `reason=enabled` verdict. The `enable` verb restores
   the `[Install]` symlink the 2.2 disable removed (a `restart` never touches it) so the web
   scheduler survives a reboot — **no operator `systemctl` step is needed** (this is the no-SSH
   reverse of `op=quiesce-web`; there is deliberately no two-POST enable+restart, which would
   race the `flock -n` and could leave the unit enabled-but-stopped reported as success).
   web-2 is re-enabled by the fan-out but its verdict is acceptance-only (DI-C3) — confirm web-2
   via its freeze/recreate lifecycle. On `inngest_enable_failed` / `inngest_start_failed` /
   `inngest_reenable_unverified` / `enabled_peer_fanout_unaccepted`, pull `reason=` from
   `/hooks/deploy-status` + Better Stack (`logger -t ci-deploy`) — do **not** SSH the host.

<!-- lint-infra-ignore end -->

The capture file is retained on-host for a later retry. Rollback is data-safe only before any
**real** (non-throwaway) reminder is armed against prod Postgres — after that, forward-fix only.

> **Do NOT target a web host with `restart-inngest-server.yml` after the cutover completes
> (arch P2-4).** Post-cutover the web hosts' inngest is intentionally stopped+disabled
> (10.0.1.40 is the sole scheduler). A routine `restart-inngest-server.yml` restart is
> LB-routed to a web host and would START its disabled unit → a TRANSIENT second scheduler on
> prod Postgres (double-fire), independent of any enable-folding — the `inngest-server`
> `ExecStartPre` flip-guard blocks only the DEDICATED host, not web hosts. The only web verb to
> touch post-cutover is `op=quiesce-web` (forward) / `op=rollback` (reverse), never `restart`.

<!-- lint-infra-ignore start -->

> **Editor guard — a "no-SSH cutover" claim must be verified verb-by-verb (#6178).** Any host
> mutation this runbook performs (quiesce/stop/disable, enable/start, a future drain/pause) needs
> its OWN no-SSH webhook verb + pinned sudoers grant — an existing verb for a *different* mutation
> (e.g. `restart`) does NOT make the cutover no-SSH; that asymmetry is exactly what left 2.2
> quiesce on operator SSH. Re-arm uses `enable` (restores the `[Install]` symlink `disable`
> removed), never `restart` (which leaves the unit enabled-at-runtime but dropped on reboot). Before
> claiming no-SSH, list every mutation and confirm each has a verb.

<!-- lint-infra-ignore end -->

### `aborted`-state recovery (P0-3)

If the flip's DBSIZE gate tripped (`"exit_code":1`, `"reason":"dbsize-nonzero"`), the oneshot
refused to start and transitioned the flag to the terminal `aborted` (the 30s poll halts — no
re-attempt storm, and `aborted` never reads as success). The web schedulers are already
quiesced/disabled from `op=execute` 2.2, so **recover via the same rollback path**: run
`gh workflow run cutover-inngest.yml --field op=rollback` to bring the web schedulers back,
fix the Redis state (the non-zero `DBSIZE` means stale dark queue state — investigate why the
dark Redis was not empty), then re-arm from `op=execute`.

### Heartbeat suppression window (P2-14)

Both pushers (the co-located web scheduler and the dedicated host) are silent across the
window — the web pusher is quiesced at 2.2 and the dedicated host only begins pinging
`INNGEST_HEARTBEAT_URL` **after** the flip. So set a **Better Stack maintenance / suppression
window** on the `soleur-inngest-server-prd` heartbeat spanning the cutover (or rely on the
monitor's grace period) so the pusher-quiesce → post-flip gap does not page. Lift the
suppression once step 3 confirms `done` and the dedicated host is pinging.

### Bounded-outage note

The window between 2.2 (quiesce) and functions registering after 2.4 (app-repoint) is the
parent plan's **accepted bounded residual** (ADR-100: a fully zero-downtime switchover is
impossible under the single-writer constraint — two schedulers on prod Postgres would
double-fire every cron, strictly worse than a brief gap). The flip oneshot restarts inngest
**in place** (pre-installed during dark, so the window is bounded by the restart + app-redeploy,
target < 5 min — NOT a cold OCI pull). Ticks missed in-window are not backfilled; `op=verify`
enumerates them for `soleur:trigger-cron` re-fire.

## Concurrency conventions

- **One `terraform apply` at a time.** The R2 backend has `use_lockfile = false` (R2 does not support S3 conditional writes). Concurrent applies race silently. R7 in the plan documents this.
- **`inngest-bootstrap.sh` is idempotent** — second invocation against the same version is a ~50ms no-op via `systemctl is-active` + version-file match. Safe to re-run.

## Cron bug-fixer

The cron-bug-fixer Inngest function (`apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`) runs daily at `0 6 * * *` UTC, selecting a qualifying `type/bug` issue and spawning `claude-code` to fix it. It also accepts a manual-trigger event for operator-initiated runs.

### Event name and payload

- **Event:** `cron/bug-fixer.manual-trigger`
- **Payload:** `{ "issue_number": <positive integer> }` (optional)
- **Validation:** If `issue_number` is present, it must be a positive integer. Invalid values are rejected with a Sentry fallback report and the function returns `ok: false` without selecting any issue.

When `issue_number` is omitted, the function falls through to the priority cascade (see Override semantics).

### Override semantics

- **Without override:** The handler runs the priority cascade, selecting the first qualifying issue in order: `priority/p3-low` → `priority/p2-medium` → `priority/p1-high`. Issues matching the title skip-regex (`/^(\[Content Publisher\]|flaky|flake|test-flake|test)[: [(]/i`) or carrying skip-labels (`bot-fix/attempted`, `ux-audit`, `synthetic-test`) are excluded.
- **With override:** The `issue_number` bypasses the cascade entirely. The operator owns ensuring the target issue is fix-issue-compatible (has `type/bug` label, is open, is not in the skip-list). The handler does not re-validate these constraints on override.

### Concurrency

- **fn-scoped limit 1:** Only one `cron-bug-fixer` invocation runs at a time.
- **account-scoped `cron-platform` limit 1:** Shared across all `cron-*` functions using the `cron-platform` key. A manual trigger queues behind any in-flight cron run (daily-triage, follow-through-monitor, etc.).
- **Retries:** 1 (Inngest retries once on non-terminal failure).

Manual triggers do NOT preempt scheduled runs — they queue behind them.

### How to fire

**HTTP (PRIMARY — no SSH):** POST to the internal trigger route (see
[§ On-demand cron trigger (HTTP)](#on-demand-cron-trigger-http--primary) for the
full Bearer + `data` contract):

```bash
TOKEN=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -sS -X POST https://app.soleur.ai/api/internal/trigger-cron \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"event":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'
unset TOKEN
```

Without `issue_number` (runs the default cascade) — omit `data` (or send `{}`):
```bash
  -d '{"event":"cron/bug-fixer.manual-trigger"}'
```

Or via the skill: `plugins/soleur/skills/trigger-cron/scripts/trigger.sh
--event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}'`.

**Last-resort diagnosis (on-host, only if the HTTP route is itself down):** the
Inngest CLI talks to the loopback event endpoint and requires being on the
Hetzner host. Use ONLY when the public route is unreachable:

```bash
# on the Hetzner host (last-resort)
inngest send '{"name":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'
```

**Inngest dashboard:** Navigate to the Events tab → Send Event → paste the JSON body above.

### How to observe results

1. **Sentry cron monitor:** `scheduled-bug-fixer` — shows `ok` / `error` heartbeat status per run.
2. **GitHub PRs:** Filter by `bot-fix/*` branch prefix — `gh pr list --search "head:bot-fix/"`.
3. **Inngest dashboard:** Run history for `cron-bug-fixer` shows step-by-step execution (mint-installation-token → precreate-labels → select-issue → setup-workspace → claude-eval → detect-pr → auto-merge-gate → notify-ops-email → sentry-heartbeat).

### Common failure modes

| Mode | Symptom | Resolution |
|------|---------|------------|
| Invalid override | Sentry fallback: "Manual-trigger issue_number must be a positive integer" | Re-send with a valid positive integer |
| Empty cascade | Function returns `ok: true`, `selectedIssue: null` — no qualifying issue at any priority level | Expected when no open `type/bug` issues exist; no action needed |
| claude-eval timeout | Sentry fallback: "claude-eval aborted by timeout (3000000ms budget exceeded)" | The 50-minute AbortController fired; check Anthropic usage for the aborted run |
| Workspace setup failure | Sentry fallback: "Failed to scaffold ephemeral cron workspace" | Check GitHub App installation token minting, repo clone permissions |
| No PR detected | Warning log: "No bot-fix PR detected after claude-eval" | The agent did not produce a PR — review the claude-eval step output in Inngest dashboard |
| Auto-merge gate: non-bot author | Gate returns "author is not a recognized bot" | PR was opened by a human or unrecognized bot account |
| Auto-merge gate: missing label | Gate returns "missing bot-fix/auto-merge-eligible label" | Agent did not add the eligibility label; review PR manually |
| Auto-merge gate: multi-file diff | Gate strips eligibility label, adds `bot-fix/review-required` | PR touches >1 file; requires human review before merge |
| Auto-merge gate: non-p3-low source | Gate strips eligibility label, adds `bot-fix/review-required` | Source issue priority is not `priority/p3-low`; requires human review |

## Plan deviations from `2026-05-18-feat-pr-f-inngest-iac-plan.md`

See the `## Plan Deviations (Phase 1)` section of the plan for full context. Summary:
1. 4 Inngest secrets are `random_id`-generated, not operator-minted.
2. Single workplace-scope Doppler personal token (was: two per-config service tokens).
3. `[ack]` operator-mint count: 6 → 2.
4. OCI image tag is plain `vX.Y.Z` (not `vinngest-vX.Y.Z`).
5. cloud-init.yml embedding + `server.tf triggers_replace` for `inngest-bootstrap.sh` skipped — OCI image is the sole delivery path.

## PR-G post-merge: Flipping `SOLEUR_FR5_ENABLED` to `true`

Per ADR-033 (per-tenant scope grants), the env flag `SOLEUR_FR5_ENABLED` is no longer a tenant-level gate — it is a global kill-switch. The per-grant deny-by-default predicate at `apps/web-platform/app/api/webhooks/stripe/route.ts:437` is the actual tenant-level authorization gate. **Even with the flag at `true`, no Inngest event fires for a tenant who has not granted the action class via `/dashboard/settings/scope-grants`.** This decoupling is what makes the flip operator-routable in PR-G (#3947).

### Prerequisites (all must be true before flip)

1. **PR-G merged to `main`**; Vercel auto-deploy green; Hetzner web-platform unit has restarted with the new image (or per the deploy substrate's restart policy).
2. **Migrations 048 + 049 applied to prd Supabase.** Verify via `psql` (or Supabase MCP):
   ```bash
   doppler run -p soleur -c prd -- psql "$DATABASE_URL_POOLER" -c '\d+ public.scope_grants'
   doppler run -p soleur -c prd -- psql "$DATABASE_URL_POOLER" -c '\d public.users' | grep runtime_explainer_dismissed_at
   ```
   Expected shape: 7 columns on `scope_grants`, RLS enabled, 2 WORM triggers (`scope_grants_no_update`, `scope_grants_no_delete`), 1 partial index (`scope_grants_active_idx`), 3 RPCs (`grant_action_class`, `revoke_action_class`, `anonymise_scope_grants`) with explicit `REVOKE EXECUTE FROM PUBLIC, anon` and the correct `GRANT EXECUTE TO` for each role.
3. **T&C version 2.0.0 deployed.** Middleware redirect to `/accept-terms` on next request will fire for the operator + first dogfood founder. Coordinate dogfood timing accordingly.
4. **BetterStack on-call live** (per PR-F flip-prerequisite list at the top of this runbook).
5. **Synthetic Stripe smoke against prd webhook passed** (see § "Synthetic smoke" below) — the smoke runs against a **preview env** with the flag temporarily on, NOT against prd before the prd flip.
6. **CPO sign-off captured** in `knowledge-base/legal/compliance-posture.md` Active Items (PR-G brand-survival threshold: single-user incident).
7. **First dogfood founder selected** and onboarding-ready. Their `scope_grants` row will be granted by them via `/dashboard/settings/scope-grants` after PR merges (no backfill per brainstorm K16).

### Flip command

```bash
doppler secrets set SOLEUR_FR5_ENABLED=true -p soleur -c prd
```

Verify:
```bash
doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain
# → true
```

### Roll-back command (if first invocation surfaces a regression)

```bash
doppler secrets set SOLEUR_FR5_ENABLED=false -p soleur -c prd
```

Stripe redelivery (up to 3 days) preserves at-least-once if the flip+rollback cycle drops events in flight.

### Synthetic smoke procedure (one-off, no separate script)

Run from a Vercel preview env (NOT prd) before the prd flip. Replace `<founder-uuid>` with a seeded grant's `founder_id`:

```bash
# 1. Seed the grant in the preview env's Supabase (one-time, founder-id-bound).
#    Sign in to /dashboard/settings/scope-grants as the operator's preview account;
#    select finance.payment_failed at draft_one_click; submit. The row lands in
#    public.scope_grants.

# 2. Compose a synthetic Stripe payload.
STRIPE_PAYLOAD=$(jq -nc --arg fid "<founder-uuid>" '{
  type: "invoice.payment_failed",
  data: { object: { customer: "cus_smoke_test", id: "in_smoke_test",
                    customer_email: "smoke@soleur.test",
                    amount_due: 4200, currency: "usd",
                    last_finalization_error: { code: "card_declined" } } }
}')

# 3. Sign with the preview env's webhook secret.
TS=$(date +%s)
PAYLOAD_TO_SIGN="${TS}.${STRIPE_PAYLOAD}"
SIG_HEX=$(printf '%s' "$PAYLOAD_TO_SIGN" \
  | openssl dgst -sha256 -hmac "$STRIPE_WEBHOOK_SECRET" -hex \
  | awk '{print $2}')
SIG_HEADER="t=${TS},v1=${SIG_HEX}"

# 4. POST to the preview webhook endpoint.
curl -sS -X POST "https://<preview-domain>/api/webhooks/stripe" \
  -H "Stripe-Signature: $SIG_HEADER" \
  -H "Content-Type: application/json" \
  -d "$STRIPE_PAYLOAD"
# Expected: HTTP 200; webhook returns {"received": true}.

# 5. Wait ~5s, then query Inngest via the loopback API.
doppler run -p soleur -c <preview-config> -- bash -c '
  curl -sS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" \
    "$INNGEST_BASE_URL/v1/events?name=finance.payment_failed&cel=event.data.founderId=='\''<founder-uuid>'\''&limit=1"
'
# Expected: { "data": [ { id: "...", data: { founderId: "<founder-uuid>", tier: "draft_one_click", ... } } ], ... }

# 6. Confirm the founder's /dashboard/audit page renders the new run with the
#    redacted summary, action class, tier-at-time, and the Request-human-review
#    affordance. Confirm the CFO function wrote a messages row with
#    trust_tier='draft_one_click', status='draft' (DB CHECK enforces).

# 7. Revert the preview-env flag and clean up the synthetic grant.
```

After the preview smoke passes, flip prd per the command above; within 1h fire a single prd synthetic smoke against the operator's own seeded grant; assert Inngest dashboard shows the run AND `/dashboard/audit` renders it; close #3947 with `gh issue close 3947 --reason completed`; run `/soleur:postmerge`.

## Related

- ADR-030 (Inngest as durable trigger layer)
- ADR-033 (per-tenant scope grants substrate)
- PR-F (#3940) — Inngest trigger layer + CFO autonomous-draft
- PR-G (#3947, PR #3984) — cohort-exposure surface + per-grant deny-by-default
- PR-A (#3960 close) — IaC for inngest-server
- `apps/web-platform/server/inngest/client.ts` — fail-closed startup guards (ADR-030 I4)
- `apps/web-platform/server/scope-grants/is-granted.ts` — webhook predicate's grant probe (ADR-033)

## Fresh-host provisioning (#4118)

A new Hetzner VM (intentional `terraform destroy && terraform apply`, full
`-replace`, or a brand-new Soleur user running `terraform apply` against an
empty Hetzner project) installs Inngest automatically via the cloud-init
`runcmd:` block at `apps/web-platform/infra/cloud-init.yml`. The block pulls
`ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`, extracts the embedded
`inngest-bootstrap.sh`, sources `INNGEST_CLI_VERSION` + `INNGEST_CLI_SHA256`
from the image's `Config.Env`, and runs the script — same install path as the
operator-triggered deploy webhook, just fired at first boot.

The currently-running prod VM is unaffected by this addition. `hcloud_server.web`
has `lifecycle.ignore_changes = [user_data]` (`apps/web-platform/infra/server.tf`),
so cloud-init.yml edits never re-render the existing host.

### Verification (no SSH required)

```bash
# Run from the operator's workstation. 200 or 401 = Inngest is alive.
curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 \
  https://app.soleur.ai/api/inngest
```

Anything other than `200` / `401` means Inngest is absent or unreachable.
Investigate `/var/log/cloud-init-output.log` on the host (via Hetzner console
if SSH is also broken).

### Upgrade path (existing operator workflow, unchanged)

1. Push `vinngest-vX.Y.Z` tag.
2. The `build-inngest-bootstrap-image.yml` GHA workflow builds the OCI image.
3. The operator triggers the deploy webhook
   `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z`.

Cloud-init installs only on FRESH hosts; live upgrades still go through the
webhook. Pinning is documented inline in `cloud-init.yml`'s drift-sentinel
comment ("Pinned image tag tracks
`apps/web-platform/infra/inngest.tf:locals.inngest_cli_version`").

### Tier 2 follow-up

A weekly disaster-recovery test that exercises the full fresh-`terraform apply`
path against a clean Hetzner test-workspace is tracked in #4126 (deferred).
Until that lands, the post-merge verification above is the operator-driven
canary on the prod VM.
