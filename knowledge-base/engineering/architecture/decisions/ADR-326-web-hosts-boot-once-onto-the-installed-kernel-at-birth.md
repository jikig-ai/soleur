---
title: Web hosts boot once onto the installed kernel at birth
status: active
date: 2026-11-10
---

# ADR-326: Web hosts boot once onto the installed kernel at birth

## Context

A web host is born from a Hetzner image whose kernel is whatever the image shipped with. The bounded
apt step installs packages, but a newly installed kernel only runs after a reboot, and web hosts are
never rebooted in place: a host is replaced, not rebooted (ADR-263, 2026-10-08). So every host served
on its image kernel for its whole life, and replacing it did not change that (#12008). The only
mechanism that runs at birth is cloud-init, whose runcmd runs once per instance (ADR-257).

## Decision

Every web host birth (create and replace) installs the archive's generic kernel package on the
bounded apt line, then boots onto it once before doing anything that is not safe to run twice:

- `linux-image-generic` joins the bounded `apt-get install` inside `STAGE=apt_install`. The retry runs
  `dpkg --configure -a` before attempt 2.
- The runcmd item right after the apt block (`STAGE=kernel_settle`) reads the target kernel from the
  meta-package's dependency and compares it to the running one. On a mismatch it writes a marker on
  the root disk, removes cloud-init's `scripts_user` semaphore and reboots. On the next boot runcmd
  re-runs from item 1 on the new kernel. Every item before the settle step is idempotent: none
  touches Doppler, docker, `/mnt/data` or LUKS.
- A second mismatch with the marker present, an unreadable or empty target, a missing semaphore, or a
  reboot that returns, is a named fatal on the existing on_err path. It is never a loop.
- The readiness verdict (`soleur-fresh-boot-ready`) gains `kernel=`, and refuses `ready` unless the
  running kernel equals the target. The boot window and the trail deadline grow by one reboot, together.

Rejected: (A) a reboot at the end of runcmd plus a systemd unit to resume, which re-orders every
non-idempotent step; (B) cloud-init `packages:` with `package_reboot_if_required`, which reverses the
#6090 user_data budget work and reboots outside the stage/error channel; and `cloud-init clean`, which
re-runs every module, not only runcmd.

This is the one recorded exception to ADR-257's "runcmd runs once per instance". The reboot happens
inside birth, before the host serves, so ADR-263's "replaced, not rebooted" rule for serving hosts is
unchanged. So is the claim boundary in ADR-263's 2026-10-11 and 2026-10-12 addenda: LUKS is
provisioned once, after the reboot, so no reopen happens at birth.

## Consequences

- A born host runs the archive kernel of its birth day, and the readiness row says so. Kernel currency
  then follows from replacement cadence (`host-kernel-patch-cadence.md`), not from in-place patching.
- Birth takes one extra reboot (about 4 minutes). The create job's timeout rose from 30 to 40 minutes.
  `kernel-currency.test.sh` computes each job's worst case from the trail's literals.
- The semaphore path is a cloud-init internal. If a cloud-init release renames it, the guard fails the
  birth with a named fatal. That is a red run, not a silent pass; the suite pins the path to one site.
- The web user_data budget was re-baselined (25,000 to 25,400 B) with the measured render, because the
  step must be inline: it runs before the baked bootstrap is seeded.
