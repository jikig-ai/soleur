# Learning: pin a workflow step's control-flow skeleton, not patterns over its body

## Problem

PR 11688 added a guard (`diagnose-on-failure` in `plugins/soleur/test/npm-publish-oidc.test.sh`) meant to
guarantee that a failed `npm publish` always fails the job and always reaches a failure-only diagnose step. The first
version matched patterns over the publish step's `run:` body (a guarded `if ! npm publish ...; then`, an `exit 1`
after it, a marker before `exit 0`, a ban on `|| true`/`set +e`/`--dry-run`). The review panel and then a
verification pass defeated it ten different ways with the property violated and the suite green: an unconditional
early `exit 0` before the publish, a marker inside `if false`, an `exit 1` that sat in `echo ... # exit 1`, a
`trap 'exit 0' EXIT`, a step-level `if: ${{ false }}`, `BASH_ENV`/`NODE_OPTIONS`/`PATH` in step/job/workflow `env`,
a second publish spelled `pnpm publish` or `npm \` newline `publish`, a `uses:` publish action, and
`echo "$(printf 'dry-run=true\n' >> .npmrc)"` (an echo line that rewrites `.npmrc`).

## Solution

Reduce the step to its control flow and compare that to a pinned golden: drop only `echo "..."` lines whose body has no
`$(`, `${`, backtick or backslash (the marker echo becomes `<MARKER>`), collapse whitespace, and require equality.
Add: exactly one publish of any spelling (continuations joined, `uses:` publish actions counted), the publish
step's `env` pinned to the two names its body reads, `working-directory` pinned, job and workflow `env` empty,
`defaults.run` refused at job and workflow level, no `continue-on-error` on any other step, and the diagnose step
exactly `bash .github/scripts/npm-oidc-diagnose.sh`. An intentional flow change now reds the guard and must update the
golden in the same diff, which is the point.

## Key Insight

A pattern grep over a script body is satisfied by every construct that contains the pattern and does not execute
it (a dead branch, a comment tail, a quoted echo, a trap). For a guard whose property is control flow, compare the
control flow. And the fix for a vacuous guard is itself written holding the old defect in mind: the first skeleton
dropped every `echo "..."`, which re-opened the hole through command substitution, and was found only by the
verification pass.

## Session Errors

1. **Edit tool rendered ` ` as a raw separator inside a test payload; the U+2028 assertion then checked the wrong run and was vacuous.** Recovery: rebuilt the payloads from ASCII pieces (`printf '\xe2\x80\xa8'`) and moved the assertion inside the loop. Prevention: build separator/control payloads at run time, never as `\u` escapes in an edited file; already in the review skill's sharp edges.
2. **The worktree directory was removed mid-session by something outside the session.** Recovery: everything was committed and pushed, `git worktree prune && git worktree add` on the existing branch. Prevention: commit and push after each verified unit (already `wg-ship-push-before-merge` and the work skill's commit-immediately rule); the reaper defect is already tracked by the sibling worktree for the live-session reap.
3. **Hook-denied commands:** `git add` of a file created by a heredoc in the same call, `pgrep -f`, `sleep 60; cat ...`, `rm -f "$D/*"`, `git stash list` inside a compound command. Recovery: create the file first, use captured PIDs / `list_runs` / Monitor, quote `"${D:?}"/*`. Prevention: already hook-enforced.
4. **Adding one entry to an existing `AFFECTED_*_PATHS` array in `scripts/lib/test-affected-paths.sh` made the affected gate degrade to the full battery (`reason=runner-changed`, INDEX-SHAPE), which was then refused behind two sibling full-gate runs.** Recovery: reverted the entry; the suite is reached through its own source closure and the bounded selection ran 280 of 703. Prevention: only a NEW `AFFECTED_<LABEL>_PATHS` block or an `ALWAYS_ON_SUITES` entry for a NEW suite is an admitted index edit; do not touch an existing block for a new file that the suite's own source reaches.
5. **The first fix batch re-opened the guard's hole one level up (command substitution inside an `echo`, unconstrained `env`).** Recovery: tightened the echo dropper and pinned env. Prevention: on a fix to a vacuous guard, review the NEW assertions before the new code (already a review-skill rule; added the skeleton insight there).
6. **A check kept for safety was redundant (the `clean`ed copy against the squeezed copy), so its mutant survived as equivalent.** Recovery: deleted the redundant check rather than documenting an equivalent mutant. Prevention: a surviving mutant is fixture-inadequate or equivalent; when equivalent, remove the code.
7. **Several of my own scripted edits failed on anchors (indentation, `%d` formatting of a template, a prefix collision on `run_diag clong`).** Recovery: assert-then-write scripts wrote nothing on failure, so each was safely retried. Prevention: assert the anchor before writing (already the practice).
