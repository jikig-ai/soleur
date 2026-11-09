---
title: "Host kernel patch and reboot cadence, per host class"
category: runbook
tags: [kernel, patching, cadence, hosts, follow-through, exposure]
---

# Host kernel patch and reboot cadence, per host class

**Status:** current as of 2026-11-09 (#12008, items 2 and 3). Items 1 and 4 of that issue (patching the web hosts when the
distro ships a fix, and the newer-LTS evaluation) stay open on the issue and are not covered here.

**What this is.** A written cadence for each host class (web, inngest, registry, git-data), the route that applies it, who
authorizes it and how to verify it, plus the two machine checks that back it. **What this is not.** It performs, schedules
and authorizes nothing: every act below is owner-authorized, one typed go naming the exact command
(`hr-menu-option-ack-not-prod-write-auth`). A host is replaced, never patched in place (`hr-prod-host-config-change-immutable-redeploy`),
and nothing here uses SSH.

**Public repository rule (ADR-322).** This file and the probe it describes carry no kernel string, no vulnerability id, no host
name or address and no exposure verdict. What is exposed or unpatched is answered in a session from the reader and is never
written into a file, a tracker comment or an issue.

## The two machine checks

| Check | File | What it answers |
|---|---|---|
| Cadence probe | `scripts/followthroughs/host-kernel-cadence-12008.sh` (suite: the `.test.sh` beside it) | Is any host row past its cadence? One fixed line, notify-only. |
| Exposure suite | `scripts/host-tcp-exposure.test.sh` | Does the Terraform still declare deny-all inbound on the non-web firewalls, with every server bound? |

The cadence numbers (one per class) are the four `CADENCE_DAYS_*` constants at the top of the probe. This runbook never copies
them: edit the constants, nothing else.

## Class table

<!-- lint-infra-ignore start: names the owner-authorized routes this runbook describes; it performs none of them -->

| Class | Route (an `apply_target` of `apply-web-platform-infra.yml`) | Interlock | Authorizes | Verify after |
|---|---|---|---|---|
| web (standby host) | `web-host-replace` | typed confirm token, reviewer-gated environment, plan gate (exactly one delete and one create of that key) | owner, per dispatch | a fresh reader run shows a reset uptime and a changed kernel for that row |
| web (primary host) | none | the replace path refuses it at input validation and in the plan gate (see the web section) | owner decision, not an act | n/a |
| inngest | `inngest-host-replace`, then the separately human-approved cutover resume | scheduler pause window, resume approval | owner, per dispatch | a fresh reader run, then the scheduler health the cutover runbook names |
| registry | `registry-host-replace` (or the dispatcher re-fire) | registry preflight; the registry is the only image pull path and a replace destroys before it creates | owner, per dispatch | a fresh reader run, then an image pull from a web host |
| git-data | `git-data-host-replace` only | three interlocks (see the git-data section); volumes and the volume passphrase are preserved by omission | owner, per dispatch | a fresh reader run once the git-data emitter is delivered and the reader reads that source (#12385) |

<!-- lint-infra-ignore end -->

Every route starts with its rehearsal (`plan_only` where the workflow offers it) and ends with a reader run. A replace does
**not** by itself guarantee a patched kernel: no cloud-init file runs a package upgrade, so a new host boots the base image
plus whatever package state the mirror holds that day. The verification step is therefore mandatory,
and "the uptime reset" without "the kernel changed" means the host was rebuilt but not patched. Whether cloud-init should upgrade
packages is tracked separately; do not edit a cloud-init file to find out (see the registry section).

## web

- Each web host is a `hcloud_server.web[<key>]`. The standby host takes the replace route in the table; its own runbook is
  [web-host-replace.md](./web-host-replace.md).
- The primary web host has **no activation path**. The replace path refuses it (see the web-host-replace runbook section
  "`web-1` is refused"), because it is topologically different (the workspaces volume attachment is hardcoded to it and is ForceNew). The reboot workflow that once existed
  is retired (see [web-host-reboot.md](./web-host-reboot.md), ADR-263 addendum 2026-10-12: "a host is replaced, not rebooted").
  So a primary-host row past its cadence has no sanctioned act today. That is an owner decision, not a gap an agent closes:
  escalate it. Acknowledging a row that is overdue by design is deferred to the change that arms the tracker.

## inngest

Replace, then the human-approved cutover resume. The sole scheduler goes dark for the replace window, so the owner picks the
window. Runbooks: [inngest-server.md](./inngest-server.md), [inngest-luks-cutover-6894.md](./inngest-luks-cutover-6894.md).

## registry

Replace through its own route. **No cadence act edits** `cloud-init-registry.yml`, `zot-registry.tf` or `variables.tf`: a merge that
touches any of the three auto-fires the registry host replace with no reviewer gate
([registry-host-replace-dispatch.md](./registry-host-replace-dispatch.md)). Anything that needs a change to those files is its own
owner-authorized plan, not a cadence act.

## git-data (its own path)

<!-- lint-infra-ignore start: describes the owner-authorized git-data route and why no reboot route exists; it prescribes no act -->

The reboot primitive adopted for the registry was **not** adopted for this host (ADR-115, including the 2026-09-18 amendment),
and a new reboot route for it would be a new decision superseding that ADR, which is the founder's call and is not authorized here.
The only sanctioned route is `git-data-host-replace`, held by three interlocks: rung-2 evidence for the current cloud-init, an empty
plaintext volume id, and the SSH authorization map. Volumes and the volume passphrase are preserved by omission.
`git-data-host-rotate` is the only route allowed to touch the encrypted store and needs a founder rotation decision, so it is never
a cadence act. Runbooks: [git-data-rung2-rehearsal.md](./git-data-rung2-rehearsal.md), [git-data-birth.md](./git-data-birth.md),
[git-data-luks-cutover-5274.md](./git-data-luks-cutover-5274.md).

<!-- lint-infra-ignore end -->

Until the interlocks clear, a git-data row past its cadence is escalated to the owner and agents take no action on it.

## Per-class view (a session procedure, not a mode)

In a session, with the Better Stack read credentials injected, run the reader (the cve-exposure skill's `host-state.sh`) and divide
each row's `uptime_s` by 86400, then compare it with that class's constant in the probe header. The reader's output stays in the
session. There is no table script and no stored view, deliberately: a stored per-host table is the exposure register ADR-322 rejected.

## Reading the tracker line

Once the tracker is armed, the daily follow-through sweeper posts exactly one of three lines and nothing else (no class,
count or version): `host-kernel-cadence: review-needed` (exit 5, some row is past its cadence), `host-kernel-cadence:
cannot-establish` (exit 3, some row is unknown or the reader failed) and `host-kernel-cadence: nothing-to-report` (exit 2,
every required row is fresh, observed and within its cadence; not an assurance about unmeasured hosts). Which row, and why, is
answered in a session only. The probe header owns the rules, including the uptime proxy caveat and the roles it grades or ignores.

**Arming precondition.** The tracker (#12504) is armed only once a session run of the probe prints `review-needed` or
`nothing-to-report`, never `cannot-establish`. That needs the emitter roll-out (#12386) and the git-data reader source (#12385);
armed earlier, the sweeper would post a content-free `cannot-establish` every day. Any row that is overdue by design at that
point needs the acknowledgement mechanism first, which is added with the arming change.

## Exposure suite

`scripts/host-tcp-exposure.test.sh` asserts a **declared design**, not live state; its header owns the rules and the mapping. It
cannot see console drift, a stale attachment id or a firewall that was never applied: those need a live read of the provider, a
session-only step this suite does not do. A new server added to the Terraform makes the suite fail until its row is added to the
mapping, by design.

## Escalation

If a verification step shows no change after a replace (uptime reset but the same kernel, or no new row at all), the host was
rebuilt but not patched, or its emitter is not delivering. Do not retry the route. Report it to the owner in the session; the next
step is the package-upgrade question above, which needs an owner-authorized plan.
