---
title: An SSH drop without a pty is SIGPIPE, and my cleanup trap read it as success
date: 2026-09-28
category: runtime-errors
module: apps/web-platform/infra/workspaces-cutover.sh
issues: [9045, 8734, 9123, 9122]
pr: 9098
tags: [luks, dead-man, systemd, signals, exit-trap, review, mutation-testing]
---

# Learning: an SSH drop without a pty is SIGPIPE, and my cleanup trap read it as success

## Problem

#9045 moved the /workspaces LUKS cutover's dead-man disarm from after `app_canary` to the
host-canary door, before `docker start`. After a post-canary abort, `cleanup()` now rolls FORWARD
instead of relying on the dead-man. The plan, its six-seat review, the deepen pass and the ADR-119
addendum all rejected a watchdog on one premise: "An SSH drop delivers SIGHUP, and SIGHUP runs the
EXIT trap."

The premise was false twice over, and it was never measured:

1. The workflow runs `ssh host "bash -c '… workspaces-cutover.sh'"` with no `-t`, so no pty. A dropped
   connection delivers no SIGHUP. The script dies of **SIGPIPE** on its next write to stdout.
2. bash does run the EXIT trap on SIGPIPE, SIGTERM and SIGHUP. But `$?` inside the trap is the
   **last completed command's status**, usually 0, not 128+signal. So `cleanup()` took its
   `rc -eq 0 → exit 0` success branch: no rollback, no roll-forward, no outcome row. When `rc`
   happened to be non-zero, the trap's own first `log` raised SIGPIPE again and killed it mid-trap.

Before #9045 the still-armed dead-man covered that window, wrongly: that was the #6812 incident.
After the disarm moved, nothing covered it. The fix removed the backstop the old design silently
relied on. Three review seats (architecture, structural enumeration, code quality) measured the
behaviour with local bash probes. The plan-time panel had only reasoned about it.

## Solution

- `cleanup()` captures `rc=$?` on its **first** line, then runs `trap '' PIPE HUP INT TERM`.
  The order matters: the `trap` builtin resets `$?`.
- A `RUN_COMPLETE` sentinel is set only at the three intentional exits: ROLLBACK-mode end,
  CLEAN_STRAY end, and the single normal end. `rc==0` without it is an abnormal exit, handled as a
  failure and recorded with `abnormal_exit=1`.
- SIGPIPE is NOT ignored in the main body. DP-6 still holds: an SSH drop mid-freeze aborts into the
  trap, which rolls back.

The same review round found the other half of the class in the tests. Every door guard was pinned by
a source-text grep, so `|| true`, `|| log`, or `return 1` in place of `die` left the suites green
(19 surviving mutants). The fix executes the door through the staging suite's `repoint_case`, with
negative rows that assert the drift, `died`, no `CANARY_OK` written and no `docker start`. Every
"fire in progress" fixture had used `activating`. A running `Type=simple` transient service reads
`active` (measured on systemd 261), so production's value was the one member no test pinned.

## Key Insight

**A design that moves a backstop must enumerate the windows the old backstop covered implicitly,
and each claim about how a process dies is a measurement.** "SIGHUP runs the EXIT trap" is true and
irrelevant: the question is which signal this invocation receives, and what the trap can observe
about it. `$?` cannot tell a signal death from a clean end, so any EXIT trap that branches on success
needs an explicit completion sentinel.

## Session Errors

1. **Plan write blocked by the IaC write guard** (forwarded from planning). Recovery: IaC routing reviewed, ack marker added. **Prevention:** none needed; the guard worked as designed.
2. **human-steps lint and MD038 in the plan** (forwarded). Recovery: fixed before commit. **Prevention:** existing lints caught it.
3. **A follow-through probe would have put `HCLOUD_TOKEN` in the public-repo sweeper** (forwarded). Recovery: replaced with a marker-keyed probe needing no new secret. **Prevention:** the #8209 class is already documented; the plan applied it.
4. **`gh issue create` denied because `--body-file` named a file the same denied call was to create.** Recovery: Write tool first, then the create. **Prevention:** existing guardrail and skill text (write the body in a separate step) — followed on retry.
5. **`pgrep -f` blocked as self-matching.** Recovery: `proc.sh kill_mine`. **Prevention:** already hook-enforced.
6. **Lefthook's pre-commit affected gate ran more than 10 minutes, queued behind two sibling worktrees' full runs, for a one-constant `.ts` change.** Recovery: killed this worktree's run by ownership, ran the owning test (13/0), committed with `LEFTHOOK_EXCLUDE=bun-test`; CI owns the full battery. **Prevention:** `work/SKILL.md` already names `LEFTHOOK_EXCLUDE=bun-test` as the narrow escape; check `--capacity` before a `.ts` commit under contention.
7. **MD038 (trailing space inside a code span) failed a docs commit.** Recovery: reworded. **Prevention:** existing hook caught it.
8. **The security seat returned an empty final report.** Recovery: resumed it. **Prevention:** review/SKILL.md already says to mandate file delivery in the spawn prompt; I did it for one seat only. Mandate it for every seat.
9. **P1: the new alert broke another suite's exact-count anchors** (`betterstack-send-failed-alert-mutation.test.sh` G2 and M17 counted 1 and 7 occurrences in `betterstack-logs-alerts.tf`; the PR made them 2 and 8). No fan-out brief or targeted run included that consumer. Recovery: G2 scoped to the `monitor_send_failed` block, M17 bumped. **Prevention:** a fan-out brief must tell each agent to run every suite that `git grep -l <basename>` returns for each file it edits, not only the suites it wrote (routed to work/references/work-subagent-fanout.md, the fan-out brief template).
10. **The unmeasured SIGHUP premise survived plan review, deepen, the ADR addendum and decision-challenges.** Recovery: `cleanup()` made signal-safe; ADR and decision-challenges corrected. **Prevention:** a plan that moves or removes a backstop must list, per abort signal, what the process receives and what the trap observes, measured with a local bash probe (routed to plan-sharp-edges.md).
11. **The ADR addendum asserted "the app stays down" before the code did.** Review found it false: the app was already running. Recovery: code now stops the app and writers; the prose matches. **Prevention:** write ADR mechanics after the code, or grep each mechanic's claim against the code before commit (existing "falsify every causal claim" rule).
12. **`fixture-relative-assert` drifted 11→12 from a new `> "$RUN_SCRATCH/…"` write in T39.** Recovery: replaced the file with a variable and here-string. **Prevention:** existing work/SKILL.md 6.6 (run the fixture ratchets for new writes).
13. **`lint-shell-trace-credential-refusal --changed` flagged the (baselined) harness,** because the CI form bypasses the baseline for touched files. Recovery: added the xtrace refusal. **Prevention:** existing work/SKILL.md 6.5.
14. **19 test-design mutants survived:** source-grep door guards, `return 1` in place of `die`, a re-arm after `docker start`, and `activating` where production reads `active`. Recovery: executed door rows, `PAST_ARM` sentinels, arm-cardinality rows, `active` twins, ok()/no() self-tests and floors. **Prevention:** covered by review's structural-enumeration and test-design seats; pair them (run the execution map before the mutation audit).
15. **A runbook table cell carried `check=a|b|c`, whose pipes split the row.** Recovery: reworded, then verified pipe counts per row. **Prevention:** existing work/SKILL.md table-row pipe-count check.
16. **`terraform init && terraform validate | tail -1` printed an empty line** that read as neither verdict. Recovery: ran each with its own rc. **Prevention:** existing rule — never take a verdict through a pipe.

## Tags

category: runtime-errors
module: workspaces-cutover.sh, workspaces-luks harness, luks-monitor installer
