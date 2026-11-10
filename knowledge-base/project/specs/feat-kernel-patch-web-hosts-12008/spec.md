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
- The host reboots at most once, at the end of first boot, only when required, before it is graded healthy.
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
- FR2: After all runcmd work completes, cloud-init reboots once if and only if a reboot is required.
- FR3: The host is not graded healthy until after that reboot (or after confirming none was required).
- FR4: The cadence runbook gains a "first-boot kernel" note stating what a replace now guarantees and that the
  post-replace reader verification stays mandatory.

## Technical Requirements

- TR1: A test beside the cloud-init (shape of `apt-bounded.test.sh`) pins FR1-FR3 structurally.
- TR2: `plugins/soleur/test/cloud-init-user-data-size.test.ts` still passes under the 32,768-byte cap; measure headroom first.
- TR3: No edit to `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, inngest or git-data cloud-init.
- TR4: An ADR records the decision ("First-boot kernel upgrade and reboot on host create").
- TR5: PR, commits and filed issues use routine refresh wording only (ADR-322, CLO).

## Acceptance

- After the owner-authorized replace of the replaceable web host, a fresh reader run (session only) shows a reset
  uptime and a changed kernel for that row.
