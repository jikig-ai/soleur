---
title: "infra: apply 'SSH forward to web-2' refused at preauth since the 2026-10-28 web-2 rebirth — SSH-apply stage skipped on every merge"
type: fix
date: 2026-10-28
slug: infra-web2-ssh-preauth-after-rebirth
branch: feat-one-shot-11445-web2-ci-ssh-preauth
issue: 11445
closes: 11445
lane: cross-domain
priority: P1
domain: engineering/infra
brand_survival_threshold: none
requires_cpo_signoff: false
---

# infra: web-2 CI SSH repair after the 2026-10-28 rebirth — stale host-key pin, not an auth rejection

## Enhancement Summary

**Deepened on:** 2026-10-28
**Sections enhanced:** Hypotheses (Network-Outage Deep-Dive), Proposed Solution (precedent diff), plus gate-required additions `## Downtime & Cutover` and `## Guard Contract`
**Research agents used:** none — no agent-spawning tool exists in this harness; the deep-dive, precedent-diff, verify-the-negative, and self-audit passes ran orchestrator-side.

### Key Improvements

1. Root cause re-verified against the run log, not the issue's conclusion: `Host key verification failed.` against the stale committed pin (run 40744937376) — the issue's "auth rejection" frame is corrected on the record (AC6).
2. Repair arms re-ordered by evidence: pin re-capture unconditional → on-host diagnostic → conditional IaC twin → re-replace as documented fallback only.
3. Conditional arm designed to the repo's own contract set (`EXCLUSION_ALLOWLIST`, EXT_RESIDENCE, host-fan-out twin class, `%RAND%` script_path, dual-mode `private_key`/`agent`).

### New Considerations Discovered

- `terraform_data.deploy_pipeline_fix_web2`'s `triggers_replace` includes the pin file — the pin merge itself re-delivers the birth-frozen deploy-pipeline set (verification comes free with the merge).
- The pin file is in `apply-deploy-pipeline-fix.yml`'s push paths AND under `apply-web-platform-infra.yml`'s `apps/web-platform/infra/**` glob — one merge verifies both consumers.
- cx33 fleet-stranding history (#6393/#6400) is already enforced in-band by `stock_preflight_gate` — the fallback needs no new guard machinery.

## Overview

The 2026-10-28 web-2 rebirth (`web_host_replace` run 40720815376, host created 16:01:04Z) rotated web-2's sshd host key, while the committed pin `apps/web-platform/infra/web-2-ssh-host-key.pub` still carries the predecessor host's key (captured 2026-10-07T20:11:48Z, PR #9733). Every merge-triggered `apply-web-platform-infra.yml` run since has failed at the `SSH forward to web-2 through the web-1 bastion` step — the end-to-end probe aborts on **`Host key verification failed.`** during kex, before authentication is ever attempted (run 40744937376, `apply` job log). The follow-on `Terraform apply (SSH-provisioned resources, over the bridge)` step then skips, leaving web-2's SSH-delivered infra set undelivered and every merge red.

The repair is the documented routine post-replace re-key that was never run for this rebirth: re-capture web-2's host key into the committed pin from an admin-IP egress (`scripts/capture-web-2-host-key.sh`), plus an on-host read-only diagnostic through the same admin-IP path to confirm whether the CI deploy pubkey is also absent from `/root/.ssh/authorized_keys`. The operator-authorized heavy paths (admin-IP key install, guarded re-replace) remain available as the conditional arm and the fallback — but neither is the primary fix, because the *observed* failure is client-side host-key verification, which a re-replace alone does not repair (a re-replaced host presents yet another new host key and still needs the re-pin).

## Problem Statement / Motivation

- `apply-web-platform-infra.yml` `apply` job fails at `SSH forward to web-2 through the web-1 bastion` on every push-to-main since run 40744937376 (2026-10-28T18:38Z). `notify-apply-failure` emails ops on each merge.
- `Terraform apply (SSH-provisioned resources, over the bridge)` — the `terraform_data.*` target list in `.github/workflows/apply-web-platform-infra.yml` (the `journald_persistent_web2`, `web_bash_synthetic_install_web2`, `egress_gateway_web2`, `zot_consumer_probe_install`, `git_data_probe_install`, `inngest_consumer_probe_install` set) — has not run against web-2 since the rebirth. Web-2's fresh-boot state is drifting from what that stage delivers.
- `apply-deploy-pipeline-fix.yml` pins the same host key (`web-2-ssh-host-key.pub` in its push paths filter and its own web-2 forward/probe block), so its `terraform_data.deploy_pipeline_fix_web2` delivery to the reborn host is blocked by the same stale pin.
- **Issue's stated diagnosis is refuted by the run log.** #11445 concludes "auth rejection, not L3/L4 — the reborn host does not accept the CI SSH key." The failing step's log shows `Offending ECDSA key in /home/runner/work/_temp/web-2.known_hosts:1`, `Host key for web-2 has changed and you have requested strict checking.`, `Host key verification failed.` — the CI client aborts on the **pinned host key**, before any auth method is attempted. Web-2's sshd logging `Connection closed by 10.0.1.10 port 58066 [preauth]` is the server-side view of exactly that client abort (no `Failed publickey` line accompanies it). See `## Research Reconciliation — Spec vs. Codebase`.

## Research Insights

### Premise Validation (Phase 0.6)

- **Cited issues:** #11445 OPEN (work target), #10585 OPEN (underlying first-deploy-verification gap — context, not scope), #6406 OPEN (web-2-recreate + verify arc), #11402 OPEN (web-2 LUKS evidence red on predecessor/new host telemetry). Deferred set verified OPEN and untouched: #11388, #11266, #6027, #11308, #10835, #10768, #8965.
- **Merged-fix claims:** commit `744396abbb` is on `origin/main` (the Better Stack 422 alert fix, merged 2026-10-28T16:53Z); the `inngest_luks_key_probe_fail` alert exists in `apps/web-platform/infra/betterstack-logs-alerts.tf`; run 40744937376 is the post-merge apply for #11427 and its `apply` job `conclusion: failure` at the SSH-forward step — confirming the Logtail-422 streak ended and the SSH failure is the remaining red.
- **Collision pre-check (`scripts/collision-precheck.sh`):** open PR **#11448** names #11445 — it is THIS pipeline's own draft PR on this branch (`headRefName: feat-one-shot-11445-web2-ci-ssh-preauth`, created 2026-10-28T20:02Z), not a foreign duplicate. `proc.sh` foreign rows are unrelated worktrees' `test-all.sh` watchers (feat-one-shot-11321-11424-11426, feat-one-shot-10932-restore-exit-1, feat-one-shot-autonomous-start-followthroughs) — no issue-number overlap; noted, not blocking.
- **Stale premise found:** the issue's root-cause line ("the reborn host does not accept the CI SSH key") is refuted by the run log (see Reconciliation below). The authorized repair envelope ("install the CI deploy pubkey … or a guarded web-2 re-replace") is kept — it covers the conditional arm — but the evidence-ordered primary arm is the re-key the replace runbook already prescribes.

### Property List (mechanism-minimality restatement, Phase 0.6b)

1. CI's end-to-end web-2 probe can verify the host's identity — i.e., the committed pin equals the host key web-2's sshd offers.
2. web-2's `root` accepts the CI deploy keypair (`tls_private_key.ci_ssh` ↔ Doppler `DEPLOY_SSH_PRIVATE_KEY`) for pubkey auth.
3. The SSH-provisioned `terraform_data.*` set deferred since the rebirth gets delivered to web-2.
4. The repair survives the NEXT web-2 replace (property satisfied by re-using the documented re-capture instrument, not by new machinery).

### Cut List

- **Guarded re-replace as primary repair** → buys properties 1–3 only if the cloud-init key path is also broken; unproven and destructive. Its own workflow gates already exist (`web_host_replace_gate` + `stock_preflight_gate`, `tests/scripts/lib/`); retained as the fallback arm, not a deliverable.
- **A new CI-side auto-heal/re-pin mechanism** → buys property 4 but duplicates `scripts/capture-web-2-host-key.sh`'s documented routine path and would need TOFU exemption (`#7226` no-keyscan-in-CI rule — the script hard-refuses `CI`/`GITHUB_ACTIONS`). Cut; #10585 is the systemic-gap tracker.
- **Extending `terraform_data.deploy_pipeline_fix_web2` to carry the pubkey** → the resource's credential-boundary comment (server.tf `deploy_pipeline_fix_web2` block header, "CREDENTIAL BOUNDARY") forbids credential material in that channel; a pubkey-append is bootstrap-shaped anyway (CI cannot reach a keyless host). Cut.

### Key repo facts (verified by reading, not asserted)

- `apps/web-platform/infra/web-2-ssh-host-key.pub` — committed ECDSA-P256 pin; header records `captured: 2026-10-07T20:11:48Z`, `fingerprint: SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE`. The failing run's log shows web-2 offering `SHA256:OB3/fH+fWhoTolCCx9rNMtuW0shPUONHNbhYxRFyqic`. Mismatch is the failure.
- `scripts/capture-web-2-host-key.sh` — the routine re-key path (ADR-237). Runs `ssh-keyscan -T 10 -t ecdsa` direct to web-2's public :22; REFUSES under `CI`/`GITHUB_ACTIONS` (no-TOFU-in-CI); requires operator egress ∈ `var.admin_ips`; cross-checks the operator's `known_hosts`; writes the pin file with `#` header (method, UTC date, SHA256 fingerprint, cross-check). Prior re-pins shipped as their own PRs: `bef6dd5a07` (#9151/#9212), `f27ca5444c` (#9305), `2ef72cd651` (#9665), `9820f6f9de` (#9733).
- `apps/web-platform/infra/server.tf` — `hcloud_server.web`: `ssh_keys = [hcloud_ssh_key.default.id]` (operator key injected at create → the admin-IP sshd path exists by construction); `lifecycle { ignore_changes = [user_data, ssh_keys, image, placement_group_id] }`; `local.web_2_ssh_host_key` reads the committed pin (regex over `web-2-ssh-host-key.pub`). The `deploy_pipeline_fix_web2` header comment names the exact present gap: "a DEPLOY_SSH_PRIVATE_KEY rotation reaches web-1 via ci-ssh-key.tf but not web-2's birth-frozen authorized_keys (recovery: operator ADMIN_IPS append or a web-2 replace — ADR-237 consequence note)."
- `apps/web-platform/infra/ci-ssh-key.tf` — `tls_private_key.ci_ssh` (ED25519) → `doppler_secret.deploy_ssh_private_key` (prd_terraform `DEPLOY_SSH_PRIVATE_KEY`) → `terraform_data.root_authorized_keys` appends the pubkey to web-1 `/root/.ssh/authorized_keys` (operator-local apply; `EXCLUSION_ALLOWLIST` member in `plugins/soleur/test/terraform-target-parity.test.ts`). `output "ci_ssh_public_key_openssh"` exists for the diagnostic's expected-value read. **The resource is web-1-scoped** (`host = hcloud_server.web["web-1"].ipv4_address`); no web-2 twin exists.
- `apps/web-platform/infra/cloud-init.yml` — unconditional top-level `ssh_authorized_keys: - ${ci_ssh_public_key_openssh}` (NOT inside a `%{ if }` arm); default user is root on Hetzner ubuntu-24.04. The same template birthed prior web-2 hosts that passed this CI step, so pubkey presence is *likely but unverified* → the diagnostic, not an assumption.
- `.github/workflows/apply-web-platform-infra.yml` — the forward step resolves web-2's public+private IPs from `terraform show -json`, opens `ssh -N -L 127.0.0.1:2223:<web-2-private>:22` through the pinned web-1 bridge, then runs the e2e probe with `HostKeyAlias=web-2` + `UserKnownHostsFile=web-2.known_hosts` + `HostKeyAlgorithms=ecdsa-sha2-nistp256`, then installs the `iptables -t nat` REDIRECT for the SSH apply step. Push trigger paths include `apps/web-platform/infra/**` — **merging the pin update fires the apply and self-verifies**.
- `.github/workflows/apply-deploy-pipeline-fix.yml` — push paths include `apps/web-platform/infra/web-2-ssh-host-key.pub`; same pinned-forward shape; its `terraform_data.deploy_pipeline_fix_web2` `triggers_replace` includes `file("web-2-ssh-host-key.pub")` AND `hcloud_server.web["web-2"].id`, so the pin merge re-delivers the deploy-pipeline file set to the reborn host automatically.
- `apps/web-platform/infra/firewall.tf` — `hcloud_firewall.web` permits `tcp/22` inbound from every `var.admin_ips` entry (`dynamic "rule" { for_each = var.admin_ips }`); admin-IP egress to web-2's public :22 is the authorized operator path. `var.admin_ips` lives in Doppler `prd_terraform`; `/soleur:admin-ip-refresh` exists if the operator's egress is not allowlisted.
- `tests/scripts/lib/web-host-replace-gate.sh` + `tests/scripts/lib/stock-preflight-gate.sh` — the replace path's plan-shape gate and destroy-before-create stock preflight already exist and ran in `web_host_replace` (the `stock_abort_closing` call at the `web-host-replace` arm names #6393/#6400 — the stranded-fleet incident the brief references). A re-replace needs no new guard machinery.
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md` §"What the replace does NOT restore" — documents that a replace rotates web-2's sshd host key and the next apply-deploy-pipeline-fix run "fails closed at the end-to-end probe until `scripts/capture-web-2-host-key.sh <ip>` re-captures `web-2-ssh-host-key.pub`". Exactly this documented post-replace step is what the 10-28 rebirth missed (the #10585 gap manifesting).

### Institutional learnings applied

- `2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md` — separate the network leg from the credential leg; here the *pin* leg was the actual failure, a third leg the learning's taxonomy implies (identity ≠ reachability ≠ credential).
- `2026-03-20-ssh-forced-command-cloud-init-parity-gaps.md` — cloud-init parity gaps break CI auth silently.
- `hr-ssh-diagnosis-verify-firewall` — L3→L7 hypothesis order enforced below; the firewall leg is verified by the run artifact itself.
- `hr-no-ssh-fallback-in-runbooks`, `hr-all-infrastructure-provisioning-servers` — the mutating repair arms are expressed through committed instruments (`capture-web-2-host-key.sh`, a `terraform_data` twin if needed), not ad-hoc `ssh` writes.

## Hypotheses (L3 → L7, per plan-network-outage-checklist)

1. **L3 — Firewall allow-list.** [verified by artifact] `hcloud_firewall.web` permits tcp/22 from `var.admin_ips` for the operator path; for the CI path the bastion forward's TCP session *established* (run 40744937376 shows the forward up on 127.0.0.1:2223 and web-2's sshd answering kex — a firewall drop cannot present a host key). The operator-egress half is verified at capture time by `scripts/capture-web-2-host-key.sh` succeeding or failing the keyscan; if the egress drifted, `/soleur:admin-ip-refresh` is the documented remedy (runbook `admin-ip-drift.md`).
2. **L3 — DNS / routing.** [verified by artifact] the forward delivered web-2's banner+key through the web-1 bastion; no DNS in this path (numeric IPs, `hcloud_server_network.web["web-2"].ip` from state).
3. **L7 — TLS/proxy.** [not applicable] — SSH path, no TLS intermediary; opt-out justification: the kex transcript reached host-key presentation.
4. **L7 — Application (sshd auth).** [partially verified → scheduled diagnostic] the pin mismatch is *proven* (offered `SHA256:OB3/…` ≠ pinned `SHA256:prjb…`). Whether the CI pubkey is *additionally* absent is unproven — `cloud-init.yml`'s `ssh_authorized_keys` block should have delivered it at birth, but the run log never reached auth, so no `Failed publickey` line exists to check. Scheduled: operator-side journal + authorized_keys read in Phase B.

### Network-Outage Deep-Dive

| Layer | Status | Verification artifact |
|---|---|---|
| L3 — firewall allow-list | verified | Run 40744937376 `apply` log: `ssh -N -L` forward established through web-1 (`web-2 forward is up on 127.0.0.1:2223`) and web-2's sshd presented its ECDSA host key on the forwarded channel — a firewall drop cannot present a key. Operator half: `hcloud_firewall.web` `dynamic "rule"` over `var.admin_ips` permits tcp/22; egress membership is re-proven at capture time by the keyscan itself (script refuses on failure). |
| L3 — DNS / routing | verified | Numeric IPs only — web-2's public/private addresses are read from `terraform show -json` (`hcloud_server.web["web-2"].ipv4_address`, `hcloud_server_network.web["web-2"].ip`); the forward delivered kex bytes end-to-end. |
| L7 — TLS / proxy | not applicable | SSH path; no TLS intermediary. Opt-out artifact: the kex transcript reached host-key presentation in the run log. |
| L7 — application (sshd auth) | partially verified → Phase B closes it | `Host key verification failed.` is a client-side verdict; web-2's sshd log (`Connection closed by 10.0.1.10 port 58066 [preauth]`, quoted in #11445) is the matching server-side view — client aborted post-kex, before auth. No `Failed publickey` line is quoted, so the missing-key hypothesis is NOT yet refuted; Phase B's journal + authorized_keys read is the discriminating evidence. |

**Gap before implementation:** none blocking Phase A — the stale pin is proven by repo state + run log alone. Phase B exists precisely to close the L7 half before any conditional arm ships.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Verified reality | Plan response |
|---|---|---|
| #11445: "The reborn host does not accept the CI SSH key (auth rejection, not L3/L4)" | Run 40744937376 `apply` log: `Host key for web-2 has changed and you have requested strict checking. / Host key verification failed.` — client-side abort on `StrictHostKeyChecking` against the stale committed pin; auth never attempted | Re-pin is the unconditional primary arm; pubkey install is demoted to a diagnostic-gated conditional arm; re-replace demoted to fallback |
| #11445: repair needs "install the CI deploy pubkey … or a guarded web-2 re-replace" | The committed pin (`captured: 2026-10-07`) provably predates the 10-28 host; `web-host-replace.md` documents the re-capture as the routine post-replace step | Both authorized paths kept as conditional arms — the lighter repair the runbook prescribes is exercised first because the pin defect is proven regardless |
| Implied: "replace made the host correctly; only CI can't reach it" | `terraform_data.deploy_pipeline_fix_web2`'s `server_id` trigger re-fired on the rebirth but could not deliver (key+pin); birth-frozen state persists until the pin lands | The pin merge re-fires that resource (its `triggers_replace` includes the pin file) — the merge itself drains the deferred delivery |

## Proposed Solution

Repair in evidence order — the provable defect first, the destructive path last. **All host-touching steps run through committed instruments** (the capture script; a `terraform_data` sibling if the conditional arm fires), not ad-hoc `ssh` writes (`hr-all-infrastructure-provisioning-servers`); read-only on-host diagnostics are the exception, and they are the *evidence source* for the conditional arm.

### Phase A — Re-capture the web-2 host-key pin (unconditional; the only change every hypothesis needs)

1. Operator step (admin-IP-allowlisted egress, this worktree): `bash scripts/capture-web-2-host-key.sh 204.168.189.200` — soleur-web-2's public IPv4 per the issue; confirm against `terraform output` or the Hetzner API at run time.
   - Script refusals are the guard: non-ecdsa keyset, CI env, or a conflicting operator `known_hosts` entry each abort before write (ADR-237).
   - If the egress is not allowlisted: `/soleur:admin-ip-refresh` first (it needs its own ack per `hr-menu-option-ack-not-prod-write-auth`).
2. The regenerated `apps/web-platform/infra/web-2-ssh-host-key.pub` (new `# captured:` timestamp, `# fingerprint: SHA256:…` matching the offered `SHA256:OB3/fH+fWhoTolCCx9rNMtuW0shPUONHNbhYxRFyqic` — compare against the run-log value as a cross-check before committing) is committed to this branch.

### Phase B — On-host read-only diagnostic through the admin-IP sshd path (unconditional; decides Arm C)

An operator-local read-only session to web-2's public IP over the firewall's admin-IP tcp/22 rule (key = `hcloud_ssh_key.default`, injected at create; `PermitRootLogin prohibit-password` permits pubkey) collects three facts:

1. Presence check: `grep -c "ssh-ed25519" /root/.ssh/authorized_keys` on the host, compared against `terraform output -raw ci_ssh_public_key_openssh` (read in `apps/web-platform/infra` under `doppler run -p soleur -c prd_terraform --name-transformer tf-var`) — is the CI pubkey present?
2. Journal window: `journalctl -u ssh --since "2026-10-28 18:30" --until "2026-10-28 18:45" | grep -E "Failed publickey|Connection closed"` — does the log show only `[preauth]` closes (host-key-abort signature) or also `Failed publickey` (missing-key signature)?
3. Boot completeness: `cloud-init status --long` — did the birth render complete (an incomplete boot reframes the whole repair toward the fallback)?

Decision: key present + `[preauth]`-only log → **ship Phase A alone**. Key absent (or journal shows `Failed publickey`) → **proceed to Phase C**. cloud-init incomplete beyond key delivery → **evaluate the fallback arm**.

### Phase C — Conditional: land `terraform_data.root_authorized_keys_web2` (the IaC twin of the web-1 resource) + operator-local targeted apply

Only if Phase B shows the pubkey absent:

1. `apps/web-platform/infra/ci-ssh-key.tf`: add `resource "terraform_data" "root_authorized_keys_web2"`, mirroring the web-1 twin with: `triggers_replace = { pubkey = sha256(tls_private_key.ci_ssh.public_key_openssh), server_id = hcloud_server.web["web-2"].id }`; `connection { host = hcloud_server.web["web-2"].ipv4_address, user = "root", private_key = var.ci_ssh_private_key, agent = var.ci_ssh_private_key == null, host_key = local.web_2_ssh_host_key, script_path = "/root/tf-root-authorized-keys-web2-%RAND%.sh", timeout = "15m" }` (15m mirrors the measured-slow web-2 route in `egress_gateway_web2`); same idempotent `grep -qxF … || echo … >>` inline block.
2. `plugins/soleur/test/terraform-target-parity.test.ts`: extend `EXCLUSION_ALLOWLIST` with `"root_authorized_keys_web2"` — operator-local by construction, same class as its web-1 twin (CI cannot deliver the key that admits it).
3. `apps/web-platform/infra/web-host-provisioner-parity.test.sh`: add the EXT_RESIDENCE entry `terraform_data.root_authorized_keys_web2 → hosts:["web-2"], reason: <named>` (census at the `ci-ssh-key.tf` block; stale-entry arm requires it).
4. `apps/web-platform/infra/server.tf`: update the running-web-2 delivery census comment on `egress_gateway_web2` (per `plan-host-fanout.md` "Mechanical enforcement") and the `deploy_pipeline_fix_web2` header's "recovery: operator ADMIN_IPS append" note to name the twin.
5. Operator step (local worktree; agent auth via `hcloud_ssh_key.default`; firewall tcp/22 admin path): `cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.root_authorized_keys_web2 -input=false`. Idempotent; re-verifiable.

**Precedent diff (Phase 4.4 gate):** the twin is pattern-bound with two sibling precedents — `terraform_data.root_authorized_keys` (ci-ssh-key.tf: same trigger-shape, same `grep -qxF … || echo … >>` idempotent inline, same operator-local classification) and `egress_gateway_web2` (server.tf: the web-2 connection shape — `private_key`/`agent` dual-mode, `local.web_2_ssh_host_key`, `%RAND%` script_path, 15m timeout). The diff from the web-1 twin is exactly `host`/`host_key`/`script_path`/timeout/`server_id` trigger — nothing else varies. No novel pattern.

### Phase D — Verification (the merge is the trigger)

1. Merge the PR. Push paths (`apps/web-platform/infra/**` for `apply-web-platform-infra.yml`; the `.pub` file explicitly for `apply-deploy-pipeline-fix.yml`) fire both workflows on the merge commit.
2. `apply-web-platform-infra.yml` `apply` job: forward step must pass the end-to-end probe, then `Terraform apply (SSH-provisioned resources, over the bridge)` delivers the deferred `*_web2` set (property 3 drains automatically).
3. `apply-deploy-pipeline-fix.yml`: the pin-file hash re-fires `terraform_data.deploy_pipeline_fix_web2` (`triggers_replace` includes `file("web-2-ssh-host-key.pub")` and `hcloud_server.web["web-2"].id`) — the birth-frozen file set refreshes.
4. Confirm green via `gh run list --workflow <name> --branch main -L 3 --json conclusion` — pull the data, do not eyeball (`hr-no-dashboard-eyeball-pull-data-yourself`).

### Fallback (documented, not a phase): guarded re-replace

If Phase B shows the host broken beyond key material (incomplete cloud-init, sshd damage): dispatch `apply_target=web-host-replace`, `web_host_key=web-2`, `confirm=REPLACE-web-2`, `image_tag=<released-tag>` (the input's own description requires a pin when reading web-1's /health is wrong). The path's own gates — `web_host_replace_gate` (exact-one-replace plan shape) + `stock_preflight_gate` (destroy-before-create stock proof, the #6393/#6400 lesson — the brief's "verify cx33 stock" concern is enforced in-band by this gate, failing closed when `HCLOUD_TOKEN` is unreadable or stock is absent) — plus the `web-platform-infra-apply` environment reviewer carry the destruction authority. Note the replacement host will again need Phase A (a new host presents yet another host key) — this is why re-pin, not re-replace, is primary.

## Technical Considerations

- **Chicken-and-egg:** CI can never deliver the CI key to a host that lacks it — `root_authorized_keys_web2` is therefore operator-local by construction (`EXCLUSION_ALLOWLIST`, like its web-1 twin) and `agent = var.ci_ssh_private_key == null` flips auth to the operator's agent key locally. Do NOT wire it into either workflow's `-target` list.
- **Key rotation semantics preserved:** `server_id` in the twin's `triggers_replace` re-fires it on the next replace (cattle parity with `egress_gateway_web2`); a `tls_private_key.ci_ssh` re-roll re-fires on the pubkey hash (mirroring the web-1 twin's behavior).
- **NFRs:** reliability (ops pipeline red→green); security posture unchanged (pin = existing ADR-237 mechanism; no new ingress, no new credentials — the pubkey is public material).
- **No new autonomous-task surface** (no workflow/cron/Inngest additions) → Task Design gate skipped. **No new guard/gate/lint shipped** → Guard Contract gate skipped (the discoverability probe asserts a repaired artifact, it is not a CI gate).

## Files to Edit

- `apps/web-platform/infra/web-2-ssh-host-key.pub` — regenerated by `scripts/capture-web-2-host-key.sh` (operator-executed; the script owns the file's format).
- *(conditional — Phase C only)* `apps/web-platform/infra/ci-ssh-key.tf` — add `terraform_data.root_authorized_keys_web2`.
- *(conditional — Phase C only)* `plugins/soleur/test/terraform-target-parity.test.ts` — `EXCLUSION_ALLOWLIST` + the census test's expected set.
- *(conditional — Phase C only)* `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — EXT_RESIDENCE entry for the web-2 twin.
- *(conditional — Phase C only)* `apps/web-platform/infra/server.tf` — delivery-census + recovery-note comment updates.

## Files to Create

- `scripts/web2-ssh-pin-current.sh` — the Observability `discoverability_test` wrapper (below). Reads the committed pin, asserts exactly one non-comment `ecdsa-sha2-nistp256` key line, asserts the `# fingerprint:` header differs from the known-stale predecessor fingerprint (`SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE`), prints `PIN_CURRENT` on success, exits 1 with a named reason otherwise. Pure `bash`+`grep`+`awk` — no `ssh-keygen` dependency in the Check-10 sandbox.

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — web-2 is the standby host at LB weight 0 (`lb-weight-gate.sh` keeps it unpooled until the ADR-143 gate opens); the blast radius is the internal ops pipeline staying red and web-2's standby provisioning staying stale.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing exposed — the pin file is public host-key material (its whole design purpose per ADR-237); the CI *public* key appended in the conditional arm is likewise public material.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** no user data, no serving surface, no new trust boundary — an ops-internal repair of a documented mechanism.
- `threshold: none, reason:` the diff touches `apps/web-platform/infra/` (a preflight-flagged sensitive path) but changes only a committed host-key pin plus, at most, an idempotent authorized_keys provisioner — no user-data or serving-weight surface.

## Observability

```yaml
liveness_signal:
  what: "apply-web-platform-infra.yml 'SSH forward to web-2' step + 'Terraform apply (SSH-provisioned resources)' step exit green on the merge-triggered run — the signal this repair restores"
  cadence: per push-to-main touching apps/web-platform/infra/**
  alert_target: "operator email via notify-apply-failure (existing, fired on every red run since 10-28)"
  configured_in: ".github/workflows/apply-web-platform-infra.yml (apply job); .github/actions/notify-ops-email"

error_reporting:
  destination: "GitHub Actions run log + notify-apply-failure email"
  fail_loud: "::error::end-to-end web-2 SSH probe failed … at the forward step; job conclusion: failure"

failure_modes:
  - mode: "pin re-stales on a future web-2 replace (#10585 class)"
    detection: "the same ::error:: on the next post-replace apply run (fail-closed pin mismatch)"
    alert_route: "notify-apply-failure email"
  - mode: "CI pubkey additionally absent on web-2 (Phase B gate)"
    detection: "post-pin run's e2e probe fails with Permission denied (publickey) instead of host-key failure — a DIFFERENT, diagnosable red"
    alert_route: "notify-apply-failure email; Phase C ships the twin"
  - mode: "committed pin malformed (wrong file content merged)"
    detection: "local.web_2_ssh_host_key regex fails to parse at terraform plan — red before apply"
    alert_route: "apply-web-platform-infra.yml plan step failure"

logs:
  where: "GitHub Actions step logs (/tmp/web2-forward.log tail on failure); web-2 sshd journal via admin-IP path for diagnostics"
  retention: "Actions run retention; journald persistent on host (journald_persistent_web2)"

discoverability_test:
  command: "bash scripts/web2-ssh-pin-current.sh"
  expected_output: "PIN_CURRENT"
```

## Encryption Posture

```yaml
at_rest:
  - store: "apps/web-platform/infra/web-2-ssh-host-key.pub (repo file, not a data store)"
    mechanism: "not-applicable — public key material committed by design (ADR-237); no secret at rest"
    evidence: "scripts/capture-web-2-host-key.sh header contract (method, UTC date, SHA256 fingerprint, cross-check)"
    defends_against: "MITM substitution of web-2's identity on the bastion-forward path"
    does_not_defend: "a compromised admin-IP egress capturing a poisoned key (the operator known_hosts cross-check is the partial cover); repo-write compromise"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available — ssh-keyscan from an admin-IP egress (Phase A is exactly that read)"
in_transit:
  - connection: "operator machine -> web-2 public :22 (keyscan read; conditional Phase C SSH session)"
    enforced_at: "apps/web-platform/infra/firewall.tf dynamic rule over var.admin_ips; scripts/capture-web-2-host-key.sh refusal set"
    tls: "n/a — SSH2; host-key identity verified by the committed pin + operator known_hosts cross-check"
    cert_verification: "on (pinned host key — the property this plan restores)"
    does_not_defend: "an attacker already inside an admin source IP"
    disclosed_as: "not-publicly-claimed"
  - connection: "CI runner -> web-1 bastion -> web-2 private :22 (existing, unchanged)"
    enforced_at: ".github/workflows/apply-web-platform-infra.yml forward step + write-known-hosts.sh pins"
    tls: "n/a — SSH2 with pinned ecdsa-sha2-nistp256 host keys both hops"
    cert_verification: "on (StrictHostKeyChecking=yes + HostKeyAlias pins — the check that caught this defect)"
    does_not_defend: "CI-private-key compromise (out of this plan's scope; rotation path is the same ci-ssh-key.tf machinery)"
    disclosed_as: "not-publicly-claimed"
```

## Infrastructure (IaC)

### Terraform changes

- Conditional (Phase C only): `apps/web-platform/infra/ci-ssh-key.tf` gains `terraform_data.root_authorized_keys_web2`; `server.tf` comment updates; test-census updates in `web-host-provisioner-parity.test.sh` and `plugins/soleur/test/terraform-target-parity.test.ts`. Providers: existing `hashicorp/terraform_data` — no new providers, no new variables (`var.ci_ssh_private_key`, `local.web_2_ssh_host_key`, `local.ci_ssh_pubkey` already exist). No new sensitive variables (pubkey is public; `tls_private_key.ci_ssh` already in state).
- Unconditional: no `.tf` changes — the pin file is a data file.

### Apply path

- (b-variant) targeted operator-local apply of the new `terraform_data` only when the conditional arm fires (`terraform apply -target=terraform_data.root_authorized_keys_web2` from a local worktree, agent auth over the admin-IP firewall rule). Downtime/blast-radius: zero — an idempotent append to `/root/.ssh/authorized_keys` on a standby host. The fallback re-replace uses the workflow's own `web_host_replace_gate` + `stock_preflight_gate` (in-band cx33 stock proof — addresses the brief's fleet-stranding concern without new machinery).

### Host fan-out

- The conditional twin IS the host fan-out entry: `root_authorized_keys` (web-1) ↔ `root_authorized_keys_web2` (web-2). Class per `plan-host-fanout.md`: **twin** — both hosts need the pubkey for symmetric CI auth; the artifact's fresh-boot counterpart is cloud-init `ssh_authorized_keys` (parity-test compliant by the existing counterpart rule). `EXT_RESIDENCE` gains the (file, `terraform_data.root_authorized_keys_web2`, hosts:[web-2]) row. The running-web-2 delivery census comment on `egress_gateway_web2` updates with the new channel.

### Distinctness / drift safeguards

- No dev/prd confusion surface (single prd root). `server_id` in `triggers_replace` pins the resource to the current web-2 instance id (re-fires on replace). The pin file's `# captured:` + `# fingerprint:` header is the drift evidence the next replace's operator reads.

### Vendor-tier reality check

- None — Hetzner, no free-tier-gated resource.

## Architecture Decision (ADR/C4)

No new architectural decision — the repair applies **ADR-237** (ssh host keys are pinned; re-capture is the routine re-key path) exactly as written, and the conditional arm reuses the **ADR-220** SSH-delivery shape (dedicated terraform_data, pinned host key, credential-tiered key material).

**C4 check (completeness mandate executed):** enumerated (a) external human actors — none added (the operator already exists); (b) external systems — none added (Hetzner, existing); (c) containers/data-stores — none added (a repo file + a provisioner resource on an existing host); (d) actor↔surface relationships — unchanged (the admin-IP SSH edge operator→web-2 already exists for `hcloud_ssh_key.default`). The work phase MUST re-run the three-file read (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) before writing "no C4 impact" into the PR, and cite the elements checked; expected impact: none.

## Downtime & Cutover

**Offline-inducing operation.** The unconditional path (pin re-capture + commit) mutates no running resource — zero downtime. The conditional arm appends one line to `/root/.ssh/authorized_keys` on web-2 — no restart, no service contact.

**Serving-surface evaluation.** web-2 is the standby host at Cloudflare LB weight 0 (`lb-weight-gate.sh`; ADR-143 keeps it unpooled until the runtime-bind gate opens) — nothing it does or fails to do serves traffic, so even the fallback `web-host-replace` dispatch takes no serving surface offline. Zero-downtime is the *default state* of every arm here, not a cutover design requirement: there is no in-flight request surface on the host.

**Residual risk.** The fallback re-replace destroys-then-creates a *standby* resource — a fleet-capacity (HA-margin) event, not a serving event; `web_host_replace_gate` + `stock_preflight_gate` bound it, and the workspaces volumes survive by omission (`prevent_destroy` + gate backstops). Authorization for that arm comes from the `web-platform-infra-apply` environment reviewer — the workflow's existing gate, unchanged.

## Guard Contract

### Guard 1 — web2-ssh-pin-current probe (`scripts/web2-ssh-pin-current.sh`)

**Property.** The committed `apps/web-platform/infra/web-2-ssh-host-key.pub` is parseable pin material for the CURRENT web-2: exactly one non-comment `ecdsa-sha2-nistp256` key line, and its `# fingerprint:` header does not equal a fingerprint recorded for a predecessor host.

**Assembly.** Every consumer of web-2's host identity flows through this one file: `local.web_2_ssh_host_key` (server.tf regex) feeds every `terraform_data` connection dialing `hcloud_server.web["web-2"]`, and `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh` renders it into the known_hosts for BOTH CI forwards (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`). Single chokepoint — the committed file itself.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Pin file's `# fingerprint:` header equals the predecessor fingerprint `SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE` (the stale-pin defect — file is parseable, property still fails) | RED |
| 2 | Pin file contains zero non-comment key lines (emptied by a bad write — the guard's own "0 checked" shape) | RED |
| 3 | Pin file contains two non-comment key lines (a second member appended after a compliant first) | RED |
| 4 | Probe edited so its key-line extraction drops the `!/^#/` comment filter — a header line then counts as a key line | RED — harness row: the probe's own extraction is mutated, not the artifact |
| 5 | A valid post-rebirth pin (any fingerprint outside the predecessor set, exactly one ecdsa key line — e.g. the captured `SHA256:OB3/…` file) | PASS — must-pass input differing from the incumbent stale file in exactly the way the contract permits |

**Anchor.** The predecessor fingerprint is a probe constant anchored to the incident's own evidence OUTSIDE the commit — run 40744937376's log (`SHA256:OB3/…` offered) plus the pre-fix committed file (`SHA256:prjb…` pinned). A diff weakening both file and probe constant is the residual risk; the run-log artifact is the anchor. The probe encodes "not a known-predecessor fingerprint", not "equals today's" — the next legitimate re-capture stays green without editing the probe.

## Domain Review

**Domains relevant:** Engineering (infrastructure change — CTO-leader per `brainstorm-domain-config.md`)

### Engineering

**Status:** error — no agent-spawning tool is available in this harness (plan ran inside a one-shot Task subagent); the orchestrator self-assessed per the domain's Assessment Question ("significant architectural decisions, infrastructure changes").

**Assessment:** the change is repair-scope, not architecture-scope: it re-executes ADR-237's documented re-key path and (conditionally) extends an existing IaC twin. The real architecture question — replace-path first-deploy verification — is already tracked as #10585 and deliberately out of scope. Technical forks this plan surfaced are recorded in `knowledge-base/project/specs/feat-one-shot-11445-web2-ci-ssh-preauth/decision-challenges.md` as `pending - assumed:` rows (no CTO subagent spawnable).

### Product/UX Gate

Not relevant — the mechanical UI-surface scan over `## Files to Edit`/`## Files to Create` finds no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or ui-surface term. Tier: NONE.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Restore CI-key authorized access on web-2" [issue #11445 Recommended fix] | Phase A + Phase D | mapped |
| 2 | "install the CI deploy pubkey via an admin-IP sshd path" [issue #11445, path (a)] | Phase B diagnostic + conditional Phase C (`terraform_data.root_authorized_keys_web2` + operator-local apply) | mapped (conditional on diagnosis) |
| 3 | "a guarded web-2 re-replace baking the key in cloud-init — verify cx33 stock in the target location first" [brief + issue #11445, path (b)] | Fallback arm (workflow's own `stock_preflight_gate` is the in-band stock check) | mapped as fallback — evidence order places it last because the proven defect is the stale pin, which a re-replace does not fix |
| 4 | "10585 … the underlying gap" [brief] | `## Deferred / Out of Scope` | descoped — justification: explicitly listed as context, not work target; the gap ("replace does not verify first deploy/key provisioning") has its own open issue |
| 5 | "6406 (web-2-recreate + verify arc), 11402 (web-2 LUKS evidence on the predecessor host)" [brief] | `## Deferred / Out of Scope` | descoped — justification: context issues; the pin repair is independent and the LUKS-evidence arm belongs to the birth-side workstream |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase A pin re-capture + `web-2-ssh-host-key.pub` edit | "Restore CI-key authorized access on web-2" | asked (via the repair ask; mechanism chosen by evidence — the stale pin is the proven failure, and `web-host-replace.md` documents re-capture as the routine post-replace step) |
| Phase B on-host diagnostic | "the soleur-web-platform firewall permits tcp/22 from admin addresses" | inferred — justification: evidence gate between the two authorized repair paths; read-only, and the run log cannot show which of the two remaining hypotheses (missing key vs sshd-layer) holds without it |
| Phase C conditional `terraform_data.root_authorized_keys_web2` + census/test edits | "install the CI deploy pubkey via an admin-IP sshd path" | asked (conditional — only if Phase B shows the key absent; expressed through IaC per `hr-all-infrastructure-provisioning-servers` rather than a raw append) |
| `scripts/web2-ssh-pin-current.sh` | — | inferred — justification: Phase 2.9 observability gate requires a local, ssh-free discoverability command discriminating this plan's repaired artifact; `ssh-keygen`/whole-suite forms fail Check-10's sandbox constraints |
| Fallback re-replace arm | "a guarded web-2 re-replace baking the key in cloud-init" | asked (kept as documented fallback; workflow gates already enforce the stock preflight the brief demands) |

### Split Assessment

- Subsystems touched: 2 — `apps` (web-platform infra), `scripts`
- Planned files: 2 unconditional + 4 conditional | Estimated changed lines: ~30 unconditional (+ ~120 conditional)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — not met
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `apps/web-platform/infra/web-2-ssh-host-key.pub` carries the post-rebirth key: `# fingerprint:` header ≠ `SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE` and matches the key web-2's sshd offered in run 40744937376 (`SHA256:OB3/fH+fWhoTolCCx9rNMtuW0shPUONHNbhYxRFyqic`), with a `# captured:` timestamp ≥ 2026-10-28.
- [ ] AC2 — `bash scripts/web2-ssh-pin-current.sh` exits 0 and prints `PIN_CURRENT`.
- [ ] AC3 — The first `apply-web-platform-infra.yml` run on the merge commit completes the `SSH forward to web-2 through the web-1 bastion` step and runs `Terraform apply (SSH-provisioned resources, over the bridge)` to a non-skipped conclusion (verified via `gh run view`/`gh run list`, not the dashboard).
- [ ] AC4 — Phase B evidence is recorded on #11445 (comment): authorized_keys key-presence verdict + the journal grep result + `cloud-init status` outcome — whichever arm it selected.
- [ ] AC5 — If (and only if) Phase B found the pubkey absent: `terraform_data.root_authorized_keys_web2` exists in `ci-ssh-key.tf`, `EXCLUSION_ALLOWLIST` in `terraform-target-parity.test.ts` includes it, `web-host-provisioner-parity.test.sh` EXT_RESIDENCE includes it, and the host's `/root/.ssh/authorized_keys` contains `local.ci_ssh_pubkey` post-apply (operator-side grep output captured on the issue).
- [ ] AC6 — #11445 is commented with the root-cause correction (host-key pin, not auth rejection) citing run 40744937376's log lines — the issue's stated diagnosis is wrong and the record must not stand uncorrected.

## Test Scenarios

1. `scripts/web2-ssh-pin-current.sh` against the CURRENT stale pin → exits 1 (red before repair). After Phase A writes the new pin → exits 0, `PIN_CURRENT` (the probe discriminates the exact defect).
2. Shape: pin file has exactly one non-comment line matching `ecdsa-sha2-nistp256 AAAA…` — run `write-known-hosts.sh web-2 <pin> /tmp/kh` locally to prove the CI writer accepts it (the same shape check every CI consumer applies; runs locally, no host contact).
3. Conditional arm only: `terraform-target-parity.test.ts` and `web-host-provisioner-parity.test.sh` (incl. its mutation suite's EXT_RESIDENCE arms) run green with the new twin registered; `terraform plan` on the root shows `terraform_data.root_authorized_keys_web2` create-only.

## Open Code-Review Overlap

- `#2197` (billing refactor scope-out) mentions `apps/web-platform/infra/server.tf` in a hypothetical `count = 2` sentence. **Disposition: acknowledge** — different concern (rate-limiter singleton documentation), our conditional server.tf edit is comment-only; no fold-in.

## Deferred / Out of Scope

- **#10585** — host-replace does not verify first deploy / key provisioning (the systemic gap that let this recur). Context issue; its fix is a workflow-verification change, not this repair.
- **#6406** — web-2-recreate + verify arc; the predecessor-host verification saga. Context only.
- **#11402** — web-2 LUKS evidence red. Context only; if Phase B's `cloud-init status` read implicates the birth path, escalate there rather than widening this plan.
- Deferred by the brief and NOT touched: #11388, #11266, #6027, #11308, #10835, #10768, #8965.
- **Note for #10585's owner:** the conditional twin's *rotation* rationale (`server.tf` `deploy_pipeline_fix_web2` header — "a DEPLOY_SSH_PRIVATE_KEY rotation … not web-2's birth-frozen authorized_keys") is a candidate permanent twin deliverable under that issue even when Phase B clears the key.

## Sharp Edges

- **Do NOT run `ssh-keyscan` or any SSH contact from this pipeline/CI** — `scripts/capture-web-2-host-key.sh` refuses `CI`/`GITHUB_ACTIONS` by design (#7226 no-TOFU-in-CI). The pin update is operator-executed output committed to this branch.
- **Do NOT wire `root_authorized_keys_web2` into a CI `-target` list** — CI cannot deliver the credential that admits it; `terraform-target-parity.test.ts` enforces the exclusion-allowlist shape.
- **Do NOT dispatch `web-host-replace` as the first move** — it cannot fix a stale pin, destroys before it creates, and its own stock gate exists precisely because cx33 has gone 0/6-orderable before (#6393/#6400, measured 0-of-3 EU DCs 2026-07-26).
- **The issue's conclusion is wrong — correct it on the record (AC6)** before work; otherwise later triage inherits the auth-rejection misframe.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6 — filled above (`none` + scope-out reason for the sensitive path).

## References

- Issue: #11445; failing run `40744937376` (`apply` job, `SSH forward to web-2` step, 2026-10-28T18:38Z); replace run `40720815376`.
- ADRs: ADR-237 (host-key pinning), ADR-220 (git-data root-access precedent for dedicated keys), ADR-148 (web-host-replacement gated dispatch), ADR-143 (LB-weight gate).
- Runbooks: `knowledge-base/engineering/operations/runbooks/web-host-replace.md` §"What the replace does NOT restore"; `git-data-luks-cutover-5274.md` §"Re-capturing web-2's host key"; `admin-ip-drift.md`.
- Scripts/gates: `scripts/capture-web-2-host-key.sh`; `tests/scripts/lib/web-host-replace-gate.sh`; `tests/scripts/lib/stock-preflight-gate.sh`; `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh`.
- Learnings: `2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md`; `2026-03-20-ssh-forced-command-cloud-init-parity-gaps.md`; `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`.
- Context issues: #10585, #6406, #11402, #11372 (resolved); prior re-pin PRs #9212, #9305, #9665, #9733.

## Plan Review

Not run — this harness exposes no agent-spawning tool for the review panel (headless pipeline arm). The plan's evidence spine is the run log itself; technical forks are persisted to `decision-challenges.md` with `pending - assumed:` rulings per the delegation rule.
