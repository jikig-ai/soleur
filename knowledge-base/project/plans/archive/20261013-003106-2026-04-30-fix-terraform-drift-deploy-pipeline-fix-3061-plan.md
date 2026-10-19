---
title: "Fix: Terraform drift on terraform_data.deploy_pipeline_fix (#3061) — apply pending ci-deploy.sh / canary-bundle-claim-check.sh changes"
type: fix
classification: ops-only-prod-write
date: 2026-04-30
issue: "#3061"
requires_cpo_signoff: false
---

# Fix: Terraform drift on `terraform_data.deploy_pipeline_fix` (#3061) — apply pending trigger-file changes

> **Ops-remediation runbook.** No code change, no PR. Operator runs `terraform apply` against `prd_terraform`, then closes #3061. Pattern is the 10th occurrence of the same drift class — the structural fix is tracked separately in `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" (already wired post-#3022) and the canonical post-apply contract lives in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` ("When NOT to use this probe").

## Enhancement Summary

**Deepened on:** 2026-04-30
**Sections enhanced:** Overview (PR-attribution table corrected), Research Insights (5 new findings), Risks (provider-pin verified), Acceptance Criteria (5-input file-hash assertions)
**Research sources:** `git show <SHA>:server.tf` for trigger-expression evolution, `apps/web-platform/infra/.terraform.lock.hcl` for provider pins, `apps/web-platform/infra/main.tf` for backend config, `plugins/soleur/skills/ship/SKILL.md` for the `DPF_REGEX` shape, `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`, learnings `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` + `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` + `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`, GitHub issues #3014 / #3019 / #3022 / #3033 / #3042 / #3045 / #2881.

### Key Improvements

1. **PR attribution corrected.** `canary-bundle-claim-check.sh` was added to `triggers_replace` in **#3042 (87bc9227)**, not #3014. Verified empirically via `git show b2fed080:server.tf` (4-input) vs `git show 87bc9227:server.tf` (5-input). The original draft conflated "file introduced" (#3014) with "added to trigger" (#3042).
2. **Structural gap surfaced.** The `/ship` Phase 5.5 `DPF_REGEX` (`plugins/soleur/skills/ship/SKILL.md:448`) is **stale**: it matches only the 4 legacy files (`ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `hooks.json.tmpl`) and does NOT match `canary-bundle-claim-check.sh`. Empirical test: `echo 'apps/web-platform/infra/canary-bundle-claim-check.sh' | grep -E '^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$'` → no match. This is exactly why this 10th drift was not caught at PR-merge time on #3042. Filing as a follow-up enhancement (out-of-scope for this remediation; tracked in §Research Insights).
3. **Provider/version pins confirmed.** `.terraform.lock.hcl` pins `hcloud 1.60.1`, `cloudflare 4.52.7`, `random 3.8.1`. Local `terraform version` reports `Terraform v1.10.5 on linux_amd64` — exact match with CI's `TERRAFORM_VERSION: 1.10.5`. No cross-version surprises during apply.
4. **Backend lock state confirmed.** `apps/web-platform/infra/main.tf:13` declares `use_lockfile = false  # R2 does not support S3 conditional writes`. The "no lock, freeze merges manually" risk in the plan is empirically grounded, not speculative.
5. **Acceptance Criteria scope expanded to 5 files.** Pre-deepen, post-merge ACs covered server-side hashes for 3 scripts. Trigger expression now hashes 5 inputs; ACs already cover the full set (`ci-deploy.sh`, `canary-bundle-claim-check.sh`, `cat-deploy-state.sh`) plus the implicit `webhook.service` (asserted via `systemctl is-active webhook` since the file IS the unit definition) and `hooks.json` (asserted via the `chown root:deploy /etc/webhook/hooks.json` provisioner step's idempotency). No AC text change needed — this is a clarification.

### New Considerations Discovered

- **Stale `/ship` gate is the structural cause of THIS occurrence.** The whole point of #2881 / `/ship` Phase 5.5 was to catch trigger-file edits at PR-merge time. PR #3042 edited `canary-bundle-claim-check.sh`, which IS in the 5-input trigger but is NOT in the gate's 4-file regex — so the gate did not fire, no apply was scheduled, and 12h later the cron drift detector filed #3061. The remediation here resolves the immediate drift; a separate follow-up issue is needed to widen the gate regex to include `canary-bundle-claim-check.sh` and to add a regression test that asserts the regex matches every file in the trigger expression.
- **Apply takes ~30 s of webhook unavailability**, not the originally-cited <2 s. The provisioner sequence is: 4 file uploads (~10 s over SSH on slow links) + chmod/chown (~1 s) + grep-guarded env append (~1 s) + `systemctl daemon-reload` + `systemctl restart webhook` (~2 s) + `rm -f /mnt/data/.env` (idempotent). The webhook itself is only down for the `restart webhook` step (~2 s) but the file-upload window is when an in-flight deploy could read a partially-rolled-out script. Mitigation unchanged: freeze merges; apply window is short either way.
- **Verification contract canonical source.** `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md:26-44` ("When NOT to use this probe") is the canonical source for the file+systemd post-apply contract. Cross-referenced and consistent with this plan's Phase 3.

## Overview

The nightly drift detector (`scheduled-terraform-drift.yml`) reported exit code 2 on `apps/web-platform/infra/` at 2026-04-29 19:40 UTC and re-confirmed it at 2026-04-30 08:25 UTC: `terraform_data.deploy_pipeline_fix` needs replacement (`triggers_replace = (sensitive value) # forces replacement`, "Plan: 1 to add, 0 to change, 1 to destroy"). This is **intentional drift** caused by recent merges that touched the four scripts hashed into the resource's trigger expression.

The trigger expression in `apps/web-platform/infra/server.tf:219-225` is:

```hcl
triggers_replace = sha256(join(",", [
  file("${path.module}/ci-deploy.sh"),
  file("${path.module}/webhook.service"),
  file("${path.module}/cat-deploy-state.sh"),
  file("${path.module}/canary-bundle-claim-check.sh"),
  local.hooks_json,
]))
```

So *any* edit to those files — or to `hooks.json.tmpl` (rendered into `local.hooks_json`) — re-hashes and demands a re-provision. The recent merges that drove this drift cycle:

| PR | Merged | File touched |
|---|---|---|
| #3045/#3046 (`1edf7a62`) | 2026-04-29 16:43 UTC | `ci-deploy.sh` (image-baked seed for `/mnt/data/plugins/soleur`) |
| #3042 (`87bc9227`) | 2026-04-29 15:56 UTC | `canary-bundle-claim-check.sh` + `ci-deploy.sh` (Layer 3 mount path + dynamic chunk discovery) — **also widened the trigger expression to add `canary-bundle-claim-check.sh` as a 5th hashed input** (verified via `git show b2fed080:server.tf` vs `git show 87bc9227:server.tf`) |
| #3014 (`b2fed080`) | 2026-04-26 | `ci-deploy.sh` only (close `/dashboard` error.tsx outage gaps; introduced `canary-bundle-claim-check.sh` as a new file but did NOT yet add it to the trigger) |

This is the documented steady state for `deploy_pipeline_fix` — the in-file comment (server.tf:201) says *"Shows as 'will be created' in CI drift reports -- expected behavior (#1409)"*. The resource exists because `hcloud_server.web` has `lifecycle { ignore_changes = [user_data] }` (server.tf:49), so cloud-init never re-applies to the existing server; `deploy_pipeline_fix` is the sole path for pushing `ci-deploy.sh` / `webhook.service` / `cat-deploy-state.sh` / `canary-bundle-claim-check.sh` / `hooks.json` updates to the running production host (per server.tf:215-218 comment).

**Resolution:** run `terraform apply -target=terraform_data.deploy_pipeline_fix` from `apps/web-platform/infra/` via `doppler run --project soleur --config prd_terraform` (matching the `/ship` Phase 5.5 gate's exact form). This re-provisions the four files over SSH, `chown`/`chmod`s `hooks.json`, `systemctl daemon-reload`s, and restarts the webhook. Then verify via the **file+systemd contract** (NOT the legacy HTTP-200 probe — that returns 403 from CF Access since #3019) and close #3061.

**Why intentional (not a manual change):**

- The drift is on `triggers_replace`, not on any Hetzner/Cloudflare cloud state field — manual SSH edits to `/usr/local/bin/ci-deploy.sh` on the server would NOT shift the trigger hash (the hash is over the **local** repo files, not the server copy).
- Git history confirms the most recent trigger-file changes: `1edf7a62` (#3045/#3046, 2026-04-29 16:43 UTC), `87bc9227` (#3042, 2026-04-29 15:56 UTC), `b2fed080` (#3014, 2026-04-26). The drift run started at 2026-04-29 19:40 UTC — ~3 hours after the last trigger-file merge, ~30 minutes after the next-scheduled drift cron tick (`0 6,18 * * *`).
- No `.tfstate` tamper, no failed prior apply (the resource exists in state with a stable `id`).

## User-Brand Impact

- **If this lands broken, the user experiences:** the next deploy webhook restart fails or runs against stale `ci-deploy.sh` / `canary-bundle-claim-check.sh`, which would either (a) hang the next deploy on the old container-mount layout from before #3045/#3046 (no `/mnt/data/plugins/soleur` seed → MCP plugins missing), or (b) skip Layer 3 canary verification on the next deploy (the entire point of #3042). Either is a degraded-deploy state, not a user-visible outage.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — the apply only touches webhook scripts on the production host. No user data, no auth surface, no external-service credentials are mutated; `local.hooks_json` is sensitive (contains `WEBHOOK_DEPLOY_SECRET`) but it is already on the server and the apply only re-writes the same value.
- **Brand-survival threshold:** `none` — the diff is ops-only, no sensitive path under preflight Check 6 regex (`apps/web-platform/server/**`, `apps/web-platform/app/api/**`, migrations, auth/middleware). Scope-out: `threshold: none, reason: ops-remediation runbook with no code change, no migration, no credential rotation, no user-facing surface — only re-provisions four shell scripts already present on the prod host`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim / next-step | Reality | Plan response |
|---|---|---|
| "If the drift is intentional, run `terraform apply` locally to update state" (auto-generated issue body) | Correct. The drift is intentional and apply is the right action. | Follow it verbatim — no revert needed. |
| "triggers_replace changed (sensitive value)" | The values are sensitive because the hash inputs include `local.hooks_json`, which interpolates `var.webhook_deploy_secret`. Terraform masks the trigger content, not the fact of change. | Accept the masking — the issue body shows `# forces replacement`, which is enough signal. |
| Issue milestone: "Post-MVP / Later" | Auto-assigned by the drift workflow. | Leave as-is; closing the issue is sufficient. |
| Triage comment: "blocks the gate tracked in #3043" | #3043 is not in scope for this remediation; the comment is informational. | No action — close-out comment can mention #3043 as related. |
| Prior plan (#2618, 2026-04-19) prescribes `triggers_replace = sha256(... 4 files ...)` | server.tf:219-225 now hashes **5** inputs (4 files + `local.hooks_json`); `canary-bundle-claim-check.sh` was added to the trigger by #3014 (b2fed080). | This plan reflects 5-input trigger; recovery / idempotency notes extend to all 5. |
| #2618 plan AC: "Webhook smoke-test returns HTTP 200" | Returns **HTTP 403** post-CF-Access (#3019 surface). Canonical contract is now file+systemd. | Use file+systemd contract per `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`. The HTTP probe is exclusively for webhook code-path debugging. |
| `terraform output` name | `outputs.tf:1` declares `output "server_ip"` (not `server_ipv4` — #3019 plan was wrong on this). | Use `terraform output -raw server_ip`. |

## Implementation Phases

### Phase 1 — Confirm drift source locally (≤ 5 min)

- [ ] From the worktree, run `terraform init -input=false` in `apps/web-platform/infra/` (re-init because the worktree has no `.terraform/` directory).
- [ ] Run the plan in the exact CI form, mirroring `.github/workflows/scheduled-terraform-drift.yml`:

  ```bash
  cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3061-tf-drift/apps/web-platform/infra
  # Extract R2 creds separately (name-transformer would mangle them to TF_VAR_*)
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform plan -detailed-exitcode -no-color -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

- [ ] Expected: exit code 2, "Plan: 1 to add, 0 to change, 1 to destroy" targeting **only** `terraform_data.deploy_pipeline_fix`. No other resources in the plan.
- [ ] **Abort condition:** if the plan names any resource other than `deploy_pipeline_fix`, stop and escalate — that indicates additional drift outside this issue's scope.

### Phase 2 — Apply (≤ 3 min) — REQUIRES PER-COMMAND OPERATOR ACK

- [ ] **Freeze merges.** R2 backend has `use_lockfile = false` (main.tf — R2 lacks S3 conditional writes). There is NO state lock — two concurrent applies will race. Confirm no PR is in merge queue:

  ```bash
  gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'
  ```

  Expect empty output. If non-empty, wait or coordinate via Discord before proceeding.
- [ ] Verify SSH agent has the prod private key loaded:

  ```bash
  ssh-add -l | grep -i ed25519
  ```

  The Terraform `connection` block at server.tf:227-232 uses `agent = true`. Apply fails with "no suitable auth method" if no key is loaded. Per learning `2026-04-06-terraform-data-connection-block-no-auto-replace.md`, `connection` block changes do NOT auto-replace, so the current state still uses `agent = true` and requires a loaded agent.
- [ ] **Show the exact apply command and wait for explicit `go` from the operator** (per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`). Do NOT execute on a generic "yes" / menu choice.

  ```bash
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -target=terraform_data.deploy_pipeline_fix -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

  Note: omit `-auto-approve` so terraform's own confirmation prompt surfaces (interactive `yes`). The `-target` flag scopes the apply strictly to the drifted resource — matches the `/ship` Phase 5.5 gate's exact prescription (plugins/soleur/skills/ship/SKILL.md:468).

- [ ] Expected sequence in apply output: destroy of `terraform_data.deploy_pipeline_fix` → create (file provisioner uploads `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, `hooks.json`) → remote-exec `chmod +x` on three scripts + `chown root:deploy /etc/webhook/hooks.json` + `chmod 640 /etc/webhook/hooks.json` + Doppler env idempotent append + `systemctl daemon-reload` + `systemctl restart webhook` + `rm -f /mnt/data/.env`.
- [ ] Apply completes "Apply complete! Resources: 1 added, 0 changed, 1 destroyed."
- [ ] **Recovery (tainted resource).** If the SSH provisioner fails mid-apply, the resource will be tainted. Run `terraform state list | grep deploy_pipeline_fix`; if present, rerun the same apply (all provisioner steps are idempotent by design):
  - `chmod +x /usr/local/bin/{ci-deploy.sh,cat-deploy-state.sh,canary-bundle-claim-check.sh}` — idempotent.
  - `chown root:deploy /etc/webhook/hooks.json` + `chmod 640 /etc/webhook/hooks.json` — idempotent.
  - `grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy || printf ...` — explicitly grep-guarded (server.tf:271).
  - `systemctl daemon-reload` + `systemctl restart webhook` — idempotent.
  - `rm -f /mnt/data/.env` — idempotent (`-f` swallows ENOENT).

### Phase 3 — Verify production via file+systemd contract (≤ 5 min)

- [ ] **Use the file+systemd contract**, not the legacy HTTP probe. Per `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe", the HTTP probe returns HTTP 403 from CF Access on anonymous calls and is therefore unreliable for post-apply verification. The file+systemd contract is provisioner-layer and observes exactly what the apply was meant to deliver:

  ```bash
  cd apps/web-platform/infra
  SERVER_IP=$(terraform output -raw server_ip)
  LOCAL_CI_HASH=$(sha256sum ci-deploy.sh | awk '{print $1}')
  LOCAL_CANARY_HASH=$(sha256sum canary-bundle-claim-check.sh | awk '{print $1}')
  LOCAL_CAT_HASH=$(sha256sum cat-deploy-state.sh | awk '{print $1}')
  ssh -o ConnectTimeout=5 root@"$SERVER_IP" "
    sha256sum /usr/local/bin/ci-deploy.sh /usr/local/bin/canary-bundle-claim-check.sh /usr/local/bin/cat-deploy-state.sh
    systemctl is-active webhook
  "
  ```

- [ ] Expected: each remote sha256 matches the corresponding `LOCAL_*_HASH`, AND `systemctl is-active webhook` returns `active`.
- [ ] If a hash mismatches, the file provisioner did not land that file — taint the resource (`terraform taint terraform_data.deploy_pipeline_fix`) and re-apply.
- [ ] If `systemctl is-active webhook` returns anything other than `active` (e.g., `failed`, `activating`), pull `journalctl -u webhook --since '5 minutes ago'` over SSH for the cause and escalate.
- [ ] Lightweight liveness sanity (optional): `curl -I https://soleur.ai/health` → expect HTTP 200. A site outage in this window is coincidental — apply only touches `/etc/systemd/system/webhook.service` and the `webhook` unit; the main `soleur-web` container is unaffected.

### Phase 4 — Re-verify drift is gone (≤ 2 min)

- [ ] Re-run the plan from Phase 1. Expected: exit code 0, "No changes. Your infrastructure matches the configuration."
- [ ] If a new drift surfaces on a *different* resource, file a separate drift issue — do not conflate with #3061.

### Phase 5 — Close the issue + trigger drift workflow (≤ 2 min)

- [ ] Comment on #3061 with the Phase 4 plan output (exit 0) and close:

  ```bash
  gh issue close 3061 --comment "Applied terraform -target=terraform_data.deploy_pipeline_fix to pick up trigger-file changes from #3014 / #3042 / #3045 / #3046. Plan now exits 0. Verified via file+systemd contract (sha256 match on ci-deploy.sh, canary-bundle-claim-check.sh, cat-deploy-state.sh; webhook is active). 10th occurrence of this drift class — structural fix tracked at /ship Phase 5.5 'Deploy Pipeline Fix Drift Gate'."
  ```

- [ ] Manually trigger the drift workflow to confirm the next scheduled run will pass:

  ```bash
  gh workflow run scheduled-terraform-drift.yml
  RUN_ID=$(gh run list --workflow scheduled-terraform-drift.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch "$RUN_ID"
  gh run view "$RUN_ID" --json conclusion --jq .conclusion   # expect: success
  ```

## Acceptance Criteria

### Pre-merge (PR)

This plan produces NO code changes — it is a remediation runbook. There is no PR. All sign-off is post-merge / post-apply on `main`.

- [ ] Plan committed to `knowledge-base/project/plans/` and `tasks.md` to `knowledge-base/project/specs/feat-one-shot-3061-tf-drift/` on the feat branch.

### Post-merge (operator)

- [ ] `terraform plan` in `apps/web-platform/infra/` exits 0 (no drift).
- [ ] Scheduled drift workflow run (triggered manually in Phase 5) concludes `success`.
- [ ] Server-side sha256 of `/usr/local/bin/ci-deploy.sh` equals local `apps/web-platform/infra/ci-deploy.sh` sha256.
- [ ] Server-side sha256 of `/usr/local/bin/canary-bundle-claim-check.sh` equals local `apps/web-platform/infra/canary-bundle-claim-check.sh` sha256.
- [ ] Server-side sha256 of `/usr/local/bin/cat-deploy-state.sh` equals local `apps/web-platform/infra/cat-deploy-state.sh` sha256.
- [ ] `systemctl is-active webhook` returns `active`.
- [ ] `https://soleur.ai/health` returns HTTP 200.
- [ ] Issue #3061 is closed via `gh issue close` with a comment linking the applied run (NOT auto-closed via `Closes #3061` in any PR — there is no PR; per `cq-when-a-pr-has-post-merge-operator-actions`, ops-remediation plans use `gh issue close` post-apply).

## Risks & Non-Goals

### Risks

- **SSH agent not loaded on operator machine.** Apply requires the production SSH private key in the agent. Mitigation: Phase 2 explicitly verifies `ssh-add -l`.
- **No R2 state lock (`use_lockfile = false`).** Two concurrent applies WILL race. Phase 2 requires human coordination ("freeze merges") — there is no mechanical guard.
- **Webhook restart window.** `systemctl restart webhook` causes ~2 s deploy-webhook unavailability; the file-provisioner upload phase before that takes ~10 s during which a script is partially rolled out. Total apply-side window is ~30 s (4 file uploads + chmod/chown + grep-guarded env append + daemon-reload + restart + cleanup `rm`). Safe because no deploy should be in-flight; Phase 2 explicitly checks merge-queued PRs and the operator freezes merges before running apply.
- **Doppler `prd_terraform` config drift.** If the config is missing `CF_API_TOKEN`, `HCLOUD_TOKEN`, `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_DEPLOY_CLIENT_ID`, or `CF_ACCESS_DEPLOY_CLIENT_SECRET`, the plan fails at refresh. Mitigation: Phase 1's plan surfaces missing vars before destroy-step.
- **Provider version drift in CI.** CI uses `TERRAFORM_VERSION: 1.10.5` (scheduled-terraform-drift.yml). Operator's local `terraform version` should match — check before Phase 1.
- **Second drift detected during apply window.** If another PR merges between Phase 1 plan and Phase 2 apply that touches a trigger file, the apply will include both deltas. Mitigation: freeze merges during the ~3-minute apply window.
- **`-target` flag warning is benign here.** `terraform apply -target=...` prints "The -target option is not for routine use" — that warning is correct general guidance, but for *this* class (deliberately drifted single resource matching the `/ship` Phase 5.5 gate) it is the documented form.

### Non-Goals

- **Not** implementing a structural prevention. That work is tracked at `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" (already wired post-#3022) and the closed-out enhancement issue #2881.
- **Not** changing the `triggers_replace` expression to avoid drift (e.g., by hashing a version number). The current content-hash design is correct — it guarantees production reflects committed code.
- **Not** auditing other `terraform_data.*_install` resources; only `deploy_pipeline_fix` is drifted per the issue.
- **Not** updating `/ship` gate or postmerge runbook documentation — both already reflect the file+systemd contract (per #3022 / 2026-04-29 learning).

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Revert PRs #3014 / #3042 / #3045-3046** | Each is a merged fix for an active outage class (Layer 3 canary regression, dashboard error.tsx, image-baked plugin seed). Reverting abandons working fixes. Apply is strictly better. |
| **`terraform state rm` the resource** | Removes state without re-applying — leaves the server with stale `ci-deploy.sh` / `canary-bundle-claim-check.sh`, the very thing the trigger is designed to push. Violates `hr-all-infrastructure-provisioning-servers`. |
| **Manual `scp` of changed files to the server** | Violates `hr-all-infrastructure-provisioning-servers`. Does not restart the webhook, does not re-`chown`/`chmod` `hooks.json`, does not re-write `webhook.service`. |
| **Apply via `gh workflow run` from a CI workflow** | No production-applicable CI workflow exists today (apply runs on operator workstations only — `scheduled-terraform-drift.yml` is plan-only). Adding one is out-of-scope per `wg-when-deferring-a-capability`; `#2881`-closed enhancement covered the design. |
| **Use the legacy HTTP-200 webhook smoke-test** | Returns HTTP 403 from CF Access on anonymous probes (since CF Access landed in front of `/hooks/*`). The file+systemd contract is the canonical post-apply verification per #3022 / 2026-04-29 learning. |

## Test Strategy

No code changes → no unit tests. Verification happens in Phases 3-5:

- **Phase 3** = file+systemd contract (server-side sha256 match + `systemctl is-active webhook`).
- **Phase 4** = regression test of the drift condition (plan exits 0).
- **Phase 5** = end-to-end test of the drift-detection workflow (`gh workflow run` → `success`).

`ci-deploy.test.sh` and `canary-bundle-claim-check.test.sh` were extended by the originating PRs and ran on merge — no new tests needed.

## Files to Edit

None (this is an ops runbook, not a code change).

## Files to Create

None.

## Open Code-Review Overlap

**`apps/web-platform/infra/server.tf`** appears in #2197 (`refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc + Sentry breadcrumb UUID policy`) — but the reference is to the rate-limiter `count = 1` invariant in a documentation context, NOT to the `terraform_data.deploy_pipeline_fix` resource that drives this drift. **Disposition: Acknowledge.** No code change in this remediation; #2197 stays open and tracks its own separate concern.

No matches for `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, or `hooks.json.tmpl` in any open code-review issue. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 100`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure ops remediation (run terraform apply, close issue). No code changes, no user-facing surface, no new dependencies, no external services. CTO domain is implicit (the current task IS engineering per `pdr-do-not-route-on-trivial-messages-yes`), so no CTO routing.

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, the User-Brand Impact section above resolves to `threshold: none` with explicit scope-out rationale (ops-only path).

## Research Insights

- **Pattern recurrence count.** Closed `infra-drift` issues for the same `deploy_pipeline_fix` class: #988, #994, #1412, #1505, #1899, #2234, #2618, #2873/#2874, #3019. With #3061, this is the 10th occurrence. The **structural fix** (auto-applying via `/ship`) was already designed and tracked at #2881 (closed 2026-04-29 as `won't-fix-as-spec`, replaced by the conditional `/ship` Phase 5.5 gate that surfaces the apply command at PR-creation time).
- **Stale `/ship` Phase 5.5 `DPF_REGEX` (deepen-pass finding).** `plugins/soleur/skills/ship/SKILL.md:448` defines:

  ```bash
  DPF_REGEX='^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$'
  ```

  This regex is **out of sync** with the 5-input `triggers_replace` expression in `server.tf:219-225` — it does NOT include `canary-bundle-claim-check.sh`. Empirical proof:

  ```bash
  $ echo 'apps/web-platform/infra/canary-bundle-claim-check.sh' \
      | grep -E '^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|hooks\.json\.tmpl)$'
  $ echo "exit=$?"
  exit=1
  ```

  Consequence: PR #3042, which only edited `canary-bundle-claim-check.sh`, did NOT trigger the `/ship` gate, so no apply was scheduled at merge time and the cron drift detector filed #3061 12 h later. This is the proximate cause of the 10th drift.

  **Recommended follow-up (out-of-scope for this remediation, file as a new issue post-apply):** widen `DPF_REGEX` to:

  ```bash
  DPF_REGEX='^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|canary-bundle-claim-check\.sh|hooks\.json\.tmpl)$'
  ```

  AND add a regression test in `plugins/soleur/test/` (or wherever the ship-gate test lives) that parses the `triggers_replace` block in `server.tf` and asserts every `file("${path.module}/<X>")` matches `DPF_REGEX`. This makes the gate self-healing against future trigger-list growth.
- **Verification contract evolution.** #2618 plan / #2874 closure / #3019 plan all asserted "HTTP 200" against `https://deploy.soleur.ai/hooks/deploy-status`. CF Access in front of `/hooks/*` made anonymous probes 403 since at least #2618. Canonical contract is now file+systemd, documented in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe" and surfaced by `/ship` Phase 5.5.
- **`terraform output` name.** `apps/web-platform/infra/outputs.tf:1` declares `output "server_ip"` — not `server_ipv4` (the #3019 plan got this wrong; corrected here per #3022 learning).
- **`canary-bundle-claim-check.sh` joined the trigger expression in #3042 (87bc9227), not #3014.** Verified empirically: `git show b2fed080:apps/web-platform/infra/server.tf` (#3014) shows the legacy 4-input trigger; `git show 87bc9227:apps/web-platform/infra/server.tf` (#3042) shows the current 5-input form. The 5-input trigger is now: `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, `local.hooks_json` (rendered from `hooks.json.tmpl`). Recovery / idempotency notes extend to all five.
- **AGENTS.md rules applied:**
  - `hr-menu-option-ack-not-prod-write-auth` — Phase 2 shows the exact apply command and waits for explicit per-command go-ahead; no `-auto-approve` on production scope.
  - `hr-all-infrastructure-provisioning-servers` — no manual SSH fix; the Terraform apply IS the fix.
  - `hr-never-label-any-step-as-manual-without` — every step is automated via CLI; no manual browser/SSH handoff.
  - `hr-when-a-plan-specifies-relative-paths-e-g` — verified all five trigger-file paths exist via `git ls-files apps/web-platform/infra/`.
  - `hr-weigh-every-decision-against-target-user-impact` — User-Brand Impact section resolves to `none` with scope-out rationale.
  - `cq-when-a-pr-has-post-merge-operator-actions` — Acceptance Criteria split into Pre-merge (PR) and Post-merge (operator). Issue close uses `gh issue close` post-apply (NOT `Closes #3061` in a PR body — there is no PR).
- **Learning referenced:**
  - `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` — file+systemd contract.
  - `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — full pattern analysis.
  - `knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` — per-command ack discipline.
  - `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` — `-replace=` fallback context.

## References

- Issue: #3061
- Resource definition: `apps/web-platform/infra/server.tf:211-279`
- Workflow: `.github/workflows/scheduled-terraform-drift.yml`
- Prior plan (8th occurrence): `knowledge-base/project/plans/2026-04-19-fix-terraform-drift-deploy-pipeline-fix-plan.md`
- Prior plan (9th occurrence): `knowledge-base/project/plans/2026-04-29-fix-deploy-pipeline-fix-ship-gate-and-postapply-contract-plan.md`
- Structural fix gate: `plugins/soleur/skills/ship/SKILL.md` (Phase 5.5 "Deploy Pipeline Fix Drift Gate")
- Post-apply contract: `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` ("When NOT to use this probe")
- Triggering merges: #3014 (b2fed080), #3042 (87bc9227), #3045/#3046 (1edf7a62)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with a non-empty scope-out rationale.
- `-target` apply prints "The -target option is not for routine use." This warning is correct in general — but for this class of single-resource intentional drift, `-target` is the documented form per `/ship` Phase 5.5 (plugins/soleur/skills/ship/SKILL.md:468).
- No `-auto-approve` on `prd_terraform`. Operator must read the plan output and type `yes` interactively — terraform's native confirmation is the load-bearing safety net (per `hr-menu-option-ack-not-prod-write-auth`).
- Do NOT use the legacy HTTP-200 webhook probe for post-apply verification. It returns HTTP 403 from CF Access on anonymous probes. Use the file+systemd contract from Phase 3.
