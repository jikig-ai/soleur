---
title: "Fix: Terraform drift surfaced during #3371 remediation — seo_response_headers description (#3378) + deploy_pipeline_fix triggers_replace (recurring #3061 class)"
type: fix
classification: ops-only-prod-write
date: 2026-05-09
issue: "#3485"
requires_cpo_signoff: false
---

# Fix: Terraform drift on `cloudflare_ruleset.seo_response_headers` + `terraform_data.deploy_pipeline_fix` (#3485)

> **Ops-remediation runbook.** No code change, no PR. Operator runs two consecutive `terraform apply -target=...` invocations against `prd_terraform`, then closes #3485. Each apply is per-command-ack gated per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`. The `deploy_pipeline_fix` half follows `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md` verbatim, including the file+systemd contract verification (NOT the legacy HTTP-200 probe).

## Enhancement Summary

**Deepened on:** 2026-05-09
**Sections enhanced:** Overview (Drift B source PR/SHA confirmed live), Phase 3 (Hetzner firewall name corrected), Phase 5 (Cloudflare zone-id var + jq path corrected), Acceptance Criteria (live label-existence check), Research Insights (5 new findings live-verified)
**Research sources:** `git log -1 main -- <5 trigger files>`, `apps/web-platform/infra/.terraform.lock.hcl`, `apps/web-platform/infra/{firewall,seo-rulesets,outputs,variables}.tf`, `.github/workflows/scheduled-terraform-drift.yml`, `gh label list`, `gh issue view {3043,3379}`, learnings 2026-04-29 / 2026-04-24 / 2026-04-19 / 2026-04-06 / 2026-04-19-admin-ip / 2026-04-22-admin-ip-followthrough / 2026-04-18-cloudflare-default-bypasses-dynamic-paths / 2026-04-21-cloudflare-waf-ua-allowlist-and-narrow-token.

### Key Improvements

1. **Drift B source PR/SHA confirmed live.** `git log -1 --pretty=format:'%H %ai %s' main -- ci-deploy.sh webhook.service cat-deploy-state.sh canary-bundle-claim-check.sh hooks.json.tmpl` returns `b1a7c7ec 2026-05-07 10:14:30 +0200 fix(ci): bump web-platform-release deploy poll ceiling to 900s (#3398) (#3400)`. The plan's "suspected source" is now confirmed source — close-out comment can name #3398/#3400 outright. The next-most-recent touch is `1edf7a62` (#3045/#3046, 2026-04-29) which was already remediated by #3061's apply, so the unaccounted delta is exactly the b1a7c7ec edit.
2. **Hetzner firewall name corrected.** `apps/web-platform/infra/firewall.tf:2` declares `name = "soleur-web-platform"` (NOT `web-platform-firewall` as the initial draft of Phase 3 wrote). `hcloud firewall describe web-platform-firewall` would have returned "firewall not found." Phase 3 SSH source-list pre-check now uses the correct name.
3. **Cloudflare zone-id source corrected.** Phase 5 initial draft cited `${CLOUDFLARE_ZONE_ID}` env var; the actual variable is `cf_zone_id` (`apps/web-platform/infra/variables.tf:80`), Doppler-backed key `CF_ZONE_ID`. Operator pulls via `doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain`. The `cf_api_token` is `CF_API_TOKEN` (`variables.tf:56`).
4. **Cloudflare API jq path corrected.** Initial Phase 5 jq path was `headers["x_robots_tag"].value`; the actual `action_parameters` shape (verified in `apps/web-platform/infra/seo-rulesets.tf:303-308`) is a `headers` ARRAY of objects with `name`/`operation`/`value`. Corrected jq filter selects the array element where `name == "X-Robots-Tag"`.
5. **GitHub label existence verified live.** Per AGENTS.md `cq-gh-issue-label-verify-name` and the deepen-plan quality check on prescribed labels: `gh label list --limit 200 | grep -E "^(infra-drift|domain/engineering|chore|priority/p3-low|priority/p2-medium)\s"` returns all five — issue #3485 already carries `infra-drift`; if a follow-up is filed against #3043 (gate-fire follow-through), `domain/engineering` + `chore` + `priority/p3-low` are valid.
6. **Provider/version pins verified live.** `apps/web-platform/infra/.terraform.lock.hcl` confirms `cloudflare 4.52.7` (constraints `~> 4.0`) and `hcloud 1.60.1` (constraints `~> 1.49`); `.github/workflows/scheduled-terraform-drift.yml:24` pins `TERRAFORM_VERSION: "1.10.5"`. Operator must match `terraform v1.10.5` locally — Phase 1.2 already requires this.
7. **#3043 follow-through context (post-deepen citation).** `#3043` is OPEN as of 2026-05-09 and explicitly says "First PR after merge that touches any of the 4 [now 5] trigger files [...] should fire the new `/ship` Phase 5.5 [...] Operator confirms the gate fires." If `/ship` did NOT surface the apply on #3398/#3400 (i.e., #3398's PR body has no "deploy_pipeline_fix-drift-gate" tag), this remediation is the proof-point #3043 was waiting for — Phase 7.4 records that as a closure signal for #3043.

### New Considerations Discovered

- **`/ship` Phase 5.5 gate possibly skipped on #3398/#3400.** The drift cron filed #3485 12 h post-merge instead of the apply being scheduled at PR-merge time. Two possible causes: (a) the `/ship` skill wasn't invoked on #3398 (operator merged via a non-`/ship` path), or (b) the gate fired but the apply was deferred and forgotten. Phase 7.4 explicitly checks the source PR for the gate tag; if absent, file against #3043 with `process gap` (gate not consulted) rather than `regex gap` (gate consulted but missed the file).
- **Drift A's `id`/`ref` regenerate is NOT a Terraform bug.** Per `apps/web-platform/infra/seo-rulesets.tf:294-308`, the `cloudflare_ruleset` `rules` block carries server-assigned `id` and `ref` fields. Editing ANY field of a rule (including description) causes Cloudflare's API to mint a new `id`/`ref` on PUT — Terraform shows them as `(known after apply)` but they are not state corruption. The state will stabilize on the new IDs after Phase 2 apply; subsequent plans (Phase 6) will exit 0.
- **Apply order also limits Cloudflare API blast radius.** Drift A is constrained to a single Transform Rule row inside one ruleset. Even if the Cloudflare API rejects partial mid-PUT (it shouldn't — rulesets are PUT atomically per `2026-04-03-github-ruleset-put-replaces-entire-payload.md` analog for CF), the worst case is the entire `seo_response_headers` ruleset rolling back to pre-apply state — which is the current (drifted) state. No semantic regression.
- **L3 firewall pre-check fires by resource shape, not symptom.** Per the deepen-plan Phase 4.5 trigger ("any resource whose definition contains `provisioner "file"`, `provisioner "remote-exec"`, or a `connection { type = "ssh" ... }` block"), `terraform_data.deploy_pipeline_fix` qualifies on all three. Verified in `server.tf:227-232` (connection) and `server.tf:233-262` (file + remote-exec provisioners). Phase 3.3's pre-check is non-skippable; the firewall name fix above makes the `hcloud firewall describe` command actually work.

## Overview

The Phase 1 pre-apply check of the #3371 remediation runbook (`knowledge-base/project/plans/2026-05-09-fix-terraform-drift-seo-page-redirects-3371-plan.md`) discovered that the original target of #3371 (`cloudflare_ruleset.seo_page_redirects`) is **already in state** (`id 68dfde060e28478ebd419926fb1107de`) and serving 301s for all 10 source URLs. #3371 was closed.

But `terraform plan` against `prd_terraform` reports `Plan: 1 to add, 1 to change, 1 to destroy` — two **other** drifts have accumulated since 2026-05-06 and were out of scope for #3371. Per the #3371 plan's Phase 1 halt condition (and AGENTS.md `wg-when-an-audit-identifies-pre-existing`), they are filed as #3485 and remediated here.

### Drift A — `cloudflare_ruleset.seo_response_headers` (description-only)

```text
# cloudflare_ruleset.seo_response_headers will be updated in-place
~ resource "cloudflare_ruleset" "seo_response_headers" {
    id   = "51e84830aab949aeb0c1df8282efa07d"
    name = "X-Robots-Tag on subdomains + RSS feed"
  ~ rules {
      ~ description = "X-Robots-Tag: noindex, nofollow on api.soleur.ai GET responses" -> "X-Robots-Tag: noindex, nofollow on api.soleur.ai GET responses (no-op until proxied — see #3379)"
      ~ id          = "391ba663fba04bb4bc30fca0d6f172c7" -> (known after apply)
      ~ ref         = "391ba663fba04bb4bc30fca0d6f172c7" -> (known after apply)
    }
}
```

- **Source PR:** #3378 (`docs(infra): document api.soleur.ai X-Robots-Tag no-op (DNS-only CNAME bypasses CF edge)`, commit `556fa567`).
- **Functional impact:** zero — only the Cloudflare rule description string changes (`apps/web-platform/infra/seo-rulesets.tf:294`). `id` / `ref` regenerate on edit; rule semantics (`set_config: x_robots_tag noindex,nofollow` on `host eq "api.soleur.ai" and http.request.method eq "GET"`) are unchanged.
- **Apply class:** routine; standard `prd_terraform` discipline.

### Drift B — `terraform_data.deploy_pipeline_fix` (recurring class — 11th occurrence)

```text
# terraform_data.deploy_pipeline_fix must be replaced
-/+ resource "terraform_data" "deploy_pipeline_fix" {
    ~ id               = "d34ded19-7fdb-253e-5971-64568f12c6b3" -> (known after apply)
    ~ triggers_replace = (sensitive value) # forces replacement
}
```

- **Drift class:** identical to #3061 / #2618 / #2873 / #2874 / #1899 / etc. The trigger expression in `apps/web-platform/infra/server.tf:219-225` hashes 5 inputs (`ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, `local.hooks_json`); a recent merge changed one of those.
- **Likely source:** PR #3398/#3400 (`fix(ci): bump web-platform-release deploy poll ceiling to 900s`, commit `b1a7c7ec`, 2026-05-08) — touches `ci-deploy.sh`. To be confirmed during Phase 1 plan output review.
- **Existing structural fix tracker:** `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" (#2881 closed; #3043 open follow-through tracking gate fires). The gate's `DPF_REGEX` was widened post-#3061 to include `canary-bundle-claim-check.sh` (verified at `plugins/soleur/skills/ship/SKILL.md:450`).
- **Operator-level remediation:** standard `terraform apply -target=terraform_data.deploy_pipeline_fix` per the precedent runbook `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`. Uses interactive ack (no `-auto-approve`).

**Resolution:** two consecutive `terraform apply -target=...` invocations from `apps/web-platform/infra/` via `doppler run --project soleur --config prd_terraform`. Drift A first (smallest blast-radius — Cloudflare description string), then Drift B. Each per-command-ack gated. Verify Drift B via the file+systemd contract (NOT the legacy HTTP-200 probe — that returns 403 from CF Access since #3019). Re-run drift detector after both applies; expect clean plan ("No changes").

## User-Brand Impact

- **If this lands broken, the user experiences:** (Drift A) zero — the description-only edit cannot fail destructively; if the Cloudflare API rejects, the existing rule (with stale description) keeps serving. (Drift B) the next deploy webhook restart could fail or run against a stale `ci-deploy.sh`, which would degrade the next deploy (e.g., the 900s poll ceiling from #3398 would not apply, returning the prior 600s timing — the very regression the merge was meant to fix). Neither path is a user-visible outage; both are degraded-deploy states recoverable via re-apply.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — Drift A mutates only a Cloudflare rule description string. Drift B re-provisions five webhook scripts already on the prod host. No user data, no auth surface, no external-service credentials are mutated; `local.hooks_json` is sensitive (contains `WEBHOOK_DEPLOY_SECRET`) but it is already on the server and the apply only re-writes the same value.
- **Brand-survival threshold:** `none` — the diff is ops-only, no sensitive path under preflight Check 6 regex (`apps/web-platform/server/**`, `apps/web-platform/app/api/**`, migrations, auth/middleware). Scope-out: `threshold: none, reason: ops-remediation runbook with no code change, no migration, no credential rotation, no user-facing surface — only updates a Cloudflare rule description string and re-provisions five shell scripts already present on the prod host`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim / next-step | Reality | Plan response |
|---|---|---|
| Drift A: "description-only no-op from #3378" | Confirmed — `apps/web-platform/infra/seo-rulesets.tf:294` shows the new description string; the only field changes in the plan are `description`, `id`, `ref` (last two are server-assigned on edit, always re-generate). | Apply as a description-only no-op; no rollback needed. |
| Drift B: "recurring #3061-class drift; follow `2026-04-30-...-3061-plan.md` verbatim" | Confirmed — `triggers_replace = (sensitive value) # forces replacement` matches the #3061 signature exactly. The 5-input trigger hasn't changed since #3042; the precedent plan applies verbatim. | Phases 3-7 mirror the precedent plan's Phases 1-5 with no semantic deviation. |
| Drift B: "use file+systemd contract, NOT legacy HTTP-200 probe" | Canonical contract per `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe". HTTP probe returns 403 from CF Access on anonymous calls since #3019. | Phase 4 uses sha256 + `systemctl is-active webhook`; HTTP probe is explicitly NOT in the verification path. |
| `/ship` Phase 5.5 `DPF_REGEX` | Widened post-#3061 to include `canary-bundle-claim-check.sh` (`plugins/soleur/skills/ship/SKILL.md:450` shows all 5 files). | The stale-regex root cause from #3061 is closed — the present recurrence is a different surface (likely `ci-deploy.sh` from #3398/#3400). #3043 still tracks gate-fire follow-through. |
| Issue body: "/tmp/3371-plan.txt (operator-local)" | Operator-local file from the #3371 session; not in repo. | Phase 1 re-runs the plan locally to re-confirm the two drifts before applying — no dependency on the older artifact. |
| `terraform output` name | `apps/web-platform/infra/outputs.tf:1` declares `output "server_ip"` (not `server_ipv4`). | Use `terraform output -raw server_ip` in Phase 4. |
| Backend lock state | `apps/web-platform/infra/main.tf:13` declares `use_lockfile = false  # R2 does not support S3 conditional writes`. | Phase 2 (Drift A) and Phase 3 (Drift B) both freeze merges — there is NO mechanical state lock. |
| Provider/version pins | `.terraform.lock.hcl` pins `hcloud 1.60.1`, `cloudflare 4.52.7`, `random 3.8.1`; CI uses `TERRAFORM_VERSION: 1.10.5`. | Phase 1 verifies operator's `terraform version` matches `1.10.5` before plan/apply. |

## Implementation Phases

### Phase 1 — Confirm both drifts locally (≤ 5 min)

- [ ] From the worktree, run `terraform init -input=false` in `apps/web-platform/infra/` (the worktree has no `.terraform/` directory).
- [ ] Verify `terraform version` reports `Terraform v1.10.5` (matches CI's `TERRAFORM_VERSION`).
- [ ] Run the plan in the exact CI form, mirroring `.github/workflows/scheduled-terraform-drift.yml`:

  ```bash
  cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3485-tf-drift-fix/apps/web-platform/infra
  # Extract R2 creds separately (name-transformer would mangle them to TF_VAR_*)
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform plan -detailed-exitcode -no-color -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

- [ ] Expected: exit code 2, "Plan: 1 to add, 1 to change, 1 to destroy" with **only**:
  - `~ cloudflare_ruleset.seo_response_headers` (in-place description update).
  - `-/+ terraform_data.deploy_pipeline_fix` (replace).
- [ ] **Abort condition:** if the plan names any resource other than these two, STOP and file a follow-up triage issue. Coupling unrelated drifts into one apply is the pattern that produced #2873/#2874/#3061-class incidents — extending it across a third surface is the same antipattern at a larger blast radius.
- [ ] Identify which trigger file in Drift B was last touched (`git log -1 --pretty=format:'%H %s' main -- ci-deploy.sh webhook.service cat-deploy-state.sh canary-bundle-claim-check.sh hooks.json.tmpl`) and record in the close-out comment.

### Phase 2 — Apply Drift A (`seo_response_headers`) (≤ 2 min) — REQUIRES PER-COMMAND OPERATOR ACK

- [ ] **Freeze merges.** R2 backend has `use_lockfile = false` (main.tf:13 — R2 lacks S3 conditional writes). There is NO state lock — two concurrent applies will race. Confirm no PR is in merge queue:

  ```bash
  gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'
  ```

  Expect empty output. If non-empty, wait or coordinate via Discord before proceeding.
- [ ] **Show the exact apply command and wait for explicit `go` from the operator** (per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`). Do NOT execute on a generic "yes" / menu choice. The `-target` is scoped strictly to the description-only ruleset:

  ```bash
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -target=cloudflare_ruleset.seo_response_headers -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

  Note: omit `-auto-approve` so terraform's own confirmation prompt surfaces (interactive `yes`). The `-target` flag scopes the apply strictly to the drifted ruleset.

- [ ] Expected: "Apply complete! Resources: 0 added, 1 changed, 0 destroyed."
- [ ] No SSH agent / Hetzner credential is required for Drift A — Cloudflare API only.
- [ ] **Recovery.** If the Cloudflare API rejects (rate limit, transient 5xx), re-run the same command; the operation is idempotent (writing the same description twice is a no-op the second time the state matches).

### Phase 3 — Apply Drift B (`deploy_pipeline_fix`) (≤ 3 min) — REQUIRES PER-COMMAND OPERATOR ACK

- [ ] **Re-confirm freeze.** Merges should still be frozen from Phase 2. Re-check `gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'` returns empty.
- [ ] Verify SSH agent has the prod private key loaded:

  ```bash
  ssh-add -l | grep -i ed25519
  ```

  The Terraform `connection` block at `server.tf:227-232` uses `agent = true`. Apply fails with "no suitable auth method" if no key is loaded. Per learning `2026-04-06-terraform-data-connection-block-no-auto-replace.md`, `connection` block changes do NOT auto-replace, so the current state still uses `agent = true` and requires a loaded agent.
- [ ] **(L3 firewall pre-check, per AGENTS.md `hr-ssh-diagnosis-verify-firewall`.)** The Phase 3 apply opens an SSH session to the prod host. Verify the operator's current egress IP is in the Hetzner firewall allow-list before invoking apply:

  ```bash
  curl -s ifconfig.me/ip
  # Firewall name is "soleur-web-platform" (apps/web-platform/infra/firewall.tf:2), NOT "web-platform-firewall".
  hcloud firewall describe soleur-web-platform --output json | jq -r '.rules[] | select(.protocol == "tcp" and (.port // "") == "22") | .source_ips[]'
  ```

  If the operator's IP is NOT in the SSH source list, run `/soleur:admin-ip-refresh` (per AGENTS.md `hr-ssh-diagnosis-verify-firewall` runbook `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`) BEFORE invoking apply. This avoids the #3061 misdiagnosis class (SSH `connection reset by peer` mistakenly attributed to sshd/fail2ban when the cause was admin-IP drift).

- [ ] **Show the exact apply command and wait for explicit `go` from the operator** (per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`). Do NOT execute on a generic "yes" / menu choice or on stretched approval from Phase 2:

  ```bash
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -target=terraform_data.deploy_pipeline_fix -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

  Note: omit `-auto-approve` so terraform's own confirmation prompt surfaces (interactive `yes`). The `-target` flag matches the `/ship` Phase 5.5 gate's exact prescription (`plugins/soleur/skills/ship/SKILL.md:468`).

- [ ] Expected sequence in apply output: destroy of `terraform_data.deploy_pipeline_fix` → create (file provisioner uploads `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, `hooks.json`) → remote-exec `chmod +x` on three scripts + `chown root:deploy /etc/webhook/hooks.json` + `chmod 640 /etc/webhook/hooks.json` + Doppler env idempotent append + `systemctl daemon-reload` + `systemctl restart webhook` + `rm -f /mnt/data/.env`.
- [ ] Apply completes "Apply complete! Resources: 1 added, 0 changed, 1 destroyed."
- [ ] **Recovery (tainted resource).** If the SSH provisioner fails mid-apply, the resource will be tainted. Run `terraform state list | grep deploy_pipeline_fix`; if present, rerun the same apply (all provisioner steps are idempotent by design):
  - `chmod +x /usr/local/bin/{ci-deploy.sh,cat-deploy-state.sh,canary-bundle-claim-check.sh}` — idempotent.
  - `chown root:deploy /etc/webhook/hooks.json` + `chmod 640 /etc/webhook/hooks.json` — idempotent.
  - `grep -q DOPPLER_CONFIG_DIR /etc/default/webhook-deploy || printf ...` — explicitly grep-guarded (`server.tf:271`).
  - `systemctl daemon-reload` + `systemctl restart webhook` — idempotent.
  - `rm -f /mnt/data/.env` — idempotent (`-f` swallows ENOENT).

### Phase 4 — Verify production via file+systemd contract (Drift B) (≤ 5 min)

- [ ] **Use the file+systemd contract**, NOT the legacy HTTP probe. Per `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` "When NOT to use this probe", the HTTP probe returns HTTP 403 from CF Access on anonymous calls and is therefore unreliable for post-apply verification. The file+systemd contract is provisioner-layer and observes exactly what the apply was meant to deliver:

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
- [ ] Lightweight liveness sanity (optional): `curl -I https://soleur.ai/health` → expect HTTP 200. A site outage in this window is coincidental — the apply only touches `/etc/systemd/system/webhook.service` and the `webhook` unit; the main `soleur-web` container is unaffected.

### Phase 5 — Verify Drift A semantics (≤ 2 min)

- [ ] Confirm the Cloudflare ruleset still serves the noindex header on `api.soleur.ai`. The header is a no-op until that subdomain is proxied (per #3379), so the Cloudflare API is the source of truth for "the rule is installed". The Doppler-backed Terraform variable is `var.cf_zone_id` (`apps/web-platform/infra/variables.tf:80`), key `CF_ZONE_ID`; API token is `CF_API_TOKEN` (`variables.tf:56`):

  ```bash
  CF_ZONE_ID=$(doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain)
  CF_API_TOKEN=$(doppler secrets get CF_API_TOKEN -p soleur -c prd_terraform --plain)
  curl -s "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/rulesets/51e84830aab949aeb0c1df8282efa07d" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    | jq -r '
        .result.rules[]
        | select(.expression | contains("api.soleur.ai"))
        | "description=\(.description)",
          "expression=\(.expression)",
          "action=\(.action)",
          (.action_parameters.headers // [] | .[] | select(.name == "X-Robots-Tag") | "header_value=\(.value)")
      '
  ```

  Expected output:
  - `description=X-Robots-Tag: noindex, nofollow on api.soleur.ai GET responses (no-op until proxied — see #3379)`
  - `expression=(http.host eq "api.soleur.ai" and http.request.method eq "GET")`
  - `action=rewrite`
  - `header_value=noindex, nofollow`

  Note: `action_parameters.headers` is an ARRAY of `{name, operation, value}` objects (verified in `apps/web-platform/infra/seo-rulesets.tf:303-308`), NOT a map keyed by header name. The jq `select(.name == "X-Robots-Tag")` is load-bearing.
- [ ] If the description still shows the pre-apply string, re-run Phase 2.

### Phase 6 — Re-verify both drifts are gone (≤ 2 min)

- [ ] Re-run the plan from Phase 1. Expected: exit code 0, "No changes. Your infrastructure matches the configuration."
- [ ] If new drift surfaces on a *different* resource, file a separate drift issue — do not conflate with #3485. Per the #3371 plan's halt condition: each accumulated drift class deserves its own issue and runbook.

### Phase 7 — Close the issue + trigger drift workflow (≤ 2 min)

- [ ] Comment on #3485 with the Phase 6 plan output (exit 0) and close. Per AGENTS.md `cq-when-a-pr-has-post-merge-operator-actions`, ops-remediation plans use `gh issue close` post-apply (NOT `Closes #3485` in any PR — there is no PR; this branch's plan/tasks commits use `Ref #3485` only):

  ```bash
  gh issue close 3485 --comment "Applied two consecutive targeted applies against prd_terraform:

  1. \`terraform apply -target=cloudflare_ruleset.seo_response_headers\` — description-only no-op (#3378 / 556fa567). Cloudflare API verified: rule \`391ba663fba04bb4bc30fca0d6f172c7\` now carries the (no-op until proxied — see #3379) suffix.
  2. \`terraform apply -target=terraform_data.deploy_pipeline_fix\` — recurring #3061 class (11th occurrence). Triggered by #3398/#3400 (commit \`b1a7c7ec\`, 2026-05-07 — \`ci-deploy.sh\` poll-ceiling bump to 900s). Verified via file+systemd contract: sha256 match on ci-deploy.sh, canary-bundle-claim-check.sh, cat-deploy-state.sh; \`systemctl is-active webhook\` returned \`active\`.

  \`terraform plan\` now exits 0 (No changes). Drift workflow re-triggered: <run-id>."
  ```

- [ ] Manually trigger the drift workflow to confirm the next scheduled run will pass:

  ```bash
  gh workflow run scheduled-terraform-drift.yml
  RUN_ID=$(gh run list --workflow scheduled-terraform-drift.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch "$RUN_ID"
  gh run view "$RUN_ID" --json conclusion --jq .conclusion   # expect: success
  ```

- [ ] If the gate's `DPF_REGEX` did NOT fire on the source PR (e.g., Drift B was caused by a path the regex still misses), file a follow-up issue against #3043 with the missing path and the empirical grep evidence — do not silently re-widen the regex.

## Acceptance Criteria

### Pre-merge (PR)

This plan produces NO code changes — it is a remediation runbook. There is no PR. All sign-off is post-merge / post-apply on `main`.

- [ ] Plan committed to `knowledge-base/project/plans/` and `tasks.md` to `knowledge-base/project/specs/feat-one-shot-3485-tf-drift-fix/` on the feat branch.

### Post-merge (operator)

- [ ] `terraform plan` in `apps/web-platform/infra/` exits 0 (no drift) after both applies.
- [ ] Scheduled drift workflow run (triggered manually in Phase 7) concludes `success`.
- [ ] Cloudflare API confirms the `seo_response_headers` rule for `api.soleur.ai` carries the new description (`...no-op until proxied — see #3379`).
- [ ] Server-side sha256 of `/usr/local/bin/ci-deploy.sh` equals local `apps/web-platform/infra/ci-deploy.sh` sha256.
- [ ] Server-side sha256 of `/usr/local/bin/canary-bundle-claim-check.sh` equals local `apps/web-platform/infra/canary-bundle-claim-check.sh` sha256.
- [ ] Server-side sha256 of `/usr/local/bin/cat-deploy-state.sh` equals local `apps/web-platform/infra/cat-deploy-state.sh` sha256.
- [ ] `systemctl is-active webhook` returns `active`.
- [ ] `https://soleur.ai/health` returns HTTP 200.
- [ ] Issue #3485 is closed via `gh issue close` with a comment naming the source PR/SHA for Drift B (#3398/#3400, `b1a7c7ec`) (NOT auto-closed via `Closes #3485` in any PR — there is no PR; per `cq-when-a-pr-has-post-merge-operator-actions`).
- [ ] If a follow-up against #3043 is filed (gate-fire follow-through), labels `domain/engineering`, `chore`, `priority/p3-low`, and `infra-drift` are valid (verified live via `gh label list --limit 200` per `cq-gh-issue-label-verify-name`).

## Risks & Non-Goals

### Risks

- **No state lock between Drift A and Drift B applies.** R2 backend has `use_lockfile = false` (main.tf:13). The operator must keep merges frozen across BOTH applies (~5 min total) — a third-party PR merging between Phase 2 and Phase 3 that touches a `deploy_pipeline_fix` trigger file would couple a new drift into Phase 3 without explicit ack. Mitigation: Phase 3 re-checks the merge queue.
- **SSH agent not loaded for Drift B.** Apply requires the production SSH private key in the agent. Mitigation: Phase 3 explicitly verifies `ssh-add -l`.
- **Admin IP drift causing SSH `connection reset` (per AGENTS.md `hr-ssh-diagnosis-verify-firewall`).** Same misdiagnosis class that produced #2681. Phase 3 includes the L3 firewall pre-check before any sshd/service-layer hypothesis.
- **Webhook restart window (~30 s).** `systemctl restart webhook` causes ~2 s deploy-webhook unavailability; the file-provisioner upload phase before that takes ~10 s during which a script is partially rolled out. Total apply-side window is ~30 s. Safe because no deploy should be in-flight; Phase 3 explicitly checks merge-queued PRs and the operator freezes merges before running apply.
- **Doppler `prd_terraform` config drift.** If the config is missing `CF_API_TOKEN`, `CF_ZONE_ID`, `HCLOUD_TOKEN`, `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_DEPLOY_CLIENT_ID`, `CF_ACCESS_DEPLOY_CLIENT_SECRET`, or the AWS R2 keys (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), the plan or apply fails at refresh. Mitigation: Phase 1's plan surfaces missing vars before either apply.
- **Provider version drift in CI vs. operator.** CI uses `TERRAFORM_VERSION: 1.10.5` (`scheduled-terraform-drift.yml`). Operator's local `terraform version` should match. Mitigation: Phase 1 verifies.
- **Drift A before Drift B is the intentional order.** Drift A (Cloudflare description) is the smallest blast-radius and has no SSH dependency, so applying it first separates the (well-understood) ruleset apply from the (SSH-dependent) deploy-pipeline apply. If Drift A fails, the operator can pause without having mutated the prod webhook host.
- **`-target` flag warning is benign here.** `terraform apply -target=...` prints "The -target option is not for routine use" — for *this* class (intentionally drifted single resources matching the `/ship` Phase 5.5 gate), `-target` is the documented form.

### Non-Goals

- **Not** implementing a structural prevention. That work is tracked at `/ship` Phase 5.5 "Deploy Pipeline Fix Drift Gate" (already wired post-#3022 and widened post-#3061) and `#3043` (open follow-through). The present recurrence proves the gate is still a heuristic, not a guarantee — but #3043 is the right venue for that conversation.
- **Not** changing the `triggers_replace` expression to avoid drift (e.g., by hashing a version number). The current content-hash design is correct — it guarantees production reflects committed code.
- **Not** auditing other `terraform_data.*_install` resources or other `cloudflare_ruleset.*` resources; only the two named in the issue are in scope.
- **Not** addressing #3379 (api.soleur.ai is DNS-only CNAME so the X-Robots-Tag rule is a no-op). The description-only edit in Drift A documents that gap; the fix lives in #3379.
- **Not** updating `/ship` gate or postmerge runbook documentation — both already reflect the file+systemd contract.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **One coupled `terraform apply` (no `-target`)** | Lands two unrelated drifts in one apply — exactly the antipattern that produced #2873/#2874 (coupled drifts hide which apply caused which side effect at recovery time). Two `-target`-scoped applies are explicit. |
| **Apply Drift B first, then Drift A** | Drift B has SSH/Hetzner dependency and a ~30 s webhook restart window. Putting the lower-risk Cloudflare-only apply first means a Drift A failure pauses the operator before mutating the prod host. |
| **Revert PRs #3378 / #3398 / #3400** | #3378 documents a real semantic state (api.soleur.ai is DNS-only CNAME — the rule IS a no-op until proxied). #3398/#3400 fixed a real CI poll-ceiling regression. Reverting either abandons working fixes; apply is strictly better. |
| **`terraform state rm` either resource** | Removes state without re-applying — leaves Cloudflare with a stale description (Drift A) or the webhook host with stale `ci-deploy.sh` (Drift B). Violates `hr-all-infrastructure-provisioning-servers`. |
| **Manual `scp` of ci-deploy.sh + manual Cloudflare dashboard edit** | Violates `hr-all-infrastructure-provisioning-servers`. Does not restart the webhook, does not re-`chown`/`chmod` `hooks.json`, and dashboard edits to a Terraform-managed ruleset will themselves drift the next plan. |
| **Apply via `gh workflow run` from a CI workflow** | No production-applicable apply CI workflow exists today (`scheduled-terraform-drift.yml` is plan-only). Adding one is out-of-scope per `wg-when-deferring-a-capability`; `#2881`-closed enhancement covered the design. |
| **Use the legacy HTTP-200 webhook smoke-test for Drift B** | Returns HTTP 403 from CF Access on anonymous probes (since CF Access landed in front of `/hooks/*`). The file+systemd contract is the canonical post-apply verification per `#3022` / 2026-04-29 learning. |

## Test Strategy

No code changes → no unit tests. Verification happens in Phases 4-7:

- **Phase 4** = file+systemd contract for Drift B (server-side sha256 match + `systemctl is-active webhook`).
- **Phase 5** = Cloudflare API contract for Drift A (rule description matches the new string).
- **Phase 6** = regression test of the drift condition (plan exits 0 on both surfaces).
- **Phase 7** = end-to-end test of the drift-detection workflow (`gh workflow run` → `success`).

`ci-deploy.test.sh` and `canary-bundle-claim-check.test.sh` already gate any future trigger-file changes at PR-merge time; no new tests needed for the present remediation.

## Files to Edit

None (this is an ops runbook, not a code change).

## Files to Create

None.

## Open Code-Review Overlap

Verified against `gh issue list --label code-review --state open --json number,title,body --limit 100`:

- **`apps/web-platform/infra/server.tf`** appears in #2197 (`refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc + Sentry breadcrumb UUID policy`) — reference is to an unrelated rate-limiter `count = 1` invariant in a documentation context, NOT to `terraform_data.deploy_pipeline_fix`. **Disposition: Acknowledge.** No code change in this remediation; #2197 stays open.
- **`server.tf` + `deploy_pipeline_fix`** appear in #3216 (`review: PR fix-dpf-regex-canary-bundle-3068 — code-quality + architecture findings (resolved inline)`) — that PR's findings were resolved inline in #3068; the issue is review record-keeping. **Disposition: Acknowledge.** No fold-in surface for this remediation.
- No matches for `seo-rulesets.tf`, `seo_response_headers`, `ci-deploy.sh`, `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`, or `hooks.json.tmpl` in any other open code-review issue.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure ops remediation (run two terraform applies, close one issue). No code changes, no user-facing surface, no new dependencies, no external services beyond the existing Cloudflare and Hetzner accounts. CTO domain is implicit (the current task IS engineering per `pdr-do-not-route-on-trivial-messages-yes`), so no CTO routing.

Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, the User-Brand Impact section above resolves to `threshold: none` with explicit scope-out rationale (ops-only path).

## Research Insights

- **Pattern recurrence count.** Closed `infra-drift` issues for the same `deploy_pipeline_fix` class: #988, #994, #1412, #1505, #1899, #2234, #2618, #2873/#2874, #3019, #3061. With #3485 (Drift B), this is the 11th occurrence. The structural fix is wired — `/ship` Phase 5.5 includes `canary-bundle-claim-check.sh` since the post-#3061 widening — but it remains a PR-merge-time heuristic, not a guarantee against every trigger-file edit slipping through.
- **`/ship` Phase 5.5 `DPF_REGEX` is current.** `plugins/soleur/skills/ship/SKILL.md:450` reads `DPF_REGEX='^apps/web-platform/infra/(ci-deploy\.sh|webhook\.service|cat-deploy-state\.sh|canary-bundle-claim-check\.sh|hooks\.json\.tmpl)$'` — all 5 trigger-file inputs covered. Empirical match against `apps/web-platform/infra/ci-deploy.sh` (the suspected #3398/#3400 source for Drift B): grep returns 1, regex fires. Open question for the close-out comment: did `/ship` actually surface the apply command on the #3398 PR? If not, the gate-fire follow-through (#3043) needs an empirical event for this PR.
- **Verification contract canonical source.** `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md:26-44` ("When NOT to use this probe") is the canonical source for the file+systemd post-apply contract. Cross-referenced and consistent with this plan's Phase 4.
- **Drift A description string.** `apps/web-platform/infra/seo-rulesets.tf:294` reads `description = "X-Robots-Tag: noindex, nofollow on api.soleur.ai GET responses (no-op until proxied — see #3379)"` — exactly what the plan output expects to apply. The semantic fact (api.soleur.ai is DNS-only CNAME bypassing the CF edge) is documented at #3378's PR body and tracked at #3379.
- **`terraform output` name.** `apps/web-platform/infra/outputs.tf:1` declares `output "server_ip"` — confirms the precedent plan's correction (NOT `server_ipv4`).
- **Backend lock state.** `apps/web-platform/infra/main.tf:13` declares `use_lockfile = false  # R2 does not support S3 conditional writes`. The "no lock, freeze merges manually" risk is empirically grounded.
- **Provider/version pins (assumed unchanged from #3061 plan).** `.terraform.lock.hcl` pins `hcloud 1.60.1`, `cloudflare 4.52.7`, `random 3.8.1`. CI's `TERRAFORM_VERSION: 1.10.5`. Operator should verify before Phase 1.
- **L3 firewall pre-check fires here per AGENTS.md `hr-ssh-diagnosis-verify-firewall`.** Drift B's apply opens an SSH session via Terraform's `connection` block. Even though there is no current SSH symptom, the rule's intent is to verify the L3 surface BEFORE any apply that depends on it — admin IP drift is a known recurrence (`knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`) and `hcloud firewall describe` + `curl ifconfig.me/ip` is the load-bearing pre-check.
- **AGENTS.md rules applied:**
  - `hr-menu-option-ack-not-prod-write-auth` — Phases 2 and 3 each show the exact apply command and wait for explicit per-command go-ahead; no `-auto-approve` on production scope; Phase 3 explicitly notes that Phase 2's approval does NOT stretch.
  - `hr-all-infrastructure-provisioning-servers` — no manual SSH or dashboard fix; the Terraform applies ARE the fix.
  - `hr-ssh-diagnosis-verify-firewall` — Phase 3 includes the L3 firewall pre-check before invoking any apply that depends on SSH.
  - `hr-never-label-any-step-as-manual-without` — every step is automated via CLI; no manual browser/SSH handoff except the operator's interactive `yes` to terraform's confirmation prompt.
  - `hr-when-a-plan-specifies-relative-paths-e-g` — verified all five trigger-file paths exist via `git ls-files apps/web-platform/infra/`; verified `apps/web-platform/infra/seo-rulesets.tf` exists for Drift A; verified `apps/web-platform/infra/server.tf` includes both `seo_response_headers` (via grep — actually defined in `seo-rulesets.tf`) and `terraform_data.deploy_pipeline_fix`.
  - `hr-weigh-every-decision-against-target-user-impact` — User-Brand Impact section resolves to `none` with scope-out rationale.
  - `wg-when-an-audit-identifies-pre-existing` — the original #3371 audit surfaced these two drifts, both filed as #3485 before remediation per the gate.
  - `cq-when-a-pr-has-post-merge-operator-actions` — Acceptance Criteria split into Pre-merge (PR) and Post-merge (operator). Issue close uses `gh issue close` post-apply (NOT `Closes #3485` in a PR body — there is no PR).
- **Learning referenced:**
  - `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` — file+systemd contract.
  - `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — full pattern analysis.
  - `knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` — per-command ack discipline.
  - `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` — `-replace=` fallback context.
  - `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md` — L3 firewall pre-check rationale.

## References

- Issue: #3485
- Parent triage (closed, original target already in state): #3371
- Drift A source: #3378 (`556fa567`); semantic gap tracked at #3379
- Drift B suspected source: #3398 / #3400 (`b1a7c7ec`); confirm in Phase 1
- Drift B precedent runbook (verbatim template): `knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md`
- Drift B prior occurrences: #3061 (10th), #3019 (9th), #2873/#2874 (8th), #2618 (7th), #2234, #1899, #1505, #1412, #994, #988
- Resource definitions: `apps/web-platform/infra/seo-rulesets.tf:252-340` (Drift A), `apps/web-platform/infra/server.tf:211-279` (Drift B)
- Workflow: `.github/workflows/scheduled-terraform-drift.yml`
- Structural fix gate: `plugins/soleur/skills/ship/SKILL.md` (Phase 5.5 "Deploy Pipeline Fix Drift Gate", `DPF_REGEX` at line 450 — already widened to include `canary-bundle-claim-check.sh`)
- Gate follow-through tracker: #3043
- Closed structural enhancement: #2881
- Post-apply contract: `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` ("When NOT to use this probe")
- Plan output (operator-local from #3371 session, not in repo): `/tmp/3371-plan.txt`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with a non-empty scope-out rationale.
- Each `-target` apply prints "The -target option is not for routine use." This warning is correct in general — but for this class of single-resource intentional drift, `-target` is the documented form per `/ship` Phase 5.5 (`plugins/soleur/skills/ship/SKILL.md:468`).
- No `-auto-approve` on `prd_terraform`. Operator must read each plan output and type `yes` interactively — terraform's native confirmation is the load-bearing safety net per `hr-menu-option-ack-not-prod-write-auth`. **Phase 2's `yes` does NOT stretch to Phase 3.** Each apply requires its own explicit go-ahead.
- Do NOT use the legacy HTTP-200 webhook probe for Drift B post-apply verification. It returns HTTP 403 from CF Access on anonymous probes. Use the file+systemd contract from Phase 4.
- `seo_response_headers` is a `cloudflare_ruleset` resource, not a Terraform-managed Cloudflare WAF rule. `id` and `ref` always regenerate on edit (server-assigned) — that is expected, not drift in itself.
- The `connection { agent = true }` in `server.tf:227-232` does NOT auto-replace per `2026-04-06-terraform-data-connection-block-no-auto-replace.md`. The current state still expects the SSH agent; Phase 3 verifies before applying.
- Apply order matters: Drift A first (Cloudflare-only, no SSH) so a failure does not leave the prod webhook host mid-mutation. If you reorder, you accept that a Drift B failure mid-Phase-3 leaves the operator with a partially-applied state AND an unapplied Cloudflare description change.
- L3 firewall admin-IP drift is the #1 mis-diagnosed cause of "SSH connection reset" during these applies. Phase 3's pre-check (`hcloud firewall describe` + `curl ifconfig.me/ip`) is non-skippable per AGENTS.md `hr-ssh-diagnosis-verify-firewall`.
