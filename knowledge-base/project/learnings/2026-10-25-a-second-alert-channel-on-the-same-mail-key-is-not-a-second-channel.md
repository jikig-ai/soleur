---
title: "A second alert channel that shares the first one's mail key is not independent cover"
date: 2026-10-25
category: workflow-patterns
tags: [monitoring, sentry-cron, resend, orphan-sweep, identity-proof, failure-email]
---

# Learning: a second alert channel on the same credential is not independent cover

## Problem

Issue #10952 added a monitored signal to the two read-only Hetzner orphan sweeps in `scheduled-terraform-drift.yml`. The sweeps already sent a failure email. The first design called the aggregator email "defence in depth" against a sweep email that fails to send.

Both emails use one `RESEND_API_KEY`. A revoked or rate-limited key silences both at once. Only the routed Sentry cron monitor reaches the operator without that key, and it is created unrouted until #10972 (due 2026-10-27).

A second claim in the same change had the same shape. A 404 on the project-identity GET was first described as "this token belongs to another project". A 404 also means the pinned volume is gone. The job did not measure which, so the cause text had to say both.

## Solution

- Describe what each channel depends on. The runbook and ADR-241 now say the sweep emails and the aggregator email share one mail key. They also say the routed Sentry monitor is the only path that does not.
- Give the identity proof a closed vocabulary (`ok`, `other-id`, `bad-body`) so the response body is never printed. Give the cause sentence three arms: refused (401/403), 404 (volume gone or other project, not measured), and everything else.
- Assert the property in the suite rather than by reading: the aggregator email and the sweep email are separate steps, the subject order is checked by job name, and the `000` curl status is treated as a transport failure.

## Key Insight

Before calling two alerts redundant, list what each one needs to fire (credential, network path, scheduler). If the lists intersect, the cover is only as independent as the part that does not intersect. A cause sentence has the same rule: state only what the job measured.

## Session Errors

1. **Worktree reaped between turns.** Recovery: `git worktree prune` then `git worktree add`, then `npm ci --ignore-scripts`. **Prevention:** none new; the session-start gate already lists worktrees.
2. **YAML parse failure from single quotes inside a single-quoted email body.** Recovery: doubled the quotes. **Prevention:** parse the workflow with a YAML loader before pushing; the suite does.
3. **Step selector matched two steps in the rung-2 sweep.** Recovery: select by the step whose `if` is `failure()`. **Prevention:** assert selector cardinality is exactly one.
4. **A body-names-both-results check broke a must-pass reword row.** Recovery: removed it; the subject-order check covers the property. **Prevention:** a new assertion must be run against every must-pass row before it is kept.
5. **Job order inverted** because the job map sorts alphabetically (inngest first). Recovery: look jobs up by name. **Prevention:** never index a sorted collection by position in a test.
6. **Mutation row `sleep-trailing` changed nothing** because the `done` anchor was indented. Recovery: re-anchored on the `if (( id_fetched != 1 ))` line. **Prevention:** `cq-assert-anchor-not-bare-token`; confirm every mutation row changes the script before counting it.
7. **Local gate queued behind sibling full-gate runs and was stopped twice; the stopped parent left child runners holding queue tickets.** Recovery: read `test-all.sh --capacity`, then `kill_mine 'test-all.sh'`. **Prevention:** check `--capacity` before starting the gate. The cleanup helper already exists, so no new issue.
8. **Hooks blocked `git stash list` and a self-matching `ps … | awk` pipeline.** Hooks worked as intended. **Prevention:** use `list_runs` and an argv-slot anchor.
9. **Mistyped a commit SHA once.** Recovery: re-derived it with `git rev-parse`. **Prevention:** copy SHAs from command output, never retype them.
10. **A task-completion notification "exit code 0" was nearly read as the gate verdict.** Recovery: read `GATE_RC=0` from the log. **Prevention:** already covered by the work skill's wrapper-is-a-guard rule.
11. **Ended a pipeline turn on a statement of intent ("moving on to qa, compound and ship") with no tool call, so the turn stopped and the user had to ask why.** Recovery: resumed with the branch sync. **Prevention:** after a phase marker, the same message must contain the next tool call; a "paused" or "moving on" line without one is a stop.

## Tags

category: workflow-patterns
module: scheduled-terraform-drift, sentry cron monitors
