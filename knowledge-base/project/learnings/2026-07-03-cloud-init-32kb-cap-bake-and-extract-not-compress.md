---
title: Cloud-init 32KB cap — bake-and-extract beats compression; measure before choosing
date: 2026-07-03
category: infrastructure
module: apps/web-platform/infra
tags: [terraform, hetzner, cloud-init, user_data, ADR-080, docker, image-bake]
issue: 5921
pr: 5922
---

# Learning: Cloud-init 32KB user_data cap — bake-and-extract, not compress

## Problem

A fresh Hetzner web host could not be provisioned. `server.tf` rendered 22 bootstrap
scripts + `hooks.json` as base64 into cloud-init `user_data` (~282 KB, ~8.6× over
Hetzner's 32,768-byte hard cap). The issue proposed gzip+base64 compression as option 1.

## Root Cause

`user_data` size is a hard provider cap, not a soft budget. As the host's bootstrap
surface grew (scripts + a 10.7 KB `hooks.json`), inlining everything as base64 blew
past the cap. Compression was assumed sufficient without measurement.

## Solution

**Measure before choosing.** Measured gzip+base64 web `user_data` = 140,856 B — still
4.3× over the 32,768 cap. That falsified the compression option outright.

**Bake-and-extract** (extends ADR-080's image-baked-host-asset model):
- Bake the 22 scripts + `hooks.json.tmpl` + `journald-soleur.conf` + a new
  `soleur-host-bootstrap.sh` into the app image at `/opt/soleur/host-scripts/`.
- cloud-init's *minimal* launcher pulls the image, `docker cp`s the baked set,
  verifies a **Terraform-computed combined content-hash**, then runs the (now-trusted)
  baked bootstrap installer — which installs each file with an authoritative mode,
  injects `webhook_deploy_secret` into `hooks.json`, and writes the fail-closed
  `/run/soleur-hostscripts.ok` sentinel the terminal `docker run` gates on
  (`poweroff -f` on absence). The install ceremony lives in the baked script so it
  costs **zero** `user_data` bytes.
- Result: web `user_data` ~282 KB → ~29,290 B (≈3.1 KB under the cap). `fail2ban` /
  `journald-soleur.conf` stay inline (consumed pre-Docker). Running `web-1` is
  unaffected (`ignore_changes=[user_data]`); its scripts still arrive via the
  unchanged SSH/webhook provisioners.

## Key Insight

1. **Measure the "obvious" fix before adopting it.** The issue's option 1 (compress)
   was 4.3× short — a 30-second `gzip | base64 | wc -c` measurement redirected the
   whole design.
2. **The content-hash turns ADR-080's stale-image trap into a loud failure.** A baked
   asset can silently drift from what Terraform expects; the Terraform-computed hash
   verified at boot makes drift a boot-time abort instead of a latent bug.
3. **Fail-closed sentinel + `poweroff` on absence** is the right shape for a blind
   fresh-host surface with no SSH: a half-provisioned host removes itself rather than
   serving traffic in an unknown state.
4. A `cloud-init-user-data-size.test.ts` guard now pins web < 30,500 B (strict) with a
   structural extraction contract + Dockerfile↔server.tf baked-set parity, so the cap
   can't be silently re-breached. git-data host (a no-docker host, mechanism N/A) was
   found ALSO over cap post-#5918 (~41.7 KB) and filed as #5927; the size test pins it
   at a no-further-growth ceiling.

## Session Errors

- **Trailer-parse ship gate false-positive** — commit body had a `Guards:` prose line
  that matched the ship-skill trailer gate's `^Word: value` candidate regex, so the
  gate flagged it as a demoted trailer even though the real trailer (`Ref #5921`) was
  correctly the final paragraph. Recovery: reworded `Guards:` → `Guard tests:` (two
  words breaks the single-token candidate shape) via reset + amend + cherry-pick (the
  offending commit was not HEAD). **Prevention:** avoid leading a commit-body prose
  line with a single capitalized token + colon (`Note:`, `Result:`, `Caveat:`,
  `Guards:`) — the ship trailer gate cannot distinguish prose from a demoted real
  trailer. Recurring but low-severity (different subsystem = ship skill); documented,
  not filed, to avoid net-growing the backlog.
- **IaC-routing hook blocked plan-phase Writes** (forwarded from session-state.md) —
  literal `systemctl` / `/etc/systemd/system/` tokens in pseudocode tripped the
  PreToolUse IaC-routing hook. Recovery: sanctioned `iac-routing-ack` opt-out +
  neutralizing illustrative literals. Already-enforced (opt-out exists); no change.
- **`git tag` forced-annotated** — `git tag <name> HEAD` failed with "no tag message"
  (config forces annotated). Recovery: `git branch -f` for the backup ref. One-off
  machine-config quirk.
- **Scratchpad dir absent** — a `sed`/redirect into the session scratchpad path failed
  until `mkdir -p`. **Prevention:** `mkdir -p` the scratchpad before first write.
  Transient one-off.

## Prevention

- Keep the `cloud-init-user-data-size.test.ts` guard green — it is the regression net.
- When a provider imposes a hard size cap, prefer **externalize (bake/extract)** over
  **compress**; only fall back to compression after measuring it clears the cap with
  margin.

## Related

- ADR-080 (runtime-plugin-deploys-via-image-rebuild) — amended by this PR
- `knowledge-base/engineering/operations/runbooks/fresh-host-bootstrap-recovery.md`
- Issue #5927 (git-data host over cap — hard blocker on ADR-068 Phase 2)
