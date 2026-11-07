# Learning: user-facing copy that names an action must be checked against that action's live status, and a "teeth" control must run the real controls

## Problem

PR 11566 (issues 11486 and 11520) shipped two kinds of artifact that read as verified and were not:

1. **Refusal copy naming an action that fails.** The Edit-409 string told a founder "Send it or Discard it". The plan's own first task was a read-only `pg_policies` check, which found no UPDATE policy on `public.messages`, so Discard answers 403 in production (P1 issue 11569). The copy was written from intent (CPO proposals, plan-reviewed three times) and never checked against what the named button does today. Two review seats (data-integrity, user-impact) converged on it.
2. **A "scorer teeth" row that computed a constant.** It overrode the scorer to `return 0` inside a subshell and counted how many rows of a literal list that override accepted, so the count was the list length whatever the real scorer or the real controls did. Four seats flagged it independently; the author's own three-mutation battery could not, because every mutation perturbed `mh_caught`'s output and none perturbed the teeth row itself.

Smaller escapes in the same scorer: an unanchored `grep -qF` credited a `FAIL:` quoted mid-line, a detail line, a strict prefix of the fragment, and an empty fragment; and the "mid-line" control line had one space before `FAIL`, so it could never match the two-space needle, anchor or not.

## Solution

- Edit copy now names Send only; the Discard half returns in the change that fixes 11569 (tracked as item 12 on the deferral issue 11572).
- `mh_caught` is a line-start literal match (`awk index() == 1` on `"  FAIL: " + fragment`) that refuses an empty fragment.
- The controls are a table (`label|fragment|log`); the teeth row replays that same table under an overridden scorer and expects every row to flip, against a LITERAL count (a count derived from the table shrinks with it). A missing control log answers `missing`, so a negative control cannot pass vacuously.
- Verified by driving the scorer variants (`> 0` anchor, whitespace-strip, regex mode, truncated fragment, counts-PASS, always-yes) against the control logs: each is killed by a named control.

## Key Insight

Two checks that are cheap and that review kept having to do for the author:

1. For any string that tells a user to do X, run the command that shows what X does right now. Plan-time rulings about wording do not cover the state of the thing the wording points at, and a finding discovered inside the same PR (the missing policy) is the strongest hint that a sibling artifact depends on it.
2. A control that proves a guard "has teeth" must call the real controls, not a stand-in. Ask of every such row: if I delete half the table, what turns red? If the answer is "nothing, only the floor", the row is a constant.

## Session Errors

1. **Plan assumed one added line in an `AFFECTED_*_PATHS` array keeps `--affected` bounded.** The runner reported `AFFECTED_FALLBACK reason=runner-changed` (~135 min of suites) because only single-line `run_suite` registrations are admitted. Recovery: ran the declared-edge suites that reference the index lib plus the replay ratchet; CI runs the full battery anyway. **Prevention:** read `_aff_classify_runner_diff`'s grammar (learning 2026-10-05) before a plan promises a bounded gate for an edit to `scripts/lib/test-affected-paths.sh`.
2. **A backgrounded `tests/scripts/test-argv-bearer-sweep.sh` hung 27 minutes.** A stub `docker` waited on the inherited stdin. Recovery: killed it, reran with `< /dev/null` (829 passed, 0 failed). **Prevention:** run every agent-launched suite with stdin closed (`< /dev/null`); the stdin dependency itself is tracked on issue 11572 (item 13).
3. **`gh issue create --body-file $S/...` was refused by the guardrails gate** (a `$VAR` path it cannot expand). Recovery: literal absolute path. **Prevention:** write the body to a file in a separate step and pass a literal path.
4. **A commit was refused as "on main".** An earlier call had left the shell cwd at the bare repo root. Recovery: `cd` into the worktree in its own call, then commit. **Prevention:** begin every git write with an explicit `cd <worktree> && git branch --show-current`.
5. **`MIN_BATTERY` set by hand twice (+4 then +2 instead of +6).** Recovery: the suite's floor failed loudly on the first run. **Prevention:** derive the bump from the ledger-label count of a full pristine run, as the plan already said.
6. **The Playwright browser install did not complete on this host** (download reaches 100%, then hangs, even with the platform override), so the nav-states gate failed at `browserType.launch` for all 35 tests. Recovery: recorded as INFRA-BLOCKED; the diff is copy-only and the AC4 invariant prints nothing. **Prevention:** none beyond the existing preflight; CI's containerized `e2e` job is the gate.

## Tags
category: test-failures
module: followthroughs mutation harness, dashboard today-card
tags: copy-vs-live-state, teeth-row, scorer-controls, mutation-harness, affected-gate
