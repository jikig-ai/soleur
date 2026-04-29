# Fix: Terraform drift on `terraform_data.deploy_pipeline_fix` — apply pending ci-deploy.sh changes (#2618)

> **2026-04-29 NOTE:** This plan's webhook smoke-test acceptance criterion ("Expected: HTTP 200" against `https://deploy.soleur.ai/hooks/deploy-status`) is **legacy** and incorrect post-CF-Access. Use the file+systemd contract documented in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe" subsection. Tracking: #3034.

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** Overview, Phase 1-5, Risks, Research Insights
**Research sources:** repo file inspection (server.tf, scheduled-terraform-drift.yml, deploy-status-debugging.md), git log of trigger files, learning `2026-04-06-terraform-data-connection-block-no-auto-replace.md`, AGENTS.md rule corpus.

### Key Improvements

1. **Corrected deploy-status `curl` call** — uses `X-Signature-256` (not `X-Hub-Signature-256`) and the documented openssl `sed` extraction; matches `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` byte-for-byte.
2. **Added `-replace` alternative** — explicit `-replace=terraform_data.deploy_pipeline_fix` per the `2026-04-06-terraform-data-connection-block-no-auto-replace.md` learning; usable if `triggers_replace` evaluation is somehow stale.
3. **Provider-pin cross-check** — `.terraform.lock.hcl` confirms hcloud 1.60.1 / cloudflare 4.52.7 / random 3.8.1; local `terraform init` will reuse these, so no provider-version surprises.
4. **Backend cred extraction corrected** — `use_lockfile = false` in main.tf (R2 limitation); no DynamoDB lock to clear, no split-brain risk between concurrent applies.
5. **Explicit "no-op" guard for `/mnt/data/.env`** — the provisioner's `rm -f /mnt/data/.env` is documented idempotent; re-running apply on a tainted resource is safe.

### New Considerations Discovered

- `use_lockfile = false` means R2 backend has NO state lock. Two concurrent applies would race; explicit human coordination is the only guard. Phase 2 notes this.
- `ssh_key_path` variable is only referenced for `hcloud_ssh_key.default` (a create-time attribute with `ignore_changes = [public_key]`), so the dummy CI key value never matters at apply time for this fix. Any existing local public key works.
- The webhook restart happens inside the provisioner's final `remote-exec` block; if provisioning fails between `file` uploads and `systemctl restart webhook`, the server has new `ci-deploy.sh` on disk but the old webhook still running. The file upload is atomic per-file; either all four files are new (apply succeeded) or the resource is tainted and needs re-apply.

## Overview

The nightly drift detector (`scheduled-terraform-drift.yml`) reported exit code 2 on `apps/web-platform/infra/` at 2026-04-18 18:55 UTC: `terraform_data.deploy_pipeline_fix` needs replacement (`triggers_replace` changed, 1 to add / 1 to destroy). This is **intentional drift**: PR #2576 ("perf(pdf): qpdf concurrency gate + container tmpfs /tmp") merged at 2026-04-18 14:29 UTC — ~4.5 hours before the drift scan — modifying `apps/web-platform/infra/ci-deploy.sh` to add `--tmpfs /tmp:rw,nosuid,nodev,size=256m` on the canary and production `docker run` sites. The `triggers_replace` expression is `sha256(join(",", [file(ci-deploy.sh), file(webhook.service), file(cat-deploy-state.sh), local.hooks_json]))` (server.tf:110-115), so the hash legitimately changed; the apply simply has not run yet.

This is the documented steady state for `deploy_pipeline_fix` — the in-file comment says *"Shows as 'will be created' in CI drift reports -- expected behavior (#1409)"*. The resource exists because `hcloud_server.web` has `lifecycle { ignore_changes = [user_data] }`, so cloud-init never re-applies to the existing server; `deploy_pipeline_fix` is the sole path to push `ci-deploy.sh`/`webhook.service`/`cat-deploy-state.sh`/`hooks.json` updates to the running production host (per #2185 comment in server.tf:107-109).

**Resolution:** run `terraform apply` locally from `apps/web-platform/infra/` (via `doppler run --name-transformer tf-var`, matching the CI invocation per `cq-when-running-terraform-commands-locally`). This re-provisions the four files over SSH, `systemctl daemon-reload`s, and restarts the webhook. Then close #2618 once the next scheduled drift run returns exit 0.

**Why intentional (not a manual change):**

- The drift is on `triggers_replace`, not on any Hetzner/Cloudflare cloud state field — manual SSH edits to `/usr/local/bin/ci-deploy.sh` on the server would NOT shift the trigger hash (the hash is over the **local** repo files, not the server copy).
- Git history confirms the most recent trigger-file change: `10d21653` (PR #2576, merged 14:29 UTC) touched `ci-deploy.sh`. The drift run started at 18:55 UTC. Prior to that, the last trigger-file change was `932135b5` (PR #2187) on 2026-04-14.
- No `.tfstate` tamper, no failed prior apply (no `terraform state list` orphan per `cq-terraform-failed-apply-orphaned-state` — the resource exists in state with a stable `id`).

## Research Reconciliation — Spec vs. Codebase

| Issue claim / next-step | Reality | Plan response |
|---|---|---|
| "If the drift is intentional, run `terraform apply` locally to update state" (auto-generated issue body) | Correct. The drift is intentional and apply is the right action. | Follow it verbatim — no revert needed. |
| "triggers_replace changed (sensitive value)" | The *values* are marked sensitive because the hash inputs include `local.hooks_json`, which interpolates `var.webhook_deploy_secret`. Terraform masks the trigger content, not the fact of change. | Accept the sensitive masking. The issue body already contains enough signal (plan shows `# forces replacement`). |
| Issue milestone: "Post-MVP / Later" | Auto-assigned by drift workflow. | Leave as-is; closing the issue is sufficient. |

## Implementation Phases

### Phase 1 — Confirm drift source locally (≤ 5 min)

- [ ] From the worktree, run `terraform init -input=false` in `apps/web-platform/infra/` (re-init because the worktree has no `.terraform/` directory).
- [ ] Run the plan in the exact CI form:

  ```bash
  cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2618-terraform-drift-deploy-pipeline-fix/apps/web-platform/infra
  # Extract R2 creds separately (name-transformer would mangle them)
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform plan -detailed-exitcode -no-color -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

- [ ] Expected: exit code 2, "Plan: 1 to add, 0 to change, 1 to destroy" targeting only `terraform_data.deploy_pipeline_fix`. No other resources in the plan.
- [ ] **Abort condition:** if the plan names any resource other than `deploy_pipeline_fix`, stop and escalate — that indicates additional drift outside this issue's scope.

### Phase 2 — Apply (≤ 3 min)

- [ ] **Freeze merges.** R2 backend has `use_lockfile = false` (main.tf:15). There is NO state lock — two concurrent applies will race and corrupt state. Before Phase 2, confirm no PR is in merge queue (`gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'` should be empty).
- [ ] Verify SSH agent has the prod private key loaded (`ssh-add -l | grep -i ed25519`). The Terraform `connection` block uses `agent = true` (server.tf:117-122) — apply fails with "no suitable auth method" if no key is loaded. Per the learning `2026-04-06-terraform-data-connection-block-no-auto-replace.md`, `connection` block attributes are NOT in `triggers_replace`, so changing from `private_key` to `agent = true` was silent; the current state still uses `agent = true` and requires a loaded agent.
- [ ] **Primary apply path** — let `triggers_replace` drive replacement organically:

  ```bash
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -auto-approve -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

- [ ] **Alternative (fallback) path** — explicit `-replace` flag if `triggers_replace` somehow shows no-op after Phase 1 (edge case per learning `2026-04-06-terraform-data-connection-block-no-auto-replace.md`):

  ```bash
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -auto-approve -input=false \
    -replace=terraform_data.deploy_pipeline_fix \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

- [ ] Expected sequence in apply output: destroy of `terraform_data.deploy_pipeline_fix` → create (file provisioner uploads `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `hooks.json`) → remote-exec chmods + `chown root:deploy /etc/webhook/hooks.json` + `chmod 640 /etc/webhook/hooks.json` + Doppler env idempotent append + `systemctl daemon-reload` + `systemctl restart webhook` + `rm -f /mnt/data/.env`.
- [ ] Apply completes "Apply complete! Resources: 1 added, 0 changed, 1 destroyed."
- [ ] **Recovery (tainted resource).** If the SSH provisioner fails mid-apply, the resource will be tainted in state. Run `terraform state list | grep deploy_pipeline_fix` — if present, rerun apply (all provisioner steps are idempotent by design):
  - `chmod +x /usr/local/bin/ci-deploy.sh` — idempotent.
  - `chmod +x /usr/local/bin/cat-deploy-state.sh` — idempotent.
  - `chown root:deploy /etc/webhook/hooks.json` + `chmod 640 /etc/webhook/hooks.json` — idempotent.
  - `grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy || printf ...` — explicitly grep-guarded (server.tf:155).
  - `systemctl daemon-reload` + `systemctl restart webhook` — idempotent.
  - `rm -f /mnt/data/.env` — idempotent (`-f` swallows ENOENT).
- [ ] Only invoke `terraform state rm` after `terraform state list | grep deploy_pipeline_fix` confirms an orphan on the Terraform side AND the cloud-side resource is genuinely absent (per `cq-terraform-failed-apply-orphaned-state`). For this resource there is no cloud-side object (it's a `terraform_data`), so state-rm recovery means re-planning from scratch — preferred only as last resort.

### Phase 3 — Verify production (≤ 5 min)

- [ ] Confirm webhook restarted cleanly — hit `/hooks/deploy-status` with CF Access headers + HMAC-sha256. The exact form is documented in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (the header is `X-Signature-256`, NOT `X-Hub-Signature-256`):

  ```bash
  WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET --project soleur --config prd_terraform --plain)
  CF_ACCESS_CLIENT_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID --project soleur --config prd_terraform --plain)
  CF_ACCESS_CLIENT_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET --project soleur --config prd_terraform --plain)
  SIGNATURE=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
  curl -sf -X GET \
    -H "X-Signature-256: sha256=$SIGNATURE" \
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
    https://deploy.soleur.ai/hooks/deploy-status
  ```

- [ ] Expected: HTTP 200 with a JSON body. The `reason` field should be `ok` (prior deploy succeeded, exit_code 0) OR `running` if a deploy is in flight. Any `doppler_*`/`command_*`/`production_start_failed` reason after our apply indicates the webhook came back up but is now in a broken state — escalate. See `deploy-status-debugging.md` Reason Taxonomy table.
- [ ] Run `curl -I https://soleur.ai/health` — expect HTTP 200 (basic liveness). If the site is DOWN after webhook restart, the issue is NOT our Terraform apply (apply only touches `/etc/systemd/system/webhook.service` and restarts the `webhook` unit — the main `soleur-web` container is unaffected). A site outage in this window is coincidental and must be triaged separately.

### Phase 4 — Re-verify drift is gone (≤ 2 min)

- [ ] Re-run the plan from Phase 1. Expected: exit code 0, "No changes. Your infrastructure matches the configuration."
- [ ] If a new drift surfaces on a *different* resource, file a separate drift issue — do not conflate.

### Phase 5 — Close the issue + trigger drift workflow (≤ 2 min)

- [ ] Comment on #2618 with the Phase 4 plan output (exit 0) and close:

  ```bash
  gh issue close 2618 --comment "Applied terraform to pick up ci-deploy.sh changes from PR #2576 (qpdf concurrency + tmpfs /tmp). Plan now exits 0. Verified webhook /hooks/deploy-status returns 200."
  ```

- [ ] Manually trigger the drift workflow to confirm the next scheduled run would pass:

  ```bash
  gh workflow run scheduled-terraform-drift.yml
  gh run list --workflow scheduled-terraform-drift.yml --limit 1 --json databaseId,status --jq '.[0]'
  # Poll via Monitor tool until status == completed, then:
  gh run view <id> --json conclusion --jq .conclusion   # expect: success
  ```

## Acceptance Criteria

### Pre-merge (PR)

This plan produces NO code changes — it is a remediation runbook. There is no PR. Work is ops-only.

### Post-merge (operator)

- [ ] `terraform plan` in `apps/web-platform/infra/` exits 0 (no drift).
- [ ] Scheduled drift workflow run (triggered manually in Phase 5) concludes `success`.
- [ ] `https://deploy.soleur.ai/hooks/deploy-status` returns HTTP 200 with valid JSON.
- [ ] `https://soleur.ai/health` returns HTTP 200.
- [ ] Issue #2618 is closed with a comment linking the applied run.
- [ ] The `/tmp/*` tmpfs flag from PR #2576 is confirmed active on the next canary deploy (this will happen on the next normal merge to main — no explicit test needed, but record the expectation).

## Research Insights

- **#1409 (disk-monitor) set the pattern** — `terraform_data.*_install` resources that push files to the already-provisioned host trigger on content hash, and the apply path *is* the deploy. This is not a bug; it's the "fix existing-server" pattern that complements cloud-init (cloud-init bootstraps new servers; these resources catch the live one because `ignore_changes = [user_data]` on `hcloud_server.web`).
- **#2185 extended the pattern** for `ci-deploy.sh` + `webhook.service` + `hooks.json`, explicitly calling out (server.tf:107-109) that `deploy_pipeline_fix` is the sole path for pushing these updates to production.
- **`cat-deploy-state.sh` + `hooks.json.tmpl`** were folded into the same trigger in PR #2187 (commit `932135b5`), so any change to any of the four files re-triggers replacement. This is the right ergonomics — one apply deploys all the deploy-pipeline scripts atomically.
- **Learning referenced:** `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` (related `terraform_data` provisioner behavior — connection block changes do NOT auto-replace, but `triggers_replace` changes DO, which is what we're seeing).
- **AGENTS.md rules applied:**
  - `cq-when-running-terraform-commands-locally` — use `doppler run --name-transformer tf-var`, extract R2 creds separately.
  - `cq-terraform-failed-apply-orphaned-state` — only invoke `terraform state rm` after running `terraform state list`; here we expect no orphans.
  - `cq-deploy-webhook-observability-debug` — verify webhook via `/hooks/deploy-status` with CF Access + HMAC headers.
  - `hr-all-infrastructure-provisioning-servers` — no manual SSH fix; the Terraform apply IS the fix.
  - `hr-never-label-any-step-as-manual-without` — every step is automated via CLI; no manual browser/SSH handoff.

## Open Code-Review Overlap

None.

No open code-review issues match `apps/web-platform/infra/server.tf`, `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, or `hooks.json.tmpl`. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a pure ops remediation (run terraform apply, close issue). No code changes, no user-facing surface, no new dependencies, no external services. CTO domain is implicit (the current task IS engineering per `pdr-do-not-route-on-trivial-messages-yes`), so no CTO routing.

## Risks & Non-Goals

### Risks

- **SSH agent not loaded on operator machine.** Apply requires the production SSH private key in the agent (server.tf:117-122 `agent = true`). If unloaded, apply fails mid-provisioner; mitigation: Phase 2 explicitly verifies `ssh-add -l` first.
- **Webhook restart window.** `systemctl restart webhook` in the provisioner causes a brief (<2s) deploy-webhook unavailability. Safe because no deploy should be in-flight at 2026-04-19; Phase 2 explicitly checks for merge-queued PRs before running apply.
- **No R2 state lock (`use_lockfile = false`).** Per main.tf:15, R2 does not support S3 conditional writes, so Terraform cannot acquire a backend lock. Two concurrent applies WILL race and can corrupt state. Phase 2 requires human coordination ("freeze merges") — there is no mechanical guard. If other Terraform operators exist on the team, announce the apply before starting.
- **Doppler `prd_terraform` config drift.** If the `prd_terraform` config is missing `CF_API_TOKEN`, `HCLOUD_TOKEN`, `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_CLIENT_ID`, or `CF_ACCESS_CLIENT_SECRET`, the plan fails at refresh. Mitigation: Phase 1's plan will surface missing vars before any destroy-step.
- **Provider version drift in CI.** CI uses `TERRAFORM_VERSION: 1.10.5` (scheduled-terraform-drift.yml:24). The operator's local `terraform` binary should match — check `terraform version` before Phase 1. A major version mismatch can produce spurious plan deltas.
- **Second drift detected during apply window.** If another PR merges between Phase 1 plan and Phase 2 apply that touches a trigger file, the apply will include both deltas. Mitigation: freeze merges during the ~3-minute apply window.
- **`rm -f /mnt/data/.env` side-effect.** The provisioner's final remote-exec deletes `/mnt/data/.env`. Per server.tf:158-160 comment, this is one-time cleanup (the file was removed in a prior apply and is not recreated). Re-apply is safe because `rm -f` is idempotent and no code path currently writes to that path.

### Non-Goals

- Not moving the deploy-pipeline-fix pattern to a post-merge GitHub Action (that would be `wg-after-merging-a-pr-that-adds-or-modifies` territory, but no workflow-file change is part of #2618). A post-merge auto-apply is tracked implicitly by the existing drift-detection cadence; filing an enhancement issue is out of scope for this fix. **If this drift pattern recurs twice more** (i.e., a third "intentional drift" issue for `deploy_pipeline_fix` in ≤30 days), file an enhancement to auto-apply on PRs that touch `apps/web-platform/infra/*.sh` or `*.service`.
- Not changing the `triggers_replace` expression to avoid drift (e.g., by hashing a version number). The current content-hash design is correct — it guarantees production reflects committed code.
- Not auditing other `terraform_data.*_install` resources; only `deploy_pipeline_fix` is drifted per the issue.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Revert PR #2576** | #2576 is a merged perf improvement (qpdf concurrency cap + tmpfs /tmp) with 5 new passing tests. Reverting abandons a fix for two already-drained scope-outs (#2472, #2473). Apply is strictly better. |
| **`terraform state rm` the resource** | State removal without apply leaves the server without the new `ci-deploy.sh` — the very change that PR #2576 intended. Violates `hr-all-infrastructure-provisioning-servers` (Terraform remains source of truth). |
| **Manual `scp` of `ci-deploy.sh` to the server** | Violates `hr-all-infrastructure-provisioning-servers` explicitly. Does not restart the webhook. Does not update `webhook.service` or `hooks.json`. |
| **Add a post-merge `terraform apply` GitHub Action now** | Enhancement territory; expands scope beyond "resolve #2618". Track separately if the pattern recurs. |

## Test Strategy

No code changes → no unit tests. The verification happens in Phases 3 and 4:

- **Phase 3** = integration test of the deployed webhook (HTTP 200 on `/hooks/deploy-status`, `/health`).
- **Phase 4** = regression test of the drift condition (plan exits 0).
- **Phase 5** = end-to-end test of the drift-detection workflow (`gh workflow run` → `success`).

No new tests, no test runner invocation. `ci-deploy.test.sh` was already extended by PR #2576 to assert the tmpfs flag; that test ran on merge and passed.

## Files to Edit

None (this is an ops runbook, not a code change).

## Files to Create

None.
