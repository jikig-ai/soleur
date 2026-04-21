---
name: Cloud-init packages: stage silent-drop audit pattern
description: Cloud-init records package-install failures in the boot log but does not fail the run by default. A runcmd audit that dpkg -s's each declared package converts silent drops into loud failures that operators can diagnose.
type: integration-issue
tags: cloud-init, terraform, hcloud, fail2ban, apt, infrastructure
related:
  - 2026-04-03-doppler-not-installed-env-fallback-outage.md
  - 2026-04-06-terraform-data-connection-block-no-auto-replace.md
  - 2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md
issue: 2680
pr: 2682
---

# Cloud-init `packages:` stage silent-drop audit pattern

## Problem

PR #2655 shipped `terraform_data.fail2ban_tuning` with a positive assertion
(`test "$(fail2ban-client get sshd bantime)" = '600'`). Pre-apply operational
recovery revealed the production server had NO `fail2ban-client` binary —
`cloud-init.yml` correctly declared `fail2ban` in `packages:` but the package
never landed on the instance. If terraform apply had run straight through, the
provisioner would have failed mid-list, leaving the resource in a partial
state requiring `terraform state rm` recovery per
`cq-terraform-failed-apply-orphaned-state`.

## Root cause

Two independent causes:

1. **Cloud-init's `package_update_upgrade_install` module is non-fatal.** When
   apt fails transiently (lock contention, network blip, "No space left on
   device" at first boot), the failure is recorded in
   `/var/log/cloud-init-output.log` but subsequent modules continue. No
   `runcmd` or downstream check on the existing server saw a problem — the
   miss was invisible until a positive assertion several PRs later touched
   the binary.

2. **`lifecycle { ignore_changes = [user_data] }` means cloud-init runs
   exactly once.** The hcloud_server was provisioned with `ignore_changes =
   [user_data, ssh_keys, image]` so cloud-init-yml edits never re-apply to
   the existing instance. A later fix to `packages:` would not heal the
   existing server. This is load-bearing for import-artifact handling and
   cannot be removed — it is the reason `terraform_data.fail2ban_tuning`
   (and `terraform_data.doppler_install`, `deploy_pipeline_fix`, etc.) exist
   as `remote-exec` bridges.

The same class hit Doppler installs previously (see
`2026-04-03-doppler-not-installed-env-fallback-outage.md`, PR #1493/#1496).
One-off fixes per missing package do not close the class.

## Solution

**Per-package bridge (existing pattern, applies to existing servers):**
Prepend an idempotent `dpkg -s <pkg> >/dev/null 2>&1 || apt-get install -y
<pkg>` `remote-exec` provisioner to the existing `terraform_data.<feature>`
resource, before the `file` provisioner that depends on the package's
filesystem layout (e.g., `/etc/fail2ban/jail.d/`). Follow with a
post-install re-verification (`dpkg -s <pkg> || exit 1`) to catch the
"install reported success but package is in rc state" edge case.

**Systemic audit (new, applies to fresh servers):** Add a `runcmd` audit to
`cloud-init.yml` that parses the rendered `packages:` list at runtime from
`/var/lib/cloud/instance/cloud-config.txt` and asserts every entry via
`dpkg -s`. Self-heal once via `apt-get update && apt-get install -y
$missing`; exit non-zero if any package is still missing. Cloud-init then
marks the boot failed and the operator investigates via the Hetzner console.

The audit must run **AFTER** `systemctl restart sshd` so the operator
retains hardened SSH access even if the audit halts the rest of cloud-init:

```yaml
runcmd:
  # Apply SSH hardening immediately so the operator always has a working
  # hardened shell, even if the audit below fails and halts cloud-init.
  - systemctl restart sshd

  # Runtime parse of packages: from rendered cloud-config — no hardcoded
  # list to drift.
  - |
    set -e
    required_packages=$(awk '/^packages:$/{flag=1; next} /^[^ ]/{flag=0} flag && /^  - /{sub(/^  - /, ""); print}' /var/lib/cloud/instance/cloud-config.txt)
    if [ -z "$required_packages" ]; then
      echo "FATAL: package audit could not parse packages: list from cloud-config.txt" >&2
      exit 1
    fi
    missing=""
    for pkg in $required_packages; do
      dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
    done
    if [ -n "$missing" ]; then
      echo "FATAL: cloud-init packages: stage did not install:$missing" >&2
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq $missing
      for pkg in $missing; do
        dpkg -s "$pkg" >/dev/null 2>&1 || { echo "FATAL: $pkg still missing after recovery install" >&2; exit 1; }
      done
    fi
```

## Key insights

1. **Runtime-parse beats hardcoded list.** An early draft of this audit
   hardcoded `for pkg in curl fail2ban jq`. Review flagged drift risk:
   adding a package to `packages:` without updating the audit re-introduces
   the silent-drop class. Parsing `/var/lib/cloud/instance/cloud-config.txt`
   at runtime makes the audit self-synchronizing with the declared list.
   The awk pattern (`/^packages:$/` to next `^[^ ]` line) works because
   cloud-init writes the merged YAML to disk verbatim.

2. **sshd restart before audit is non-obvious but load-bearing.** The audit
   is a fail-fast gate: if it exits non-zero, all following runcmd steps
   (Doppler install, Docker install, webhook) are skipped. If `systemctl
   restart sshd` is among the skipped steps, the operator diagnosing the
   failure reaches the host on default (unhardened) sshd config. Flipping
   the order keeps the security baseline intact even on partial boots.

3. **apt-signed packages are exempt from the pinned-version + SHA-256 rule.**
   `2026-04-06-doppler-cli-checksum-cloud-init.md` mandates version pinning
   and checksum verification for third-party binaries downloaded via `curl`.
   That rule does NOT apply to `apt-get install` — apt's GPG-signed
   repository metadata is the trust boundary. No version pin or checksum is
   needed for `apt install fail2ban`.

4. **`triggers_replace` scope is content-only, by design.** Per
   `2026-04-06-terraform-data-connection-block-no-auto-replace.md`, changes
   to a `terraform_data` resource's provisioner body do NOT force
   replacement unless the content is included in the `triggers_replace`
   hash. For our fix, the `dpkg -s` install step runs opportunistically
   whenever the resource re-creates (jail file hash change), AND on every
   fresh resource creation. It does NOT re-run on every apply — but it
   doesn't need to: once fail2ban is installed, `dpkg -s` short-circuits.

## Session errors

1. **WebFetch blocked by cloudinit.readthedocs.io (403).** — Recovery:
   sourced cloud-init module ordering facts from an existing learning
   (`2026-04-03-doppler-not-installed-env-fallback-outage.md`) and Ubuntu
   24.04 knowledge. — Prevention: when `readthedocs.io` or similar blocks
   WebFetch, check `knowledge-base/project/learnings/` for prior citations
   of the same fact before attempting other fetch paths. The learning files
   often quote the relevant section verbatim.

## Prevention

- When a new `terraform_data` resource depends on a package being present
  (filesystem path, binary on PATH, systemd unit), prepend a `dpkg -s
  <pkg> || apt-get install -y <pkg>` inline as the FIRST provisioner,
  before `file` or the binary-calling `remote-exec`. Do not rely on the
  package being present just because `cloud-init.yml` declares it —
  `ignore_changes = [user_data]` means the existing server may have missed
  the install.

- Any `runcmd` additions that can halt cloud-init must run AFTER
  `systemctl restart sshd` so the operator retains hardened SSH access on
  partial boots.

- Use runtime-parse for cross-file invariants whenever possible. Comment-
  enforced invariants ("this list MUST match the block at the top") are a
  class of drift bug waiting to happen. When a value must match in two
  places, make one place read from the other at runtime.
