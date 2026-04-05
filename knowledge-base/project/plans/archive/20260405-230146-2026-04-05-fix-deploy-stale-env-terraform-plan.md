---
title: "fix: deploy pipeline uses stale .env instead of Doppler secrets"
type: fix
date: 2026-04-05
---

# fix: deploy pipeline uses stale .env instead of Doppler secrets (Terraform)

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 4
**Research sources:** Context7 (Terraform docs), institutional learnings (6 relevant), WebSearch (systemd hardening)

### Key Improvements

1. Added exact `doppler run` command for `terraform apply` (dual credential pattern from prior learning -- bare `doppler run` breaks R2 backend)
2. Added concrete `remote-exec` inline commands for the webhook.service unit file write (copy-paste ready)
3. Documented that webhook restart causes zero user-facing downtime (async 202 pattern) -- removes the risk row
4. Added pre-apply SSH key verification step to prevent the encrypted key failure that has occurred twice

### New Considerations Discovered

- The `terraform_data` trigger hash should include the webhook.service content as a Terraform local to avoid string duplication in `triggers_replace` and `remote-exec`
- `rm -f /mnt/data/.env` in `remote-exec` is a one-shot operation -- if the resource is tainted and re-created, the `rm -f` runs again harmlessly (idempotent)
- The webhook service runs as `User=deploy` but `ci-deploy.sh` needs `sudo` for `chown 1001:1001` -- the `NoNewPrivileges` omission comment in cloud-init documents this constraint

## Overview

The web-platform deploy pipeline silently uses a stale `/mnt/data/.env` file
instead of Doppler secrets. The repo version of `ci-deploy.sh` (which exits
on Doppler failure) has never been propagated to the existing server because
`server.tf` uses `lifecycle { ignore_changes = [user_data] }`. Three
compounding issues prevent Doppler secrets from reaching the container:

1. Stale `ci-deploy.sh` on server (old version with silent `.env` fallback)
2. Missing `EnvironmentFile` in the running webhook systemd unit
3. `ProtectSystem=strict` blocks `/var/lock` (flock fails)

**Impact:** 13 newer Doppler secrets (including `SENTRY_DSN`) never reach the
container. All server-side errors are silently lost.

Closes #1548

## Problem Statement / Motivation

Every deploy uses the stale `/mnt/data/.env` from initial provisioning instead
of the current 32 Doppler `prd` secrets. This was discovered during the #1533
Sentry investigation -- manual SSH confirmed the container has only 18 env vars
(from stale `.env`) while Doppler has 32. The container has `STRIPE_PUBLISHABLE_KEY`
(removed from Doppler) but no `SENTRY_*` vars.

Manual SSH fixes were attempted in #1533 and reverted -- this must go through
Terraform to prevent drift (AGENTS.md hard rule).

## Research Insights

### Existing Learnings Applied

- `integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md`:
  Documents the original discovery. The `.env` fallback was removed from the
  repo version of `ci-deploy.sh`, but the server still runs the old version
  that has the fallback.
- `integration-issues/sentry-dsn-missing-from-container-env-20260405.md`:
  Confirms SENTRY_DSN is missing from container env, container has 18/32
  secrets.
- `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`:
  Documents the `terraform_data` provisioner pattern and the encrypted SSH
  key pitfall. Use `agent = true` in connection blocks to leverage the SSH
  agent.

### Existing Pattern: disk_monitor_install

`server.tf` already contains `terraform_data.disk_monitor_install` (lines
47-77) that uses the exact pattern needed:

- `triggers_replace` with `sha256()` of the script content
- `connection` block with SSH to the server
- `file` provisioner to push the script
- `remote-exec` provisioner to set permissions and reload systemd

This is the template for the new `ci-deploy-install` and
`webhook-service-update` resources.

### Lock File Path Decision

The `ci-deploy.sh` lock file defaults to `/var/lock/ci-deploy.lock` (line 107).
`ProtectSystem=strict` makes `/var` read-only, blocking flock.

**Two options:**

| Approach | Change | Pros | Cons |
|----------|--------|------|------|
| A: Add `/var/lock` to ReadWritePaths | Update webhook.service | Standard lock path, no script change | One more systemd override |
| B: Change lock path to `/mnt/data/.ci-deploy.lock` | Update ci-deploy.sh default | Already writable, no systemd change | Lock file in data dir, not conventional |

**Decision: Option A** -- `/var/lock` is the conventional location for lock
files. The systemd unit already has `ReadWritePaths=/mnt/data`, adding
`/var/lock` is a one-line change. This also future-proofs against other
scripts that may need `/var/lock`.

## Proposed Solution

All changes go through `apps/web-platform/infra/` Terraform. One new
`terraform_data` resource follows the existing `disk_monitor_install` pattern.

### Phase 1: Update cloud-init for new servers

Update `cloud-init.yml` to add `/var/lock` to `ReadWritePaths` in the
webhook.service unit definition. This ensures new servers provisioned from
scratch get the correct configuration.

### Phase 2: Provision existing server via terraform_data

Create a single `terraform_data.deploy_pipeline_fix` resource that performs
all three operations in one SSH session (script push, systemd update, stale
file cleanup are one logical operation):

- `triggers_replace`: `sha256(join(",", [file("ci-deploy.sh"), <systemd_unit_content>]))` -- re-runs when either changes
- `file` provisioner: push `ci-deploy.sh` to `/usr/local/bin/ci-deploy.sh`
- `remote-exec` inline sequence:
  1. `chmod +x /usr/local/bin/ci-deploy.sh`
  2. Write updated webhook.service unit with `EnvironmentFile=/etc/default/webhook-deploy` and `ReadWritePaths=/mnt/data /var/lock`
  3. `systemctl daemon-reload && systemctl restart webhook`
  4. `rm -f /mnt/data/.env` (one-time cleanup; comment documents this is intentionally not re-triggerable)

**Note on duplication:** The webhook.service unit content appears in both
`cloud-init.yml` (for new servers) and the `remote-exec` inline string (for
the existing server). This is acceptable because the provisioner is a
one-time bridge -- future servers use cloud-init. Document the duplication
with a comment in `server.tf` pointing to the cloud-init source of truth.

### Research Insights

**Terraform provisioner guidance (Context7):** Terraform docs state provisioners
are a "last resort" -- but this is exactly the correct use case. The server
exists with `ignore_changes = [user_data]`, and there is no declarative
alternative for pushing config to a running server outside cloud-init. The
existing `disk_monitor_install` resource established this pattern.

**Concrete `remote-exec` inline for webhook.service:**

```hcl
provisioner "remote-exec" {
  inline = [
    "chmod +x /usr/local/bin/ci-deploy.sh",
    "cat > /etc/systemd/system/webhook.service << 'UNITEOF'\n[Unit]\nDescription=Webhook deploy listener\nAfter=network.target\n\n[Service]\nType=simple\nEnvironmentFile=/etc/default/webhook-deploy\nExecStart=/usr/local/bin/webhook -verbose -hooks /etc/webhook/hooks.json -port 9000 -ip 127.0.0.1\nRestart=on-failure\nRestartSec=5\nUser=deploy\nGroup=deploy\nProtectSystem=strict\nProtectHome=read-only\nPrivateTmp=true\nReadWritePaths=/mnt/data /var/lock\nReadOnlyPaths=/etc/webhook /usr/local/bin /etc/default/webhook-deploy\nTimeoutStopSec=180\n\n[Install]\nWantedBy=multi-user.target\nUNITEOF",
    "systemctl daemon-reload",
    "systemctl restart webhook",
    "rm -f /mnt/data/.env",
  ]
}
```

**Note:** The `NoNewPrivileges` directive is intentionally omitted because
`ci-deploy.sh` requires `sudo` for `chown 1001:1001 /mnt/data/workspaces`
(documented in cloud-init comment on line 146).

### Phase 3: Apply and verify

Run `terraform apply` to execute all provisioners atomically, then verify:

1. `ci-deploy.sh` on server matches repo version
2. webhook.service has correct EnvironmentFile and ReadWritePaths
3. `/mnt/data/.env` is deleted
4. Trigger a deploy and verify container gets all 32 Doppler secrets
5. Verify `/health` endpoint shows `sentry: "configured"`

## Technical Considerations

- **Encrypted SSH key:** The learning from #1505 documents that
  `private_key = file(...)` fails with passphrase-encrypted keys with an
  opaque `ssh: parse error in message type 0`. The existing `disk_monitor_install`
  uses `private_key = file(var.ssh_private_key_path)` and was applied with a
  temporary unencrypted key. Keep consistent with the existing pattern.
  **Pre-apply verification step:** Before running `terraform apply`, verify
  SSH agent is loaded: `ssh-add -l | grep -q ed25519`. If not, generate a
  temp unencrypted key per the #1505 learning.
- **Dual credential pattern for terraform apply:** The R2 backend needs raw
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, while Terraform variables
  need `TF_VAR_*` names. Use the documented nested pattern:

  ```text
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -target=terraform_data.deploy_pipeline_fix \
      -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub" \
      -var="ssh_private_key_path=/tmp/tf_temp_key" \
      -input=false
  ```

- **CI drift detection:** `terraform_data` resources with `remote-exec` show
  as "will be created" in CI drift reports because CI uses dummy SSH keys.
  This is expected behavior (documented in #1409 for disk_monitor_install).
- **Atomicity:** All operations are in a single `terraform_data` resource,
  executing sequentially in one SSH session.
- **Rollback:** If `terraform apply` fails partway, re-run it. Provisioners
  are idempotent (file overwrites, systemd reload, rm -f).
- **Post-merge apply:** These `terraform_data` resources require real SSH
  access. They cannot be applied in CI. Must run `terraform apply` locally
  in the same session as the merge (learning from #1505).
- **EnvironmentFile already in cloud-init:** The cloud-init webhook.service
  already has `EnvironmentFile=/etc/default/webhook-deploy` (line 140). The
  issue is that this was never applied to the running server. The provisioner
  fixes this for the existing server.
- **Webhook restart causes zero user-facing downtime:** The webhook uses
  async fire-and-forget mode (`include-command-output-in-response: false`,
  `success-http-response-code: 202`). A restart only affects incoming deploy
  requests during the < 1 second restart window. Active deploys (already
  forked by the webhook) are unaffected because they run as a separate
  process. No user traffic flows through the webhook.
- **systemd EnvironmentFile vs /etc/environment:** `/etc/environment` is
  sourced by PAM (login sessions), NOT by systemd service units. The
  `EnvironmentFile=/etc/default/webhook-deploy` directive is the only correct
  way to inject `DOPPLER_TOKEN` into the webhook service. This was the
  root cause of the original outage (learning from #1493).

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/infra/cloud-init.yml` | Add `/var/lock` to `ReadWritePaths` in webhook.service unit |
| `apps/web-platform/infra/server.tf` | Add `terraform_data.deploy_pipeline_fix` resource (script push + systemd update + stale env cleanup) |

## Acceptance Criteria

- [x] `ci-deploy.sh` on server matches repo version (no `/mnt/data/.env` fallback)
- [x] `webhook.service` loads `DOPPLER_TOKEN` from `/etc/default/webhook-deploy`
- [x] `webhook.service` has `ReadWritePaths=/mnt/data /var/lock`
- [ ] Deploy successfully pulls all 32 Doppler prd secrets into the container
- [ ] `curl https://app.soleur.ai/health | jq .sentry` returns `"configured"`
- [ ] `/mnt/data/.env` is deleted from the server
- [ ] `terraform plan` shows no unexpected drift after apply

## Test Scenarios

### Scenario 1: ci-deploy.sh Version Match

**Given** `terraform apply` has been run successfully
**When** comparing server script to repo version
**Then** `ssh root@<server> md5sum /usr/local/bin/ci-deploy.sh` matches `md5sum apps/web-platform/infra/ci-deploy.sh`

### Scenario 2: webhook.service Configuration

**Given** `terraform apply` has been run successfully
**When** inspecting the webhook systemd unit
**Then** `ssh root@<server> systemctl cat webhook.service` shows:

- `EnvironmentFile=/etc/default/webhook-deploy`
- `ReadWritePaths=/mnt/data /var/lock`

### Scenario 3: Stale .env Removed

**Given** `terraform apply` has been run successfully
**When** checking for stale env file
**Then** `ssh root@<server> ls /mnt/data/.env 2>&1` returns "No such file or directory"

### Scenario 4: Full Deploy Pipeline

**Given** all Terraform changes applied and webhook restarted
**When** triggering a deploy via the CI release workflow
**Then** the container starts with all 32 Doppler prd secrets
**API verify:** `ssh root@<server> docker exec soleur-web-platform printenv | wc -l` returns >= 32

### Scenario 5: Sentry Verification

**Given** a successful deploy with all Doppler secrets
**When** querying the health endpoint
**Then** `curl -sf https://app.soleur.ai/health | jq -r '.sentry'` returns `configured`

### Scenario 6: Lock File Works

**Given** webhook.service has `ReadWritePaths=/mnt/data /var/lock`
**When** `ci-deploy.sh` executes `flock` on `/var/lock/ci-deploy.lock`
**Then** the lock is acquired successfully (no permission denied error)

### Scenario 7: cloud-init Correctness for New Servers (code review only)

**Given** the updated `cloud-init.yml`
**When** reviewing the webhook.service unit definition in the template
**Then** `ReadWritePaths` includes both `/mnt/data` and `/var/lock`
**Note:** Verified by code review only -- no new server provisioning needed.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/deployment fix using existing Terraform patterns.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Encrypted SSH key blocks `terraform apply` | Pre-apply: verify `ssh-add -l` shows key, or generate temp unencrypted key per #1505 learning |
| Wrong Doppler credential pattern breaks `terraform init` | Use documented dual credential pattern: export raw AWS creds first, then `doppler run --name-transformer tf-var` |
| Stale env file deletion is irreversible | The file is already stale and harmful -- deletion is the desired outcome |
| CI drift reports show provisioner resources as "will be created" | Expected behavior (documented in #1409), add comments to the resources |
| Post-merge apply is forgotten | Apply in same session as merge; drift detection workflow catches gaps |

## References and Research

### Internal References

- `apps/web-platform/infra/server.tf:47-77` -- `disk_monitor_install` pattern (template)
- `apps/web-platform/infra/cloud-init.yml:132-155` -- webhook.service unit definition
- `apps/web-platform/infra/ci-deploy.sh` -- Current repo version (hardened, no fallback)
- `apps/web-platform/infra/variables.tf:102-106` -- `doppler_token` variable

### Institutional Learnings

- `2026-04-03-doppler-not-installed-env-fallback-outage.md` -- Original `.env` fallback discovery, systemd EnvironmentFile requirement
- `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` -- Provisioner pattern and SSH key pitfall
- `sentry-dsn-missing-from-container-env-20260405.md` -- SENTRY_DSN missing from container confirmation
- `2026-04-05-terraform-doppler-dual-credential-pattern.md` -- Exact `doppler run` command for Terraform with R2 backend
- `2026-03-29-doppler-service-token-config-scope-mismatch.md` -- Service token scoping (confirms the server's token is config-scoped)
- `2026-03-21-async-webhook-deploy-cloudflare-timeout.md` -- Async webhook pattern (confirms restart is zero-downtime)
- `2026-03-28-canary-rollback-docker-deploy.md` -- Canary deploy pattern in ci-deploy.sh (what the fix enables)

### External References

- [Terraform terraform_data resource](https://developer.hashicorp.com/terraform/language/resources/terraform-data) -- Official docs confirming terraform_data as provisioner container
- [Terraform provisioners: last resort](https://developer.hashicorp.com/terraform/language/resources/provisioners/syntax) -- Provisioners are last resort; this use case qualifies (no declarative alternative for existing servers with ignore_changes)
- [systemd EnvironmentFile directive](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#EnvironmentFile=) -- Official systemd docs confirming EnvironmentFile is the correct mechanism

### Related Issues

- #1548 -- This issue
- #1533 -- Sentry investigation that discovered the stale env
- #1539 -- PR that added hardening code (health endpoint sentry field)
- #1493 -- Doppler fallback removal (repo-side fix)
- #1505 -- Drift detection that caught unapplied provisioners
- #1409 -- Disk monitor provisioner (established the pattern)
