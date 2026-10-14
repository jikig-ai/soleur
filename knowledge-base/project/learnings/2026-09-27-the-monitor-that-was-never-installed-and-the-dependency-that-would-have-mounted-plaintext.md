---
title: "The monitor that was never installed, and the dependency that would have mounted plaintext"
date: 2026-09-27
category: integration-issues
module: apps/web-platform/infra (luks-monitor, workspaces-luks.tf, betterstack-logs-alerts.tf)
issue: 8706
pr: 9044
tags: [systemd, terraform, observability, better-stack, heartbeat, guard-design, luks]
---

# Learning: the monitor that was never installed, and the dependency that would have mounted plaintext

## Problem

web-1's daily LUKS at-rest probe (`luks-monitor.timer`) produced no output off-box for nine weeks.
The apply log of run 36005279546 showed why: `0 timers listed.` and an empty `UnitFileState`. The
units and `/usr/local/bin/luks-monitor` were never installed. The only installer was the tail of
`workspaces-cutover.sh`, and both real cutover runs that passed the host canary died in
`app_canary`, before that tail.

Nothing noticed because the shared heartbeat had a second pusher (the verify job, over SSH), and
the heartbeat manifest's static arming guard matched a line of code that had never executed.

## Solution

- `terraform_data.luks_monitor_install` (workspaces-luks.tf) delivers the probe, the emit helper
  and both units, writes the `SOLEUR_SENTRY_DSN=` line, arms and asserts the timer, and kicks one
  `--no-block` run. It is targeted by the per-merge SSH apply, so the arming line runs on every
  change to its inputs.
- `logtail_exploration_alert.luks_monitor_host_timer_dark` pages when no `OK:` row from
  `_SYSTEMD_UNIT=luks-monitor.service` on `host_name='soleur-web-platform'` lands in 27 h. The verify
  job's rows (session scope, no unit) cannot keep it quiet.
- A follow-through closes #8706 after three consecutive host-timer nights.

Review then changed the design in one place that mattered: `luks-monitor.service` carried
`RequiresMountsFor=/mnt/data`. That is Requires-strength, so the first daily start with `/mnt/data`
unmounted would have started `mnt-data.mount` and mounted whatever fstab names — on web-1 the
superseded plaintext volume. It is now ordering-only (`After=`), and the probe reports
`not_mounted` itself. Same downgrade as `inngest-cutover-flip.service` (#7228).

## Key Insight

Arming something that never ran is not a delivery change, it is a first execution. Everything the
dormant thing declares — its dependencies, its env file, its restart semantics — runs for the first
time too, and none of it has been reviewed as live behaviour. A plan line saying "no changes to
luks-monitor.service" was true about bytes and silent about the unit's first start.

Second: a shared log source is a shared namespace. An alert keyed on a unit name is host-agnostic
unless it names the host, and web-2 ships to the same Better Stack source as web-1.

Third, on guards: the first round of this PR's guards were deny-lists or single spellings (one
`systemctl start X.service` regex, a `cat`-only leak check, an `inline`-only writer census, a
presence-only follow-through predicate). The structural-enumeration seat found seven evasions in
one pass. Writing the guard against the grammar (every start verb, suffix optional, unit-file
dependencies) and as an allowlist (the only permitted ways to touch the env file) closed the class.

## Session Errors

1. **Plan-write guard blocked a Research Insights edit (systemd wording).** Recovery: added the
   iac-routing ack. **Prevention:** none needed; the guard worked as designed.
2. **An advisor consult was sent with a literal `{PLAN_TEXT}` placeholder.** Recovery: re-sent with
   the plan text. **Prevention:** one-off.
3. **A scripted plan edit failed on a duplicate heading match.** Recovery: anchored at line start.
   **Prevention:** assert `s.count(old) == 1` before every scripted replace (already the rule).
4. **A research agent claimed `lower_than` + `treat_as_zero` is silent on empty data.**
   Recovery: disregarded against the `claude_cost_capture_dark` precedent. **Prevention:** one-off.
5. **The first `query_period` API probe used the wrong request body (HTTP 422).** Recovery: read
   the API docs, re-ran with `chart` + `queries`; 97200 was accepted and read back unclamped.
   **Prevention:** read the create-endpoint docs before a vendor probe.
6. **The first install-suite draft had five bugs:**
   - an unnormalised expected set;
   - Python `$` used where Terraform's RE2 `$` means something else (Python also matches before a
     trailing newline);
   - a basename comparison against the mutation copy;
   - a mutation anchor that also matched another alert;
   - a fatal (rc 2) where RED was meant.

   Recovery: fixed before commit; mutation rows now grade by the named `[FAIL]` check.
   **Prevention:** when a test re-implements a vendor regex engine, translate the anchors (`$` →
   `\Z`); make every mutation anchor unique in its file.
7. **The test-design reviewer's first mutants landed in the token installer (non-unique anchor).**
   Recovery: re-anchored. **Prevention:** same as 6.
8. **The commit hook refused the full battery.** Editing `scripts/test-all.sh` degrades the
   affected run to full, and two sibling runs were active. Recovery:
   `LEFTHOOK_EXCLUDE=bun-test` plus the scoped selector. **Prevention:** known contention class
   (ADR-133); no new action.
9. **The local scoped gate queued ~40 min behind sibling worktrees and was stopped.** CI's
   required `test` check runs the full battery; `deploy-script-tests` (infra suites) is NOT
   required, so ship must read it explicitly. **Prevention:** known; stated in the PR body.
10. **The plan left `RequiresMountsFor=/mnt/data` on a unit this PR arms for the first time.**
    Recovery: ordering-only `After=`. **Prevention:** plan-sharp-edges bullet added (arming a
    dormant unit re-reads its dependency directives).
11. **First-round guards were deny-lists or single spellings.** Recovery: rewritten against the
    grammar and as allowlists; 50 mutation rows. **Prevention:** the review skill's
    structural-enumeration rule already covers it; this PR is another instance.
12. **The alert predicate had no host condition although web-2 ships to the same source.**
    Recovery: `host_name='soleur-web-platform'` conjunct, measured live. **Prevention:** added to
    the "TO ADD ANOTHER LOGS ALERT" recipe in `betterstack-logs-alerts.tf`.
13. **I handed the docs agent a reason code that does not exist (`not_luks`).** The real one is
    `device_not_luks`. Recovery: the agent checked and used the real one. **Prevention:** grep
    the emitter for any reason code before quoting it into a brief.
14. **I told the docs agent code had "landed" before I edited it.** It read pre-edit files.
    **Prevention:** brief a parallel agent with facts only after the code commit, or say
    "being written".
15. **An untracked `.soleur-runs/` was left in the worktree.** An `a && b || c` precedence mistake
    reported it ignored. Recovery: removed; later runs used `/var/tmp`. **Prevention:** keep run
    artifacts outside the worktree.
16. **PR #9041's secret-scan checks were cancelled, not failed.** Recovery: `gh run rerun
    --failed`. **Prevention:** one-off.

## Tags

category: integration-issues
module: apps/web-platform/infra
