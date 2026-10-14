# Learning: a drift guard for a log alert pinned declarations, not the sites that consume them

## Problem

PR #9376 (issue #9342) added a Better Stack Logs alert on the `DEPLOY_ROLLBACK: bwrap sandbox non-functional`
row plus a drift guard with a mutation battery. The guard was green (34/34, 12 mutation rows RED) and an 11-seat
review panel still found no P1 but 24 findings, all in the guard or its prose, none in the alert SQL. They reduced to
three shapes:

1. The needle was read from the emitter's `BWRAP_LINE=` ASSIGNMENT, while the SINK (`logger -t "$LOG_TAG"
   "$BWRAP_LINE"`) decides what journald carries. Prefixing the message, or retagging, left every row green and the
   alert dead. The same shape: attributes pinned by whole-line greps leave `confirmation_period`, `count`,
   `lifecycle`, `ignore_changes` free.
2. A mutation row was graded RED on "inner rc is 1", i.e. any presence row failed. 15 of 22 presence rows had no unique
   catcher, so rows could be deleted unnoticed.
3. The alert text carried a copy of the decode command (`--grep '<needle>'`, no field isolation) — a third copy of
   the needle that nothing tied to the emitter, contradicting the runbook's own "filter on the decoded
   SYSLOG_IDENTIFIER" rule. `incident_cause` was also 932 chars against a previously applied maximum of 564, with no
   measured vendor limit.

## Solution

- Pin the sink call and the paging fields that the prose promises (`confirmation_period`, `recovery_period`) and add
  an open-set negative row (`count|for_each|lifecycle|ignore_changes`).
- Give every RED mutation row an expected `[FAIL]` substring and require it on the inner run's output.
- Remove the inline command from the alert text and point at the runbook's Query block (one copy, field-isolated);
  trim the text to 520 chars, inside the applied range.
- Read `-target=` lines from the MAIN plan region (first `terraform plan -no-color` to its `rc=$?`), and add a row
  that MOVES the lines out rather than deleting them.

## Key Insight

When a guard's property is "this row reaches this alert", every artifact between producer and consumer is a site: the
assignment, the sink, the tag, the allowlist, the predicate, the apply allowlist, the text an operator copies. A guard
that reads one declaration and compares it with one other declaration proves consistency, not delivery. Ask per
guard which sites are NOT read, and whether any copy of the value (needle, slug, command) exists that nothing ties
back to the source.

## Session Errors

1. **First commit hung behind the repo-wide test lock** (lefthook bun-test fired on a staged `.ts`, queued behind
   sibling sessions) — Recovery: detached retry with `LEFTHOOK_EXCLUDE=bun-test`, then ran the affected gate
   separately. **Prevention:** already in `work/SKILL.md` (queue/escape-hatch paragraph); no change.
2. **Local affected gate queued ~35 min, then the operator said to rely on CI** — Recovery: stopped waiting, relied on
   static checks. **Prevention:** none; scoped to this session's contention.
3. **Plan-tick commit tripped `lint-infra-no-human-steps`, and the first reword introduced "by hand" which tripped it
   again** — Recovery: reworded to avoid the actor and imperative co-occurrence. **Prevention:** run
   `scripts/lint-infra-no-human-steps.py <file>` before committing prose edits to a plan that mentions an apply.
4. **Throwaway anchor-check script had an unbalanced regex template** (false BAD, traceback) — Recovery: rebuilt with
   an explicit per-pattern prefix. **Prevention:** when edits cannot be run, a static replica of each mutation's
   anchor lookup is the substitute check; build it from the same patterns, never a hand template.
5. **A pattern-based process probe was blocked by the self-match hook** (twice: once in a probe, once by this very
   learning's text quoting the flag) — Recovery: used the repo's process-listing helper and reworded. **Prevention:**
   the hook already covers it; do not quote the blocked spelling inside a command's heredoc.
6. **Local `main` ref was stale during routing** (a grep for the luks template on `main` found nothing; it exists on
   `origin/main`) — Recovery: fetched and read `origin/main`. **Prevention:** already stated in `go.md`/brainstorm
   (read `origin/main`); no change.
7. **Skipped writing `session-state.md` after the planning subagent returned** — Recovery: written at compound time.
   **Prevention:** none; one-off ordering slip.
8. **Operator instruction to skip local tests conflicted with the skills' verification steps** — Recovery: applied
   guard edits with static checks only (`bash -n`, `shellcheck`, read-only extraction of each new row's predicate,
   anchor-lands check), stated the gap in the PR, CI is the test of record. **Prevention:** none needed beyond saying so.

## Tags
category: workflow-patterns
module: apps/web-platform/test/infra (bwrap-probe-rollback-alert guard), betterstack-logs-alerts.tf
