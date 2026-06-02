---
title: Cloning an SSH `file` provisioner does not inherit the precedent's target-parent-dir existence guarantee
date: 2026-06-02
category: integration-issues
module: apps/web-platform/infra
tags: [terraform, terraform_data, file-provisioner, scp, systemd, journald, cloud-init, precedent-cloning]
issue: 4792
pr: 4800
---

# Cloning an SSH `file` provisioner does not inherit the precedent's target-dir guarantee

## Problem

While provisioning persistent journald storage (#4792), the new
`terraform_data.journald_persistent` resource was cloned 1:1 from the established
`terraform_data.disk_monitor_install` / `fail2ban_tuning` SSH-provisioner shape in
`apps/web-platform/infra/server.tf`. The clone put a Terraform `file` provisioner
first:

```hcl
provisioner "file" {
  source      = "${path.module}/journald-soleur.conf"
  destination = "/etc/systemd/journald.conf.d/00-soleur.conf"   # parent dir does NOT exist
}
```

Terraform's `file` provisioner (scp under the hood) does **not** create remote
parent directories, and `/etc/systemd/journald.conf.d/` is **not** present by
default on Ubuntu — `systemd` ships `/etc/systemd/journald.conf` but not the
`journald.conf.d/` drop-in subdir. On the existing prod host cloud-init's
`write_files` entry (which *would* create the dir, since cloud-init auto-creates
parents) never runs because `hcloud_server.web` carries
`lifecycle { ignore_changes = [user_data] }` — the SSH provisioner is the *sole*
live-prod apply path. So the very first `terraform apply` would have failed at
scp with `No such file or directory`. tsc-equivalents (`terraform validate`,
`terraform fmt`) and the static `journald-config.test.sh` all passed green — the
bug is an apply-time runtime failure invisible to static checks.

## Root cause

The precedent the clone copied (`fail2ban_tuning`) survives **only because its
target dir is independently guaranteed to exist**: `/etc/fail2ban/jail.d/` is
created by the `fail2ban` package, and `fail2ban_tuning`'s *preceding*
`remote-exec` (`dpkg -s fail2ban || apt-get install`) ensures that package is
installed before its `file` provisioner runs. The journald clone copied the
`file → remote-exec` ordering but dropped the "ensure the destination dir exists
first" guarantee that the ordering silently depended on. **The precedent's
structural shape is faithful; its environmental precondition is not transferable.**

## Solution

Add a `mkdir -p` `remote-exec` *before* the `file` provisioner (mirrors
`fail2ban_tuning`'s pre-`file` remote-exec), so the destination dir is guaranteed
to exist on every apply:

```hcl
provisioner "remote-exec" {
  inline = ["mkdir -p /etc/systemd/journald.conf.d"]
}
provisioner "file" {
  source      = "${path.module}/journald-soleur.conf"
  destination = "/etc/systemd/journald.conf.d/00-soleur.conf"
}
```

Caught by `pattern-recognition-specialist` at multi-agent review (it empirically
verified the dir is absent on the host), not by any static gate. Added a
regression assertion to `journald-config.test.sh` (`grep 'mkdir -p
/etc/systemd/journald\.conf\.d'` inside the resource block).

## Key Insight

When cloning a Terraform `file`-provisioner block, the destination's
**parent-directory existence is part of the precedent's environment, not its
code** — it does not travel with the copied HCL. Before reusing a `file`
provisioner shape, ask: *what guarantees the destination dir exists on the target
host?* If the answer for the precedent is "a package created it" or "an earlier
provisioner created it," the clone needs its own `mkdir -p` (or a package-install)
unless it pushes into the same guaranteed-existing dir. `/etc/<tool>.conf.d/`
drop-in dirs are a recurring trap: many are NOT shipped by the base package.

## Session Errors

1. **IaC-routing hook flagged the plan twice on `ssh`/`systemctl` prose** — Recovery: added the `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out after confirming the apply path is fully Terraform-routed. Prevention: expected behavior for SSH-provisioner plans; the ack comment is the sanctioned path.
2. **Task tool unavailable in the planning pipeline subagent** — Recovery: ran per-section research inline. Prevention: known constraint of the one-shot plan subagent (`2026-05-12-task-subagent-prompt-text-only`); not a defect.
3. **`file` provisioner missing `mkdir -p` for the drop-in dir (P1)** — Recovery: added a pre-`file` `mkdir -p` remote-exec + test regression guard. Prevention: this learning + the route-to-definition bullet on the work skill's infra section ("when cloning a `file` provisioner, verify the destination parent dir is guaranteed to exist on the target host").
4. **Claimed "adding shellcheck disable directive" but committed without it (P3)** — Recovery: code-quality-analyst flagged the claim-vs-commit gap; added the directive in the review commit. Prevention: when stating an inline fix during work, apply it in the same edit cycle rather than deferring — a stated-but-uncommitted fix reads as done.
