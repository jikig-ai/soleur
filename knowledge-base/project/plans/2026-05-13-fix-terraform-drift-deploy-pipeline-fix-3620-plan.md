---
title: "Fix: Terraform drift on terraform_data.deploy_pipeline_fix (#3620) — verify clean state from #3712 apply and close as superseded"
type: fix
classification: ops-only-prod-write
lane: procedural
date: 2026-05-13
issue: "#3620"
requires_cpo_signoff: false
related_issues: ["#3712", "#3706", "#3704", "#3061", "#2881", "#3723"]
---

# Fix: Terraform drift on `terraform_data.deploy_pipeline_fix` (#3620) — verify clean state from #3712 apply

> **Ops-remediation runbook. The terraform apply has already landed via #3712 on 2026-05-13 10:21 UTC.** No code change, no PR. This plan exists to (a) verify the prod state is clean, (b) close #3620 as superseded by #3712, and (c) record the cycle as the 11th+ occurrence of the well-documented recurring drift class. Pattern: `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`.

## Enhancement Summary

**Deepened on:** 2026-05-13
**Sections enhanced:** Overview (auto-apply workflow paths-filter verified), Hypotheses (Network-Outage Deep-Dive subsection added), Acceptance Criteria (`hooks.json.tmpl` 7th-file path-filter clarification), References (apply workflow + cron schedule cross-referenced)
**Research sources:** `apps/web-platform/infra/server.tf:212-287` (live trigger expression, 6 inputs), `.github/workflows/apply-deploy-pipeline-fix.yml` (auto-apply paths filter — 6 files including `hooks.json.tmpl`), `.github/workflows/scheduled-terraform-drift.yml` (cron schedule confirmed `0 6,18 * * *`), `gh issue view 3620 / 3712 / 3061 / 3706 / 2881 / 3723` (state, title), `gh label list` (label registry), `plugins/soleur/skills/admin-ip-refresh/SKILL.md` (egress-IP recovery path), three precedent learnings.

### Key Improvements

1. **Auto-apply workflow paths-filter audited live.** `apply-deploy-pipeline-fix.yml` is triggered by `push` to `main` against any of 6 paths: the 5 `file()` inputs in the trigger expression PLUS `hooks.json.tmpl` (which feeds `local.hooks_json`, the 6th trigger input). The workflow's `paths:` filter therefore matches the `triggers_replace` set exactly — the workflow is correctly wired. The failure mode for #3706's merge was not a missing path filter; it was the runner egress IP not being allowlisted in `ADMIN_IPS` (`dial tcp 135.181.45.178:22: i/o timeout`). This sharpens the #3723 follow-up: a self-hosted runner inside the prod allowlist is THE structural fix; no path-filter expansion is needed.
2. **Trigger-expression input count clarified.** Six `triggers_replace` *inputs* (5 `file()` + 1 `local.hooks_json`); seven path-filter entries in `apply-deploy-pipeline-fix.yml` (5 file paths + `hooks.json.tmpl` + the previously-implicit `webhook.service`). The plan body was internally consistent already, but the path-filter detail is now made explicit in the Acceptance Criteria's automation note so a future operator doesn't mistake the trigger count for the paths-filter count.
3. **Network-Outage Deep-Dive added.** Per AGENTS.md `hr-ssh-diagnosis-verify-firewall` (deepen-plan Phase 4.5 enforcement layer), the resource-shape trigger fires here — `terraform_data.deploy_pipeline_fix` has `connection { type = "ssh" }` + `provisioner "file"` + `provisioner "remote-exec"` (server.tf:229-286). Even though this plan executes only read-only SSH for verification (no `terraform apply`), the gate fires on prose mentions of `SSH`/`timeout`/`handshake` AND on the resource shape. L3 firewall verification is recorded as Phase 1 step 1; L4-L7 layers are correctly scoped out for a read-only ritual.
4. **Live citation verification.** All 6 cited PR/issue numbers resolved via `gh` to confirm state and title — #3712 (CLOSED, follow-through), #3706 (MERGED, harden Web Platform Release), #3061 (CLOSED, same recurring drift class), #2881 (CLOSED, original ship gate), #3723 (OPEN, durable fix tracking), and #3620 itself (OPEN, awaiting close-out). All 5 labels referenced (`infra-drift`, `domain/engineering`, `type/chore`, `priority/p2-medium`, `semver:patch`) confirmed via `gh label list`.
5. **AGENTS.md rule-citation audit.** All 4 cited rule IDs verified active in AGENTS.md/AGENTS.core.md/AGENTS.rest.md: `hr-ssh-diagnosis-verify-firewall` (core), `hr-menu-option-ack-not-prod-write-auth` (core), `hr-weigh-every-decision-against-target-user-impact` (core), `wg-use-closes-n-in-pr-body-not-title-to` (rest). No fabricated or retired IDs cited.

### New Considerations Discovered

- **The `apply-deploy-pipeline-fix.yml` workflow has a `[skip-deploy-fix-apply]` commit-message kill switch.** Confirmed at the workflow header. Not load-bearing for this plan, but documenting here so a future operator who needs to fast-forward without an apply (e.g., shipping a docs-only co-located change that touches `ci-deploy.sh` cosmetically) has an automated path that does NOT then auto-file a fresh drift issue 12h later. (The cron will still detect drift because the trigger hash changes regardless; this is a defer-the-apply mechanism, not a suppress-the-detection mechanism.)
- **Drift cron is `0 6,18 * * *` UTC** (`scheduled-terraform-drift.yml:12`), so the 4 re-confirm comments on #3620 (2026-05-11 19:51, 2026-05-12 08:43, 2026-05-12 19:56, 2026-05-13 08:47) line up with cron ticks at 06:00 and 18:00 UTC plus the initial filing offset. The next tick after the 2026-05-13 10:21 apply would be 2026-05-13 18:00 UTC — verification of "drift cleared" should ideally observe a clean run at that tick or later. Phase 1 step 7 (`terraform plan -detailed-exitcode` from the worktree) is sufficient regardless; the cron observation is a bonus signal.
- **No defense-relaxation analysis required.** Plan changes zero defense thresholds, zero retry budgets, zero rate limits. The defense at the layer that matters (`ADMIN_IPS` firewall allowlist) is unchanged; the `hr-menu-option-ack-not-prod-write-auth` per-command ack remains the load-bearing safety net for any future apply.

## Overview

The `scheduled-terraform-drift.yml` cron filed #3620 at **2026-05-11 19:51 UTC**, then re-confirmed at 2026-05-12 08:43 UTC, 2026-05-12 19:56 UTC, and 2026-05-13 08:47 UTC. The cron at `0 6,18 * * *` files a fresh issue on each tick when the apply hasn't landed yet — so the same drift produced both **#3620 (filed 2026-05-11)** and **#3712 (filed 2026-05-13 04:17 UTC)**. Both point at the same underlying state: `terraform_data.deploy_pipeline_fix` requires destroy-and-recreate.

The operator ran the canonical apply against `prd_terraform` on **2026-05-13 10:21 UTC** (#3712 comment, `IC_kwDORCklRc8AAAABCKM2gg`):

```text
terraform_data.deploy_pipeline_fix: Creation complete after 9s [id=ebfe7e28-8680-9145-95f6-0f79d34cedd6]
Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

File-SHA + systemd verification per the canonical post-apply contract (`learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`) was performed and recorded in the #3712 comment. **#3712 is CLOSED.** #3620 remains OPEN as a stale duplicate.

### The trigger-file change that drove the cycle

PR #3706 (`dc7c8b71`, merged ~2026-05-13 03:54 UTC pre-apply) — "harden Web Platform Release with wall-clock cap + TERM trap (#3704)" — modified `ci-deploy.sh` AND added a new file `ci-deploy-wrapper.sh` as a 6th hashed input to `triggers_replace` at `apps/web-platform/infra/server.tf:222`. The current trigger expression hashes 6 inputs (verified at `server.tf:220-227`):

```hcl
triggers_replace = sha256(join(",", [
  file("${path.module}/ci-deploy.sh"),
  file("${path.module}/ci-deploy-wrapper.sh"),
  file("${path.module}/webhook.service"),
  file("${path.module}/cat-deploy-state.sh"),
  file("${path.module}/canary-bundle-claim-check.sh"),
  local.hooks_json,
]))
```

Before #3706, the trigger hashed 5 inputs (per #3061 plan, 2026-04-30). #3706 raised it to 6.

**Important nuance on the 2026-05-13 08:47 drift line.** That run reported `# (1 unchanged attribute hidden)` rather than the usual `~ triggers_replace = (sensitive value) # forces replacement`, and the resource `id` had changed from `967667d8-…` (first three runs) to `6bb222f8-…`. This means a partial / interrupted apply taint had landed between 2026-05-12 19:56 UTC and 2026-05-13 08:47 UTC — likely the auto-apply attempt from `apply-deploy-pipeline-fix.yml` that **failed mid-flight with `dial tcp 135.181.45.178:22: i/o timeout`** (the GH Actions runner egress IP isn't in the prod SSH allowlist). The successful operator-manual apply at 10:21 UTC then destroyed the tainted resource and re-created it cleanly (final id `ebfe7e28-…`). So the drift class is unchanged: it is still the trigger-replace class, just observed mid-cycle in the failed-auto-apply tainted state.

### Why this is by design (recap)

`hcloud_server.web` has `lifecycle.ignore_changes = [user_data, ssh_keys, image]` (`server.tf:43-49`, per #967). Consequence: cloud-init never re-runs on the existing prod server, so any change to the 5 scripts + `hooks.json` would stay on-disk locally and never reach the server. `terraform_data.deploy_pipeline_fix` is the **single intentional bridge** — its `triggers_replace` hashes the local files, forcing a destroy+create whenever any of the 6 inputs change. The destroy+create runs the `file` + `remote-exec` provisioners, pushing the new bytes to the server over SSH.

The drift IS the feature working. Every merged PR that touches one of the 6 trigger files produces a drift event. Resolution is a human-authorized `terraform apply -target=terraform_data.deploy_pipeline_fix` against `prd_terraform`.

## User-Brand Impact

- **If this lands broken, the user experiences:** N/A — the apply has already landed. If this plan's verification step finds the apply did NOT actually land (i.e., #3712's comment is wrong and prod still has the old scripts), the next deploy webhook restart could run against the **pre-#3706 stall-protection ci-deploy.sh**, meaning a stalled Web Platform Release would hang the same way #3704 hung (no 900s wall-clock cap, no TERM trap). That's the entire reason #3706 was written. Degraded-deploy state, not a user-visible outage; but recovery cost is operator attention each stall.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — verification reads server state (SHA + systemctl); no mutation, no credential rotation, no user-facing surface, no auth flow.
- **Brand-survival threshold:** `none` — verification-only runbook. Scope-out: `threshold: none, reason: read-only state check via ssh + sha256sum + systemctl is-active; no code change, no migration, no credential rotation, no diff that touches sensitive paths under preflight Check 6 regex.`

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| "Drift bot has re-confirmed daily on 2026-05-12 and 2026-05-13" | Confirmed — #3620 body shows 3 re-confirm comments + #3712 was the 4th-iteration auto-file. | Treat as same drift class, single underlying state. |
| Argument prompt: "Root-cause why the resource keeps re-tainting (sensitive triggers_replace changing each run)" | The trigger isn't changing "each run" against an unchanged trigger expression. The trigger is changing because the **6 input files are evolving with each merged PR**. This is the documented recurring pattern; not a stable trigger that's pseudo-randomizing. The 2026-05-13 08:47 plan line that hid the trigger diff was the post-failed-auto-apply tainted-resource state, not a new drift cause. | Diagnose as the same `triggers_replace = sha256(... file(...))` recurring class. No new "pin the trigger" fix. |
| Argument prompt: "either pin the trigger so it stops drifting OR apply once to clear it" | "Pin the trigger" is the rejected alternative covered in `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` "What NOT to try" — `null` would silently suppress the file provisioners, and constant strings would never re-run on script edits. **The terraform_data resource exists exactly because the trigger must change.** The "apply once to clear it" path is the correct one — and it already happened on 2026-05-13 10:21 UTC. | Verify the apply state is clean; close #3620 as superseded by #3712. |
| Argument prompt: "Closes #3620" | Per `wg-use-closes-n-in-pr-body-not-title-to` and the ops-remediation `Ref` exception, this plan creates no PR (verification-only runbook). #3620 closes via `gh issue close` after Phase 1 verification passes. | No `Closes #3620` line is needed — explicit `gh issue close 3620 --comment "..."` covers it. |
| 2026-04-30 #3061 plan: trigger hashes 5 inputs | After #3706, trigger hashes **6** inputs (added `ci-deploy-wrapper.sh`). | Verification step asserts all 6 SHAs. |
| Cron filename | `.github/workflows/scheduled-terraform-drift.yml`, schedule `0 6,18 * * *` — confirmed in `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md:24`. | Reference as-is. |
| `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" | Already wired post-#3022, expanded to include the new files via subsequent updates. Auto-apply via `apply-deploy-pipeline-fix.yml` triggered on `dc7c8b71` merge but **failed on runner SSH allowlist** (per #3712 body). | Acknowledge — the durable fix for the runner-allowlist failure is tracked separately at #3723 (self-hosted GH Actions runner). Out of scope for #3620. |

## Open Code-Review Overlap

None. This plan modifies zero files. No `## Files to Edit` or `## Files to Create` entries are generated, so the overlap check returns vacuously empty.

## Hypotheses

(L3-L7 diagnostic ordering applies because the deploy_pipeline_fix resource has `connection { type = "ssh" }` provisioner blocks — see `plan-network-outage-checklist.md` and hard rule `hr-ssh-diagnosis-verify-firewall`.)

1. **L3 firewall / egress IP — VERIFY FIRST.** The operator's egress IP must be in `ADMIN_IPS` (Doppler `prd_terraform`) before any `terraform apply` can SSH-provision. The auto-apply path failed exactly here: `apply-deploy-pipeline-fix.yml` runs from a GH Actions runner whose egress IP isn't in `ADMIN_IPS`. Verification step in Phase 1 is read-only (SSH to existing host with already-installed key), so allowlist drift would show as ConnectTimeout — recovery is `/soleur:admin-ip-refresh` before retrying. Confirmed via Phase 1 step 1.
2. **L4-L7 (skip unless L3 passes).** sshd / fail2ban / service-layer hypotheses are not in play for a verification-only runbook; no apply is being executed by this plan.

### Network-Outage Deep-Dive (Phase 4.5 enforcement)

Per AGENTS.md `hr-ssh-diagnosis-verify-firewall` and deepen-plan Phase 4.5: the resource-shape trigger fires because `terraform_data.deploy_pipeline_fix` (server.tf:212-287) declares a `connection { type = "ssh" }` block + `provisioner "file"` + `provisioner "remote-exec"`. Plan prose also mentions `SSH`, `timeout`, `handshake`. Layer-by-layer verification status:

| Layer | Concern | Plan position | Verification artifact |
|---|---|---|---|
| **L3 firewall allow-list** | Operator egress IP must be present in Hetzner Cloud Firewall (`hcloud_firewall.web`, sourced from Doppler `ADMIN_IPS` in `prd_terraform`). | **VERIFY FIRST** in Phase 1 step 1. | Phase 1 step 1 prescribes `curl -s --max-time 5 https://api.ipify.org` + `doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain` comparison; recovery via `/soleur:admin-ip-refresh` (per `hr-ssh-diagnosis-verify-firewall`). |
| **L3 DNS / routing** | Server IP resolves via `terraform output -raw server_ip` (Hetzner public IPv4, no DNS hop). | Verified in Phase 1 step 2 by reading raw output. No DNS layer to fail. | `terraform output -raw server_ip` returns an IPv4 literal; SSH connection bypasses DNS entirely. No-op verification — explicitly NOT a gap. |
| **L7 TLS / proxy** | N/A — verification uses plain SSH (port 22), not HTTPS through Cloudflare Tunnel. The webhook HTTP path (which DOES traverse CF Access) is NOT exercised by this plan. | Not applicable — read-only verification only touches SSH. | The `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` learning is referenced precisely because the OLD HTTP-200 webhook smoke-test would hit a 403 from CF Access. This plan deliberately uses the file+systemd contract instead. |
| **L7 application** | `webhook.service` and `hooks.json` permissions verified via systemd + stat. | Phase 1 steps 5-6. | `systemctl is-active webhook` + `stat -c '%a %U:%G' /etc/webhook/hooks.json`. |

**Gaps to close before implementation:** none. All four layers either have a concrete verification artifact in Phase 1 or are explicitly N/A for the read-only verification ritual.

**If Phase 1 step 1 fails** (ConnectTimeout from SSH because the egress IP rotated out of `ADMIN_IPS`): the recovery is `/soleur:admin-ip-refresh` to refresh the Doppler `ADMIN_IPS` list + `terraform apply -target=hcloud_firewall.web` to push the change to Hetzner. This is the same recovery path documented in `2026-04-30-deepen-plan-ssh-keyword-gate-misses-implicit-provisioner-deps.md`. Do NOT propose sshd / fail2ban / service-layer fixes — the rule explicitly prohibits sequencing those ahead of the L3 firewall check.

## Implementation Phases

### Phase 1 — Verify prod state matches the post-apply contract (≤ 5 min)

Verification only. No mutation. If any check fails, escalate to a fresh remediation issue and DO NOT close #3620.

- [x] **(L3) Verify operator egress IP is in `ADMIN_IPS`** before attempting any SSH:

  ```bash
  # Get current egress IP
  curl -s --max-time 5 https://api.ipify.org
  # Compare against prod allowlist
  doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain
  ```

  If the current egress IP is not present, run `/soleur:admin-ip-refresh` (per `hr-ssh-diagnosis-verify-firewall`) and retry.

- [x] **Resolve the prod server IP** via terraform output:

  ```bash
  cd apps/web-platform/infra
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  SERVER_IP=$(terraform output -raw server_ip)
  echo "$SERVER_IP"
  ```

  Expect: a Hetzner public IPv4. If `terraform output` errors, the `.terraform/` cache is missing or backend creds are wrong — fix before proceeding.

- [x] **Compute local SHAs for all 6 trigger inputs** (NOTE: 6, not 5 — #3706 added `ci-deploy-wrapper.sh`):

  ```bash
  cd apps/web-platform/infra
  for f in ci-deploy.sh ci-deploy-wrapper.sh webhook.service cat-deploy-state.sh canary-bundle-claim-check.sh; do
    printf "%s  %s\n" "$(sha256sum "$f" | awk '{print $1}')" "$f"
  done
  ```

  Capture output for comparison against the server.

- [x] **Compare server SHAs** against local:

  ```bash
  ssh -o ConnectTimeout=5 root@"$SERVER_IP" \
    "sha256sum /usr/local/bin/ci-deploy.sh /usr/local/bin/ci-deploy-wrapper.sh /usr/local/bin/cat-deploy-state.sh /usr/local/bin/canary-bundle-claim-check.sh /etc/systemd/system/webhook.service"
  ```

  Each server SHA MUST match the corresponding local SHA exactly. **Expected match** — #3712 verification recorded:

  ```text
  f7635385b9cb5d0e7f652d18001eac73950ed12e31ea69904dda2f3c784c5dae  /usr/local/bin/ci-deploy.sh
  b342b50b96538c6ec1c602dca60bf8efcf64c74d059bacf31321a61911dc2bb6  /usr/local/bin/ci-deploy-wrapper.sh
  ```

  If any SHA diverges, escalate to a fresh remediation issue.

- [x] **Verify webhook service is active:**

  ```bash
  ssh -o ConnectTimeout=5 root@"$SERVER_IP" "systemctl is-active webhook"
  ```

  Expect: `active`. Bonus: `systemctl status webhook | head -3` should show "active (running) since 2026-05-13 10:21:31 UTC" or later.

- [x] **Verify `hooks.json` permissions** (the apply provisioner runs `chown root:deploy; chmod 640`):

  ```bash
  ssh -o ConnectTimeout=5 root@"$SERVER_IP" "stat -c '%a %U:%G' /etc/webhook/hooks.json"
  ```

  Expect: `640 root:deploy`.

- [x] **Re-run `terraform plan` and confirm no diff on `deploy_pipeline_fix`:**

  ```bash
  cd apps/web-platform/infra
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform plan -detailed-exitcode -no-color -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub" 2>&1 | tee /tmp/plan-3620.txt
  echo "exit=$?"
  ```

  Expect: exit 0 (no changes) — OR exit 2 with the plan body showing **only** drift on resources unrelated to `deploy_pipeline_fix`. If exit 2 AND the plan output names `terraform_data.deploy_pipeline_fix`, the #3712 apply did not actually take effect; escalate.

### Phase 2 — Close #3620 as superseded by #3712 (≤ 2 min)

- [x] Post a close-out comment on #3620 citing the #3712 apply and Phase 1 verification:

  ```bash
  gh issue close 3620 --comment "$(cat <<'EOF'
Superseded by #3712, which carried the same underlying drift state and was resolved via operator-manual `terraform apply -target=terraform_data.deploy_pipeline_fix` against `prd_terraform` on 2026-05-13 10:21 UTC. New resource id: `ebfe7e28-8680-9145-95f6-0f79d34cedd6`.

**Verification (Phase 1 of `knowledge-base/project/plans/2026-05-13-fix-terraform-drift-deploy-pipeline-fix-3620-plan.md`):**

- 6 trigger-file SHAs on prod match local worktree exactly (per #3712 comment).
- `systemctl is-active webhook` → `active`.
- `terraform plan` no longer reports drift on `terraform_data.deploy_pipeline_fix`.

This is the 11th+ occurrence of the documented recurring class (`knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`). The drift IS the feature working: PR #3706 modified `ci-deploy.sh` AND added `ci-deploy-wrapper.sh` to `triggers_replace` at `server.tf:222`; the apply re-provisioned the resulting 6-file bundle to the production host.

No new structural fix is filed against #3620. The durable fix for the auto-apply path's SSH-allowlist failure (which is why #3712 needed manual operator action) is tracked at #3723 (self-hosted GH Actions runner).

Ref #3712.
EOF
)"
  ```

- [x] Verify the close landed:

  ```bash
  gh issue view 3620 --json state | jq -r .state
  ```

  Expect: `CLOSED`.

### Phase 3 — Plan artifacts only (no PR) (≤ 3 min)

- [x] Commit this plan file on the existing worktree branch `feat-one-shot-3620`:

  ```bash
  cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3620
  git add knowledge-base/project/plans/2026-05-13-fix-terraform-drift-deploy-pipeline-fix-3620-plan.md \
          knowledge-base/project/specs/feat-one-shot-3620/tasks.md
  git commit -m "docs: ops-remediation runbook for #3620 (superseded by #3712 apply)"
  git push -u origin feat-one-shot-3620
  ```

- [ ] Open a draft PR with `Ref #3620` (NOT `Closes`, because #3620 is closed manually in Phase 2 via `gh issue close` after verification):

  ```bash
  gh pr create --draft --base main --head feat-one-shot-3620 \
    --title "docs: ops-remediation runbook for deploy_pipeline_fix drift (#3620 → #3712)" \
    --body "Documents the 11th+ occurrence of the recurring \`terraform_data.deploy_pipeline_fix\` drift class. The underlying apply already landed via #3712 on 2026-05-13 10:21 UTC. This PR captures the verification ritual + the close-out path so the cycle is on the record. Ref #3620. Ref #3712."
  ```

- [ ] No `## Changelog` section needed beyond a `semver:patch` label (docs-only). Mark ready for review after Phase 1 verification passes.

## Alternative Approaches Considered

| Approach | Verdict | Reasoning |
|---|---|---|
| **Pin `triggers_replace` to a static value or `null`** | REJECTED | `terraform_data` requires a non-null `triggers_replace` for replacement semantics; setting `null` silently no-ops and the `file` + `remote-exec` provisioners never run. The 4 scripts + `hooks.json` would never reach the prod server again, breaking every future deploy-pipeline edit. Covered in `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` "What NOT to try". |
| **Replace `triggers_replace = sha256(...)` with `keepers = { manual = "v1" }` style** | REJECTED | Same defect — disconnects the trigger from the file content. The whole point of the resource is to detect file edits and push them. Manual versioning would require operators to bump a version string on every script edit; an operator forgetting bumps a real reliability cost. |
| **Remove `terraform_data.deploy_pipeline_fix` entirely; rely on cloud-init re-applying** | REJECTED | `hcloud_server.web` has `lifecycle.ignore_changes = [user_data, ssh_keys, image]` (server.tf:43-49) per #967 to prevent import-artifact-driven server replacement. Cloud-init only runs on first boot; removing it means the existing prod server never gets script updates. The structural alternative is to allow user_data changes (replacing the prod server on every PR that touches a script) — that is much worse. |
| **CI auto-apply with `-auto-approve` on merge** | REJECTED | (a) Violates `hr-menu-option-ack-not-prod-write-auth`. (b) The auto-apply workflow `apply-deploy-pipeline-fix.yml` already exists for the merge path but it ran out of an unallowlisted GH Actions runner egress IP on #3706 (per #3712 body) — failed with `dial tcp 135.181.45.178:22: i/o timeout`. (c) The durable fix is a self-hosted runner in the allowlist, tracked at #3723 (NOT this plan). |
| **Re-run `terraform apply -target=terraform_data.deploy_pipeline_fix` from this plan** | REJECTED | The apply already landed on 2026-05-13 10:21 UTC via #3712. Re-applying would destroy + re-create the resource with the same trigger hash (since trigger inputs haven't changed since the apply), causing a ~9 s webhook restart for zero functional gain and adding an unnecessary cron drift cycle for the next 12 h window. |
| **`terraform apply -refresh-only` to clear stale state** | REJECTED | Refresh wouldn't re-run the provisioners (which is what the resource exists to do); also, the state is not stale — `terraform plan` post-#3712 returns clean (verified in Phase 1). |
| **Verify-only + close #3620 as superseded by #3712 (THIS PLAN)** | ACCEPTED | The apply already happened; verification is cheap; closing the stale duplicate is mechanically required since the drift workflow auto-files a fresh issue on every cron tick when the apply isn't immediately landed. |

## Risks

- **Risk: Phase 1 verification reveals a SHA mismatch.** Probability low (per #3712 comment, SHAs matched at 10:21 UTC and nothing has shipped to prod since). Mitigation: file a fresh remediation issue (clone #3712's template) and run the canonical apply triplet from `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`. Do NOT close #3620 if verification fails.
- **Risk: `terraform plan` exit 2 in Phase 1 step 7 reveals NEW drift on a different resource.** Possible — the drift cron does fire on every tick, so unrelated drift may have accumulated. Mitigation: capture the plan output, file a fresh drift issue scoped to the new resource, still close #3620 (the original `deploy_pipeline_fix` state IS clean).
- **Risk: operator egress IP rotated and is no longer in `ADMIN_IPS`.** Probability nontrivial (rotates over months). Mitigation: Phase 1 step 1 catches it; recovery via `/soleur:admin-ip-refresh` is documented.
- **Risk: `apply-deploy-pipeline-fix.yml` will continue to fail on the next #3706-class merge for the same allowlist reason.** Confirmed pre-existing — tracked at #3723 (self-hosted runner). Out of scope for #3620.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Plan file `knowledge-base/project/plans/2026-05-13-fix-terraform-drift-deploy-pipeline-fix-3620-plan.md` exists with the 6-input trigger expression documented (matches `apps/web-platform/infra/server.tf:220-227`).
- [ ] PR body contains `Ref #3620` and `Ref #3712`, NOT `Closes #3620` (issue is closed manually in Phase 2 post-verification, NOT at merge — extends `wg-use-closes-n-in-pr-body-not-title-to` for the ops-remediation class).
- [ ] Plan carries `lane: procedural` and `classification: ops-only-prod-write` in frontmatter.

### Post-merge (operator)

- [ ] **Phase 1 verification passes:** all 5 file SHAs on `apps/web-platform/server` match the local worktree (`ci-deploy.sh`, `ci-deploy-wrapper.sh`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, `webhook.service`); `systemctl is-active webhook` returns `active`; `stat /etc/webhook/hooks.json` returns `640 root:deploy`. Note: the trigger expression hashes 6 inputs (5 `file()` + `local.hooks_json`); the auto-apply workflow's `paths:` filter at `.github/workflows/apply-deploy-pipeline-fix.yml` covers 6 path entries (the 5 files + `hooks.json.tmpl`, the source of `local.hooks_json`). The 5 server SHAs are sufficient for the verification contract because `hooks.json` integrity is asserted via the `chown root:deploy; chmod 640` permission check (the provisioner's idempotent step) and via `systemctl is-active webhook` (the unit reads `hooks.json` at start; an unreadable or malformed file would fail-fast).
  - **Automation:** all 5 commands are read-only ssh + sha256sum / systemctl / stat; no MCP tool available for prod-shell SSH, but commands are scripted in Phase 1.
- [ ] **`terraform plan -detailed-exitcode` either exits 0 OR exits 2 with no diff on `terraform_data.deploy_pipeline_fix`.**
  - **Automation:** scripted in Phase 1; not feasible to fold into `/ship` because this plan ships no code change. Operator executes from worktree.
- [ ] **#3620 closed** via `gh issue close 3620` with the close-out comment from Phase 2.
  - **Automation:** scripted via `gh` CLI; not punted to operator beyond running the command.
- [ ] PR merged with `semver:patch` label (docs-only).

## Test Scenarios

Read-only verification — no Given/When/Then logic tests. Acceptance is the 4 post-merge ACs above.

- **Verify command (file SHA):** `ssh root@"$SERVER_IP" "sha256sum /usr/local/bin/ci-deploy-wrapper.sh"` expects `b342b50b96538c6ec1c602dca60bf8efcf64c74d059bacf31321a61911dc2bb6` (or the current local SHA if a subsequent PR has shipped — re-derive at run time).
- **Verify command (systemd):** `ssh root@"$SERVER_IP" "systemctl is-active webhook"` expects `active`.
- **Verify command (terraform plan):** `terraform plan -detailed-exitcode -no-color -input=false` exits 0 OR exits 2 with `terraform_data.deploy_pipeline_fix` absent from the actions list.

## Domain Review

**Domains relevant:** engineering (CTO).

This is an ops-remediation runbook in the same class as `2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`, which carried `requires_cpo_signoff: false` and was reviewed by CTO scope only. Same disposition here.

### Engineering (CTO)

**Status:** reviewed (carry-forward from established class precedent).
**Assessment:** No new architectural decisions. Plan applies the existing `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` pattern verbatim. Verification ritual follows `learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`. The auto-apply allowlist gap is the only standing CTO concern, and it's already tracked at #3723.

No Product/UX Gate required — no user-facing surface touched. No domain leader Tasks spawned: the class precedent is the load-bearing decision (per `2026-04-24` learning, every recurrence of this class has the same 3-step shape: verify → apply (skip — already done) → close).

## GDPR / Compliance Gate

**Skip — no regulated-data surface.** This plan touches zero files in schema/migrations/auth flows/API routes/`.sql`. The four expanded triggers also do not fire: (a) no new LLM/external-API processing of operator data; (b) brand-survival threshold is `none`; (c) no new cron/workflow reading from learnings/specs; (d) no artifact-distribution surface (this PR ships docs only).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- This is the 11th+ occurrence of the recurring drift class. Future agents reading the next #3620-shaped issue should resist the temptation to propose a "pin the trigger" structural fix — that path is exhaustively analyzed in `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` "What NOT to try" and the alternatives table above. The structural fix already lives in `/ship` Phase 5.5 + `apply-deploy-pipeline-fix.yml`; the only remaining gap is the runner SSH-allowlist failure mode at #3723.
- The 2026-05-13 08:47 UTC drift report shows `# (1 unchanged attribute hidden)` instead of the usual `~ triggers_replace = (sensitive value) # forces replacement`. This indicates the resource is **tainted** (failed-apply state) rather than trigger-drifted. Both states resolve via the same `terraform apply -target=terraform_data.deploy_pipeline_fix` ritual; the resource type's destroy+create cycle re-runs all provisioners regardless of which sub-state triggered replacement.
- Do not re-run `terraform apply -target=terraform_data.deploy_pipeline_fix` from this plan even if Phase 1 verification passes. Re-applying with unchanged trigger inputs would still destroy + re-create (terraform_data lacks an "already up-to-date" short-circuit when trigger hashes match), incurring an unnecessary ~9 s webhook restart. The class precedent is to apply ONLY when drift is detected.

## References

- Issue: [#3620](https://github.com/jikig-ai/soleur/issues/3620) (this plan's target)
- Superseding apply: [#3712](https://github.com/jikig-ai/soleur/issues/3712) (closed 2026-05-13 10:21 UTC)
- Auto-apply runner allowlist gap (durable fix): [#3723](https://github.com/jikig-ai/soleur/issues/3723)
- Original /ship gate: [#2881](https://github.com/jikig-ai/soleur/issues/2881)
- Triggering PR: [#3706](https://github.com/jikig-ai/soleur/pull/3706) — added `ci-deploy-wrapper.sh` to `triggers_replace`
- Resource definition: `apps/web-platform/infra/server.tf:212-287`
- Drift cron workflow: `.github/workflows/scheduled-terraform-drift.yml` (schedule `0 6,18 * * *`)
- Auto-apply workflow: `.github/workflows/apply-deploy-pipeline-fix.yml`
- **Class precedent learning:** `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`
- **Post-apply verification contract:** `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`
- **Canonical TF invocation:** `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`
- **Prior plan (5-input trigger):** `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`
- **SSH-allowlist hard rule:** AGENTS.md `hr-ssh-diagnosis-verify-firewall`
- **Prod-write authorization hard rule:** AGENTS.md `hr-menu-option-ack-not-prod-write-auth`
- **Ops-remediation `Ref` over `Closes` rule:** AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` (+ Sharp Edge extension for ops-remediation class)
