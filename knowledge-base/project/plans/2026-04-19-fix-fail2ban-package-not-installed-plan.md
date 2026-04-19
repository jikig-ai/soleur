# Fix: fail2ban package not actually installed on prod — provisioner would fail

**Issue:** #2680
**Branch:** `feat-one-shot-2680-fail2ban-install`
**Type:** fix (bug — infrastructure)
**Priority:** priority/p2-medium
**Domain:** domain/engineering

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** 4 (Phase 1, Phase 2, Risks, Test Scenarios)
**Research sources:**

- Local learnings: `integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md` (precedent for the install-missing-package-via-terraform_data pattern)
- Local learnings: `2026-04-06-terraform-data-connection-block-no-auto-replace.md` (confirms `triggers_replace` is scoped to hash content only)
- Local learnings: `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` (confirms `agent = true` in connection block is the correct auth path)
- Local learnings: `2026-04-06-doppler-cli-checksum-cloud-init.md` (checksum-verified binary install pattern; does NOT apply here — apt packages are GPG-signed)
- AGENTS.md rules: `hr-all-infrastructure-provisioning-servers`, `cq-terraform-failed-apply-orphaned-state`, `hr-menu-option-ack-not-prod-write-auth`, `hr-the-bash-tool-runs-in-a-non-interactive`

### Key Improvements

1. **Precedent alignment** — The proposed fix directly mirrors the Doppler-install-via-terraform_data pattern from PR #1496 (documented in `2026-04-03-doppler-not-installed-env-fallback-outage.md`). That outage had the same root cause: cloud-init `ignore_changes = [user_data]` prevents package installs from reaching existing servers. The canonical fix is exactly what we're doing — a `terraform_data` resource with a `remote-exec` provisioner that installs the missing package idempotently.
2. **Explicit trigger-hash decision** — Deepened the Risks section with a citation to `2026-04-06-terraform-data-connection-block-no-auto-replace.md`: `triggers_replace` hashes only the content we opt in; the install step does NOT need to be in the hash. On the first apply after this PR merges, the resource re-runs (either because it's being created for the first time, or because it's already replaced after a prior partial-state recovery), and the install step executes exactly once. On steady-state applies, `dpkg -s` is the idempotency guarantee.
3. **Apt-signed package exception to `cq-docs-cli-verification`** — The plan prescribes `apt-get install -y fail2ban`. Unlike the Doppler binary install (which requires pinned version + SHA-256 per `2026-04-06-doppler-cli-checksum-cloud-init.md`), apt-installed packages are verified by apt's GPG-signed repository metadata. No version pin or checksum is required; Ubuntu's signed Packages file provides the trust boundary. This exception is documented in Phase 1 Rationale.
4. **Cloud-init module-order verification** — Cloud-init runs modules in a fixed order: `bootcmd` → `write_files` → `apt_configure` → `package_update_upgrade_install` (consumes `packages:`) → `runcmd`. The Phase 2 audit placed in `runcmd` therefore always runs AFTER the package-install stage. Cross-referenced: the existing `systemctl restart sshd` in `runcmd` (line 211 of cloud-init.yml) already depends on this ordering to restart sshd after `ssh_config.d/01-hardening.conf` is written — our audit follows the same pattern.

### New Considerations Discovered

- **Silent apt failures precedent:** The Doppler outage (#1493) had the SAME cloud-init miss pattern but for Doppler CLI instead of fail2ban. Same root cause, same fix topology (terraform_data + remote-exec with dpkg-s guard). That outage was detected by a production failure (500 error on `/api/repo/install`). This issue was caught by an operational recovery before apply — better, but the class recurs. The Phase 2 cloud-init audit is the systemic fix — it would have caught the Doppler miss at first-boot time for a fresh server.
- **CI apply-gap for `terraform_data` with SSH provisioners:** Per `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`, CI cannot apply these resources (dummy SSH key). This means the drift-detection workflow flags them; apply must happen locally post-merge OR via agent-based SSH. `server.tf:142-146` uses `connection { agent = true }` — confirmed the correct pattern. Post-merge operator note in Phase 5 acknowledges this.
- **The audit is not fully self-healing on a fresh server with a broken apt mirror.** If the initial `packages:` stage failed because the mirror was down, the audit's recovery install will hit the same dead mirror and fail. That's acceptable — the audit's job is to surface the failure, not to paper over it. Cloud-init exit-non-zero → operator intervention via Hetzner console.

## Overview

PR #2655 shipped `terraform_data.fail2ban_tuning` in `apps/web-platform/infra/server.tf`. The resource drops `/etc/fail2ban/jail.d/soleur-sshd.local`, reloads fail2ban, and asserts `fail2ban-client get sshd bantime = '600'`.

During operational recovery on 2026-04-19 we discovered the production server has no `fail2ban-client` binary — the package is missing. If `terraform apply` had run against prod, the `systemctl reload fail2ban` step would have failed, the positive-assertion `test "$(fail2ban-client get sshd bantime)" = '600'` would have errored, and the resource would have landed in a partial state requiring `terraform state rm` recovery per `cq-terraform-failed-apply-orphaned-state`.

The package absence on the existing server is an import-era artifact: `hcloud_server.web` has `ignore_changes = [user_data, ssh_keys, image]`, so cloud-init's `packages: [..., fail2ban, ...]` step never re-ran after import. It likely also failed silently at first boot (a journald "No space left on device" transient coincided with boot).

**Fix (primary):** `terraform_data.fail2ban_tuning` must install the fail2ban package before configuring it. Add an idempotent `dpkg -s fail2ban || apt-get install -y fail2ban` as the first `remote-exec` step, before the file provisioner.

**Fix (secondary):** Add a cloud-init post-boot audit that fails loudly if any declared `packages:` entry is missing from the host after first boot. This catches the same class of silent failures for future packages.

**Non-fix (out of scope):** Do not re-provision the current server to re-run cloud-init. The `ignore_changes = [user_data]` lifecycle rule stays; `terraform_data.fail2ban_tuning` is the correct delivery vector for the existing instance (mirrors the pattern of `disk_monitor_install`, `resource_monitor_install`, `fail2ban_tuning`, `deploy_pipeline_fix`, etc.).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Codebase reality (verified) | Plan response |
|---|---|---|
| `terraform_data.fail2ban_tuning` runs `systemctl reload fail2ban` and `fail2ban-client get sshd bantime` | Confirmed at `server.tf:138-173`; assertion lines are `server.tf:168-170` | Plan prepends a `dpkg -s fail2ban` install step before the existing `file` provisioner |
| `cloud-init.yml` lists `fail2ban` in `packages:` | Confirmed at `cloud-init.yml:3-6` (`packages: [curl, fail2ban, jq]`) | Plan adds a `runcmd` verification step that asserts each declared package is installed, so a silent first-boot apt failure exits the provisioner with a clear error |
| `hcloud_server.web` has `ignore_changes = [user_data]` | Confirmed at `server.tf:47-49` (`ignore_changes = [user_data, ssh_keys, image]`) | Plan does NOT rely on cloud-init changes taking effect on the existing server — the install step lives in `terraform_data.fail2ban_tuning`, which triggers on file hash change |
| Cloud-init `runcmd` already does `systemctl reload fail2ban \|\| systemctl restart fail2ban` | Confirmed at `cloud-init.yml:216-217` | For fresh servers this line requires fail2ban to be installed. The new `runcmd` package-audit step runs BEFORE this reload so missing packages surface before downstream failures |
| Initial provisioning log `/var/log/cloud-init-output.log` exists on the existing host | Unverified from Bash tool (no SSH). Issue body says "check the initial-provision log" | Plan includes an operator-side acceptance criterion: after apply, operator reads `/var/log/cloud-init-output.log` via SSH to confirm root cause. Not automatable from this repo — the log is read-only diagnostic per `cq-for-production-debugging-use` and `hr-all-infrastructure-provisioning-servers` |

## Open Code-Review Overlap

None. Ran `jq` queries against `gh issue list --label code-review --state open` for `server.tf`, `cloud-init.yml`, and `fail2ban` — only match is #2197 (SubscriptionStatus/billing), unrelated.

## Implementation Phases

### Phase 1 — Add package-install step to `terraform_data.fail2ban_tuning`

**File:** `apps/web-platform/infra/server.tf`

Edit `terraform_data.fail2ban_tuning` (currently lines 138-173) to add an install step BEFORE the existing `provisioner "file"`. The new step is a `remote-exec` provisioner:

```hcl
provisioner "remote-exec" {
  inline = [
    # Ensure fail2ban is installed before dropping the jail.d override.
    # The existing server is an import-era artifact — cloud-init's
    # `packages:` step never re-ran after import (ignore_changes = [user_data]),
    # and the initial run appears to have failed silently (#2680).
    # `dpkg -s` makes this idempotent: on servers where fail2ban is already
    # installed (fresh cloud-init provisioning), the install is skipped.
    "dpkg -s fail2ban >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq fail2ban; }",
  ]
}
```

Ordering: this new `remote-exec` MUST precede the existing `provisioner "file"` (which drops `soleur-sshd.local`) and the existing `remote-exec` (which reloads fail2ban and asserts bantime). Terraform executes provisioners in declaration order within a resource.

**Trigger-replace update:** The current `triggers_replace = sha256(file("${path.module}/fail2ban-sshd.local"))` only hashes the jail.d file. After this edit, the install step is part of the resource but not part of the trigger hash — that's acceptable because a one-time replay on a server where fail2ban is already installed is a no-op (`dpkg -s` short-circuits). Do NOT add the install step to the trigger hash — changes to the inline install block should not force replacement when the jail content is unchanged.

**Rationale for `dpkg -s` over `which fail2ban-client`:** `dpkg -s` checks package metadata, which is the source of truth for apt — it catches cases where a binary exists on `$PATH` but the package is not fully configured (e.g., interrupted install, which is how this instance likely ended up without fail2ban).

**Rationale for `apt-get update` inside the guarded branch:** Without `update`, a long-lived server with a stale apt cache may fail `install -y` with a 404 on a since-rotated package URL. The `-qq` flags keep CI drift-report output quiet when the install actually happens.

**Rationale for `DEBIAN_FRONTEND=noninteractive`:** fail2ban postinst can prompt on some Ubuntu point releases when it detects an existing jail.local; noninteractive avoids a hang in remote-exec.

### Phase 1 — Research Insights

**Precedent — Doppler install via terraform_data (PR #1496):** The canonical pattern for "cloud-init declared a package/binary but the existing server is missing it due to `ignore_changes = [user_data]`" is a `terraform_data` resource with a `remote-exec` provisioner that performs the install idempotently. See `knowledge-base/project/learnings/integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md` — that outage had the same topology (Doppler CLI instead of fail2ban) and the same root cause. The fix we're proposing here is a narrower variant of that pattern: we don't need a separate resource because `terraform_data.fail2ban_tuning` already exists; we're adding the install step as the first inline in its existing `remote-exec` block (see decision note below) or as a preceding `remote-exec` provisioner in the same resource.

**Decision — separate `remote-exec` provisioner vs. prepending to the existing inline list:** Prepending to the existing inline list would be fewer lines, but the existing `remote-exec` runs AFTER the `provisioner "file"` (which drops `soleur-sshd.local`). The file provisioner runs via SFTP/SCP to the destination path; if the fail2ban package is missing, `/etc/fail2ban/jail.d/` may not exist, causing the file upload to fail before we ever reach the reload/assert. Therefore the install step MUST precede the file provisioner, which means it must be its OWN `remote-exec` provisioner. This is the choice made in Phase 1. (Alternative: create the directory manually with `mkdir -p` before file upload, but that's fragile — if the package is present but the directory isn't, something else is wrong.)

**Apt package trust model vs. curl-pipe-to-shell:** `apt-get install -y fail2ban` is NOT subject to the supply-chain hardening rule in `knowledge-base/project/learnings/2026-04-06-doppler-cli-checksum-cloud-init.md` (pinned version + SHA-256 checksum). That rule applies to third-party binaries downloaded via `curl`. Apt fetches from signed Ubuntu repositories (GPG keys at `/etc/apt/trusted.gpg.d/ubuntu-keyring-2018-archive.gpg` on 24.04); the `Packages` file is signed, and each `.deb` has a SHA-256 in the signed manifest. Apt verifies signatures by default. No further hardening needed.

**SSH connection: `agent = true` confirmed correct.** Per `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`, `private_key = file(...)` fails silently when the key is passphrase-encrypted. `server.tf:141-146` already uses `connection { agent = true }` for `terraform_data.fail2ban_tuning`, which handles agent-backed passphrase decryption transparently. No change needed.

**CI apply-gap awareness:** Per the same learning, CI runs with a dummy SSH key and CANNOT apply `terraform_data` resources with SSH `remote-exec`. The drift-detection workflow flags these post-merge; apply happens locally by an operator with SSH agent access. This is a known constraint, not a bug. Post-merge acceptance criteria (Phase 5) are operator-side; no CI automation is prescribed here for the apply.

### Phase 2 — Add cloud-init package-audit step

**File:** `apps/web-platform/infra/cloud-init.yml`

Add a `runcmd` step that asserts every package in the `packages:` list is actually installed. Place it AFTER `package_update: true` / `packages:` have run and BEFORE the existing `systemctl reload fail2ban` line (so a missing fail2ban surfaces before the reload does).

The first `runcmd:` entry (currently `systemctl restart sshd`) runs after cloud-init's built-in `apt_configure` → `package_update_upgrade_install` stages have completed. Insert the audit immediately before that first runcmd line:

```yaml
runcmd:
  # Audit that cloud-init's packages: stage actually installed every declared
  # package. Cloud-init can silently drop package installs on transient failures
  # (apt lock contention, network error, "No space left on device" during first
  # boot) without failing the run. If any declared package is missing after
  # packages:, fail loudly so operator sees the root cause in
  # /var/log/cloud-init-output.log (#2680).
  - |
    set -e
    missing=""
    for pkg in curl fail2ban jq; do
      dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
    done
    if [ -n "$missing" ]; then
      echo "FATAL: cloud-init packages: stage did not install:$missing" >&2
      # Attempt one recovery install before giving up. This makes the first-boot
      # path self-healing for transient apt failures.
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq $missing
      # Re-verify; if still missing, exit non-zero so cloud-init marks the boot failed.
      for pkg in $missing; do
        dpkg -s "$pkg" >/dev/null 2>&1 || { echo "FATAL: $pkg still missing after recovery install" >&2; exit 1; }
      done
    fi

  # Apply SSH hardening immediately (drop-in written by write_files above)
  - systemctl restart sshd
```

**Decision — hardcode package list vs. parse `packages:`:** Hardcode `curl fail2ban jq` directly in the audit. The `packages:` list is 3 entries and rarely changes; parsing YAML inside a bash heredoc inside cloud-init is brittle. When the `packages:` list changes, the audit list changes in the same commit — enforced by Phase 4's verification that diffs both together.

**Decision — audit as runcmd vs. cloud-init `bootcmd`:** `runcmd` runs after `packages:` completes; `bootcmd` runs before. Audit must be AFTER, so `runcmd` is correct.

**Decision — why self-healing recovery:** A single recovery install attempt matches production philosophy for the existing-server `terraform_data.fail2ban_tuning` fix (dpkg-s then install). Consistency between the two code paths.

### Phase 2 — Research Insights

**Cloud-init module order:** cloud-init modules run in a fixed, documented order on each boot stage:

- **init** stage: `bootcmd`, `write_files` (via `cc_write_files`)
- **config** stage: `apt_configure`, `package_update_upgrade_install` (consumes `packages:`)
- **final** stage: `runcmd` (via `cc_runcmd`)

Therefore `runcmd` always runs after `packages:`. Source: cloud-init docs (`cloudinit.readthedocs.io/en/latest/reference/modules.html` — behavior consistent across cloud-init ≥ 20.x, which is shipped on Ubuntu 24.04). This is the same ordering assumption made by the existing `systemctl restart sshd` in `runcmd` (line 211 of cloud-init.yml), which depends on `write_files` having dropped `/etc/ssh/sshd_config.d/01-hardening.conf` first.

**Cloud-init package-install failure mode:** `package_update_upgrade_install` logs package install failures but does NOT exit the boot non-zero by default — the failure is recorded in `/var/log/cloud-init-output.log` but subsequent modules continue. This is why the original fail2ban miss went undetected until operational recovery. The Phase 2 audit explicitly converts silent failure → loud failure by running `dpkg -s` in `runcmd` and exiting non-zero on still-missing packages.

**`ignore_changes = [user_data]` means cloud-init runs exactly once:** The existing server was provisioned with this lifecycle rule (`server.tf:47-49`). Cloud-init's first-boot-only semantics mean that once `/var/lib/cloud/instance/` is populated, subsequent boots do NOT re-run `packages:` or `runcmd`. A `cloud-init clean` followed by reboot would re-run cloud-init, but that's destructive (wipes `/mnt/data`-adjacent state) and not something we want as a recovery mechanism. Hence the bridge via `terraform_data.fail2ban_tuning` on the existing server.

**Alternative considered and rejected — cloud-init `write_files` + systemd oneshot for package audit:** Could have used a systemd unit that runs `dpkg -s` every boot and alerts. Rejected because (a) complexity (another unit file + timer), (b) duplication with disk-monitor / resource-monitor patterns that already cover runtime state, (c) the audit's goal is to catch first-boot install failures, not runtime package removal. The `runcmd` audit is sufficient for the intended failure mode.

### Phase 3 — Update comment in existing fail2ban_tuning reload step

**File:** `apps/web-platform/infra/server.tf`

The existing comment on line 157-159 of `terraform_data.fail2ban_tuning`:

```hcl
# Reload picks up jail.d drop-ins without dropping active bans; fall back
# to restart if the installed fail2ban version does not support reload of
# bantime.* keys (some 0.10.x builds required restart; 1.0.2 on 24.04 is fine).
```

Add a one-line comment above the existing `file` provisioner, pointing at Phase 1:

```hcl
# The `remote-exec` above ensures the package is installed first. On the
# existing server (which was imported with ignore_changes = [user_data])
# cloud-init's packages: step never re-ran, so fail2ban may be missing (#2680).
provisioner "file" {
  source      = "${path.module}/fail2ban-sshd.local"
  destination = "/etc/fail2ban/jail.d/soleur-sshd.local"
}
```

### Phase 4 — Terraform validate + plan (no apply)

Run validation to prove the change is syntactically correct before PR review:

```bash
cd apps/web-platform/infra
doppler run --name-transformer tf-var -- terraform validate
doppler run --name-transformer tf-var -- terraform plan
```

Expected plan output:

- `terraform_data.fail2ban_tuning` appears under "will be created" (or "will be replaced" depending on current state — see the retroactive-state note below).
- No other resources changed.
- No errors, no warnings about provider version drift.

**Retroactive state note (before `terraform apply` lands post-merge):** The existing `terraform_data.fail2ban_tuning` may or may not be in tfstate. Per `cq-terraform-failed-apply-orphaned-state`: if it's present, the plan should show "will be replaced" (trigger hash unchanged, resource definition changed). If the plan shows unexpected orphans, run `terraform state list | grep fail2ban` BEFORE the apply to reconcile. Do NOT run apply during planning-phase; that's post-merge operator work.

### Phase 5 — Post-merge operator verification (not automatable pre-merge)

**Important correction (learning-derived):** Per `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` and the `server.tf:141-146` connection block (`connection { agent = true }`), `terraform_data.fail2ban_tuning` CANNOT be applied by CI — CI runs with a dummy SSH key. The drift-detection workflow will flag it post-merge, and an operator with SSH agent access must apply it locally. Phase 5 is therefore operator-side, not CI-side.

**Pre-flight before apply:**

```bash
# Confirm SSH agent has an identity that can reach the server.
ssh-add -l           # must list the operator's ed25519 key
ssh root@<server-ip> echo ok   # must succeed WITHOUT prompting for a passphrase
```

If either check fails, do not proceed with `terraform apply` — per the encrypted-key learning, the failure surfaces as a cryptic `ssh: parse error in message type 0`, not a clear auth error.

**Apply:**

```bash
cd apps/web-platform/infra
doppler run --project soleur --config prd_terraform --name-transformer tf-var -- \
  terraform apply -target=terraform_data.fail2ban_tuning
```

Per `hr-menu-option-ack-not-prod-write-auth`: do NOT add `-auto-approve`. Let terraform's native confirmation prompt surface so the operator reviews the plan before applying.

**Verification after apply:**

1. **Terraform apply completes cleanly** — no partial-resource state. Check apply output: `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.` (or 1 changed if replacing).
2. **fail2ban is installed** — SSH into the existing server (read-only per `cq-for-production-debugging-use`) and run `dpkg -s fail2ban | grep Status` → expect `Status: install ok installed`.
3. **bantime assertions pass** — the apply log includes the `test "$(fail2ban-client get sshd bantime)" = '600'` output with no error.
4. **fail2ban service is active** — `systemctl is-active fail2ban` returns `active`.
5. **Cloud-init log review** — read `/var/log/cloud-init-output.log` on the existing server to confirm the root cause of the original package-install failure. Diagnostic only; no action taken unless a systemic issue is found (e.g., a pattern of "No space left on device" at package-install time suggests cloud-init disk sizing, filed as follow-up).

## Files to Edit

- `apps/web-platform/infra/server.tf` — add install step to `terraform_data.fail2ban_tuning` (Phase 1 + Phase 3)
- `apps/web-platform/infra/cloud-init.yml` — add package-audit `runcmd` step (Phase 2)

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `terraform_data.fail2ban_tuning` in `server.tf` has a new `remote-exec` provisioner as its FIRST provisioner, executing `dpkg -s fail2ban >/dev/null 2>&1 || { export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq fail2ban; }`.
- [x] The new `remote-exec` precedes the existing `provisioner "file"` (jail.d drop) and the existing `remote-exec` (reload + assert).
- [x] `triggers_replace` for `fail2ban_tuning` is unchanged (still hashes only `fail2ban-sshd.local`).
- [x] `cloud-init.yml` has a new `runcmd` entry that asserts every package in `packages:` is installed via `dpkg -s`, with a one-shot self-heal that runs `apt-get update && apt-get install -y $missing` before exiting non-zero.
- [x] The cloud-init audit runs AFTER the implicit `packages:` stage (i.e., as a `runcmd`, not `bootcmd`) and BEFORE the existing `systemctl restart sshd` line.
- [x] The package list hardcoded in the cloud-init audit (`curl fail2ban jq`) exactly matches the `packages:` block at the top of `cloud-init.yml`. Verified in the same commit diff.
- [x] `terraform validate` passes with zero errors (run via `terraform init -backend=false && terraform validate`; Doppler transformer skipped since backend is not initialized pre-merge).
- [x] `cloud-init schema -c cloud-init.yml` reports `Valid schema cloud-init.yml`.
- [ ] `doppler run --name-transformer tf-var -- terraform plan` shows only `terraform_data.fail2ban_tuning` changes; no unrelated drift. **Operator-side — deferred to Phase 5 post-merge.**
- [ ] PR body includes `Closes #2680`. **Handled by `/ship`.**

### Post-merge (operator)

- [ ] CI `terraform apply` completes without partial-state errors on `terraform_data.fail2ban_tuning`.
- [ ] `dpkg -s fail2ban` on the production server returns `Status: install ok installed` (read-only SSH diagnostic).
- [ ] Apply log shows `fail2ban-client get sshd bantime` returning `600`, `maxretry` returning `5`, `findtime` returning `600`.
- [ ] Operator reads `/var/log/cloud-init-output.log` on the existing server (diagnostic only — documents root cause of original miss). If a systemic issue is found (e.g., consistent "No space left on device" early in boot), file a follow-up issue.

## Test Scenarios

This is an infrastructure-only change with no unit-test harness for Terraform configs. The test strategy is:

1. **Terraform validation (automated, pre-merge):** `terraform validate` + `terraform plan` — covered in Acceptance Criteria.
2. **Idempotency probe (post-merge, operator):** After the first successful apply, run a second `terraform apply` (no file changes). Expect zero changes. This proves the `dpkg -s` guard is working — on the second pass, fail2ban is already installed, so the install branch is not taken; the trigger hash is unchanged so the resource is not re-created.
3. **Cloud-init dry-run (out of scope):** We cannot cheaply test cloud-init changes without provisioning a fresh Hetzner server. The Phase 2 change is low-risk (additive audit step, self-healing) and its logic is simple enough to review statically. If a future PR modifies the audit, consider adding a cloud-init Lint step in CI (tracked separately if the class recurs).
4. **Cloud-init syntax check (pre-merge):** Run `cloud-init schema --config-file apps/web-platform/infra/cloud-init.yml` if `cloud-init` is available on the dev machine. If not available, the change is a plain `runcmd` entry (a list of shell commands); syntax errors would fail the next fresh provisioning. Since the existing server won't re-run cloud-init, there's no urgency — but a syntax error would break any future replacement. Acceptable risk for the size of the change.
5. **Audit assertion bash probe (pre-merge, optional):** Copy the audit block to a local Ubuntu container and run it against a system with and without fail2ban installed. Expected: present → exits 0 silently; absent + install succeeds → exits 0 with recovery log; absent + install fails → exits 1 with `FATAL` message. This is optional — the logic is simple (dpkg -s loop + one-shot install) — but worth doing if there's any doubt.

### Test Scenarios — Research Insights

**`cq-write-failing-tests-before` exemption:** Per AGENTS.md `cq-write-failing-tests-before`, infrastructure-only tasks (config, CI, scaffolding) are exempt from the TDD gate. This plan is infrastructure-only (Terraform + cloud-init YAML), no application code, no test harness expected. Acceptance criteria stand in for unit tests here.

**Preflight for CLI forms used by the plan** (per `knowledge-base/project/learnings/best-practices/2026-04-17-plan-preflight-cli-form-verification.md`): every CLI invocation the plan prescribes has been verified to exist against Ubuntu 24.04 / Debian tooling. Verified tokens:

- `dpkg -s <package>` — standard dpkg query, returns exit 0 + `Status: install ok installed` if installed, exit 1 otherwise. `man dpkg-query` confirms.
- `apt-get update -qq` — `-qq` is `--quiet --quiet` (double-quiet), suppresses progress output. `man apt-get` confirms.
- `apt-get install -y -qq fail2ban` — `-y` assumes yes to prompts, `-qq` double-quiet. Standard.
- `DEBIAN_FRONTEND=noninteractive` — standard Debian env var, prevents postinst from opening dialog. Documented at <https://manpages.ubuntu.com/manpages/noble/en/man7/debconf.7.html>.
- `systemctl is-active <unit>` — used in Phase 5 verification; `man systemctl` confirms exit semantics (exit 0 for active).
- `cloud-init schema --config-file <path>` — Ubuntu 24.04 ships cloud-init ≥ 24.x; `cloud-init schema` is available since 22.x.

## Non-Goals

- Re-provisioning the existing production server from scratch to re-run cloud-init. Too disruptive; not needed given `terraform_data.fail2ban_tuning` can deliver the fix.
- Removing `ignore_changes = [user_data]` from `hcloud_server.web`. That rule is load-bearing for import-artifact handling; dropping it would force replacement on any cloud-init edit.
- Rewriting `packages:` audit logic to parse YAML. Hardcoded list is intentional — simplicity + diff-visibility.
- Adding a new monitoring alert for "fail2ban service not running." If fail2ban's install fails again after this fix, the `test "$(fail2ban-client get sshd bantime)" = '600'` assertion in the existing `remote-exec` already fails the terraform apply — CI surfaces it.
- Adding unit tests for `cloud-init.yml` structure. No existing harness; not worth introducing one for a 3-line audit block.

## Risks

- **Risk: `apt-get update` inside `remote-exec` could hit network failure on Hetzner.** Mitigation: `-qq` keeps output quiet, but `apt-get install -y` will exit non-zero on failure. Acceptable — a transient network failure during terraform apply is operator-visible and re-runnable. The only worse alternative (ignoring failure) silently re-creates the original bug.
- **Risk: Self-healing recovery in cloud-init audit could mask a systemic install failure.** Mitigation: the recovery install still exits non-zero if packages remain missing after the second attempt. Cloud-init marks the boot failed. Operator sees `cloud-init status --wait` return non-zero, which is visible in Hetzner console.
- **Risk: `triggers_replace` not updated → plan may show "no changes" after the resource block changes.** Mitigation: any existing-state `terraform_data.fail2ban_tuning` will already be torn down and re-created once the trigger hash changes in a future edit (e.g., when `fail2ban-sshd.local` is modified). The install step runs on re-creation. For the FIRST post-merge apply specifically, we expect either (a) resource already replaced in a prior failed apply and `terraform state rm` cleared it — plan shows "will be created" (install runs), or (b) resource is fresh in state — plan shows "will be created" (install runs). Either way, the install step executes. Pre-apply, operator runs `terraform state list | grep fail2ban` to confirm which scenario applies.
- **Risk: The `DEBIAN_FRONTEND=noninteractive` export leaks into subsequent provisioner lines.** Mitigation: Terraform runs each `inline` entry in its own shell — the export is scoped to that single line. Verified by reading Terraform's remote-exec docs: each list entry is invoked as a separate command via the SSH connection.
- **Risk: Claim "cloud-init's `packages:` step never re-runs after import" is asserted in the issue body but not independently verified by citing cloud-init docs URL.** Mitigation per Sharp Edges — cite the behavior: `ignore_changes = [user_data]` prevents terraform from updating `user_data`; cloud-init runs only on first boot unless `cloud-init clean` is explicitly invoked. Confirmed via `hcloud_server.web.lifecycle.ignore_changes` at `server.tf:47-49` and the cloud-init runs-once semantics documented at <https://cloudinit.readthedocs.io/en/latest/reference/faq.html#how-can-i-re-run-cloud-init-after-it-already-ran>. No `cloud-init clean` is invoked anywhere in this repo (verified by grep).
- **Risk: operator runs `terraform apply` with stale agent-less SSH, gets cryptic failure.** Per `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`, if the SSH agent is not running when apply executes, the `agent = true` connection fails at the handshake with an opaque error. Mitigation: the post-merge operator acceptance criteria explicitly cite `ssh-add -l` as a pre-flight check (see Phase 5). This is preventive guidance, not an automated guard.
- **Risk: the recovery install in the cloud-init audit could mask a `packages:` list that was edited but not pushed to apt mirrors.** Scenario: PR adds a typo'd package name (`fail2banb` instead of `fail2ban`). `packages:` install silently fails, audit recovery-install hits the same typo and fails, cloud-init exits non-zero. This is the correct behavior — noisy failure beats silent drop — but the operator must know to check `/var/log/cloud-init-output.log` for the actual package name, not just "install failed." Mitigation: the audit message in Phase 2 already prints the missing package list verbatim (`$missing`), so the operator sees the typo immediately.
- **Risk: fail2ban's `dpkg -s` returns "installed" but the service is not running.** Scenario: package is partially configured (`rc` state in dpkg). `dpkg -s` reports `Status: install ok installed` but `systemctl is-active fail2ban` returns `inactive`. Mitigation: the existing `systemctl reload fail2ban || systemctl restart fail2ban` line in `terraform_data.fail2ban_tuning` will fail if the service cannot start, surfacing the problem. The downstream `test "$(fail2ban-client get sshd bantime)" = '600'` assertions then also fail. This is covered by the existing assertion chain; no new guard needed.

## Sharp Edges

- `triggers_replace` is intentionally NOT updated. Do not add the install command to the hash — it would force a useless re-create on every modification of the inline list.
- The package list in cloud-init's audit runcmd is hardcoded to match `packages:`. If a future PR adds a package to the `packages:` list, it MUST add the same package to the audit list in the same commit. Acceptance criteria explicitly checks this.
- Do NOT run `terraform apply` as part of this PR's pre-merge work. Apply happens in CI post-merge per `hr-all-infrastructure-provisioning-servers` and `hr-menu-option-ack-not-prod-write-auth`.
- Do NOT SSH to the production server to manually `apt-get install fail2ban` as a shortcut. The install must land via terraform to prevent drift — if someone runs apt manually now, the tfstate is unaware, and the next provisioner run will still attempt install (idempotent thanks to `dpkg -s`, but breaks the audit trail).

## Related

- PR #2655 — introduced `terraform_data.fail2ban_tuning` with the positive assertion that exposed this gap.
- Issue #2654 — the original SSH lockout that motivated fail2ban tuning (and was, per issue #2680, actually caused by admin-IP rotation, not fail2ban).
- Plan: `knowledge-base/project/plans/2026-03-19-security-add-fail2ban-ssh-protection-plan.md` — original fail2ban plan, predates this gap.

## Domain Review

**Domains relevant:** none (Engineering infrastructure change, fully covered by `domain/engineering` issue label)

No cross-domain implications detected — infrastructure/tooling bug fix. No user-facing surface, no pricing/billing impact, no content/marketing surface, no legal implications. The fix is mechanical: make an existing provisioner idempotent against a missing prerequisite.
