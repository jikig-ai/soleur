---
title: "CF Tunnel SSH bridge dry-run guard: host-touching depends on WHERE the SSH lives (workflow step vs in-script)"
date: 2026-07-18
category: integration-issues
tags: [github-actions, ssh, cf-tunnel, dry-run, workspaces-luks, git-data, cutover, playwright, wayland]
module: Web Platform Infrastructure
issue: 6649
---

# CF Tunnel SSH bridge dry-run guard — a mis-copied guard, and how to tell if a dry-run is host-touching

## Problem

The #6649 LUKS-header-escrow dry-run rehearsal (`workspaces-luks-cutover.yml -f dry_run=true`)
failed at exit 255 (`ssh: connect to host 10.0.1.10 port 22: Connection timed out`, run
29644526137 — the first-ever dry-run of the workflow). The R2 creds were verified-good
(`Verify required secrets present` passed); the failure was earlier, at host reach.

## Root cause

The `CF Tunnel SSH bridge` step carried `if: ${{ !inputs.dry_run || inputs.rollback }}`,
so the ONLY invocation it skipped was `dry_run=true`. But the `Run … cutover` step
**always** pipes the cutover script to the private host over SSH
(`${WEB_HOST_SSH:-ssh} "$WEB_HOST" … < cutover.sh`, WEB_HOST=10.0.1.10 — reachable only
via the bridge's `iptables -t nat` redirect), and `escrow_probe()` runs host-side in the
dry-run arm **by design** (outside the `DRY_RUN` gate, so a GREEN escrow signal lands
during the rehearsal before any freeze). So the dry-run IS host-touching and needs the
bridge — the guard skipped it, and the SSH timed out before the script ran.

The guard was copied verbatim from `git-data-cutover.yml`, and the plan assumed it was
"correct there, don't touch it." **That premise was false** (see below).

## Key insight — where the SSH lives determines whether a dry-run is host-touching

A `dry_run` guard on the bridge is correct ONLY if the workflow's dry-run never SSHes.
That is a per-workflow property of WHERE the SSH happens:

- **In-script, per-step DRY_RUN short-circuit** → dry-run can be host-free → guard *may* be correct.
- **Unconditional workflow-step `ssh … < script.sh`, OR an in-script step that SSHes
  before the first `DRY_RUN` gate** → dry-run IS host-touching → the bridge must run on
  every invocation (no guard).

`git-data-cutover.yml` turned out to be the SECOND case, not the first: `git-data-cutover.sh`
`main()` runs `prepare_luks_target` → `preconditions` → `bulk_rsync` (all SSH to the
git-data/web hosts) **before** the first `DRY_RUN` gate (`acquire_freeze`). So it had the
identical latent bug. Both workflows were fixed by removing the guard, matching the correct
precedent `workspaces-luks-verify.yml` (bridge runs unconditionally).

## Prevention

- **Before copying a bridge/`if:` guard between cutover workflows, trace the destination's
  SSH topology.** Grep `main()` (or the workflow's Run step) for the first `DRY_RUN` gate
  and confirm no SSH call precedes it. A guard that is correct in the source can be a
  latent SSH-timeout bug in the destination.
- Routed to the `review` skill defect catalogue as a review-spawn instruction.

## Session errors (secondary)

- **Playwright X11 sanity-check false negative.** The operator runbook proxy
  `grep XDG_SESSION_TYPE=x11 /proc/<pw-mcp>/environ` can NEVER print `x11` even when the
  fix (#6675) is active: #6675 forces X11 at the **Chrome ozone layer**
  (`--ozone-platform=x11 --disable-gpu` in `.claude/playwright-mcp.config.json`), NOT via
  a process env var; `XDG_SESSION_TYPE` stays `wayland` (inherited from the OS login
  session). **Prevention:** the real health check is the *chrome child* cmdline —
  `pgrep -f 'chrome.*playwright-mcp-profile' | head -1` then grep its
  `/proc/<pid>/cmdline` for `--ozone-platform=x11` — or simply drive a benign
  `browser_navigate` and confirm no crash. The env-var proxy should be retired from the
  runbook.
- **Cutover env gate did not auto-approve.** The workflow comments claim the
  `workspaces-luks-cutover` environment "auto-approves (DP-11 F8)", but the run sat in
  `waiting` with a pending manual deployment review (`current_user_can_approve=true`).
  **Prevention:** treat the environment reviewer as a real manual gate; either wire true
  auto-approval or correct the comment.
- **git-history-analyzer returned factually-wrong reasoning** ("git-data dry-run is
  host-free"). Caught by reading `git-data-cutover.sh` `main()` directly. **Prevention:**
  when two review agents give contradictory factual claims, resolve against the artifact,
  not by vote — and accept a correct verdict even when its stated reason is wrong.
- **R2 S3 creds have no REST-API mint path** (`/accounts/<id>/r2/api-tokens` → 404 route
  error); dashboard/Playwright is the only mechanism, and the secret must be extracted via
  `browser_evaluate(filename:)` → Doppler (output suppressed) → `shred`, never
  snapshot-read (auto-snapshot on click/navigate leaks the modal value).
