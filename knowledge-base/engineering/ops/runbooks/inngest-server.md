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
