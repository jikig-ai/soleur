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

## Fresh-host bootstrap

After `terraform apply` against a fresh `hcloud_server.web`, the inngest-server is NOT yet running on the host. The bootstrap is decoupled from cloud-init by design (the OCI image is the sole delivery path). Steps:

1. Verify the GHA workflow `.github/workflows/build-inngest-bootstrap-image.yml` has published an OCI image:
   ```
   gh api repos/jikig-ai/soleur/actions/workflows/build-inngest-bootstrap-image.yml/runs --jq '.workflow_runs[0]'
   ```
   If no run exists, push a `vinngest-vX.Y.Z` tag (operator decides the X.Y.Z of the bootstrap image; current is `v1.0.0`):
   ```
   git tag vinngest-v1.0.0 && git push origin vinngest-v1.0.0
   ```
2. Fire the deploy webhook (replace `<TAG>` with the OCI tag, e.g. `v1.0.0`):
   ```
   doppler run -p soleur -c prd_terraform -- bash -c 'echo "deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap <TAG>" | ssh -o StrictHostKeyChecking=accept-new deploy@$(terraform -chdir=apps/web-platform/infra output -raw server_ip)'
   ```
   The webhook spawns `ci-deploy.sh` which runs the OCI image's entrypoint `/inngest-bootstrap.sh` against the host's systemd via bind-mounts.
3. Verify the service is active:
   ```
   ssh root@$(terraform -chdir=apps/web-platform/infra output -raw server_ip) systemctl status inngest-server.service inngest-heartbeat.timer
   ```
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

## Key rotation

Both `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` are TF-generated via `random_id` resources. Rotation procedure:

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
3. Tag + push to trigger the OCI image rebuild:
   ```
   git tag vinngest-vN.N.N && git push origin vinngest-vN.N.N
   ```
   (where N.N.N is the bootstrap-image semver — separate from the embedded inngest-cli version.)
4. Wait for the GHA workflow to complete + the image to land in GHCR.
5. Fire the deploy webhook with the new image tag. `inngest-bootstrap.sh` detects the version mismatch, pauses → drains → restarts → resumes (~5s downtime on loopback).

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

The BetterStack heartbeat is created with `paused = true` to avoid false alerts during the post-apply / pre-bootstrap gap. After [§ Fresh-host bootstrap](#fresh-host-bootstrap) succeeds and the first heartbeat ping is received:

1. Visit `https://uptime.betterstack.com/team/520508/heartbeats` → find `soleur-inngest-server-prd` → click → toggle pause off.
2. The `lifecycle { ignore_changes = [paused] }` on `betteruptime_heartbeat.inngest_prd` ensures future `terraform apply` runs do NOT revert the unpause.
3. Confirm pings are flowing:
   ```
   curl -s https://uptime.betterstack.com/api/v2/heartbeats/460830 \
     -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)" \
     | jq '.data.attributes | {status, last_ping_at}'
   ```

## Concurrency conventions

- **One `terraform apply` at a time.** The R2 backend has `use_lockfile = false` (R2 does not support S3 conditional writes). Concurrent applies race silently. R7 in the plan documents this.
- **`inngest-bootstrap.sh` is idempotent** — second invocation against the same version is a ~50ms no-op via `systemctl is-active` + version-file match. Safe to re-run.

## Plan deviations from `2026-05-18-feat-pr-f-inngest-iac-plan.md`

See the `## Plan Deviations (Phase 1)` section of the plan for full context. Summary:
1. 4 Inngest secrets are `random_id`-generated, not operator-minted.
2. Single workplace-scope Doppler personal token (was: two per-config service tokens).
3. `[ack]` operator-mint count: 6 → 2.
4. OCI image tag is plain `vX.Y.Z` (not `vinngest-vX.Y.Z`).
5. cloud-init.yml embedding + `server.tf triggers_replace` for `inngest-bootstrap.sh` skipped — OCI image is the sole delivery path.

## Related

- ADR-030 (Inngest as durable trigger layer)
- PR-F (#3940) — Inngest trigger layer + CFO autonomous-draft
- PR-A (this PR, #3960 close) — IaC for inngest-server
- `apps/web-platform/server/inngest/client.ts` — fail-closed startup guards (ADR-030 I4)
