# Learning: a marker reading rule is a set of claims, and the premise I put in the brief was the first false one

## Problem

The fourth manual live-fire of the compound-promote create arm (2026-10-29T08:03Z, after PR #11441 added
`create_offered`) came back `no_action` / `no-pattern-qualifies` with `create_offered=6`, `patterns_open=7`,
`create_pr` absent: the model was offered six of the seven patterns and declined all of them. I then told the
operator that the marker could not separate "the model declined" from "a server gate refused a model-proposed
create", proposed new marker fields, and wrote that sentence into the one-shot brief as a premise.

It was false. The CTO read the producers: every gate except the ledger / same-run backstop returns `refuse(...)`, which
the handler stamps as `create_outcome=refused` with `create_refusal_class` and `create_detail`; no server path emits
`no-pattern-qualifies`. So run 4 was a model decline with no gate involved, the briefed fields would have been
redundant, and the PR became documentation only: a "Reading a live-fire row" subsection in
`compound-promote-runbook.md` (a nine-row table that ended at eleven rows, plus an invariant paragraph) and a one-line pointer in
`betterstack-log-query.md`.

The review then found the same two classes of defect in that prose across three rounds (21 raw findings, 11 unique, no
P1; then further P3 wording points in two fix rounds): a universal sentence followed by its own exception ("every gate returns
`refused`" then "except the backstop"); a table that was not exhaustive over the refusal vocabulary (`schema`,
`unknown-pattern`, `nearest-missing`, `no-api-key`, `internal`, the persist-side classes); a lumped row (`all-owned`
with `create_offered > 0` can only be the model's, `other` can be the model's or the backstop's); a pointer to a place
that does not exist on the row being read ("the refusal threshold in the PR body trailer" for a refused row, which has
no PR); `nearest-missing` described as "a skill that does not exist" when it also covers model-invocation-disabled
skills; and a present-tense production claim about the cost row ("absent while the incident is open") that the alert's
own predicate (a fleet-wide 24 h count of non-null `cost_usd` rows) neither predicts nor explains for one run.

## Solution

- Draft a reading rule from the producers, not from a ruling's summary: list every emitter of each reason and class
  (the model enum, `selectOffered`, the handler's `suppressed` branch, `refuse()` call sites) and write one row per
  path before writing any universal sentence. Run the claim-by-claim table against the source before the panel; the
  code-quality seat's table in round 1 found most of what rounds 2 and 3 re-found in other cells.
- State a production observation as a dated, sourced observation, and read the alert's actual predicate before
  linking an observation to it.
- A pointer to "where the value is" must name a place that exists on the row being read. A refused row opens no PR.
- When a review finds that a CTO-ruled row is slightly too strong, append a labelled review note; do not rewrite it in
  the ruler's voice. The run's CTO spawn cap (two) had already been spent on the plan phase and on a gate-shape fix.
- The product-level result is the useful part: the create arm is working as designed and the model declines;
  `create_pr` stays empty. Any next step (supplying the server's per-pattern top-3 list in the prompt, or a
  different evidence bar) is its own PR with its own operator-authorised live-fire.

## Key Insight

"The marker cannot show X" is a claim about its producers, and it costs one grep (`refuse(` and the `no_action`
emitters) to check before it goes into a brief or a message. I applied the repo's rule that a plan's or resume
brief's measured facts are preconditions to everyone else's text and not to my own previous-turn sentence.

## Tags

category: workflow-issues
module: compound-promote create arm (runbook), review of documentation that states claims about code
related: 2026-10-28-a-new-telemetry-field-is-read-through-its-reading-guide-and-the-guide-omitted-the-catch-arm.md

## Session Errors

1. **Asserted, and then relayed into a brief, that the marker could not distinguish a model decline from a gate
   refusal.** Recovery: the CTO ruling read `refuse()`/`checkCreate`; the PR was reframed as docs-only. Prevention:
   before writing "X cannot distinguish A from B" anywhere, open the producer of A and of B; treat your own earlier
   sentence like a brief's "measured" fact.
2. **Created a worktree nested inside another worktree.** `worktree-manager.sh create` was run from the detached
   post-merge worktree; when the main checkout is not a bare repo the script takes the invoking worktree's
   `--show-toplevel` as the root. Recovery: removed the nested worktree and its branch, recreated from the repository
   root. Prevention: run `create` from the repository root path, never from inside a worktree. A script fix (derive
   the root from `--git-common-dir` whenever it ends in `/.git`) is a different-subsystem change and was not made here.
3. **The technical-ruling gate failed on a planner-written row ("Applied by planner").** The deepen pass refined a
   CTO-ruled row without the ruling shape, and fixing it needed a CTO spawn, the run's second and last. Prevention: a
   refinement to a ruled row is a technical item; spawn at plan time or write it as a labelled note outside the
   ruling column; budget the two-spawn cap knowing the gate may need one.
4. **A review refinement narrowed the ruling's "only `no-pattern-qualifies` is the model's" wording after the spawn
   cap was spent.** Recovery: recorded as a labelled review refinement in the decision record. Prevention: at ruling
   time ask the CTO for the exhaustive producer table ("which reasons can a server path emit?"), so no later
   narrowing is needed.
5. **A chained `sleep 45; tail ...` was blocked by a hook.** Recovery: read the task output file with Read. Prevention:
   wait with Monitor or Read, never a sleep chain. (one-off)
6. **Two Python parses of a Better Stack row failed** (the marker is nested under `.message` as an object, not a
   string). Prevention: dump `keys` of one row before parsing (the rule that a sentence about a stored row's shape is
   a measurement). (one-off)
7. **`test-all.sh --print-selection` ran past 200 s on a contended box (five sibling runs).** Recovery: stopped it and
   relied on the targeted suites. Prevention: read `test-all.sh --capacity` first. (one-off)
8. **Three fix commits for wording on a roughly 45-line docs diff, nine review seats.** Cause: the first draft's table
   was built from the ruling's summary, and each seat round found other instances of the same two classes.
   Prevention: run the claim table against the source at drafting time, not at review.
