# Fix: verify-deploy step hardening + provision /hooks/deploy-status on live server

**Issues:** Closes #2214, Closes #2215
**Type:** fix (CI workflow hardening + infra provisioning)
**Priority:** P1
**Milestone:** Phase 3: Make it Sticky
**Semver:** patch

## Summary

PR #2187 introduced a new `/hooks/deploy-status` endpoint plus a release-workflow step that polls it to verify `ci-deploy.sh` completion on the live host. Release run `24411905995` (v0.35.11) exposed two coupled defects:

1. **#2214 (workflow):** The `Verify deploy script completion` step runs under `bash -e`. When the endpoint returns a non-JSON body (Cloudflare 404 HTML, endpoint cold-start, or any transient non-JSON response), `jq` exits non-zero during `$(echo "$BODY" | jq -r ...)` and `-e` kills the step before the existing `case` statement can decide to retry. The loop never gets a chance to time out cleanly or continue polling.
2. **#2215 (infra):** The root cause of the non-JSON body in that specific run is that `/hooks/deploy-status` was not provisioned on the running server. `hcloud_server.web.lifecycle.ignore_changes = [user_data]` means cloud-init changes never re-apply to the existing instance; the new hook only reaches prod when `terraform_data.deploy_pipeline_fix` re-provisions via `remote-exec`, which requires `terraform apply` to run.

These are two halves of the same incident. The workflow must be hardened **regardless** of whether the endpoint is reachable, because endpoint outages (cold starts, Cloudflare edge blips, webhook service restarts, future re-provisioning windows) will recur. And the terraform apply must also run so production actually has the hook.

## Goals

- Verify-deploy step tolerates non-JSON / empty / error responses without killing the step; treats them as "keep polling" up to the existing timeout window.
- Real deploy failures (valid JSON with `exit_code >= 1`) still fail fast.
- `/hooks/deploy-status` returns a valid signed JSON response on the live server after apply.
- Next release workflow run after both fixes passes the verify step end-to-end.

## Non-Goals

- Changing the exit-code taxonomy or state-file format of `ci-deploy.sh` / `cat-deploy-state.sh` (out of scope — covered by #2205 and already landed).
- Adding a second endpoint or alternative verification path (e.g., polling docker image digest on host). The `/hooks/deploy-status` + `/health` two-layer scheme is the intended design.
- Reworking `hcloud_server.web`'s `ignore_changes = [user_data]` lifecycle (tracked separately; changing it now would force server replacement).

## Background and Evidence

**Issue #2214 problem location:** `.github/workflows/web-platform-release.yml`, "Verify deploy script completion" step (lines 94-155 on the current main HEAD). Current failing block:

```bash
EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
TAG=$(echo "$BODY" | jq -r '.tag // ""')
```

Under `bash -e` (GitHub Actions default for `run:` blocks), a `jq: parse error` on non-JSON input propagates through `$(...)` and terminates the step before the `case "$EXIT_CODE"` retry logic fires. Run `24411905995` logged exactly this — `jq: parse error: Invalid numeric literal at line 1, column 5` — from the very first poll attempt.

**Issue #2215 problem location:** `apps/web-platform/infra/server.tf` — `terraform_data.deploy_pipeline_fix` resource. Its `triggers_replace` includes:

```hcl
triggers_replace = sha256(join(",", [
  file("${path.module}/ci-deploy.sh"),
  file("${path.module}/webhook.service"),
  file("${path.module}/cat-deploy-state.sh"),
  local.hooks_json,
]))
```

Since PR #2187 added both `cat-deploy-state.sh` (new file) and the new `deploy-status` block in `hooks.json.tmpl`, the hash has drifted. A `terraform apply` will replace the resource and trigger `remote-exec` to push the new files and restart webhook. The provisioner writes `/etc/webhook/hooks.json`, chmod 640, chown root:deploy, `systemctl restart webhook`.

**Confirmed live state at 2026-04-14 18:57 UTC** (from issue body):

```bash
$ curl -sf -X GET -H "X-Signature-256: sha256=..." https://deploy.soleur.ai/hooks/deploy-status
HTTP 404: Hook not found
```

adnanh/webhook returns plaintext `Hook not found` on 404 — that's the HTML/text body that broke `jq`.

**Why both issues are one PR:** #2214 alone is insufficient — even with a tolerant jq wrapper, if the endpoint stays 404 forever the step correctly times out and fails the release (which is worse than the current crash because it still fails, just after 120s instead of immediately). #2215 alone is insufficient — fixing prod today doesn't protect against the next cold-start / outage / re-provision window. Shipping them together closes both halves of the incident and produces a verifiable green release.

## Approach

### Part A — Workflow hardening (#2214)

**Chosen approach:** Tolerant jq parsing with a sentinel value, following the pattern suggested in the issue body. This is surgical, preserves fast-fail semantics for real deploy failures, and keeps the existing `case` control flow intact.

Rationale vs. alternatives:

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **Tolerant jq + sentinel** | Surgical, keeps `case` structure, clear log lines per attempt | Adds one new case branch | **Chosen** |
| Drop `-e` from the step shell | One-line fix | Every future command failure in the loop also silently ignored; loses defensive behavior for unrelated bugs | Rejected |
| `set +e` around jq, `set -e` after | Scoped | Brittle — easy to miss a branch; mixes with `continue` semantics | Rejected |
| Pre-validate JSON with `jq -e .` guard | Clean | Still crashes on non-JSON unless wrapped; becomes the same fix | Rejected (same cost) |

**Detection rule:** If any of `jq` invocations fail (non-zero exit) OR the body starts with a non-JSON character, treat the response as "endpoint not ready" and retry. Use `jq -e .` as a pre-check rather than parsing three separate fields and tolerating each.

**Edge cases captured:**

- Empty body → existing `[ -z "$BODY" ]` branch handles it; no change needed.
- Body is valid JSON but missing fields → existing `// -99`, `// "unknown"`, `// ""` defaults handle it; the `*)` case branch (any EXIT_CODE not in `{0, -1, -2, -3}`) fails fast as intended. This is preserved.
- Body is HTML / plaintext (current failure) → new `parse_error` sentinel branch logs and retries.
- HTTP 5xx with empty body → already handled by empty-body branch.
- HTTP 5xx with HTML error page → new sentinel branch.
- Valid JSON with `exit_code: 5` → `*)` branch fires, `::error::` and exit 1. Unchanged.
- Timeout: after 24 attempts × 5s = 120s, the final `::error::` + exit 1 fires as today.

### Part B — Terraform apply (#2215)

**Chosen approach:** Run `terraform apply` from the worktree against the `prd_terraform` Doppler config. Follow the constitution rule for local terraform runs (name-transformer + separate AWS env vars for R2).

**Expected plan output** (one replacement):

```text
# terraform_data.deploy_pipeline_fix must be replaced
-/+ resource "terraform_data" "deploy_pipeline_fix" {
      ~ id               = "..." -> (known after apply)
      ~ triggers_replace = "<old-hash>" -> "<new-hash>"
      # (connection, provisioners unchanged)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Expect no other drift; if the plan shows anything outside `deploy_pipeline_fix`, stop and triage before applying (a change to `hcloud_server.web` would force server replacement; a change to the volume attachment would detach workspaces).

**Why we can't automate this end-to-end inside the PR CI:** No CI workflow runs `terraform apply` today — terraform is applied by an operator with SSH + Doppler access. This is the single legitimate manual step. The plan documents the exact command so the operator can run it from the worktree.

### Ordering

1. Merge the workflow hardening first (#2214 fix) — this alone makes future cold-starts / outages non-fatal.
2. Run `terraform apply` (#2215) — this makes the endpoint return 200 in prod.
3. Trigger a release (or wait for the next real one) to prove the verify step passes.

If the sequence is reversed (apply first, then merge), that's fine too — but the workflow hardening is the lasting fix and should be in main regardless.

## Files to Change

### Workflow fix (#2214)

- `.github/workflows/web-platform-release.yml` — rewrite the `jq` parsing block in "Verify deploy script completion" step to tolerate non-JSON bodies via `jq -e .` guard + sentinel branch in the existing `case`.

### No infra file changes

- `apps/web-platform/infra/` files are already correct. The issue is state-vs-reality drift, not file content. #2215 is resolved by running `terraform apply`, not by editing code.

### Documentation

- `knowledge-base/project/learnings/bug-fixes/` — new learning file capturing the "cold-start observability endpoint crashed release workflow" pattern so future endpoints with signed GET verify steps get the tolerant-jq treatment by default.

## Implementation Detail

### Workflow change — exact replacement

**Current block (lines 118-151 of `.github/workflows/web-platform-release.yml`):**

```yaml
            BODY=$(cat /tmp/status-body 2>/dev/null || echo "")
            if [ -z "$BODY" ]; then
              echo "Attempt $i/$STATUS_POLL_MAX_ATTEMPTS: HTTP $HTTP_CODE, no body"
              sleep "$STATUS_POLL_INTERVAL_S"
              continue
            fi
            EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
            REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
            TAG=$(echo "$BODY" | jq -r '.tag // ""')
```

**Replacement:**

```yaml
            BODY=$(cat /tmp/status-body 2>/dev/null || echo "")
            if [ -z "$BODY" ]; then
              echo "Attempt $i/$STATUS_POLL_MAX_ATTEMPTS: HTTP $HTTP_CODE, no body"
              sleep "$STATUS_POLL_INTERVAL_S"
              continue
            fi
            # Tolerate non-JSON bodies (endpoint cold-start, 404 HTML, transient
            # Cloudflare edge error). Without this guard, jq's parse error under
            # bash -e kills the step before the retry loop can react (#2214).
            if ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
              echo "Attempt $i/$STATUS_POLL_MAX_ATTEMPTS: HTTP $HTTP_CODE, non-JSON body (endpoint not ready)"
              sleep "$STATUS_POLL_INTERVAL_S"
              continue
            fi
            EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
            REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')
            TAG=$(echo "$BODY" | jq -r '.tag // ""')
```

Indentation: preserve the exact 12-space indentation used in the current `run: |` block. Do not introduce heredocs or multi-line shell strings that drop below the YAML base indentation (AGENTS.md hard rule).

### Terraform apply — exact command sequence (#2215)

From the worktree root:

```bash
cd apps/web-platform/infra

# R2 backend credentials (separate — not transformed to TF_VAR_*).
export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)

# Provider credentials (transformed to TF_VAR_*).
doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform init
doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform plan -out=/tmp/deploy-status.tfplan

# Review plan: expect only terraform_data.deploy_pipeline_fix to be replaced.
# If any other resource shows changes (especially hcloud_server.web or hcloud_volume_attachment),
# stop and triage before applying.
doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform apply /tmp/deploy-status.tfplan
```

**Expected apply side-effects on the server:**

- New `/etc/webhook/hooks.json` written with both `deploy` and `deploy-status` entries.
- New `/usr/local/bin/cat-deploy-state.sh` written, chmod +x.
- `/usr/local/bin/ci-deploy.sh` re-written (same content as current file; benign).
- `/etc/systemd/system/webhook.service` re-written (same content).
- `systemctl restart webhook`.
- `rm -f /mnt/data/.env` (idempotent; no-op if already absent).

No downtime expected — webhook restart is sub-second and the deploy isn't actively running.

### Verification — post-apply

```bash
WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
CF_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
CF_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
SIG=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')

curl -sf -X GET \
  -H "X-Signature-256: sha256=$SIG" \
  -H "CF-Access-Client-Id: $CF_ID" \
  -H "CF-Access-Client-Secret: $CF_SECRET" \
  https://deploy.soleur.ai/hooks/deploy-status
```

**Expected first response:** `{"exit_code":0,"reason":"ok","tag":"v0.35.11", ...}` (state file was written by the last successful deploy of v0.35.11), **or** `{"exit_code":-2,"reason":"no_prior_deploy"}` if the state file on `/var/lock` didn't survive the restart.

Either response is acceptable — both are valid JSON and both exercise `cat-deploy-state.sh` correctly. The workflow's next release run will land a fresh state file.

## Test Scenarios

> **Note:** Infrastructure-only tasks (workflow YAML, terraform apply) are exempt from the work-skill TDD gate per AGENTS.md. The scenarios below are verification steps, not unit tests.

### Local dry-run of the workflow change

`actionlint` (or `yamllint`) over the modified workflow file:

```bash
actionlint .github/workflows/web-platform-release.yml
```

Expected: zero errors.

Optionally, extract the `run:` block and run it locally against a simulated response to prove the new branch behaves:

```bash
# Simulate a non-JSON body
BODY="Hook not found"
HTTP_CODE=404
if [ -z "$BODY" ]; then echo "no body branch"; exit 0; fi
if ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
  echo "non-JSON branch: HTTP $HTTP_CODE, non-JSON body (endpoint not ready)"
  exit 0
fi
echo "should not reach here"; exit 1
```

Expected: prints `non-JSON branch: HTTP 404, non-JSON body (endpoint not ready)`, exits 0.

Simulate valid JSON:

```bash
BODY='{"exit_code":0,"reason":"ok","tag":"v0.35.11"}'
if ! echo "$BODY" | jq -e . >/dev/null 2>&1; then echo "wrong branch"; exit 1; fi
EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
echo "parsed EXIT_CODE=$EXIT_CODE"
```

Expected: `parsed EXIT_CODE=0`.

### Production verification after apply

The curl command in the Verification section above must return HTTP 200 + valid JSON.

### End-to-end release verification

After both changes are live, trigger the next web-platform release (either by merging a real change to `apps/web-platform/**` or by `workflow_dispatch` with `skip_deploy: false`). The release must reach the end of the `Verify deploy script completion` step with `ci-deploy.sh completed successfully for vX.Y.Z`.

If a release had already been queued during the gap (unlikely given P1 nature), confirm no back-to-back failure.

## Acceptance Criteria

### From #2214

- [ ] Non-JSON response body does not crash the step — logs `HTTP $HTTP_CODE, non-JSON body (endpoint not ready)` and continues polling.
- [ ] Timeout path still triggers after 120s of continuous non-JSON / no-body responses (`::error::ci-deploy.sh did not report completion ...`).
- [ ] Real deploy failures (valid JSON with `exit_code >= 1`) still fail fast with `::error::`.
- [ ] Test: workflow step logic verified against simulated non-JSON body (see Test Scenarios).

### From #2215

- [ ] `terraform apply` runs successfully in `prd_terraform` config (only `terraform_data.deploy_pipeline_fix` replaced; no other drift).
- [ ] `/hooks/deploy-status` returns HTTP 200 with valid JSON to a signed GET.
- [ ] The next `web-platform-release` workflow run passes the `Verify deploy script completion` step.

### Cross-cutting

- [ ] PR body includes `Closes #2214` and `Closes #2215`.
- [ ] PR has `semver:patch` label (workflow + ops fix, no plugin component changes).
- [ ] No `plugin.json` / `marketplace.json` version bumps (frozen sentinels).
- [ ] A learning file is created in `knowledge-base/project/learnings/bug-fixes/` capturing the "signed-GET verify step must tolerate non-JSON bodies" pattern.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `terraform plan` shows unexpected drift (e.g., hcloud_server changes) | Low | High — server replacement loses `/mnt/data` state until volume reattaches | Always review plan before apply; halt if anything outside `deploy_pipeline_fix` shows changes. Our lifecycle guards (`ignore_changes = [user_data, ssh_keys, image]`) are specifically designed to prevent this. |
| Webhook restart coincides with an in-flight deploy | Very low | Medium — deploy could lose its hook reply; health check + retry path still works | Time the apply outside an active release (check `gh run list --workflow=web-platform-release.yml --status=in_progress`). |
| Doppler `prd_terraform` token lacks apply permissions | Low | Low — plan will succeed, apply will 401 | Verify with `doppler secrets -p soleur -c prd_terraform` locally first; fall back to user-scoped Doppler login if needed. |
| State file on `/var/lock/ci-deploy.state` missing post-restart | Low | Low — returns `-2 no_prior_deploy` once, then next deploy writes it | Documented as acceptable outcome. No action needed. |
| `jq -e .` behaves differently across jq versions | Very low | Low — all GHA runners use jq 1.6+ which supports `-e` consistently | No mitigation needed. |
| Workflow change merged but apply deferred; next release still hits 404 | Medium | Low — step now retries 24× and fails at 120s with a clear "endpoint not ready" timeout message instead of a confusing `jq parse error` | This is the exact scenario the workflow hardening is designed for. Acceptable interim state. |

## Rollout

1. Create PR with the workflow change + learning file. Label `semver:patch`, `bug`, `priority/p1-high`, `domain/engineering`. Body includes `Closes #2214\nCloses #2215`.
2. QA + review per constitution. Squash-merge.
3. Operator runs `terraform apply` per the command block in Implementation Detail.
4. Operator manually triggers `web-platform-release.yml` via `workflow_dispatch` with `skip_deploy: false` to validate end-to-end, OR waits for the next natural release.
5. Confirm `Verify deploy script completion` passes. Close both issues via merge (#2214) and manual close with apply evidence (#2215).

## Alternative Approaches Considered

| Alternative | Reason rejected |
|---|---|
| Drop `bash -e` from the step shell (`shell: /usr/bin/bash`) | Disables defensive behavior for unrelated bugs in the loop; the current issue is scoped to jq, so the fix should be scoped to jq. |
| Parse only `exit_code` (skip `reason`/`tag` until validated) | Reduces observability without meaningfully reducing parse-error risk — any field could still be missing on malformed input. |
| Replace `/hooks/deploy-status` with direct SSH to `cat /var/lock/ci-deploy.state` | Violates AGENTS.md ("SSH is for infrastructure provisioning only, never for logs"). |
| Bake the deploy-status provisioning into the CI release workflow (auto-apply on drift) | Out of scope and risky — would require giving the release workflow Hetzner + Cloudflare + R2 creds and SSH keys. Belongs in a separate terraform-CI plan if pursued. |
| Remove `ignore_changes = [user_data]` so cloud-init re-applies | Would force server replacement on every cloud-init diff. Tracked separately; not a fix for this incident. |

## Domain Review

**Domains relevant:** engineering (CTO)

No Product/UX Gate — infrastructure + CI workflow change with no user-facing surface.

### CTO (Engineering)

**Status:** self-assessed (agent is primary CTO-domain author for this plan)
**Assessment:** The fix is surgical, preserves existing control-flow invariants (`case` statement, timeout, error-exit on `exit_code >= 1`), and follows the established pattern for signed GET observability endpoints. The terraform apply is a routine re-provisioning governed by an existing `terraform_data` resource with an already-drifted `triggers_replace` hash — no new infra surface. Both changes are reversible (revert the workflow change; re-run apply if the remote-exec fails mid-flight). No architectural implications.

Key signals supporting ship:

- `triggers_replace` already captures `cat-deploy-state.sh` and `hooks.json` — the resource is correctly modeling drift; we just need to run apply.
- `hcloud_server.web` lifecycle (`ignore_changes = [user_data, ssh_keys, image]`) prevents accidental server replacement.
- Workflow change preserves all four existing `case` branches; only adds a pre-parse guard.
- `jq -e .` is consistent across jq ≥ 1.5 and present on `ubuntu-latest` runners by default.

## References

- PR #2187 — webhook observability feature (source of the coupled defects).
- Release run `24411905995` (v0.35.11) — the failing run.
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — call pattern and reason taxonomy for the endpoint.
- `apps/web-platform/infra/server.tf` — `terraform_data.deploy_pipeline_fix` resource (source of truth for existing-server provisioning).
- `apps/web-platform/infra/hooks.json.tmpl` — both hook definitions.
- `apps/web-platform/infra/cat-deploy-state.sh` — the hook handler on the server.
- AGENTS.md rules applied: never SSH for logs; terraform-for-infra; local terraform requires `--name-transformer tf-var` + separate AWS env vars; no heredocs in `run:` blocks; hard-fail on non-zero without investigation.
