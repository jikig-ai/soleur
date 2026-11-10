---
feature: feat-kernel-patch-web-hosts-12008
issue: 12008
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-11-10-first-boot-kernel-currency-web-hosts-brainstorm.md
---

# Feature: First-boot kernel currency for web hosts

Public-repository rule (ADR-322): no kernel string, vulnerability id, host address or exposure verdict in this spec.

## Problem Statement

A web host replace (the sanctioned refresh route) boots the stock base image and installs four named packages, so the
new host runs the base image's kernel. A replace is therefore a rebuild, not a kernel refresh, and the cadence
runbook can only detect the gap after the fact (#12503).

## Goals

- A replaced web host comes up on the archive's current generic kernel.
- The host reboots at most once per birth, only when the running kernel differs from the installed generic kernel,
  and is graded healthy only after that reboot (amended 2026-11-10, CTO re-ruling: graded single reboot).
- Merging changes no running host.

## Non-Goals

- Inngest, registry and git-data cloud-init (separate owner-authorized PRs; #12503 narrowed to them).
- Any act on the web host the replace path refuses (owner decision; #9421 is the permanent route).
- A baked/snapshot image, a pinned kernel version, or a full package upgrade.
- The newer-LTS migration evaluation (split to its own deferred issue).
- A public status page or in-app banner system.

## Functional Requirements

- FR1: The bounded apt step in `apps/web-platform/infra/cloud-init.yml` installs the generic kernel meta package inside
  the existing `timeout` + retry + named-stage contract (a failure is a named fatal, never silent).
- FR2: As the last runcmd step (after vector install, before the readiness verdict), a baked helper compares the
  running kernel with the one the generic kernel meta package points to; on a mismatch it records a pending marker
  and the current boot id under `/var/lib/soleur`, enables a one-shot post-reboot unit and reboots once. A second
  mismatched boot is a named fatal, never another reboot.
- FR3: The readiness verdict is emitted after that reboot by the post-reboot unit (after the volume, LUKS and the
  app container are up and egress enforcement is re-proven), and it requires the running kernel to match and, after
  a reboot, the boot id to differ. The replace job's boot trail waits longer when it sees the reboot stage.
- FR4: The cadence runbook gains a "first-boot kernel" note stating what a replace now guarantees and that the
  post-replace reader verification stays mandatory.

## Technical Requirements

- TR1: A new suite (`kernel-currency.test.sh`, apt-bounded's instrument self-test + floor shape) pins FR1-FR3
  behaviourally and structurally; `fresh-boot-ready.test.sh` gains the kernel predicate rows.
- TR2: `plugins/soleur/test/cloud-init-user-data-size.test.ts` still passes (`WEB_GZIP_BUDGET` 25,000 on the
  base64-gzip render, ~180 B headroom); all logic is baked into `soleur-host-bootstrap.sh`.
- TR3: No edit to `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, inngest or git-data cloud-init.
- TR4: An ADR records the decision ("First-boot kernel upgrade and reboot on host create").
- TR5: PR, commits and filed issues use routine refresh wording only (ADR-322, CLO).

## Acceptance

- After the owner-authorized replace of the replaceable web host, a fresh reader run (session only) shows a reset
  uptime and a changed kernel for that row.
