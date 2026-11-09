# Learning: a PR sitting in the merge queue can still carry failing check conclusions — admission is not green

## Problem

While verifying the #12495 post-merge state (ref #12269), PR #12520 was observed inside the merge
queue — `added_to_merge_queue` at 2026-11-09T22:20:41Z, `mergeQueueEntry.position: 2` — while its
head SHA `68c37bff9e` simultaneously carried three FAILURE check conclusions:
`deploy-script-tests (4/4)`, `deploy-script-tests-fixed`, `deploy-script-tests-done` (the advisory
red-on-main tracked by #10613). Any poll or reader that treats "queued" as "all checks green" gets
the wrong picture; any poll that treats a FAILURE line on the head as "not queued" gets it wrong in
the other direction.

The same observation run showed a second non-equivalence: the queue entry's state was `UNMERGEABLE`
with `mergeable: UNKNOWN` — GitHub had admitted the PR to the queue and still had not finished
deciding whether it could merge. `UNMERGEABLE` persisted across two queries ~15 minutes apart, so
admission ≠ merged-eventually either; the entry's cause was unresolved at write time (a watch was
armed on it).

## Solution

Read the queue state and the check state as two independent signals and never collapse them:

1. Queue membership/position/state: GraphQL
   `repository.pullRequest.mergeQueueEntry { position state }` and
   `repository.mergeQueue(branch:"main").entries` — `gh pr view --json` does not expose
   `mergeQueueEntry` on current `gh` (unknown-field error), and `MergeQueue` has no `entryCount`
   field.
2. Check state: `gh pr view <N> --json statusCheckRollup`, compared against the required set —
   for this repo, ruleset id 14145388's `required_status_checks` is exactly 12 contexts
   (`affected-index-ratchet`, `dependency-review`, `e2e`, `guards-ruleset`,
   `oracle-review-required`, `quality-guards`, `secret-guards`, `sentry-destroy-required`,
   `skill-security-scan PR gate`, `tenant-integration-required`, `test`, `vendor-pin-required`).
   The three failing `deploy-script-tests*` contexts are not in it, which is *why* the PR was
   admissible — but an outsider reading the rollup alone would not know that.

## Key Insight

GitHub merge-queue admission is gated on the required-check set, not on the rollup being green.
Three independent predicates must not be conflated:

- **Admitted** — `mergeQueueEntry` exists.
- **Green** — every required context (and, separately, every context at all) reports SUCCESS.
- **Mergeable** — entry state resolves `MERGEABLE` / the group build passes.

A ship or postmerge poll that needs "did it land" should key on PR `state: MERGED`, and on
`mergeQueueEntry` presence/state for "is it still progressing" — never on "the rollup is clean" or
"it is in the queue" as proxies for either.

## Session Errors

1. **`gh pr view --json mergeQueueEntry` failed with `Unknown JSON field`** — the mergeQueueEntry
   field is not exposed by `gh pr view` on this version. **Prevention:** go straight to
   `gh api graphql` for merge-queue state; the field names above are verified working.
2. **`MergeQueue.entryCount` does not exist in the GraphQL schema** — the first queue query erred
   on `undefinedField`. **Prevention:** enumerate `entries(first:N)` and count client-side.

## Tags

category: integration-issues
module: ci/merge-queue
