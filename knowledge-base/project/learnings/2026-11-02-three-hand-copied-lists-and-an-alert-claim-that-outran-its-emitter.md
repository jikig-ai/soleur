# Learning: a gate pin needs ONE source for its address set, and an alert comment must be checked against the emitter it watches

## Problem

PR #11854 pinned the Doppler token `access` level in the Inngest host-replace gate (#11831) and added a Better Stack silence alert for the cutover-flip unit (#11820). A 12-seat review plus a 4-seat fix round found no P1, but the same two classes recurred in the first draft.

1. **The gate named the two token addresses in three hand-copied lists** (the allow-set, the per-address action rule, and the new access pin). A third address added to the allow-set alone would have been admitted without being judged by either of the other two. Every existing fixture used one token at a time, so a gate that judged only the first token also passed.
2. **The alert comments claimed more than the emitter supports.** "The `noop-*` row is the only object-typed one" and "the `noop-done` check before `op=resume` covers a read-only flip token" were both false: every `emit_state` row is a JSON object (the ERR trap's `unexpected-exit(...)` row is unthrottled), and `noop-done` proves only the Doppler read, since the first flip-token write happens after `op=resume`.

## Solution

- Name the token addresses and their required access once, in a jq `tokens` map, and derive the allow-set, the action rule and the access pin from it. Pin in the suite that the code names the addresses exactly twice. Print `address want= got=` on abort, with the planted value truncated and reduced to a safe charset.
- Add fixtures in the shape production produces (both tokens in one plan, one right and one wrong, in both orders, both replace orders), not only single-token shapes.
- Read the alert's pinned host from the file that renders it (`inngest-bootstrap.sh`) and its tag from the emitter, so a rename reds the guard instead of silently disarming the alert.
- State the alert's blind spot in the artifact: it sees a unit that fails before the script's first emit, not one that fails after it.

## Key Insight

Two checks the first draft skipped, both cheap. Before shipping a pin over an address set, ask "how many places name the set, and what judges an address that only some of them list?". Before writing a sentence about what an alert can and cannot see, read every `logger` and `emit_state` call under the watched tag; a universal claim ("only", "every") is a claim about that enumeration.

## Session Errors

1. **The planning subagent returned no Session Summary and no artifact.** Recovery: ran `soleur:plan` inline once (the documented recovery arm). **Prevention:** none beyond the existing recovery contract; the subagent had spent its budget on research without writing the skeleton first.
2. **The first plan failed three gates** (guard-contract matrix lacked its `**Mutation matrix.**` field label, no `## Scope Check`, and the observability probe named a whole test suite that preflight kills at its 15 s cap). Recovery: fixed before deepen proceeded. **Prevention:** run `scripts/lint-guard-contract.py` and read the Scope Check schema before writing the plan, not after the deepen gates fail.
3. **I dispatched toward an A5 rotation rehearsal that another session had already run and was repairing.** The user interrupted ("isn't the other session ... already ran it?"). Recovery: listed the workflow's recent runs and found a failed `rotate`, a queued `converge` and a pending `plan`. **Prevention:** before dispatching any `workflow_dispatch`, list that workflow's recent runs (`gh run list --workflow=<file> --limit 8`) and look for in-flight or failed runs from a sibling session; a worktree named for the same workflow is a second signal.
4. **A stray `git stash list` and a `pgrep -f` were each blocked by the repo's hooks.** Recovery: re-ran without them. **Prevention:** already hook-enforced; one-off.
5. **After the gate refactor the M5 mutation anchor (`then "read/write" else "read" end`) no longer existed and the row aborted as "mutation did not land".** Recovery: the row's own landing guard caught it; re-pointed the sed at the map values. **Prevention:** none needed; the landing guard did its job.
6. **The alert census count (17 to 18) lives in five places** (two census floors, `EXPECT_BLOCKS`, the exploration-count anchor, and stale header prose), found only by running the sibling suites. Recovery: bumped all five. **Prevention:** when adding a resource of a class, `git grep -l <a sibling resource name>` across tests and docs at plan time and list every hit under Files to Edit.
7. **Two false sentences in my own comments** (see Problem 2) and a third, "#11266 holds the suppression", which is wrong (the idea lives in #11820's body). Recovery: review (code-quality, security, git-history) found them; corrected. **Prevention:** for every causal or universal sentence a diff adds, name the falsifying command and run it before writing the sentence.
8. **The affected-test gate hit its time budget (rc=6) and one suite was red on `main` for a calendar reason** (`check-cloudflare-token-drift`: the committed inventory passed its 90-day limit on 2026-11-02). Recovery: re-ran the suite in isolation and on a clean detached `origin/main` worktree, filed #11860, treated CI as authoritative for the rest. **Prevention:** none for this PR; #11860 tracks the suite.

Related: `knowledge-base/project/learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`, `knowledge-base/project/learnings/2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md`.

## Tags
category: workflow-issues
module: infra-gates
