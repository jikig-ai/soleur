---
name: config-gate-half-fix-and-unmasked-deterministic-deadlock
description: A feature gate that removes a resource's CREATOR but leaves a hard consumer requirement on that resource turns a flaky race into a deterministic deadlock; and an early-abort fix upstream can unmask a second, previously-hidden failure the paused arc never saw.
metadata:
  type: project
---

# Config-gate half-fix + the unmasked deterministic deadlock (#6090 / #6178)

## Problem

Fresh web-2 hosts (weight-0 warm standby) failed every `web-2-recreate`: `webhook.service`
died with systemd **226/NAMESPACE**, `:9000` never bound, and every deploy fan-out reported
`ok_peer_fanout_degraded` → the standby was undeployable. This blocked the #6178 Inngest
cutover, whose runbook step-1a needs a clean web-2 recreate.

The #6090 arc had already peeled and merged four earlier causes (three GHCR cold-boot auth
layers + a config-phase apt hang) and was **PAUSED (2026-07-07)** blocked on #6178, with the
remaining cause named as "the inngest co-location itself" — a circular-looking entanglement.

## Root cause (two composing facts)

1. `webhook.service`'s `ReadWritePaths=` listed `/var/lib/inngest` as a **mandatory** token
   (no `-` prefix). systemd fails a unit with 226/NAMESPACE if a mandatory `ReadWritePaths`
   target is absent.
2. PR-1 #6344 (`web_colocate_inngest`, default **false**) gated OFF the **only** runcmd block
   that CREATES `/var/lib/inngest` (the inngest-bootstrap). So on a default fresh host the dir
   is never created, yet the webhook still hard-required it.

⟹ #6344 **converted a previously-flaky `/var/lib/inngest` ordering race into a DETERMINISTIC
deadlock** by removing the dir-creator while leaving the hard consumer requirement in place.

## Why the paused arc never saw it

The arc's last diagnosis (2026-07-07) predates #6344 (2026-07-11). Separately, a
`deploy-fanout tag_malformed` bug (#6353/#6354) was aborting the fan-out at the tag stage —
BEFORE it ever reached the `:9000` bind poll. Fixing #6354 **unmasked** the deadlock: the first
post-#6344, post-#6354 recreate (run `29169983049`) was the first to get past the tag abort and
observe web-2 die at `:9000` (502 for the full 1800s). That deterministic-deadlock signal was
NEW evidence the paused arc never had.

## Solution

Mark `/var/lib/inngest` `-`-optional (`-/var/lib/inngest`) in **both** lockstep copies —
`cloud-init.yml` (baked at boot) and the standalone `webhook.service` (base64-delivered to
running web-1 via `server.tf` `deploy_pipeline_fix.triggers_replace`). The `-` prefix means
"ignore if absent"; when present (colocate=on) it is still a real ReadWritePath, so no
regression. `inngest-server.service` (the dir's OWNER) correctly keeps the mandatory form.

Chose `-`-optional over a templatefile `%{ if web_colocate_inngest }` guard **because the
standalone `webhook.service` reaches web-1 via raw `file()`, not `templatefile()`** — a
`%{ if }` directive would ship literally as text and break the unit. `-`-optional is also the
more correct expression: it states a flag-independent property ("this unit does not own the
dir") and matches the adjacent `-/var/lib/vector` precedent (PR #4257).

## Key insights (generalizable)

1. **A feature gate that removes a resource's CREATOR must also relax every hard CONSUMER
   requirement on that resource** — otherwise the gate flips a tolerable race into a permanent
   failure. When adding/flipping a `%{ if flag }` gate around a `mkdir`/create step, grep every
   `ReadWritePaths=`/`Requires=`/`After=`/mount/FK that references the created path and confirm
   each tolerates absence in the gated-off state.
2. **An upstream early-abort bug MASKS every failure downstream of the abort point.** When you
   fix an early abort (a malformed-tag reject, a failed precondition, a 401), re-run the
   newly-unblocked path to capture fresh signal BEFORE trusting a paused arc's last diagnosis —
   the arc only ever saw the FIRST broken step (cf. the review "multi-step saga fix" class).
3. **systemd `-` prefix on `ReadWritePaths`** = optional (skip if absent); bare = mandatory
   (226/NAMESPACE if absent). Ownership rule: only the unit that CREATES a dir should
   hard-require it; consumer units that merely reference it should mark it `-`-optional.
4. **Two byte-identical config copies delivered by different mechanisms are a lockstep contract**
   — guard with a byte-identity parity test, and assert exactly ONE `ReadWritePaths=` line per
   file so `head -1` extraction can't be silently defeated by a future second (systemd
   accumulates the directive).

## Session Errors

1. **Planning subagent: IaC-routing PreToolUse hook rejected the initial plan Write** (prose
   quoted `systemctl`). Recovery: added the `iac-routing-ack: plan-phase-2-8-reviewed` opt-out
   (the fix IS Terraform/cloud-init-routed; the `systemctl` tokens are quotes of managed
   behavior). Prevention: when a plan's prose must quote a managed host command, add the
   iac-routing-ack up front. (Recurring class, already covered by the opt-out mechanism.)
2. **shellcheck SC2034 on `eval`-consumed test vars** (`CI_RWP`/`WS_RWP`/`*_COUNT`). shellcheck
   can't see through `assert`'s `eval "$condition"`. Recovery: `# shellcheck disable=SC2034`.
   Prevention: annotate eval-consumed helper vars with the disable directive at write time.
3. **`# shellcheck disable` is per-line (next line only)** — the first fix covered CI_RWP but
   not the adjacent WS_RWP. Recovery: a directive before each assignment. Prevention: one
   directive per silenced line, not one for a block.
4. **`cloud-init schema -c cloud-init.yml` returns "Invalid schema: user-data"** — this is
   EXPECTED, not a regression: the file is a Terraform templatefile (`${...}`, `%{ if }`,
   `$${...}`) that is not valid raw cloud-init until rendered. Prevention: before treating a
   cloud-init schema failure as a regression, run it against `git show origin/main:<file>` — an
   identical failure proves it's the template artifact, not your diff.

## Tags
category: best-practices
module: apps/web-platform/infra
