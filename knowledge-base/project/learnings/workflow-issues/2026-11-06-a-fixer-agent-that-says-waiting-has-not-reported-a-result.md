# Learning: a fixer agent that says "waiting" has not reported a result

## Problem

PR-D (#12187, issue #12011) ran a full-coverage review at the `single-user incident` tier. Fix round 2 went to three agents in parallel: web code and tests, plugins (the hold gate), and the CLO for the published documents. The web agent and the CLO reported complete. The plugins agent's last message was "Waiting for the monitor to report the hold-gate run." and it never sent another. Eight hours later its transcript showed it idle, no hold-gate process running, and the tree it left behind was red:

- `hold-gate-eval.test.sh` aborted at its own control block (`has_line: command not found`): the helper was defined 190 lines after the first control that called it (rc=2).
- With that fixed, 14 further failures, all in rows the agent had added: `w_tz`/`r_tz` used by an arm 240 lines before they were defined; two mutation rows pinned to the `wa-key` hash while running on other keys; per-arm assertion minimums that were all the literal `1` while the whole-suite floor still read 1770 against a 2009-assertion green run.
- A mutation row (`wa-valid-shape`) that survived because the guard it targets is subsumed by the next check (a calendar round trip), so the mutant was equivalent.
- `scripts/guard-vacuity-floor.test.sh` went red: the new `arm_floor` helper opened with `if (( v >= $2 ))` on a line mentioning `PASS`, which that guard reads as a whole-suite floor it cannot rebuild, so the "mutant could not be built" ratchet grew from 17 to 18.

## Solution

The lead stopped trusting the agent's status and re-ran the suite itself:

1. Read the log's own `RC=` line, never the background-task notification (its "exit code 0" was the launcher's).
2. Moved `has_line` and `w_tz`/`r_tz` above first use.
3. Replaced the per-key pins with ones computed from `blobhash <key>`.
4. Made a `valid_until:` line with no value a damaged text (the awk prints `V:`+value so an empty value is distinguishable from an absent line), which also made the shape guard non-redundant and gave its mutant an input that kills it.
5. Rewrote `arm_floor` as `(( v >= $2 )) && { ...; return 0; }` so no line starts with `if (( ... ))` over a counter.
6. Set every floor from the measured green run: per-arm counts exact for small arms and within 0.5% for large ones, suite floor 2000 of 2009, gh-stub floor 995 of 1000.

## Key Insight

- A background agent's "waiting for the monitor" is a stall, not a result. If it has not reported within the time its work takes, read its transcript tail and the process list; if nothing is running, take over rather than waiting. Only the verdict line of a log you read yourself counts.
- In a sequential bash suite a helper must be defined before the first control that calls it. A control block placed early to "arm" the suite is the first place a later-defined helper breaks.
- A mutation row needs an input the mutant changes. When one guard is subsumed by the next, either give the guard its own case (here: an empty value) or delete the row; an equivalent mutant "survives" forever.
- Per-arm minimums of `1` look like floors and guard nothing. Take them from the green run, in the same edit that adds the rows.
- Guards that scan for floors by shape (`if (( … ))` on a counter line) will adopt a helper you write; keep helper code out of that shape.
- Two PRs that edit published legal documents always conflict on `apps/web-platform/lib/legal/legal-doc-shas.ts`. Resolve by recomputing the three hashes from the merged `docs/legal/*.md`, never by choosing a side; run the SHA guard, mirror-drift and placement lints afterwards.

## Session Errors

1. **Fixer agent parked on a monitor for ~8 h and left a red suite** — Recovery: lead took over, ran the suite, fixed the ordering, pins, shape guard, `arm_floor` and floors. **Prevention:** a delegated fix is not done until the delegator has read the suite's own `RC=`; add to the delegation brief "run your suite to completion yourself and return within your run; do not park on a Monitor" (the review fix-round brief already says it; the work-phase brief did not).
2. **Background-launch notification read as a verdict** ("completed, exit code 0" while the suite had not finished) — Recovery: read the log's `RC=` line. **Prevention:** already covered by the work skill's wrapper-verdict rule; no new rule.
3. **`guard-vacuity-floor` ratchet grew from 17 to 18 from a helper's shape** — Recovery: rewrote `arm_floor`. **Prevention:** run `scripts/guard-vacuity-floor.test.sh` whenever a suite gains a counter-comparing helper (file-selected sets cannot see it).
4. **CLO's first "accept the lag in the published documents" ruling contradicted the required `enforce` check** — Recovery: confirmed by reading `pr-quality-guards.yml`, ruling withdrawn, documents and mirrors amended. **Prevention:** a ruling that tolerates drift between published documents gets checked against the required-check list before it is applied.
5. **First edit to `lib/internal-auth.ts` invalidated the home-census CLO binding** — Recovery: reverted byte-for-byte, reader moved to `lib/internal-auth-named.ts` (CTO D2). **Prevention:** read `CENSUS_PATHS` before editing any file in a governed set.
6. **The affected-tests gate queued behind another session's lock and timed out repeatedly** — Recovery: treated as unmeasured, CI is the gate. **Prevention:** none in this repo; disclosed to the operator.
7. **A Bash call with `ps … | awk` and one with `git stash list` were refused by hooks** — Recovery: `proc.sh` helpers; no stash command at all. **Prevention:** already hook-enforced.
8. **PR became CONFLICTING with `main` after the review panel** (found only by a late `git merge-tree`) — Recovery: merged `origin/main`, recomputed the legal SHA pins. **Prevention:** re-run `git merge-tree --write-tree origin/main HEAD` after every long fix round, not only before the panel.
9. **Small slips:** a single-quoted psql string with `\x27` (syntax error), a grep for the wrong bold-marker phrase that read as "amendment lost", `TaskStop` on an agent id that no longer existed. One-offs, no recurrence vector.

## Tags

category: workflow-issues
module: ship hold gate, review fix rounds, legal published documents
