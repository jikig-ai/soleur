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
files a `[ci/inngest-pool]` issue + Sentry `error` when the session count crosses
~70% of the pool cap (`pool_pressure`, leading indicator) or `EMAXCONNSESSION`
fires / the count reaches the cap (`pool_exhausted`). These modes are
**excluded from the auto-restart gate** — a restart re-opens all of inngest's
pooler connections at once and DEEPENS exhaustion (#5558). **Do NOT restart
inngest-server for a `[ci/inngest-pool]` alert.** Triage (no-SSH first):

1. **Read the alert** (no SSH) — `gh issue view "$(gh issue list --state open --search 'in:title \"[ci/inngest-pool]\"' --json number --jq '.[0].number')" --comments`. The body carries the per-state breakdown + `total` vs cap and the run log.
2. **Re-read the live pool** (no SSH, read-only) — confirm the trend via the same Management-API path the probe uses:
   ```
   SUPA=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
   curl -s --max-time 15 -X POST \
     https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query \
     -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' \
     -d '{"query":"select state, count(*) from pg_stat_activity group by state"}' | jq .
   ```
3. **Clear stale sessions** (no SSH, read-only client cap is the real fix) — if `idle` / `idle in transaction` sessions are climbing, terminate them via the same `/database/query` path (still no host login):
   ```
   curl -s --max-time 15 -X POST \
     https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query \
     -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' \
     -d '{"query":"select pg_terminate_backend(pid) from pg_stat_activity where state = '\''idle'\'' and state_change < now() - interval '\''10 minutes'\''"}'
   ```
   The durable fix is already live: inngest-server runs `--postgres-max-open-conns 10` (#5559, `inngest-bootstrap.sh:354`), UNDER the session-pool cap (live 30 as of 2026-06-18; project default 15). Confirm the live `default_pool_size` — the #5562 decision is to revert the #5558 stopgap 30 → the project default 15 and rely on the client cap (see `apps/web-platform/infra/inngest.tf`). The watchdog's `SESSION_POOL_CAP` env tracks the live cap (currently 30); drop it to 15 in lockstep when the revert lands.
4. **`pool_probe_unavailable`** (401/403/non-JSON) is a *soft* mode — the probe itself is degraded, not the pool. Check the printed response body in the run log; a Supabase Management-API 401 is often a validation/scope signal, not pure auth (verify the PAT in Doppler `prd` and the `SUPABASE_ACCESS_TOKEN` GH secret).

### Last-resort (host login)

Only after the three no-SSH steps above fail to resolve the pressure, inspect
inngest-server's own connection count on the host:
```
ssh root@<host> 'journalctl -u inngest-server.service -n 50 | grep -i "conn\|pool\|EMAXCONN"'
```
A host-level restart is the WRONG lever here (it worsens `EMAXCONNSESSION`); the
host login is for log inspection only, not remediation.

## Key rotation

Both `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` are TF-generated via `random_id` resources.

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

The `lifecycle { ignore_changes = [paused] }` on `betteruptime_heartbeat.inngest_prd` ensures future `terraform apply` runs do NOT revert the unpause regardless of which option you used.

Confirm pings are flowing:
```
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -s https://uptime.betterstack.com/api/v2/heartbeats/460830 \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.attributes | {status, last_ping_at}'
unset TOKEN
```

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
  - → Ship **both** `--postgres-uri` and `--redis-uri`. Postgres alone does NOT persist the queue.
- **0.3 Fail-closed vs silent fallback — Inngest FAILS CLOSED.** With a reachable-but-refused backend
  it exits non-zero (`failed to connect … connection refused`); `/health` never returns 200; **no**
  silent degrade to a healthy SQLite state. → The existing `/health` 200 gate already catches an
  *unreachable* backend. The residual silent-non-durable risk is **flags-absent** (ExecStart drops the
  flags → defaults to SQLite **while** `/health`=200). The hard gate therefore asserts: (a) the running
  inngest cmdline contains `--postgres-uri` AND `--redis-uri`, (b) `inngest-redis` unit active + Redis
  ping, (c) Postgres reachable — NOT a "fail-open post-start assertion".
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
