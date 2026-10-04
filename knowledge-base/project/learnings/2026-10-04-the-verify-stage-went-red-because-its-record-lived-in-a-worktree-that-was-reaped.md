# Learning: a staged bootstrap's `verify` reads red once the worktree that ran it is reaped

## Problem

The #9462 proof (dispatch the release workflow, check the narrow App source, flip ADR-241 D11 to `accepted`)
needed the bootstrap script's `verify` stage to print `SOLEUR_BOOTSTRAP_READY_FOR_PR2`. In a fresh session it
printed five PASS lines and one FAIL, "the recorded slug is the live token and was stored", and stopped.

Nothing live was wrong. That check compares the token's slug with `TOKEN_SLUG` and `TOKEN_STORED` in the script's
gitignored `.env`, which sits beside the script. The worktree that ran the original bootstrap had been removed by
`cleanup-merged`, and a gitignored file dies with its worktree. The generator's own skill text already says so
("a fresh checkout without it turns a satisfied stage into a rotation plan"), so this was a documented property,
met in practice for the first time.

## Solution

Judge the flip on the evidence that is live and attribute each line to its source:

- the production run (success, `headSha` descends from the switch merge, the credential-check and mint steps
  success, exactly one `source=soleur-infra-app/prd` notice);
- the other `verify` checks (environment secret listed, repository level not listing it, one token, both copies
  equal their sources);
- the READY line the switch PR (#9453) recorded before it merged.

State the red check and its cause in the amendment, and do not claim READY was re-observed. Do not restore the
record by hand: the only writer is `mint-and-store-token`, which treats a lost `.env` as "nothing proves the live
token is the stored one", mints a replacement and revokes the current token. That is a production write, so it is
not done to repair bookkeeping.

## Key Insight

A verification step whose evidence is a gitignored file beside a script is only as durable as the directory it
sits in, and on this repo that directory is a worktree with a short lease. Separate "the system disagrees" from
"my record of the system is gone" before reading a red verify, and say which one it is in the artifact, because
the first blocks the flip and the second does not.

Two instrument notes from the same session. A count over a failed read is a vacuous zero: the organization-level
secret listing returned HTTP 403, and `| grep -c` printed `0`, which reads as "no shadowing secret". It was recorded
as not checked. And a four-seat docs review found 11 wording and placement defects in the first draft of the
amendment (entry order, an unattributed `verify` result, "a rotation" hiding a credential change, a status bullet
that read as covering both release jobs when only the build job's caller was proven), all fixed in one round.

## Session Errors

1. **`worktree-manager.sh create` stopped at a `Proceed? (y/n)` prompt in a non-interactive Bash call and created
   nothing.** Recovery: re-ran with `echo y |` and confirmed with `git worktree list`. Prevention: after any
   worktree create, assert the path exists before the first edit.
2. **`gh pr view --json isInMergeQueue,mergeQueueEntry` failed twice (unsupported fields).** Recovery: read the
   queue entry through GraphQL (`pullRequest.mergeQueueEntry`). Prevention: for merge-queue state use GraphQL, and
   run `gh pr view --json` with no field once to see the supported set.
3. **`gh api orgs/<org>/actions/secrets | grep -c` printed `0` over an HTTP 403.** Recovery: re-ran without the
   count, saw the 403, recorded the listing as not checked. Prevention: print the producer's status (or the first
   line of its error) before counting its output.
4. **A first draft of the ADR amendment shipped five defects the panel found:** placed before the entry that had
   landed earlier, "(a rotation)" for a mint-and-revoke, a `verify` result with no run or date, a status bullet
   scoped to "a release run", and a missing References line. Recovery: one review-fix commit. Prevention: for an
   amendment that cites a measurement, write the source and scope in the same sentence as the number.
5. **The shell's working directory drifted into the primary checkout after a `cd <primary> && ...` one-liner,
   flipping the session's reported working directory.** Recovery: every later command named its worktree path.
   Prevention: in a worktree session, do not `cd` out in a compound command; use `git -C` or absolute paths.

## Tags

category: workflow-issues
module: operator-bootstrap, ADR-241
