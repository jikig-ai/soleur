---
title: An accepted residual named an actor that never existed, and the inngest host ran without its firewall for 65 of 78 days
date: 2026-09-25
category: security-issues
module: apps/web-platform/infra (inngest host)
tags: [hetzner, firewall, terraform, accepted-risk, guard-window, better-stack, sshd]
issues: ["#8754", "#8846", "#8867", "#6442"]
---

# Learning: an accepted residual named an actor that never existed

## Problem

`hcloud_firewall_attachment.inngest` bound the dedicated inngest host's deny-all Hetzner firewall by
server id. `inngest-host-replace` never targeted it, and a code comment explained why that was fine:
"the next full/drift apply reconciles server_ids". But no such apply existed:

- the drift check only runs `plan`;
- the per-merge apply never listed the address;
- only the birth job targeted it.

So every replace left the new host with no cloud firewall. Measured from the jobs API and apply logs,
the host was unfirewalled 2026-07-09→07-31, 2026-08-12→09-09, and 2026-09-09→2026-09-25 (still
open). That is about 65 of 78 days, with public sshd for the whole period. A 2026-07-20 plan review had
found this ("no such automated path exists"); the response was to correct the comment, not to change
the mechanism.

## Solution

Bind the firewall on the server itself with `firewall_ids = [hcloud_firewall.inngest.id]`. In hcloud
provider 1.63.0 this attribute is sent inside ServerCreate, so the host boots firewalled, and a replace
cannot leave it stale. The attachment is forgotten with `removed { destroy = false }`. That block and
its per-merge `-target` are permanent, following the doppler-write-token precedent.

Two guards pin this:

- **Guard 1 (static).** It strips `#`, `//` and `/* */` comments before matching. It refuses:
  - a duplicate or decoy `hcloud_server "inngest"` header;
  - override and `.tf.json` files;
  - server-side bindings (another attachment's `server_ids`, another firewall's `apply_to`);
  - `ignore_remote_firewall_ids` and `ignore_changes` that cover `firewall_ids`;
  - any `rule` on the deny-all firewall.

  Its RED rows and floor are reconciled against the file.
- **`firewall_not_bound` counter (replace gate, plan level).** The replacement's
  `.change.after.firewall_ids` must equal the firewall's own plan-entry id. If that id is absent or
  unknown, the gate fails closed.

## Key Insight

1. **A residual accepted on the strength of "X will reconcile it" is a claim about an actor. Name the
   run that does it, or the residual is unmitigated.** Before accepting one, grep for a job that
   actually targets the address. If none exists, the accepted risk is permanent, not transient.
2. **A static guard's window is usually narrower than the property it names.** "Born with the
   firewall" was bypassable four ways (`//`, `/* */`, a decoy block, override files), each producing a
   plan identical to the compliant one. On a fresh create the plan JSON carries no
   `.after.firewall_ids`; only `.configuration…expressions.firewall_ids.references` distinguishes the
   cases. On a replace the value is known. A plan-level check belongs on the path where the value is
   decidable: here, the replace gate.
3. **For a rare-event question, a zero is only evidence once the window is proven covered.** Proving
   that no one logged in over SSH needed three things:
   - the exact event string (`Accepted publickey`), because a bare `Accepted` matches
     `PubkeyAcceptedAlgorithms` rejections;
   - one query per window, because a noisy grep hits the 5,000-row cap;
   - a positive control (common sshd rows from the same host) showing the window's logs were shipped.

   Result: intervals 2 and 3 show zero successful logins. Interval 1 has no rows at all and stays
   inconclusive.
4. **A watchdog that substring-greps a marker also matches its own issue bodies**, once some component
   logs incoming webhook payloads (#8846). Select telemetry by the emitter (`SYSLOG_IDENTIFIER`) plus a
   start-of-message anchor.

## Session Errors

1. **Plan phase:** two wrong commit attributions, a lint issue, and a v2 firewall design that needed a
   rewrite. Recovery: fixed during deepen-plan. **Prevention:** existing plan-quality rules; no change.
2. **The plan's git-data server id was stale;** the host was replaced at 09:24, after planning.
   Recovery: noted in the work report; the 3.2 premise must be re-measured. **Prevention:** re-measure
   live ids at execution time (existing "plan-quoted numbers are preconditions" rule).
3. **I told an implementation agent to run `test-all --affected`,** and the lefthook `bun-test` hook
   ran it again inside a commit. About 30 minutes on a contended machine, until the operator asked.
   Recovery: killed only this worktree's runs; used `LEFTHOOK_EXCLUDE=bun-test` plus targeted suites.
   **Prevention:** on a contended machine, brief spawned implementers with
   `LEFTHOOK_EXCLUDE=bun-test` and targeted suites only, and rely on CI's required `test` context.
   `infra-validation` is not a required check, so verify it explicitly on the PR head before merge.
4. **The user-impact review agent returned an empty final result.** Recovery: resumed it, and it
   delivered by writing a file. **Prevention:** existing rule (mandate file delivery in the spawn
   prompt); I did not apply it to every seat.
5. **Guard 1 as first shipped could be bypassed four ways.** Recovery: hardened after review, with
   mutation-proven rows. **Prevention:** the structural-enumeration seat on guard-shaped PRs (existing).
6. **`gh issue create --body-file $S/...` was refused by the filing hook,** and the `mv` in the same
   command never ran. Recovery: separate steps with a literal path. **Prevention:** existing rule
   (write the body file in its own step and pass an absolute literal path).
7. **The filing gate refused two filings:** one had no user-visible consequence, one was small enough
   to fix inline. Recovery: added the `meta/machinery` label; folded the clause (o) fix into PR-B; used
   `Mandated-By` for #8867. **Prevention:** none needed; the gate worked as designed.
8. **Grepping `Accepted` matched `PubkeyAcceptedAlgorithms` rejections,** which I briefly read as
   accepted logins. Recovery: re-queried with `Accepted publickey`. **Prevention:** runbook bullet
   (#8754) in `betterstack-log-query.md` Query mechanics.
9. **Every multi-day `sshd` window hit the 5,000-row cap,** so counts taken from them were incomplete.
   Recovery: counted the rare string per window, plus a coverage probe. **Prevention:** the same
   runbook bullet.
10. **The legal-writer agent read its commit exit code from a piped `tail`.** Recovery: verified the
    commit via `git log` and `git status`. **Prevention:** existing rule (capture the exit code on the
    line immediately after the command).
11. **I wrote an issue-body file inside the worktree while an agent was committing there.** Recovery:
    moved it to the scratchpad. **Prevention:** scratch files go in the scratchpad, never the worktree.
12. **Discovered defect:** the inngest health watchdog feeds its own false alarm. Filed as #8846.
    **Prevention:** tracked there.

## Tags

category: security-issues
module: apps/web-platform/infra
