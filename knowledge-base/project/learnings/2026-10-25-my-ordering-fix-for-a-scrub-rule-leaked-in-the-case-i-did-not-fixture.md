# Learning: a scrub rule moved relative to a strip leaked in the case I did not fixture, twice

## Problem

PR #10975 ships the stunnel terminator's journal to Better Stack behind a fail-open filter and a Doppler-token scrub rule (`pii_scrub_string`). The review panel (11 seats) found no P1 and the CTO ruled the forks, but the fix rounds then reproduced the PR's own class (a guard narrower than its claim) three times inside the fixes themselves:

1. The review said "a token split by a control byte reassembles past the rule", so the rule moved AFTER the control-character strip. That closed the split case and opened its mirror: a token directly preceded by a newline, tab or carriage return lost the separator to the strip, glued onto the preceding text, and the `(^|[^A-Za-z0-9])` anchor refused it. The whole token shipped.
2. Running the rule both before and after the strip closed that, and opened a third case: pass 1 redacted the head of a token split after 20 or more body characters, the strip glued the rest onto `dp.[redacted]`, and pass 2 could not match the remainder. The tail shipped.
3. Anchoring the three drop patterns as whole lines (the right fix for substring drops) turned two "keeps another unit's line" fixtures vacuous: their messages had no `LOG5[n]:` prefix, so the anchored patterns no longer matched them and the unit-scope condition was never exercised. Deleting the unit scope left the suite green.

Each regression was found by a seat (security, test-design, the verification pass), not by my own verification, because each fix was checked against the example that motivated it.

## Solution

- Make the first scrub pass admit the stripped characters inside its body class, so one pass redacts a token split anywhere in its body or preceded by a stripped separator; keep the second pass for a split inside the `dp.` prefix itself.
- Prove it with a generated corpus rather than two hand fixtures: 265 cases (every split position of the token, five separator types, a separator before the token, a separator plus a split) through the real VRL, asserting no five-character fragment of the body survives. `vector vrl --input` takes a file of many JSON lines, so the corpus runs in one container start.
- Give the unit-scope keep fixtures a real `LOG5` drop-shaped message, then confirm by mutation (drop the scope from the condition) that exactly those two fixtures go red.
- Add a late-split fixture and a separator-plus-early-split fixture; confirm the late-split one reds under the previous rule on a mutated copy.

## Key Insight

A rule whose correctness depends on the ORDER of two string transforms has a two-dimensional failure space (separator before the token, separator inside it, at every offset), and a fix verified against the one case that prompted it moves the leak to a neighbouring cell. When the fix reorders or repeats a transform, enumerate the cells with a generated corpus before committing; two hand fixtures are a sample, and the unsampled cell is where the next review round finds the leak. The same holds in the other direction for predicates: ANCHORING or narrowing a matcher turns every keep-fixture that relied on the wider match into a vacuity, so after narrowing, re-derive each keep-fixture's input against the new predicate and mutate the condition the fixture claims to pin.

## Session Errors

1. **The worktree was reaped twice.** The first was a 240-minute lease expiring while a rate-limited planning subagent paused the session; the second was a manually re-attached worktree (`git worktree add` of an existing branch; `worktree-manager.sh create` only creates new branches) that had no lease, so a sibling session's reaper deleted it mid-gate. Recovery: `git worktree prune`, `git worktree add`, `session-state.sh acquire_lease … 480`, re-run `npm ci`. **Prevention:** after any manual `git worktree add`, acquire a lease immediately (bullet added to the git-worktree skill); commit and push as you go so a reaped directory loses nothing.
2. **The planning subagent died on a weekly rate limit and lost uncommitted work.** Recovery: re-ran planning with "commit and push as you go". **Prevention:** brief long-running subagents to commit and push per section.
3. **A control-character-before-token leak, introduced by my reorder of the Doppler rule.** Recovery: the double pass, then the tolerant body class. **Prevention:** brute-force every split position and separator type before committing a change to the order or number of passes (this learning); the review skill already says to grade a fix commit as its own change.
4. **A tail leak, introduced by the double pass.** Found by the verification pass. Recovery: tolerant first-pass body class plus a 265-case check. **Prevention:** as above.
5. **Whole-line anchoring made two keep-fixtures vacuous.** Found by the test-design seat. Recovery: real `LOG5` messages in the fixtures, mutation-checked. **Prevention:** a bullet in the review skill (narrowing direction of "a fix that widens a matcher leaves its fixtures on the old side").
6. **A raw control byte cannot cross the PII suite's three stages.** `vector vrl --print-object` prints it unescaped and the next stage's JSON parse rejects it, so my strip-order fixture failed with a pipeline error rather than an assertion. Recovery: U+2028 (same stripped class, valid unescaped JSON). **Prevention:** when a harness chains stages through printed JSON, test a separator class that survives the hand-off and cover the control-byte cases through `vector test`, which keeps the event in memory.
7. **My docker wrapper mounts only `/tmp` and `/var/tmp`.** Suites that read repo files under `/data` showed false reds (egress rollup 27/2, the filter suite's behaviour rows 23/2) until I ran them with their own engine path. **Prevention:** run each suite the way its own header says; treat a red that appears only through a wrapper as an environment artifact until reproduced without it.
8. **The PII suite needs `SENTRY_USERID_PEPPER` and `BETTERSTACK_LOGS_TOKEN` set (dummies), and `vector vrl --input` inside the container needs an absolute path.** **Prevention:** read the suite header's env list before the first run.
9. **A non-literal floor (`MIN_VERDICTS`) put the new suite into `guard-vacuity-floor`'s uncovered set (ratchet 15 grew to 16).** Recovery: one `if` per arm with its own literal. **Prevention:** run `scripts/guard-vacuity-floor.test.sh` after adding or reshaping any floor (the repo already documents this).
10. **The decision-challenges ruling shape rejected my annotation.** The gate requires `Ruled by CTO agent, <date>: <decision>` with the colon right after the date. Recovery: moved the annotation after the colon. **Prevention:** run `technical-ruling-gate.sh` on the file right after editing a ruling row.
11. **The affected-tests gate was killed by a worktree deletion once, ended rc 6 (budget expired while queued) once, and queued at position 10 behind sibling sessions this time.** Neither partial run is evidence. **Prevention:** record CI as the authoritative gate on rc 6, never label the run passed, and re-run in ship Phase 4.
12. **Hook blocks: `git stash list` (a read-only use, blocked by the stash guard) and a `ps | awk` pattern that self-matches.** Recovery: dropped the stash probe; used the log file and `list_runs`. **Prevention:** use the commands the hook's message names.
13. **The shell cwd resets to the bare root after a `cd` into a scratch directory, and log mtimes (+01:00) against UTC `date` nearly made a live gate look stalled.** **Prevention:** `cd` into the worktree at the start of every Bash call; compare timestamps in one zone.
14. **Minor:** bun 1.4.4 installed against the pinned 1.4.2 (warning only); a `timeberio` image-name typo; ugrep `grep` shim quirks on non-UTF-8 files (use python or `/usr/bin/grep -a`); `vector validate` accepted VRL that `vector test` rejected (the reason the new suite exists). **Prevention:** none beyond what is already recorded.

## Tags
category: logic-errors
module: apps/web-platform/infra/vector.toml, vector-pii-scrub, terminator filter
