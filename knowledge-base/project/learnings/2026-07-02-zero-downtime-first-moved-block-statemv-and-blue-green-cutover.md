---
title: "Zero-downtime-first: a moved-block wedge clears with `terraform state mv` (no reboot), and singleton→cluster cutover is blue-green — default to it before accepting downtime"
date: 2026-07-02
category: workflow-patterns
tags: [zero-downtime, terraform, state-mv, blue-green, moved-block, hetzner, cutover, adr-068, infra]
issue: 5887
---

# Learning: default to zero-downtime; the rebooting path is rarely the only one

## Problem

The #5877 `moved`-block migration (singleton → `for_each` on the prod web host) wedged both target-scoped terraform apply pipelines. The remediation was framed — in the issue, the plan's first draft, and my own first summary — as an **operator maintenance-window `terraform apply` that reboots the running web host**. That framing treated downtime as the baseline.

It wasn't. Two cheaper, zero-downtime paths existed and were only found by asking "what's the zero-downtime version?" *before* accepting the reboot.

## What actually worked (zero downtime)

1. **Clear the wedge with `terraform state mv`, not an apply.** The wedge is caused *only* by **pending** `moved` blocks. Consuming them is a pure state re-address — `terraform state mv 'hcloud_server.web' 'hcloud_server.web["web-1"]'` (×3) — with **zero infra change, zero reboot, no new hosts**, fully reversible (back up state first via `terraform state pull`). After it, the plan-time "Moved resource instances excluded by targeting" error is gone. `moved` blocks and `state mv` are equivalent; the blocks are just the declarative form that auto-consumes *on apply* (with the apply's other side effects). When you want the re-address WITHOUT the side effects, do it as a state op.

2. **Singleton→cluster cutover is blue-green.** A fresh host created by `for_each` is **born into the placement group at creation — no reboot**. Only the pre-existing host needs the power-off (Hetzner attaches a placement group only to a stopped server). So the zero-downtime sequence is: provision the new host (in the group) → drain the old host (stop its cloudflared connector / router weight) → attach the old host to the group (reboot) **while drained** → restore. The reboot happens to a non-serving host.

## The generalizable rule

For any change that would take a serving surface offline — a host reboot/replace, a singleton→cluster cutover, a lock-taking/table-rewriting DB migration, a deploy that drops in-flight requests — **default to a zero-downtime path and prove it, before accepting downtime.** The zero-downtime toolkit: blue-green, rolling, expand-contract (add-nullable → backfill → enforce → drop), `state mv`/state-only re-address, `CREATE INDEX CONCURRENTLY`, `ADD CONSTRAINT … NOT VALID` then `VALIDATE`, drain-then-act. Downtime is acceptable only with explicit justification + a bounded window + operator sign-off. Encoded as deepen-plan Phase 4.55 + a review defect-class.

## Layer-2 gotchas (found by actually triggering the pipeline)

- **Clearing a plan-time error can expose an apply-time cascade.** After the `state mv`, the CI apply reached *further* and failed differently: CI's `-target` allow-list includes `hcloud_firewall_attachment.web`, which depends on the whole `hcloud_server.web` `for_each` map, so a *targeted* apply **cascades into the un-provisioned cluster** (web-1 placement attach → `server_not_stopped`; web-2 create → user_data bug). Lesson: a targeted apply pulls in its targets' dependencies' *pending changes* — a `for_each` refactor can silently make an allow-listed resource drag the whole cluster into every CI apply. Verify the actual pipeline, don't assume "cleared the error = green."
- **Hetzner `user_data` caps at 32,768 bytes.** A fresh server whose cloud-init inlines base64-encoded scripts (`base64encode(file(...))` ×N) can exceed it; the existing host dodges it via `lifecycle { ignore_changes = [user_data] }`. Fix: `base64gzip()` the user_data (cloud-init auto-decompresses) or fetch scripts at boot instead of embedding. Filed #5921.

## Key insight

The reboot was the default only because nothing forced a zero-downtime evaluation first. The moment you ask "what's the state-only / blue-green / concurrent version?", the answer usually exists — and for a live single-operator brand surface, that question is mandatory, not optional. See ADR-068 §Amendment (2026-07-02, #5877/#5887).
