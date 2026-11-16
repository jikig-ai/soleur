---
title: The web-2 kernel-currency replace — five operational traps (parallel CI fix, queued run, uutils multicall, empty drain, post-rebirth marker)
date: 2026-11-16
category: integration-issues
module: .github/workflows/cf-lb-overlay.yml, .github/workflows/web-host-escrow-diagnose.yml, knowledge-base/engineering/operations/runbooks/web-host-replace.md
tags: [web-host-replace, lb-weight-gate, web2_marker, uutils, ubuntu-26.04, github-actions, collision-probe]
issues: [12613, 12820, 12008, 9421, 12705, 12782, 12790]
---

# Learning: five traps hit during the web-2 kernel-currency replace

Context: PR #12613 (web hosts boot onto the installed kernel at birth, PR 1/7 of #9421) merged 2026-11-16T11:34Z as `c2ec3b2c06`. web-2 was then replaced the same day (run 43862798565, `image_tag=v0.413.0`). It is healthy but drained at weight 0. #12820 tracks the restore to serving. Ref #12008, Ref #9421.

## 1. A CI fix that a parallel feature PR had already carried

**Problem.** PR #12782 (`fix-ci-uutils-timeout-124`, opened 2026-11-15T11:21Z) fixed the ubuntu-26.04 uutils breakage: the mint ref-hang row exiting 124 vs 137, the multicall `sleep` row, and the `test-scripts` runner pin. PR #12705 had been open since 2026-11-12. Its title was about something else ("dark opt-in PostToolUse gh-output framing hook"), but it carried the same three fixes in `.github/workflows/ci.yml` and `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`. #12705 merged at 2026-11-16T00:04Z as `f4302a681b`, and #12782 was closed as superseded at 09:42Z.

**Key insight.** A CI fix often rides inside an unrelated feature PR whose author hit the same breakage. A search by title or issue misses it. Only a probe over the **files** the fix touches finds it.

**Solution.** Before fixing breakage on main, run the files probe: `gh pr list --state open -L 100 --json number,files --jq '.[] | select(any(.files[].path; . == "<file>")) | .number'` for each file you will edit. `soleur:one-shot` Step 0a.5 already prescribes this anchor probe for freeform prompts. The gap appears when a CI fix is made by hand outside one-shot, for example during a postmerge session.

## 2. A workflow_dispatch run sat "queued" for 28 minutes, and a later dispatch ran at once

**Measured.** Run 43859369519 of `web-host-escrow-diagnose.yml` was created at 11:37:23Z. Its only job started at 12:05:15Z and succeeded at 12:05:36Z. A second dispatch, run 43861275484, was created at 11:50:39Z and its job started 8 s later. The `infra-privileged` environment has no required reviewers (its only protection rule is `branch_policy`), so the wait was not an approval gate. The cause was not measured: it was a hosted-runner allocation stall, not a capacity signal.

**Key insight.** The first run **still executed** 28 minutes later, even though the operator had treated it as cancelled ("cancel said completed"). A queued run that you think you cancelled can still run. That is harmless for a read-only diagnose. For a mutating workflow it is a second apply.

**Solution.** When a dispatch stays queued, dispatch a fresh run so you are not blocked. Then confirm the old run's final state from its **job** `startedAt` / `conclusion` (`gh run view <id> --json jobs`), not from what the cancel command printed. Before dispatching the fresh run of a mutating workflow, check that the old one ended in `cancelled`.

## 3. argv0 does not change uutils' multicall dispatch

**Problem.** On ubuntu-26.04 the coreutils are uutils, a multicall binary. A test that needed a process whose `comm` differs from `sleep` used `exec -a <name> sleep …`. The process still dispatched as `sleep` and kept the `sleep` comm.

**Solution.** Run the long-lived process as a `/bin/sh` script with a bounded loop (the shape #12705 landed). The interpreter is then a real, separate binary whose comm you control. Runner pins to ubuntu-24.04 stay until #12790 unpins them.

## 4. The post-replace drain refuses an empty change set when the IPv4 is unchanged

**Problem.** The runbook's "After replacing web-2: reconcile the load-balancer origin address" section says to run `arm=ga-pool-update mode=drain` because a replaced server can come back with a new public IPv4. This time it kept 204.168.189.200 (server 176328334). The pool origin was already correct, and already at weight 0 from the pre-replace drain (run 43862065138). The drain (run 43864446112) therefore refused an empty change set.

**Solution.** Read the replaced server's IPv4 first, from the replace run's apply output or the Hetzner API, and never by SSH. Compare it with the pool origin. If they are equal, skip the drain and go straight to the serve prerequisites. The runbook section now says so.

## 5. web2_marker right after a rebirth deletes the inherited marker, and serve is days away

**Measured.** `web2_marker` run 43868653055 reported `RED reason=probe_predates_ready` and deleted the marker inherited from the previous instance. That is the documented post-rebirth state (runbook web2_marker reason table). Readiness was `fresh_boot_ready … kernel=1` at 2026-11-16T12:08:35Z.

**Timeline to serve** (#12820):
1. The host's daily `luks-monitor` probe writes a row newer than the readiness row: at most 26 h, so by 2026-11-17 ~14:00Z.
2. The next `web2_marker` run (daily at 04:41Z, or a dispatch from `main`) reports `marker_written`.
3. `WORKSPACES_LUKS_SOAK_DAYS` (3 by default) elapses from readiness: not before 2026-11-19T12:08Z (`B_workspaces_luks_soak_not_elapsed` until then).
4. Dispatch `cf-lb-overlay.yml` from `main` with `arm=ga-pool-update mode=serve confirm=UPDATE-GA-LB-POOL`. It waits for the owner's approval on `web-platform-infra-apply`. Never SSH.

**Key insight.** Running `web2_marker` immediately after a replace gains nothing and destroys the inherited marker. Plan the serve step about 3 days after the replace, not the same day. Until then the fleet has one serving host (web-1), with no failover.

## Session Errors

1. **The superseded CI fix (#12782).** A day of work was duplicated by #12705. — Recovery: closed as superseded after confirming main carried all three fixes. — **Prevention:** before a hand-made CI fix on main, run the files-based open-PR probe from `soleur:one-shot` Step 0a.5 (the anchor probe) over every file the fix edits. It is already skill-enforced inside one-shot; outside one-shot it is a habit, recorded here.
2. **The escrow-diagnose run stuck in "queued" was read as cancelled, but it ran 28 min later.** — Recovery: a fresh dispatch ran at once. — **Prevention:** confirm a cancelled run's terminal state from its job `conclusion` before re-dispatching a *mutating* workflow (section 2).
3. **`exec -a` did not change uutils' multicall `sleep` dispatch.** — Recovery: a `/bin/sh` wrapper. — **Prevention:** on uutils runners, never rely on argv0 to rename a coreutils process. Use a shell-script process (section 3).
4. **The post-replace drain was dispatched without first reading the server IPv4, and it refused an empty change set.** — Recovery: none needed; the pool was already correct at weight 0. — **Prevention:** web-host-replace.md now says to compare the IPv4 first and skip the drain when it is unchanged.
5. **`web2_marker` was dispatched right after the rebirth and deleted the inherited marker.** — Recovery: wait out the probe and the soak (#12820). — **Prevention:** already documented in the runbook's web2_marker reason table (`probe_predates_ready`). Plan serve for about 3 days after the replace.
6. **This session's `worktree-manager.sh cleanup-merged` ran past the 120 s foreground timeout** (about 60 worktrees under `.worktrees/` plus many `.claude/worktrees/agent-*`), and the harness moved it to the background. — Recovery: it completed with exit 0. — **Prevention:** one-off. Run it with `run_in_background` when the worktree count is high.
7. **A sentence inherited from the resume brief was wrong.** The brief said the stuck run was cancelled ("cancel said completed"). Its job timings show it executed at 12:05Z. — Recovery: corrected here from `gh run view --json jobs`. — **Prevention:** re-measure inherited claims before writing them down (compound Phase 0.5).
