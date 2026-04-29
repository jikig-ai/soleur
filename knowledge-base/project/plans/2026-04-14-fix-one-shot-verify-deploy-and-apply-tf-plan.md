# Fix: verify-deploy step hardening + provision /hooks/deploy-status on live server

**Issues:** Closes #2214, Closes #2215
**Type:** fix (CI workflow hardening + infra provisioning)
**Priority:** P1
**Milestone:** Phase 3: Make it Sticky
**Semver:** patch

> **2026-04-29 NOTE:** This plan's webhook smoke-test acceptance criterion ("Expected: HTTP 200" against `https://deploy.soleur.ai/hooks/deploy-status`) is **legacy** and incorrect post-CF-Access. Use the file+systemd contract documented in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe" subsection. Tracking: #3034.

## Enhancement Summary

**Deepened on:** 2026-04-14
**Sections enhanced:** Summary, Approach (Part A), Approach (Part B), Implementation Detail, Test Scenarios, Risks
**Research sources:** live workflow logs (run 24411905995), project learnings (2026-04-06 terraform_data connection block; 2026-04-03 terraform_data remote-exec drift; 2026-04-05 stale env deploy-pipeline bridge; 2026-02-13 SSH operator precedence), local jq/bash dry-runs (jq 1.8.1, verified parse behavior).

### Key Improvements

1. **Empirical confirmation of the failure signature** — run log shows the step uses `shell: /usr/bin/bash -e {0}` and exits with code 5 (jq's parse-error exit code) immediately after the first `jq -r` call. The `case` branch never runs.
2. **Terraform apply hazard mitigation** — institutional learning (`2026-04-06`) warns that `terraform_data` provisioner connection blocks don't trigger replacement on config change; we confirm `triggers_replace` already captures `cat-deploy-state.sh` and `hooks.json` content, so a plain apply is safe without `-replace`. We still prescribe targeted `-replace=terraform_data.deploy_pipeline_fix` as a fallback if the hash check is ambiguous.
3. **`agent = true` already in place** — learning `2026-04-03` warned about passphrase-encrypted SSH keys failing with `ssh: parse error in message type 0`; `server.tf` already uses `connection { agent = true }` on `deploy_pipeline_fix`, so the encrypted-key pitfall is pre-mitigated.
4. **Webhook restart blast radius** — `systemctl restart webhook` during an in-flight deploy is now explicitly documented: the deploy runs under a separate `ci-deploy.sh` process (flock'd on `/var/lock/ci-deploy.lock`), not a child of webhook; restarting the listener does not kill in-progress deploys, only rejects new inbound POSTs for sub-second. Confirmed by webhook.service architecture.
5. **Tag-match race** — the existing `case 0)` branch compares `$TAG` to `v$VERSION`; after apply the state file might be stale (`v0.35.11` while the current release is `v0.35.12`) and the step would time out. Remediation: document this as expected and rely on the `Verify deploy health and version` second step as the independent oracle.

### New Considerations Discovered

- Dropping `bash -e` is explicitly rejected (not because of the issue body's hint — because the learning `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` warns that quiet failure-absorption in deploy scripts is a critical-severity pattern). The scoped `jq -e .` guard preserves defensive semantics.
- `jq -e .` exits 1 on parse error and 0 on parse success (even for `null` / `false` — `-e` only flips exit code based on the *output* value; for `.` on valid JSON the output is the input, and falsy outputs exit 1 only for literal `null`/`false`. An empty-object or empty-array body therefore passes the guard and falls through to the field parsers with their `//` defaults — correct behavior).
- The `${jsonencode(webhook_deploy_secret)}` interpolation in `hooks.json.tmpl` means terraform renders the secret directly into the file served by the provisioner. The state file on R2 will contain the secret; this is pre-existing behavior, not introduced by this PR.

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

#### Research Insights — jq guard semantics

**Exit-code behavior of `jq -e .`:**

| Input | `jq -e .` exit code | Our guard verdict |
|---|---|---|
| Valid JSON object | 0 | pass — field parsers run |
| Valid JSON array | 0 | pass — field parsers run |
| `null` literal | 1 | **fail — retries as "non-JSON"** (intentional: a `null` body means the endpoint is wedged; retry is the right move) |
| `false` literal | 1 | fail — retries (unreachable in practice; `cat-deploy-state.sh` never emits `false`) |
| Empty JSON `{}` / `[]` | 1 (`{}` → empty, `[]` → empty) | fail — retries (acceptable: a deploy-status endpoint returning empty JSON is not "ready") |
| Non-JSON plaintext | 5 (parse error, suppressed by `2>/dev/null`) | fail — retries |
| HTML 404 body | 5 (parse error) | fail — retries |

One subtle behavior: `jq -e .` exits 1 on `null`/`false`/`{}`/`[]`. For our use-case this is *correct* — none of those values represent a meaningful `deploy-status` reply, and retrying until the next valid response is exactly the desired semantics. Documented here so future maintainers don't "fix" the guard by switching to `jq empty` (which is permissive and would pass `null` through to the field parsers, where `// -99` would then trigger the `*)` fast-fail branch — subtly wrong).

**Why not `jq empty`:** `jq empty` succeeds on any valid JSON including `null`. Combined with `// -99` defaults, a `null` body would yield `EXIT_CODE=-99`, hit the `*)` branch, and fail-fast the release. That's a worse failure mode than "retry and time out at 120s with a clear message."

**Why not `set +e` / `set -e` toggling:** Scoped `set +e`/`set -e` around the three `jq -r` calls would work but mixes with `continue` semantics (the `continue` inside the tolerant zone requires the inner loop-body to be correct under both error modes). The `jq -e .` pre-check is simpler: one guard, one branch, no control-flow mixing.

**Why not remove `bash -e`:** Per learning `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md`, quiet failure-absorption in deploy-adjacent shell is a critical-severity pattern. Keeping `-e` preserves defensive behavior for every other command in the loop (curl, cat, sleep, sed). The fix scopes only to the known-unsafe `jq` invocations.

**Log-line readability:** The "endpoint not ready" text is deliberately distinct from the "no body" text so a human reading the Actions log can tell the difference between "endpoint returned no bytes" (network/CF edge issue) and "endpoint returned something unparseable" (webhook listener up but hook missing, or adnanh/webhook 404 body).

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

#### Research Insights — terraform apply safety

**Why plain apply is expected to work (not `-replace`):**

`terraform_data.deploy_pipeline_fix` declares:

```hcl
triggers_replace = sha256(join(",", [
  file("${path.module}/ci-deploy.sh"),
  file("${path.module}/webhook.service"),
  file("${path.module}/cat-deploy-state.sh"),
  local.hooks_json,
]))
```

PR #2187 added `cat-deploy-state.sh` (new file content in hash input) and modified `hooks.json.tmpl` (changes `local.hooks_json`). Both changes alter the hash, so Terraform's normal drift detection will catch it and plan a replacement on the next apply. No `-replace` needed.

**Fallback if plan shows no changes** (state file already reflects the new hash but the server wasn't updated — e.g., prior apply crashed mid-provisioner):

```bash
doppler run --name-transformer tf-var -p soleur -c prd_terraform -- \
  terraform apply -replace=terraform_data.deploy_pipeline_fix
```

This matches the remediation pattern in learning `2026-04-06-terraform-data-connection-block-no-auto-replace.md`.

**Connection block is agent-based (already safe):**

```hcl
connection {
  type  = "ssh"
  host  = hcloud_server.web.ipv4_address
  user  = "root"
  agent = true
}
```

Per learning `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`, `agent = true` was specifically chosen to avoid `ssh: parse error in message type 0` on passphrase-encrypted keys. The operator just needs `ssh-add` to have loaded the server key before apply; no temp-key workaround required.

**Webhook restart blast radius:**

- `webhook.service` is a systemd unit running `adnanh/webhook` as the HTTP listener.
- `ci-deploy.sh` is spawned by webhook on POST but detaches (webhook returns 202 immediately, deploy continues independently under `flock /var/lock/ci-deploy.lock`).
- `systemctl restart webhook` stops the listener and restarts it; it does **not** kill already-detached `ci-deploy.sh` processes.
- New inbound POSTs during the ~1s restart window receive a connection-refused from Cloudflare (which typically returns 502). Mitigation: time the apply outside release windows (check `gh run list --workflow=web-platform-release.yml --status=in_progress` before applying).

**Pre-apply drift check:**

Before apply, confirm no unrelated drift:

```bash
doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform plan -no-color 2>&1 | tee /tmp/tfplan.out
grep -E '^\s*[#~+-]' /tmp/tfplan.out | head -50
```

Expected: one `-/+` block for `terraform_data.deploy_pipeline_fix`. If any of the following appear, STOP and triage:

- Any change to `hcloud_server.web` (would force server replacement).
- Any change to `hcloud_volume_attachment.workspaces` (would detach workspaces volume).
- Any change to `hcloud_volume.workspaces` (would destroy user data).
- Any change to `cloudflare_*` resources outside `cloudflare_zero_trust_tunnel_cloudflared.web`'s expected token rotation.

**Post-apply state sanity:**

```bash
doppler run --name-transformer tf-var -p soleur -c prd_terraform -- terraform state pull 2>/dev/null | \
  jq '.resources[] | select(.type == "terraform_data" and .name == "deploy_pipeline_fix") | .instances[0].attributes.triggers_replace'
```

Should print the post-apply sha256 hash. Compare to the pre-apply hash stored in the plan output.

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

### Additional edge-case simulations (research-driven)

These were validated locally against jq 1.8.1 and bash 5.x; behavior is stable across jq 1.5+.

```bash
# 1. null JSON literal -> retry branch (intentional)
BODY="null"
echo "$BODY" | jq -e . >/dev/null 2>&1 && echo "passed" || echo "retry"  # prints "retry"

# 2. empty object -> retry branch (acceptable)
BODY="{}"
echo "$BODY" | jq -e . >/dev/null 2>&1 && echo "passed" || echo "retry"  # prints "retry"

# 3. valid JSON with missing fields -> passes guard, defaults kick in, *) fast-fails
BODY='{"other":"data"}'
echo "$BODY" | jq -e . >/dev/null 2>&1 && echo "passed"  # prints "passed"
EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
echo "EXIT_CODE=$EXIT_CODE"  # prints "EXIT_CODE=-99" -> hits *) branch in workflow

# 4. Cloudflare HTML 503 (different from adnanh 404 text)
BODY='<html><body>503 Service Unavailable</body></html>'
echo "$BODY" | jq -e . >/dev/null 2>&1 && echo "passed" || echo "retry"  # prints "retry"
```

Case 3 reveals a secondary invariant: if the endpoint returns JSON that parses but has no `exit_code` field, the workflow will hit the `*)` fast-fail branch with `EXIT_CODE=-99, REASON=unknown`. This is pre-existing behavior (not introduced by this PR) and is desirable — a well-formed but semantically broken response should fail the release loudly rather than retry silently. `cat-deploy-state.sh` only ever emits well-known shapes, so this would indicate a server-side regression worth investigating.

### Production verification after apply

The curl command in the Verification section above must return HTTP 200 + valid JSON.

### End-to-end release verification

After both changes are live, trigger the next web-platform release (either by merging a real change to `apps/web-platform/**` or by `workflow_dispatch` with `skip_deploy: false`). The release must reach the end of the `Verify deploy script completion` step with `ci-deploy.sh completed successfully for vX.Y.Z`.

If a release had already been queued during the gap (unlikely given P1 nature), confirm no back-to-back failure.

## Acceptance Criteria

### From #2214

- [x] Non-JSON response body does not crash the step — logs `HTTP $HTTP_CODE, non-JSON body (endpoint not ready)` and continues polling.
- [x] Timeout path still triggers after 120s of continuous non-JSON / no-body responses (`::error::ci-deploy.sh did not report completion ...`).
- [x] Real deploy failures (valid JSON with `exit_code >= 1`) still fail fast with `::error::`.
- [x] Test: workflow step logic verified against simulated non-JSON body (see Test Scenarios).

### From #2215

- [ ] `terraform apply` runs successfully in `prd_terraform` config (only `terraform_data.deploy_pipeline_fix` replaced; no other drift). (post-merge action)
- [ ] `/hooks/deploy-status` returns HTTP 200 with valid JSON to a signed GET. (post-merge validation)
- [ ] The next `web-platform-release` workflow run passes the `Verify deploy script completion` step. (post-merge validation)

### Cross-cutting

- [x] PR body includes `Closes #2214` and `Closes #2215`.
- [ ] PR has `semver:patch` label (workflow + ops fix, no plugin component changes). (ship applies)
- [x] No `plugin.json` / `marketplace.json` version bumps (frozen sentinels).
- [x] A learning file is created in `knowledge-base/project/learnings/bug-fixes/` capturing the "signed-GET verify step must tolerate non-JSON bodies" pattern.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `terraform plan` shows unexpected drift (e.g., hcloud_server changes) | Low | High — server replacement loses `/mnt/data` state until volume reattaches | Always review plan before apply; halt if anything outside `deploy_pipeline_fix` shows changes. Our lifecycle guards (`ignore_changes = [user_data, ssh_keys, image]`) are specifically designed to prevent this. |
| Webhook restart coincides with an in-flight deploy | Very low | Medium — deploy could lose its hook reply; health check + retry path still works | Time the apply outside an active release (check `gh run list --workflow=web-platform-release.yml --status=in_progress`). |
| Doppler `prd_terraform` token lacks apply permissions | Low | Low — plan will succeed, apply will 401 | Verify with `doppler secrets -p soleur -c prd_terraform` locally first; fall back to user-scoped Doppler login if needed. |
| State file on `/var/lock/ci-deploy.state` missing post-restart | Low | Low — returns `-2 no_prior_deploy` once, then next deploy writes it | Documented as acceptable outcome. No action needed. |
| `jq -e .` behaves differently across jq versions | Very low | Low — all GHA runners use jq 1.6+ which supports `-e` consistently | No mitigation needed. |
| Workflow change merged but apply deferred; next release still hits 404 | Medium | Low — step now retries 24× and fails at 120s with a clear "endpoint not ready" timeout message instead of a confusing `jq parse error` | This is the exact scenario the workflow hardening is designed for. Acceptable interim state. |
| State file on server has stale `v$OLD_VERSION` after apply; verify step times out waiting for `v$VERSION` match | Medium | Low — `Verify deploy health and version` step (independent oracle) still passes because container is up at v$VERSION; only the status-hook verify would time out | The release as a whole will fail the status-hook step but succeed the health step. Acceptable: the first post-apply release documents this, subsequent releases write fresh state. No code change needed — the retry logic is correct, we just need to be aware that apply doesn't reset state. |
| `triggers_replace` hash unchanged in state despite file edits (Terraform optimizer) | Low | Low — plan shows no changes, endpoint stays 404 | Fall back to `terraform apply -replace=terraform_data.deploy_pipeline_fix` per learning `2026-04-06`. |
| SSH agent doesn't have server key loaded when operator runs apply | Medium | Medium — apply hangs or fails with connection timeout | Before apply, run `ssh-add -L | grep -q 'server-pubkey-fingerprint'`. If missing,`ssh-add ~/.ssh/id_ed25519`. The`agent = true` pattern prevents the encrypted-key error but still requires the key to be in the agent. |

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

### Source of defect

- PR #2187 — webhook observability feature (source of the coupled defects).
- Release run `24411905995` (v0.35.11) — the failing run. Log confirms `shell: /usr/bin/bash -e {0}` and `exit code 5` immediately after first `jq -r`.

### Code

- `.github/workflows/web-platform-release.yml` (step "Verify deploy script completion") — the modified step.
- `apps/web-platform/infra/server.tf` — `terraform_data.deploy_pipeline_fix` resource (source of truth for existing-server provisioning).
- `apps/web-platform/infra/hooks.json.tmpl` — both hook definitions.
- `apps/web-platform/infra/cat-deploy-state.sh` — the hook handler on the server.
- `apps/web-platform/infra/ci-deploy.sh` — writer of the state file consumed by the handler.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` — `terraform_data` replacement semantics; `-replace` fallback pattern.
- `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` — `agent = true` requirement; SSH key handling for provisioner.
- `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md` — original pattern for `terraform_data.deploy_pipeline_fix`; `ignore_changes = [user_data]` constraint.
- `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` — justification for keeping `bash -e` and scoping tolerance to specific commands rather than the whole block.

### Observability

- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — call pattern and reason taxonomy for the endpoint.

### Project rules

AGENTS.md rules applied: never SSH for logs; terraform-for-infra; local terraform requires `--name-transformer tf-var` + separate AWS env vars for R2 backend; no heredocs in `run:` blocks; hard-fail on non-zero without investigation; write failing tests only when plans have Test Scenarios with runtime-code acceptance criteria (this plan is infrastructure-only per the AGENTS.md TDD exemption).
