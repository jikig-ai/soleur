# Learning: SSH-to-webhook provisioner migration — mount namespace and sudoers traps

## Problem

Replacing SSH-based Terraform provisioners (`connection` + `provisioner "file"` + `provisioner "remote-exec"`) with a webhook handler that runs inside a systemd service's mount namespace introduces two classes of silent runtime failures that SSH never encountered:

1. **ReadOnlyPaths conflict**: SSH provisioners run as root via a direct SSH session — completely outside the service's mount namespace. The webhook handler is exec'd by the webhook binary, which runs inside `webhook.service`'s `ProtectSystem=strict` namespace. Any path listed in `ReadOnlyPaths` (e.g., `/etc/webhook`) is read-only to the handler, even with root-equivalent sudo. The `mktemp` + `mv` atomic write pattern fails at `mktemp` when the destination directory is read-only.

2. **Sudoers exact argument matching**: When the handler needs to restart its own service via `sudo systemd-run`, the sudoers Cmnd_Alias pins full paths (`/usr/bin/systemctl`). The handler script initially used bare command names (`systemctl`), which sudo resolves to the same binary but compares as a literal string mismatch — silently denied.

## Solution

1. Move `/etc/webhook` from `ReadOnlyPaths` to `ReadWritePaths` in both the standalone `webhook.service` and the cloud-init inline copy. The HMAC authentication on the webhook endpoint is the access control layer — the mount namespace ReadOnly was defense-in-depth that conflicts with the new handler's write requirement.

2. Use full absolute paths in the handler's sudo invocation to match the sudoers Cmnd_Alias exactly: `sudo /usr/bin/systemd-run --on-active=3s --unit=webhook-self-restart /usr/bin/systemctl restart webhook`.

## Key Insight

When migrating from SSH provisioners to in-service webhook handlers, audit every path the old provisioner wrote against the service's `ProtectSystem`/`ReadOnlyPaths`/`ReadWritePaths` declarations. SSH runs outside the namespace; webhook handlers run inside it. The same file operations that worked over SSH will silently fail inside the namespace. Similarly, any `sudo` invocation must use full paths matching the sudoers Cmnd_Alias — sudo resolves command names but compares arguments as literal strings.

## Session Errors

1. **Bash `(( PASS++ ))` under `set -e`** — `(( 0 ))` evaluates to falsy (exit code 1), which `set -e` treats as failure. Recovery: replaced with `PASS=$((PASS + 1))`. Prevention: never use `(( var++ ))` in `set -e` scripts when the variable starts at 0.

2. **CWD drift after `cd` into infra dir** — `git add` from `apps/web-platform/infra/` caused pathspec mismatch because git interprets paths relative to CWD. Recovery: used absolute path from worktree root. Prevention: always use worktree-absolute paths for git commands.

3. **ReadOnlyPaths P1 caught at review, not implementation** — the mount namespace conflict was invisible during `terraform validate` (which only checks HCL syntax) and the handler test suite (which uses `TEST_DESTDIR` sandbox). Prevention: when writing handlers for systemd-sandboxed services, cross-check every destination path against the service unit's `ReadOnlyPaths`/`ReadWritePaths` at implementation time, not review time.

4. **Sudoers path mismatch P1 caught at review** — the bare `systemctl` vs `/usr/bin/systemctl` mismatch was invisible in the test suite (which mocks sudo). Prevention: when writing sudoers entries with pinned arguments, copy the exact argument list into the handler script — never retype it.

5. **`triggers_replace` changed without updating drift guard test** — adding `infra-config-apply.sh` and `push-infra-config.sh` to `server.tf`'s `triggers_replace` without updating `ship-deploy-pipeline-fix-gate.test.ts`'s `TRIGGER_FILES` array caused CI `test-bun` to fail post-merge. Recovery: hotfix PR #4493. Prevention: when editing `triggers_replace` in `server.tf`, grep for `TRIGGER_FILES` and `DEPLOY_PIPELINE_FIX_TRIGGERS` and update all three locations in the same commit. The drift guard test exists precisely to catch this — but only post-merge if the test wasn't run pre-merge.

6. **Terraform write-only provider attribute used in `environment {}` block** — `cloudflare_zero_trust_access_service_token.deploy.client_secret` is write-only in the Cloudflare provider (available at creation, empty on subsequent `terraform refresh`). The `local-exec` provisioner's `environment {}` block referenced this state attribute, producing an empty `CF_ACCESS_SECRET`. Recovery: added Terraform variables sourced from Doppler (#4494). Prevention: when referencing provider-managed credentials in Terraform, check the provider docs for write-only attributes. If the attribute is sensitive and the provider is cloud-hosted, assume write-only until verified — use Doppler/vault variables instead.

7. **curl `-d` strips newlines, breaking HMAC** — the push script used `curl -d @file` to send the payload, but `-d` strips newlines from the file content. The HMAC was computed over the raw file (with newlines from the heredoc), but the server received the stripped version and computed a different HMAC → 500. Recovery: switched to `--data-binary @file` (#4495). Prevention: always use `--data-binary` (not `-d`) when the payload has been HMAC-signed over the raw bytes. `-d` is for form data; `--data-binary` preserves byte-for-byte fidelity.

## Tags
category: infrastructure
module: apps/web-platform/infra
