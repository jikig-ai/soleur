# Learning: advice prose added to an emitted message becomes false-match surface for every assertion anchored on a token it names

## Problem

PR #9505 rebuilt the Hetzner stock-preflight gate on `GET /server_types?name=<type>` after Hetzner removed
`/v1/datacenters` (HTTP 410), which had failed every host create/replace fail-closed. The rewrite was green from the
start (RED 92/43 against the old lib, then 137/137, 34/34 mutation rows). A 12-seat review panel still found 77 raw
findings (9 canonical defects, one P1), and the two fix rounds then reproduced classes the PR was meant to close:

1. **The P1 was in code the diff did not rewrite.** A create row with no address was skipped by
   `[[ -z "$addr" ]] && continue`, so one valid row beside one addressless row passed with a single fetch. Chasing it
   exposed a second defect on the same line: `IFS=$'\t' read -r addr stype sloc` treats tab as IFS-whitespace and
   **collapses a leading empty field**, so a row with no address but a real target was shifted left and misattributed
   (fail-closed, wrong message). Both were pre-existing; the fix round found them only because a test had to name the
   offender.
2. **My own new advice text broke the assertions written against it.** The unreachable-class abort message was
   extended with transient/NOT-transient advice that itself names `api_error=rate_limit_exceeded` and
   `curl exit 22`. Two T7b greps for `api_error=` immediately matched the prose (the suite went red and I caught it).
   Three greps for `curl exit 22` matched the same prose and stayed GREEN: the verification seat hard-coded
   `curl exit 7` in the lib and T7b, T20b and T20c all still passed, so T20c ("the 502 aborts through the status")
   could not tell exit 22 from a dead server. The suite caught the first pair because it failed; nothing caught the
   second until a fresh reader asked which other tokens the new prose contains.
3. **A correction reached the sites I was looking at, not its twins.** The claim "the body's error code is the ONLY
   thing separating a removed endpoint from a flaky network" was false (curl's own exit already separates 6/7/28 from
   22). I corrected the advice string and the suite comment and left the same sentence in two lib comments one screen
   away.
4. **A measured fact was transcribed from memory.** The header said an unknown `?name=` returns "200 with `[]`";
   the measured body is `{"server_types":[]}` (a top-level `[]` is `MALFORMED:shape` in the same gate).

## Solution

- Missing-address rows now abort per row; rows are split by parameter expansion on the literal tabs (`@tsv` escapes
  every tab inside a value, so the surviving tabs are exactly the delimiters), preserving empty fields.
- Assertions on a message's REASON now anchor on the segment the code writes (`with a 2xx: curl exit 22`,
  `curl exit 22 api_error=`), and the transient/NOT-transient lists are pinned whole with `grep -qF`, so moving one
  member across the divide goes red.
- Every twin of the corrected claim was rewritten after grepping its paraphrases; the measured facts were
  re-probed (read-only token, shapes only) and restated at the strength the evidence supports ("an inference from 20
  entries, not a vendor guarantee").
- 87-row mutation battery on a scratch mirror (not committed), a row per guard added during review, each required to
  land (`diff -q` against a pristine backup) and to go RED at a named case; the suite also runs on Ubuntu 24.04
  userland (jq 1.7, curl 8.5.0) in a container, which the CI runner shares.

## Key Insight

**Adding explanation to a message is a change to the oracle every existing assertion reads.** A grep that anchored on
a bare token (`api_error=`, `curl exit 22`) was precise when the message was one sentence and becomes a false match
the moment advice prose names the same token. The failure is one-directional and silent in the dangerous half: the
assertion that FAILED was fixed, the ones that kept passing were not looked at. After extending any emitted text, list
the tokens the new prose contains and grep the suite for assertions on each; anchor on the code-written segment, or pin
the whole sentence.

Two companions from the same session: (a) when a fix corrects a claim, grep the claim's paraphrases across every site
that restates it before committing, because the sites you did not open are the ones the correction misses; (b) a
read-source fix that removes an endpoint is the moment to MEASURE the replacement's edge cases (unknown name, repeated
parameter, past-dated deprecation) with a read-only token rather than trusting the plan's reading of the docs — three
plan premises became data in ten minutes.

## Session Errors

1. **Guardrail hook blocked writing the fix brief into the shared git dir** (`$(git rev-parse --git-dir)` resolves
   under the bare checkout while other worktrees exist). Recovery: wrote the brief to the session scratchpad under a
   lead-unique name. **Prevention:** route-to-definition added to `risk-tier-and-fix-rounds.md` — persist briefs in the
   scratchpad, not the git dir.
2. **Started `TEST_GROUP=affected bash scripts/test-all.sh` while other worktrees held full-gate runs**; it queued
   (`LOCK_WAIT_HEARTBEAT ... position=2 of 7200s`) for 7+ minutes and would have raced the next commit (the runner
   flags a commit made during its run as a suite writing to the repo). Recovery: stopped the task, relied on the
   targeted suites. **Prevention:** same reference bullet — check `--capacity` first, stop a queued run instead of
   waiting.
3. **Two T7b assertions on `api_error=` matched the advice prose I had just added** (found by the suite). **Prevention:**
   after extending emitted text, grep the suite for assertions on each token the new prose contains
   (`cq-assert-anchor-not-bare-token`); anchor on the reason segment.
4. **Three `curl exit 22` assertions matched the same prose and stayed green** (found only by the verification seat).
   **Prevention:** run one mutation per changed token (hard-code a different value in the lib and require RED) before
   calling the pin done.
5. **Corrected a false claim in the advice string and the suite comment but left the same sentence in two lib
   comments.** **Prevention:** grep the claim's paraphrases (`ONLY`, `only discriminator`) across the whole file set
   before committing a correction.
6. **Wrote an unmeasured body shape into a header** ("200 with `[]`" for `{"server_types":[]}`), caught by the pattern
   seat. **Prevention:** paste the measured line into the comment instead of paraphrasing it from memory.
7. **A battery row anchored on text a later edit had changed (N4 matched a comment and the message; N19h's anchor went
   stale; N20h weakened an assertion over a correct SUT and could not redden).** The landing assertion reported all
   three. **Prevention:** regenerate row anchors after each lib edit and drop rows that mutate only an assertion.
8. **The turn ended with a first-person commitment still pending; the stop hook refused.** Recovery: took the next
   action (drafted the PR body) and declared the blocking background jobs. **Prevention:** none beyond the hook.
9. **One transient `gh` connection reset in the plan phase** (forwarded from session-state.md); re-ran. One-off.

## Tags
category: workflow-issues
module: tests/scripts/lib/stock-preflight-gate.sh
