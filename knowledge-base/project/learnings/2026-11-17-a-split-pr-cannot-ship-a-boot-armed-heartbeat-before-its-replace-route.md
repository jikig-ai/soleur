---
title: "A split PR cannot ship a boot-armed heartbeat before its replace route"
date: 2026-11-17
category: integration-issues
module: apps/web-platform/infra
tags: [planning, heartbeat, betterstack, bastion, plan-review, readiness]
issue: 12866
---

# Learning: a split PR cannot ship a boot-armed heartbeat before its replace route

## Problem

While planning web-1 retirement step 2 (#12866, ADR-327), the CTO made two rulings on the same day.
F3 added a self-pinged Better Stack heartbeat to the new bastion host, and F7 split the step into
PR 2a (host and birth route) and PR 2b (#12879, replace route). Nobody saw that the two collide until
the Kieran reviewer read `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`. That test requires
every `arming: "dedicated-host-boot"` row in `plugins/soleur/lib/heartbeat-manifest.ts` to declare a
`replace_target`, an `apply_target` option for it, and a `-replace='hcloud_server.<host>'` line in
the workflow. There is no exception for a paused heartbeat (see the `paused_boot_prd` fixture). PR 2a
could not have passed CI with the heartbeat in it.

The same review found a second assumption from an earlier route. `fresh-host-boot-trail.sh` exits 0
on a clean boot, on a skipped read (unbound token), and on `cloud_init_complete` without
`fresh_boot_ready`. It also accepts an event that has no `host_name` tag. A route that reads "ready"
from that exit code reports a host ready that never was.

## Solution

- The CTO re-ruled: the heartbeat, its timer, its manifest row and its egress allowlist entry all move
  to #12879. The cost is recorded as an accepted gap: 2a has no signal after birth. This is safe only
  because nothing depends on the bastion until step 3, which #12879 blocks.
- The plan adds an opt-in strict mode to the reader (`BOOT_TRAIL_STRICT=1`, `BOOT_TRAIL_HOST_NAME`).
  It requires an exact host tag and a `BOOT_TRAIL_SINCE` anchor, treats an unbound token as not
  ready, and prints one `verdict=` line. The decision lives in a library
  (`scripts/lib/bastion-boot-verify.sh`), following `git-data-boot-signal-poll.sh`.

## Key Insight

When a plan splits a host's routes across PRs, check every parity test that ties a resource to a
route before deciding which PR gets the resource. Heartbeats, host creates and replace targets are
all paired by such tests in this repo. Grep the resource type across `plugins/soleur/test/` and
`plugins/soleur/lib/` for the manifest that pairs it. The ruling that splits the PR is the point
where this check is cheapest.

## Session Errors

1. **`HCLOUD_TOKEN` absent from Doppler `prd_terraform`.** Recovery: used `HCLOUD_TOKEN_READONLY` for
   the catalog read. **Prevention:** read-only probes use the read-only token by default.
2. **Hetzner `/v1/datacenters` returned HTTP 410 (deprecated).** Recovery: read stock from
   `server_types[].locations[].available`, as `stock-preflight-gate.sh` already does.
   **Prevention:** copy the probe from the repo's gate, not from memory of the API.
3. **A `cd` into the bare repo's plugin references dir left the shell outside the worktree.**
   Recovery: `cd` back, and read plugin files by absolute path. **Prevention:** never `cd` to read;
   use absolute paths (hr-when-in-a-worktree-never-read-from-bare).
4. **`gh issue create` refused by a hook for a missing `--milestone`.** Recovery: read the parent
   issue's milestone and re-run. **Prevention:** already hook-enforced; pass `--milestone` on the first try.
5. **The plan placed a boot-armed heartbeat in a PR with no replace route.** Recovery: CTO re-rule
   moved it to #12879. **Prevention:** a plan Sharp Edges entry (routed with this learning): grep the
   pairing manifest and parity test before assigning a heartbeat to a split PR.
6. **The plan decided readiness from the boot-trail reader's exit code.** Recovery: strict mode with a
   `verdict=` line, a host-tag match and a required anchor. **Prevention:** the same Sharp Edges entry;
   AP-027 already requires the anchor.
7. **The plan told a cloud-init-only host to follow the 1,024-line web egress resolver.** That
   resolver is delivered in a file bundle, not by cloud-init, and rendering it would make every web
   egress edit replace the bastion. Recovery: a small bastion-only `bastion-egress.sh` that takes the
   two rules that matter (atomic swap, never empty the set). **Prevention:** before saying "follow X",
   check how X is delivered and what it costs to carry.
8. **Smaller plan errors caught at review:** a uniqueness check written as a variable validation
   (needs Terraform 1.9; the root allows 1.7), costs in EUR in a USD ledger column, a reference to the
   workflow-level concurrency group that read as a job-level one, and an `ip`-family table that would
   leave IPv6 open. Recovery: each fixed in the plan. **Prevention:** the sharp-edges pass and the
   five-agent panel caught all of these. Keep running both on infra plans.
9. **A stop hook fired on a closing sentence promising an edit.** Recovery: made the edit in the same
   turn. **Prevention:** do the step before writing about it.

## Tags

category: integration-issues
module: apps/web-platform/infra
