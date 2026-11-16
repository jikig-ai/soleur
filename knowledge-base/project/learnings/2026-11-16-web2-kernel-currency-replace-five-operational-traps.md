---
title: The web-2 kernel-currency replace — five operational traps (parallel CI fix, queued run, uutils multicall, empty drain, post-rebirth marker)
date: 2026-11-16
category: integration-issues
module: .github/workflows/cf-lb-overlay.yml, .github/workflows/workspaces-luks-verify.yml, knowledge-base/engineering/operations/runbooks/web-host-replace.md
tags: [web-host-replace, cf-lb-overlay, lb-weight-gate, web2_marker, workspaces-luks, luks, uutils, ubuntu-26.04, github-actions, collision-probe]
issues: [12613, 12820, 12008, 9421, 12705, 12782, 12783, 12790]
pr: 12821
---

# Learning: five traps hit during the web-2 kernel-currency replace

Context: PR #12613 (web hosts boot onto the installed kernel at birth, PR 1/7 of #9421) merged 2026-11-16T11:34Z as `c2ec3b2c06`. web-2 was then replaced the same day (run 43862798565, `image_tag=v0.413.0`). It is healthy but drained at weight 0. #12820 tracks the restore to serving. Ref #12008, Ref #9421.

## 1. A CI fix that a parallel feature PR had already carried

**Problem.** PR #12782 (`fix-ci-uutils-timeout-124`, opened 2026-11-15T11:21Z) fixed the ubuntu-26.04 uutils breakage. PR #12705 had been open since 2026-11-12, under a title about something else ("dark opt-in PostToolUse gh-output framing hook"). It carried the same three fixes:

- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`: the mint ref-hang row now accepts exit 124 or 137.
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate-exit.test.ts`: the multicall `sleep` row.
- `.github/workflows/ci.yml`: the ubuntu-24.04 runner pins.

#12705 merged at 2026-11-16T00:04Z as `f4302a681b`. #12782 was closed as superseded at 09:42Z.

**Key insight.** A CI fix often rides inside an unrelated feature PR whose author hit the same breakage. A search by title or issue misses it. Only a probe over the **files** the fix touches finds it.

**Solution.** Before fixing breakage on main, run the files probe for each file you will edit:
`gh pr list --state open -L 100 --json number,files --jq '.[] | select(any(.files[].path; . == "<file>")) | .number'`

`soleur:one-shot` already prescribes this anchor probe in two places: a basename form at Step 0a.5, and the exact-path form above at the post-planning re-probe. The gap appeared because this CI fix was made by hand in a postmerge session. `soleur:postmerge` Phase 2 now runs the same probe when CI fails on main.

## 2. A workflow_dispatch run sat "queued" for 28 minutes, and a later dispatch ran at once

**Measured.**

- Run 43859369519 of `web-host-escrow-diagnose.yml` was created at 11:37:23Z. Its only job started at 12:05:15Z and succeeded at 12:05:36Z.
- A second dispatch, run 43861275484, was created at 11:50:39Z. Its job started 8 s later.
- Two causes are ruled out:
  - an approval gate: the `infra-privileged` environment's only protection rule is `branch_policy`, with no required reviewers;
  - a concurrency queue: the workflow declares no `concurrency:` key.
- The cause of the 27 min 52 s wait was not measured. A hosted-runner allocation stall is the likeliest reading, and it is not a capacity signal.

**Key insight.** The first run **still executed**, 28 minutes after it was created, even though it had been treated as cancelled. A queued run you think you cancelled can still run. That is harmless for a read-only diagnose. For a mutating workflow it is a second apply.

**Solution.**

- **Read-only workflow.** Dispatch a fresh run so you are not blocked. Then confirm the old run's final state from `gh run view <id> --json jobs`, not from what the cancel command printed.
- **Mutating workflow.** Confirm before you dispatch:
  1. Run `gh run cancel <id>` and wait until the run reads `status=completed`.
  2. Check every job with `gh run view <id> --json jobs --jq '.jobs[]|{name,startedAt,conclusion,steps:[.steps[]|{name,conclusion}]}'`. Each job must either have no `startedAt`, or have its plan and apply steps `skipped` or missing. A job that started and then concluded `cancelled` may have applied part of its change.
- **Two more mechanics.** `cf-lb-overlay.yml` and the infra apply share the concurrency group `terraform-apply-web-platform-host`, with `cancel-in-progress: false`. A fresh dispatch queues behind a running one, and a newer pending run replaces an older pending one. A run waiting on `web-platform-infra-apply` (which has required reviewers) is waiting for approval, not for a runner. Approve only the intended run id and reject the stale one.

## 3. A uutils multicall binary copied under a new name exits instead of running

**Problem.**

- On ubuntu-26.04 (`ubuntu-latest`), coreutils is uutils. It is a multicall binary (`/usr/bin/sleep -> ../lib/cargo/bin/coreutils/sleep`) that picks its command from the name of the file it was run as.
- The `isAlive` oracle row in `cron-claude-eval-substrate-exit.test.ts` needed a live process whose comm is `x) Z y`. It copied the sleep binary to a file of that name and ran it.
- uutils printed `coreutils: unknown program 'x) Z y'` and exited 1, so the probe read ESRCH (#12783).
- Setting argv0 to `sleep` did not help (#12783, reproduced in `docker run ubuntu:26.04`). On Linux argv0 never sets comm anyway: the kernel takes comm from the executed file's name.

**Solution.** Run the long-lived process as a `#!/bin/sh` script file carrying the wanted name, with a bounded loop that calls `$SLEEP_BIN 1` at most 120 times. This is the shape #12705 landed in that test file. The kernel names a script's process after the script file, so comm reads the script name on both GNU and uutils hosts. The ubuntu-24.04 runner pins in `.github/workflows/ci.yml` stay until #12790 unpins them.

## 4. The post-replace drain refuses an empty change set when the pool is already drained at an unchanged IPv4

**Problem.**

- The runbook's "After replacing web-2: reconcile the load-balancer origin address" section says to run `arm=ga-pool-update mode=drain`, because a replaced server can come back with a new public IPv4.
- This time the server (176328334) kept its address, 204.168.189.200.
- The pre-replace drain (run 43862065138) had already set web-2 to weight 0, so the pool origin was already correct.
- The post-replace drain (run 43864446112) therefore failed at its Plan gate with `ga-pool-update gate: empty change set` and applied nothing.

**Solution.**

1. Read the replaced server's IPv4 from the replace run's apply output (`web_2_server_ip`) or the Hetzner API, never by SSH.
2. Read web-2's live pool origin `address` and `weight`.
3. Skip the drain only when the address is unchanged **and** the weight is 0. The replace never touches the pool and keeps the weight it found, so weight 0 holds only if a pre-replace drain ran and nothing has restored weight 1 since. Restoring weight 1 can come from a `mode=serve`, a pool re-create, or an untargeted apply that omits `-var=web2_lb_weight=0`.
4. If you cannot read the pool, dispatch the drain anyway. Its empty-change-set refusal proves the pool is already drained, and it applies nothing.

The runbook section now says so.

## 5. A web2_marker run before the new host's first probe deletes the inherited marker and restarts the soak

**Measured.**

- Readiness was `fresh_boot_ready … kernel=1` at 2026-11-16T12:08:35Z.
- `web2_marker` run 43868653055 was dispatched before the new host had written a probe row. It reported `RED reason=probe_predates_ready` and deleted the marker held from the previous instance.
- That is the fail-closed behaviour documented in the runbook's web2_marker reason table.

**Mechanism.** `w2l_judge` in `scripts/lib/web2-luks-rows.sh` handles a held marker this way. The newest probe row keeps the marker, unless a readiness row is newer than that probe row. So a held marker survives a rebirth unless a `web2_marker` run lands between the new readiness row and the new host's first probe row. The runbook already states the corollary: "a replacement can inherit a present marker with its age". The early dispatch landed in that window.

**Timeline to serve** (#12820):

1. The host's `luks-monitor.timer` (`OnCalendar=daily`, `RandomizedDelaySec=1800`) writes the first probe row newer than readiness. It is expected around 2026-11-17 00:00–00:30Z if the host clock is UTC. The judge's staleness ceiling (`W2L_MAX_AGE_S=93600`, 26 h) puts the latest at 2026-11-17T14:09Z.
2. The next `web2_marker` run after that row reports `marker_written`. That is the scheduled run at 04:41Z or a dispatch from `main`. The marker's value is that run's own clock time ("the 3-day soak starts now").
3. `WORKSPACES_LUKS_SOAK_DAYS` (3 by default in `lb-weight-gate.sh`) is measured from the marker's value, not from readiness. If the scheduled 2026-11-17T04:41Z run writes it, serve is possible from about 2026-11-20T04:41Z. Until the marker exists, the gate refuses with `B_workspaces_luks_marker_absent`. After that, it refuses with `B_workspaces_luks_soak_not_elapsed` until the soak ends.
4. Dispatch `cf-lb-overlay.yml` from `main` with `arm=ga-pool-update mode=serve confirm=UPDATE-GA-LB-POOL`. It waits for the owner's approval on `web-platform-infra-apply`. Never SSH.

**Key insight.** Do not run `web2_marker` until a probe row newer than readiness exists. Here the early dispatch moved serve from the day after the replace to about 4 days after it. The marker certifies the old instance and is deleted fail-closed, so never restore it by hand. Until serve, the fleet has one serving host (web-1), with no failover.

## Session Errors

1. **The superseded CI fix (#12782).** A day of work was duplicated by #12705.
   - **Recovery:** closed #12782 as superseded, after confirming main carried all three fixes.
   - **Prevention:** `soleur:postmerge` Phase 2 now runs the files-based open-PR probe before a CI fix on main. It mirrors the `soleur:one-shot` anchor probe.
2. **The escrow-diagnose run stuck in "queued" was treated as cancelled, but it ran 28 min later.**
   - **Recovery:** a fresh dispatch ran at once.
   - **Prevention:** before re-dispatching a *mutating* workflow, confirm the old run reads `completed` and that no job started its plan or apply steps (section 2).
3. **A uutils `sleep` copied under a new file name exited with `unknown program` (#12783).**
   - **Recovery:** a `/bin/sh` script named for the wanted comm (#12705).
   - **Prevention:** on uutils runners, never copy or link a coreutils binary under a new name. For a process with a chosen comm, run a shell script file of that name (section 3).
4. **The post-replace drain was dispatched without reading the server IPv4 and the pool weight, and it refused an empty change set.**
   - **Recovery:** none needed. The pool was already correct at weight 0.
   - **Prevention:** web-host-replace.md now says to compare the IPv4 and the live web-2 weight first. Skip the drain only when the address is unchanged and the weight is 0.
5. **`web2_marker` was dispatched before the new host's first probe row, which deleted the inherited marker and restarted the soak.**
   - **Recovery:** wait out the probe and the soak (#12820).
   - **Prevention:** web-host-replace.md now names the window. Do not run `web2_marker` between the new readiness row and the first new probe row.
6. **This session's `worktree-manager.sh cleanup-merged` ran past the 120 s foreground timeout**, and the harness moved it to the background. There were about 60 worktrees under `.worktrees/` plus many `.claude/worktrees/agent-*`.
   - **Recovery:** it completed with exit 0.
   - **Prevention:** run `cleanup-merged` with `run_in_background` when `.worktrees/` holds more than about 30 entries.
7. **Three claims inherited from the resume brief were wrong, and the first draft of this learning repeated them.**
   - The stuck run was not cancelled: its job ran at 12:05Z.
   - The uutils trap was a copied binary, not `exec -a`.
   - The soak does not start at readiness.
   - **Recovery:** corrected from `gh run view --json jobs`, issue #12783, `lb-weight-gate.sh` and `workspaces-luks-verify.yml`, after a 4-agent review found them.
   - **Prevention:** re-measure every inherited claim before writing it down (compound Phase 0.5). A timeline that names a gate must cite where that gate reads its clock.
