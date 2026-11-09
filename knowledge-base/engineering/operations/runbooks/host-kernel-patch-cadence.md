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
| git-data | `git-data-host-replace` only | three interlocks (see the git-data section); volumes and the volume passphrase are preserved by omission | owner, per dispatch | a fresh reader run once its emitter is delivered |

<!-- lint-infra-ignore end -->

Every route starts with its rehearsal (`plan_only` where the workflow offers it) and ends with a reader run. A replace does
**not** by itself guarantee a patched kernel: the cloud-init files set `package_update` only, never a package upgrade, so a new
host boots the base image plus whatever package state the mirror holds that day. The verification step is therefore mandatory,
and "the uptime reset" without "the kernel changed" means the host was rebuilt but not patched. Whether cloud-init should upgrade
packages is tracked separately; do not edit a cloud-init file to find out (see the registry section).

## web

- Each web host is a `hcloud_server.web[<key>]`. The standby host takes the replace route in the table; its own runbook is
  [web-host-replace.md](./web-host-replace.md).
- The primary web host has **no activation path**. It is refused at four layers of the replace path, because it is
  topologically different (the workspaces volume attachment is hardcoded to it and is ForceNew). The reboot workflow that once existed
  is retired (see [web-host-reboot.md](./web-host-reboot.md), ADR-263 addendum 2026-10-12: "a host is replaced, not rebooted").
  So a primary-host row past its cadence has no sanctioned act today. That is an owner decision, not a gap an agent closes: record
  it with a time-boxed acknowledgement in the probe (below), tied to an issue, and escalate.

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

Until the interlocks clear, a git-data row past its cadence is acknowledged in the probe (an issue number and a 90-day cap) and agents
take no action on it.

## Per-class view (a session procedure, not a mode)

In a session, with the Better Stack read credentials injected, run the reader (the cve-exposure skill's `host-state.sh`) and divide
each row's `uptime_s` by 86400, then compare it with that class's constant in the probe header. The reader's output stays in the
session. There is no table script and no stored view, deliberately: a stored per-host table is the exposure register ADR-322 rejected.

## Reading the tracker line

Once the tracker is armed, the daily follow-through sweeper posts exactly one of three lines, and nothing else:

| Line | Exit | Meaning |
|---|---|---|
| `host-kernel-cadence: review-needed` | 5 | at least one row is past its cadence and not acknowledged |
| `host-kernel-cadence: cannot-establish` | 3 | at least one row is unknown (the default today), or the reader failed |
| `host-kernel-cadence: nothing-to-report` | 2 | every row is fresh, observed and within its cadence; this is not an assurance about unmeasured hosts |

No class, count or version is published, so a public reader learns only that some row needs review. Which row, and why, is answered
in a session. The overdue signal is the host's uptime, an upper bound on the kernel's age: a reboot onto the same kernel resets it,
and it can come from a row up to 48 hours older than the state it is paired with. The probe is armed only after a session run of
the reader shows at least one row with a fresh, observed marker; until then it can only say "cannot-establish".

**Acknowledgements.** A row past its cadence by design may carry a time-boxed acknowledgement in the probe: per row, only for an
overdue row (never an unknown one), at most 90 days past the file's last commit date, with a comment line above it carrying an
issue number. An expired date re-arms the row. Each renewal is a visible diff. The cadence values and acknowledgements are stored
beside the rule that reads them, so the suite proves they are consistent, not that they are right; the issue number and the commit-date
cap are the checks that sit outside the diff.

## Exposure suite

`scripts/host-tcp-exposure.test.sh` asserts a **declared design**, not live state: each non-web firewall declares no inbound
rule, every mapped server is bound to its firewall, no server exists outside the mapping, and the web firewall (the control) parses
with inbound rules so a parser that reads nothing cannot pass. The attachment-bound servers must equal an allow-list that only shrinks
(the registry and git-data firewalls still bind through a separate attachment resource, which attaches after first boot, #6442).

What it cannot see: console drift, a stale attachment id, a firewall that was never applied. Those need a live read of the provider,
which is a session-only step and is not done by this suite. Tunnel ingress is outbound-initiated and opens no inbound public port, so
it is out of scope. A new server added to the Terraform makes the suite fail until its row is added to the mapping in the suite: that
failure is by design.

## Escalation

If a verification step shows no change after a replace (uptime reset but the same kernel, or no new row at all), the host was
rebuilt but not patched, or its emitter is not delivering. Do not retry the route. Report it to the owner in the session; the next
step is the package-upgrade question above, which needs an owner-authorized plan.
