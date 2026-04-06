---
title: "fix: deploy pipeline Doppler secrets download fails under systemd ProtectHome"
type: fix
date: 2026-04-06
---

# fix: deploy pipeline Doppler secrets download fails under systemd ProtectHome

## Overview

Since v0.13.41, all webhook-triggered deploys fail with `FATAL: Doppler secrets download failed`. The Doppler CLI's `Setup()` function tries to create `~/.doppler/` on every invocation. The webhook.service uses `ProtectHome=read-only`, making the deploy user's home directory read-only. Without `~/.doppler/`, the CLI exits before reaching the `secrets download` command. The `2>/dev/null` in ci-deploy.sh swallows the actual error, and the script only logs the generic "FATAL" message.

## Problem Statement

Three compounding issues cause the failure:

1. **Root cause:** Doppler CLI v3.75.3 calls `configuration.Setup()` in its `PersistentPreRun` hook, which runs `os.Mkdir(~/.doppler, 0700)` before every subcommand. This fails with `mkdir /home/deploy/.doppler: read-only file system` under systemd's `ProtectHome=read-only`.

2. **Timing:** The `deploy_pipeline_fix` Terraform provisioner (merged in PR #1551, deployed as v0.13.40) pushed the hardened ci-deploy.sh (no .env fallback) and restarted the webhook service. The very next webhook-triggered deploy (v0.13.41) was the first to hit this code path under the systemd sandbox.

3. **Observability gap:** `ci-deploy.sh` line 33 runs `doppler secrets download ... 2>/dev/null`, swallowing the Doppler CLI's error message. The script only logs the generic "FATAL: Doppler secrets download failed" to syslog.

## Evidence

Server diagnosis (read-only SSH, per AGENTS.md):

```text
# Reproduced with systemd-run matching webhook.service restrictions:
$ systemd-run --pipe --wait --uid=deploy --gid=deploy \
    -p ProtectHome=read-only -p ProtectSystem=strict \
    -p PrivateTmp=true -p "ReadWritePaths=/mnt/data /var/lock" \
    -E DOPPLER_TOKEN="$TOKEN" -E HOME=/home/deploy \
    --working-directory=/ -- \
    /usr/bin/doppler secrets download --no-file --format docker --project soleur --config prd

Unable to create config directory /home/deploy/.doppler
Doppler Error: mkdir /home/deploy/.doppler: read-only file system

# Fix verified:
$ systemd-run ... -E DOPPLER_CONFIG_DIR=/tmp/.doppler ... -- /usr/bin/doppler ...
ANTHROPIC_API_KEY=sk-ant-... (success)
```

Journal evidence:

```text
Apr 05 21:30:55 ci-deploy[2861389]: FATAL: Doppler secrets download failed  (v0.13.41)
Apr 05 22:05:10 ci-deploy[2865352]: FATAL: Doppler secrets download failed  (v0.13.42)
Apr 05 22:24:59 ci-deploy[2870794]: FATAL: Doppler secrets download failed  (v0.13.43)
```

## Proposed Solution

### Fix 1: Add `DOPPLER_CONFIG_DIR` to webhook-deploy env file (Terraform)

Add `DOPPLER_CONFIG_DIR=/tmp/.doppler` to the `/etc/default/webhook-deploy` environment file. This redirects Doppler CLI's config directory to `/tmp`, which is writable and isolated by `PrivateTmp=true`.

**Files changed:**

- `apps/web-platform/infra/cloud-init.yml` -- Update the runcmd that writes `/etc/default/webhook-deploy` to include the new variables
- `apps/web-platform/infra/server.tf` -- Extend `terraform_data.deploy_pipeline_fix` remote-exec to append new env vars to existing file on the server

**Why `/tmp/.doppler` and not `ReadWritePaths=/home/deploy/.doppler`:**

| Approach | Pros | Cons |
|----------|------|------|
| `DOPPLER_CONFIG_DIR=/tmp/.doppler` | Ephemeral (PrivateTmp), no filesystem changes, no security relaxation | Extra env var |
| `ReadWritePaths=/home/deploy/.doppler` | Uses Doppler's default path | Punches write hole through ProtectHome, dir must be pre-created, persists sensitive metadata on disk |

The `/tmp` approach is more secure: PrivateTmp ensures the Doppler config is ephemeral and isolated per-service-instance, and it doesn't weaken the ProtectHome sandbox.

### Fix 2: Remove `2>/dev/null` from Doppler command (observability)

Replace the `2>/dev/null` pattern with combined output capture. On success, stderr is empty so stdout contains only secrets. On failure, the combined output contains the error message for logging.

```bash
local doppler_output
if ! doppler_output=$(doppler secrets download --no-file --format docker --project soleur --config prd 2>&1); then
    logger -t "$LOG_TAG" "FATAL: Doppler secrets download failed: $doppler_output"
    rm -f "$tmpenv"
    exit 1
fi
echo "$doppler_output" > "$tmpenv"
```

This avoids the mktemp/cat/rm dance for stderr capture. On success, the Doppler CLI writes secrets to stdout and nothing to stderr, so combined output is clean. On failure, the error message is in the variable for logging.

### Fix 3: Disable Doppler version check (optional, defense-in-depth)

Add `DOPPLER_ENABLE_VERSION_CHECK=false` to the environment file. The version check in `PersistentPreRun` contacts the Doppler API on every invocation, which is unnecessary for a service token in production and adds network latency and a potential failure point. This is not strictly required to fix the bug but eliminates a future failure vector at zero cost.

## Technical Considerations

- **Terraform provisioner pattern:** Follow the established `deploy_pipeline_fix` and `disk_monitor_install` patterns for pushing changes to the existing server. Cloud-init changes only affect new servers due to `lifecycle { ignore_changes = [user_data] }`.

- **Security:** `PrivateTmp=true` gives each systemd service its own `/tmp` namespace. Writing to `/tmp/.doppler` is equivalent to writing to a private ephemeral directory -- no other service or user can see it. This is actually more secure than writing to `~/.doppler` in the home directory.

- **Idempotency:** The Terraform provisioner can be re-run safely. Writing the env file with `printf` overwrites the previous content. The `systemctl restart webhook` picks up the new environment.

- **AGENTS.md compliance:** All server changes go through Terraform (never manual SSH). SSH was used only for read-only diagnosis.

## Acceptance Criteria

- [ ] Webhook-triggered deploys successfully download Doppler secrets
- [ ] v0.13.44+ deploys automatically via CI without manual intervention
- [ ] `journalctl -t ci-deploy` shows successful deploy logs (no FATAL)
- [ ] Doppler errors are logged to syslog with the actual error message (not swallowed by `2>/dev/null`)
- [ ] `/etc/default/webhook-deploy` contains `DOPPLER_CONFIG_DIR=/tmp/.doppler`

## Test Scenarios

- Given the webhook service is running with ProtectHome=read-only, when a deploy webhook is received, then ci-deploy.sh downloads Doppler secrets successfully
- Given DOPPLER_TOKEN is missing from `/etc/default/webhook-deploy`, when a deploy is triggered, then ci-deploy.sh logs "FATAL: DOPPLER_TOKEN not set" to syslog
- Given the Doppler API is unreachable, when a deploy is triggered, then ci-deploy.sh logs the actual Doppler error message (not just "FATAL: Doppler secrets download failed")
- Given the existing ci-deploy.sh tests, when `bash ci-deploy.test.sh` runs, then all tests pass (mock doppler uses DOPPLER_CONFIG_DIR)

## Implementation Phases

### Phase 1: Fix env file and ci-deploy.sh

1. Update `apps/web-platform/infra/cloud-init.yml`:
   - Add `DOPPLER_CONFIG_DIR=/tmp/.doppler` and `DOPPLER_ENABLE_VERSION_CHECK=false` to the webhook-deploy env file write in runcmd

2. Update `apps/web-platform/infra/webhook.service`:
   - No changes needed (EnvironmentFile already points to `/etc/default/webhook-deploy`)

3. Update `apps/web-platform/infra/ci-deploy.sh`:
   - Replace `2>/dev/null` with stderr capture and syslog logging in `resolve_env_file()`

4. Update `apps/web-platform/infra/ci-deploy.test.sh`:
   - Add test for Doppler error logging (stderr capture)
   - Ensure mock environment includes `DOPPLER_CONFIG_DIR`

### Phase 2: Update existing Terraform provisioner

1. Extend the existing `terraform_data.deploy_pipeline_fix` resource in `apps/web-platform/infra/server.tf`:
   - Add `remote-exec` commands to append `DOPPLER_CONFIG_DIR` and `DOPPLER_ENABLE_VERSION_CHECK` to `/etc/default/webhook-deploy` (do NOT rewrite `DOPPLER_TOKEN` -- it is already in the file and is a secret that should not appear in Terraform inline commands)
   - Use idempotent append pattern: `grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy || printf 'DOPPLER_CONFIG_DIR=/tmp/.doppler\nDOPPLER_ENABLE_VERSION_CHECK=false\n' >> /etc/default/webhook-deploy`
   - The existing `systemctl restart webhook` picks up the new environment
   - The ci-deploy.sh content hash change (Fix 2) will trigger re-execution of this resource automatically

No new `terraform_data` resource needed -- folding into the existing `deploy_pipeline_fix` keeps the Terraform config simpler and ensures correct ordering (env file update and script push happen in the same provisioner, before webhook restart).

### Phase 3: Apply and verify

1. Taint `terraform_data.deploy_pipeline_fix` to force re-execution: `terraform taint terraform_data.deploy_pipeline_fix`
2. Run `doppler run -p soleur -c prd_terraform -- terraform apply -target=terraform_data.deploy_pipeline_fix`
3. Verify env file: `ssh root@<server> cat /etc/default/webhook-deploy` contains all three vars
4. Trigger a deploy (push a tag or merge a PR to trigger CI)
5. Verify via `journalctl -t ci-deploy` that the deploy succeeds (no FATAL)
6. Verify container has Doppler secrets: `docker exec soleur-web-platform printenv DOPPLER_CONFIG` returns `prd`

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Add `ReadWritePaths=/home/deploy/.doppler` | Weakens ProtectHome sandbox, persists sensitive config on disk |
| Pre-create `/home/deploy/.doppler` | Doppler also writes `.doppler.yaml` inside, which ProtectHome blocks |
| Remove `ProtectHome=read-only` entirely | Over-relaxes security; multiple other systemd directives depend on it |
| Use `--config-dir` CLI flag in ci-deploy.sh | Requires modifying every `doppler` invocation; env var is simpler |
| Install Doppler inside the Docker container | Over-engineering; secrets are needed at container-start time, not inside the container |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Plan Review Feedback (Applied)

Three reviewers assessed this plan in parallel:

1. **DHH-style (overengineering):** Simplified Fix 2 stderr capture from mktemp pattern to combined output capture. Merged Phase 2 terraform resource into existing `deploy_pipeline_fix` instead of creating a new resource.

2. **Kieran-style (correctness):** Fixed DOPPLER_TOKEN handling -- append new vars to existing file instead of rewriting the entire file (avoids exposing the token in Terraform inline commands). Added idempotent grep-based append pattern. Noted test mock needs `DOPPLER_CONFIG_DIR` set.

3. **Code simplicity (YAGNI):** Labeled Fix 3 as optional defense-in-depth. Confirmed the core fix is just one env var addition. Estimated total change: ~15 lines across 4 files.

## References

- Issue: #1574
- Previous fix (stale .env): PR #1551 / #1548
- Doppler CLI source: `configuration.Setup()` calls `os.Mkdir(UserConfigDir, 0700)` in `PersistentPreRun`
- Doppler community: [Need help using doppler from a systemd service](https://community.doppler.com/t/need-help-using-doppler-from-a-systemd-service-ubuntu/713) -- similar HOME-related issue
- Learning: `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md`
- Learning: `knowledge-base/project/learnings/integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md`
- Learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
