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
| Cadence probe | `scripts/followthroughs/host-kernel-cadence-12008.sh` (suite: the `.test.sh` beside it) | Is any host row's uptime past its cadence? One fixed line, notify-only. |
| Exposure suite | `scripts/host-tcp-exposure.test.sh` | Does the Terraform still declare deny-all inbound on the non-web firewalls, with every server bound? |

The cadence numbers (one per class) are the four `CADENCE_DAYS_*` constants at the top of the probe. This runbook never copies
them: edit the constants, nothing else.

## Class table

<!-- lint-infra-ignore start: names the owner-authorized routes this runbook describes; it performs none of them -->

| Class | Route (an `apply_target` of `apply-web-platform-infra.yml`) | Interlock | Authorizes | Verify after |
|---|---|---|---|---|
| web (host the replace path accepts) | `web-host-replace` | typed confirm token, reviewer-gated environment, plan gate (exactly one delete and one create of that key) | owner, per dispatch | a fresh reader run shows a reset uptime and a changed kernel for that row |
| web (row with no sanctioned act) | none | the replace path refuses that key at input validation and in the plan gate (see the web section) | owner decision, not an act | n/a |
| inngest | `inngest-host-replace`, then the separately human-approved cutover resume | scheduler pause window, resume approval | owner, per dispatch | a fresh reader run, then the scheduler health the cutover runbook names |
| registry | `registry-host-replace` (or the dispatcher re-fire; neither form has a reviewer gate, they are main-only with the destroy guard) | registry preflight; the registry is the only image pull path and a replace destroys before it creates, so deploys are blocked while it is down | owner, per dispatch; an agent never dispatches either form without a typed go naming the command | a fresh reader run, then a read of an existing image pull or deploy log (never a new deploy) |
| git-data | `git-data-host-replace` only | three interlocks (see the git-data section); volumes and the volume passphrase are preserved by omission | owner, per dispatch | a fresh reader run once the git-data emitter is delivered and the reader reads that source (#12385) |

<!-- lint-infra-ignore end -->

Every route starts with its rehearsal (`plan_only` where the workflow offers it) and ends with a reader run. A replace does
**not** by itself guarantee a patched kernel: no cloud-init file runs a package upgrade, so a new host boots the base image
plus whatever package state the mirror holds that day. The verification step is therefore mandatory,
and "the uptime reset" without "the kernel changed" means the host was rebuilt but not patched. Whether cloud-init should upgrade
packages is tracked as #12503; do not edit a cloud-init file to find out (see the registry section).

## After a typed go

<!-- lint-infra-ignore start: states how an agent behaves after the owner authorizes one named command; it prescribes no human step -->

When the owner types a go that names an exact command from the table:

1. Run **only** the named command. A menu click, a bare "go" or an earlier approval is not a go. Do not chain a second route.
2. In the same turn, arm a Monitor on the run that command started (`hr-dispatch-async-must-arm-watch`). Find your own run by
   workflow, commit and start time, not by "latest run", and read the verdict from the run log, never from the dispatch exit code.
3. The reader's row role for a web row is the `web_host_key` input, and the confirm token is the one printed in that target's job header and runbook: the agent copies it from the owner's typed command and never composes it.
   Map the row you are acting on to its key before you type the command into the plan; the other routes take no key.
4. The exact command lines live in each class's own runbook, linked from the sections below. Start with `plan_only` where offered.
5. Verification is a fresh reader run (next section), not the workflow's green check.

<!-- lint-infra-ignore end -->

## web

- Each web host is a `hcloud_server.web[<key>]`. The hosts the replace path accepts take the replace route in the table; its own
  runbook is [web-host-replace.md](./web-host-replace.md).
- The replace path refuses one key (see the refusal section of the web-host-replace runbook): its workspaces volume
  attachment is hardcoded to it and is ForceNew, and a rebirth of it is not a supported recovery until the de-pet rebuild (#9421).
  That row therefore has no sanctioned act today. Do not offer a replace for it; the refusal text in that runbook is the authority.
  The reboot workflow that once existed is retired (see [web-host-reboot.md](./web-host-reboot.md), and the ADR-263 addendum
  2026-10-08, "immutability, not reboot": a host is replaced, not rebooted).
  A row with no sanctioned act is an owner decision, not a gap an agent closes: escalate it (see Escalation).
- App traffic reaches the web hosts through the Cloudflare load balancer for the app hostname
  (`apps/web-platform/infra/cloudflare-lb.tf`: pool `web_1` carries both web origins, the second at
  `var.web2_lb_weight`), which takes precedence over the `cloudflare_record.app` DNS record in `dns.tf`. Before planning
  any web host outage, replace or reboot, read the live pool (origins `enabled` and `weight`) instead of inferring
  serving weight from either file: both web hosts may be serving users.

## inngest

Replace, then the human-approved cutover resume. The sole scheduler goes dark for the replace window, so the owner picks the
window. Runbooks: [inngest-server.md](./inngest-server.md), [inngest-luks-cutover-6894.md](./inngest-luks-cutover-6894.md).

## registry

Replace through its own route. **No cadence act edits** `cloud-init-registry.yml`, `zot-registry.tf` or `variables.tf`: a merge that
touches any of the three wakes the registry delivery gate, which replaces the host when the rendered `user_data` changes, with
no reviewer gate ([registry-host-replace-dispatch.md](./registry-host-replace-dispatch.md)). Anything that needs a change to those
files is its own owner-authorized plan, not a cadence act.

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

In a session, with the Better Stack read credentials injected, run the reader (the cve-exposure skill's `host-state.sh`). Run it
in its own Bash call so the exit code is visible:

```bash
doppler run -p soleur -c prd_terraform -- bash plugins/soleur/skills/cve-exposure/scripts/host-state.sh
```

Then divide each row's `uptime_s` by 86400 and compare it with that class's constant in the probe header. This one-liner prints
role, states and uptime in days for every row and leaves the kernel column out; the pipe's output stays in the session:

```bash
doppler run -p soleur -c prd_terraform -- bash plugins/soleur/skills/cve-exposure/scripts/host-state.sh \
  | awk -F'\t' '$1 !~ /^SOLEUR_CVE_HOST_STATE/ { d = ($6 ~ /^[0-9]+$/) ? sprintf("%.1f", $6/86400) : "n/a"; print $1, $2, $3, d " days" }'
```

Only a row with `marker_state=fresh` and `kernel_state=observed` and a numeric uptime is gradable; every other row is unknown.
The roles the probe ignores (default-off hosts) and the roles it requires are listed in the probe header. The reader's output
stays in the session. There is no table script and no stored view, deliberately: a stored per-host table is the exposure register
ADR-322 rejected.

## Reading the tracker line

Once the tracker is armed, the daily follow-through sweeper posts the probe's stdout, which is exactly one of three fixed lines
(no class, count or version), inside the sweeper's own heading and `<details>` fold. The heading carries a verdict word, the exit
code and a timestamp, and the comment names the script path. So the public surface is the fixed line **inside the sweeper's
heading and fold**, not the line alone.

- `host-kernel-cadence: review-needed` (exit 5): some row's uptime is past its cadence.
- `host-kernel-cadence: cannot-establish` (exit 3): some row is unknown, or the reader failed.
- `host-kernel-cadence: nothing-to-report` (exit 2): every required row is fresh, observed and within its cadence.

**What `nothing-to-report` does not say.** `uptime_s` is the time since the last boot: a **lower bound** on how long the running
kernel has been running, never an upper bound on its age. Only an overdue verdict is therefore sound. `nothing-to-report` means
the uptime is inside the cadence, **not** that the running kernel carries the fix: a reboot onto the same unpatched kernel, or a
replace onto a base image that is not patched, resets the uptime and reads as within cadence. The uptime can also come from a row
up to 48 hours older than the row that carries the state, which understates it further. It is also not an assurance about
unmeasured hosts. The verify step after any act (a changed kernel, not only a reset uptime) is what shows a patch arrived; the
`reboot_required` clause that would narrow the gap is tracked as #12502.

Which row, and why, is answered in a session only. The probe header owns the rules, including the proxy caveat and the roles it
grades or ignores.

### Arming the tracker (#12504)

The tracker is filed unarmed. All of these hold before it is armed:

1. A session run of the probe prints `review-needed` or `nothing-to-report`, never `cannot-establish`. `review-needed` can print
   as soon as one required row is fresh and over its cadence (the emitter roll-out, #12386); `nothing-to-report` also needs the
   git-data reader source (#12385). #12385 is priority p3-low, so this precondition is structurally tied to a low-priority open
   issue: raise #12385's priority, or re-evaluate #12504 no later than 2027-02-09 (a proposed date; the owner may move it), so
   that "never armed" is a visible state and not a quiet one.
2. The acknowledgement mechanism for a row that is overdue by design has landed (its scope is recorded on #12504). It is a
   precondition, not a follow-up: without it the first dated `review-needed` is permanent, masks every later overdue row and
   dates when a row crossed its threshold on a public tracker.
3. The directive's `earliest=` is set to a real UTC timestamp (for example the output of `date -u +%Y-%m-%dT%H:%M:%SZ`), not the
   placeholder text, which would fail the date parse.
4. The `follow-through` label and the body edit that adds the unfenced directive are applied together, outside the 18:00 UTC
   cron window, so no real sweep lands between them.
5. Dispatch the sweeper in dry-run mode and read its log for the `issue #12504` lines: they must show the directive honored and a
   probe verdict. If they are wrong, remove the label.

Verification is the sweeper log, not a hook: the issue-create hook fires only on `gh issue create`, so the label-add and
body-edit path has no mechanical gate of its own.

### Accepted public residual

The thresholds are public in the probe, and a dated daily line on a public tracker can date a reboot or replace window (a move
from `review-needed` to `nothing-to-report`) or a lag (sustained `review-needed`). That is an accepted timing disclosure under
ADR-322, ended by closing the tracker and removing its label.

## Exposure suite

`scripts/host-tcp-exposure.test.sh` asserts a **declared design**, not live state; its header owns the rules and the mapping. It
cannot see console drift, a stale attachment id or a firewall that was never applied: those need a live read of the provider, a
session-only step this suite does not do. The live read is not yet written as a procedure; it is tracked as the live
firewall corroboration on #6442 (the attachment binding), and until that lands a green suite says only that the Terraform text
declares the design. A new server added to the Terraform makes the suite fail until its row is added to the mapping, by design.

## Escalation

If a verification step shows no change after a replace (uptime reset but the same kernel, or no new row at all), the host was
rebuilt but not patched, or its emitter is not delivering. Do not retry the route. Report it to the owner in the session; the next
step is the package-upgrade question above (#12503), which needs an owner-authorized plan.

**With no interactive session** (a scheduled or headless agent that sees `review-needed` on the tracker): stop. Do not write any
class, row or host detail into the repository, the tracker or an issue (ADR-322), and do not dispatch any route. No private
notification path dedicated to this signal exists yet, so the sweeper's generic comment is the only record and the owner reads
the verdict from the reader in the next session. Adding a private path is part of the arming change (#12504).
