# Learning: a regex guard over shell text cannot be closed, so pin the artifact; and the confound in my evidence was my own push

## Problem

PR #10061 moved the weekly weakness-digest PR onto the `soleur-infra` GitHub App (#9454 item 4: the digest PR authored and
armed as `github-actions[bot]` had its runs held and its merge-queue entry got no `merge_group` runs). The fix was a few
lines of workflow and composite change. The guard that keeps it from reverting took five review rounds.

The guard was a static python walk over the workflow YAML and the composite's inline shell. Each round a seat found a
fresh way to satisfy every rule while violating the property ("authored, pushed and armed as the App; a bare `gh` cannot
silently use the workflow token"): a second `_pr=` assignment, a quoted `function gh_app(){ "gh_gate" "$@"; }`, an alias,
a bare `gh` in a case arm or as `/usr/bin/gh`, `curl` with the gate token, a refusal ending `true || exit 1`, a commented
header line, an inlined `${{ inputs.pr-token }}`, a heredoc body. The battery grew from 21 to 72 rows and each round still
left survivors, because shell has more spellings than any list of rules.

Separately, ADR-285's evidence paragraph said PR 10013's second queue entry "was armed by a human after the held runs were
approved". A seat re-derived the timeline and found the head had also changed: a human-pushed commit (`3bee7c4974`)
replaced the bot commit, and its runs were fresh and never held. That commit was the review-trailer commit I pushed myself
while shipping #10013, so the confound was mine and I had not listed it.

## Solution

1. Keep the regex rules, but demote them to diagnostics that name which property moved, and make a hash pin the closure:
   the composite's normalised run body, env, shell, inputs and defaults, and the digest workflow's credential job, are
   sha256-pinned in the test, and any edit to either re-pins in the same PR where a reviewer sees it. Comment and
   blank-line edits normalise away (case H3 proves they stay green); rows 66 and 67 prove a content edit goes red. This
   caught the quoted-function bypass that every regex missed.
2. The pin only works because the artifact is stable and rarely edited. It is the wrong tool for a file that churns.
3. Re-derive an evidence paragraph by listing every variable that changed between the two observations (enqueuer, head
   commit, pusher, run approval state, author), including variables I changed.

## Key Insight

When review has produced a fresh bypass of a text-matching guard in two consecutive rounds, stop adding rules. The class
cannot be closed by enumeration; either delete the heuristic or pin the whole artifact so that every edit is a visible,
deliberate re-pin. The existing review-skill bullet says "delete the heuristic"; the pin is the form of that when the
guarded file must stay.

A causal claim in an ADR is a list of what changed. If I touched the system between two observations, my own action is
one of the changed variables, and it is the one I am least likely to name.

## Session Errors

1. **A new top-level heredoc write tripped the `fixture-relative-assert` ratchet** — Recovery: `assert_fixture_dir "$WM_ROOT"` before each write — Prevention: when adding a `*.test.sh` write outside a function that bound the temp root, run the two fixture ratchets before the first commit (already in work Phase 0.5 6.6).
2. **Parity test 8 anchored the branch push and the check-run POST by literal spelling** — Recovery: widened the anchors to `git_remote push` and `gh_gate api` — Prevention: after renaming a command in a composite, grep every test for its old literal, not only the suites named in the plan.
3. **`echo "rc=$?"` after `| tail -1` reported tail's status, masking a red trap-ownership lint on my own new line** — Recovery: re-ran without the pipe, annotated the bounded `mktemp` — Prevention: capture `cmd > log; rc=$?` on its own line before any pipe (already a documented class; it recurred with the rule in view).
4. **Plan's expected `app-token` notice omitted `metadata:read` and `source=`** — Recovery: corrected the literal and added pull commands — Prevention: run the producer's emit line once before writing an expected-output literal into a plan.
5. **ADR-285 omitted that the head commit changed between the two queue entries** — Recovery: listed the four variables and the confound, and made the post-merge criteria treat a human-pushed head as not evaluable — Prevention: when citing two observations of one PR, diff the head SHA and the pusher first.
6. **My first guard matched callers by exact string, scanned only the first step containing `pr create`, and tested refusals by text** — Recovery: resolved spellings plus a raw cross-check count, one-step composite, exact refusal bodies — Prevention: for a guard over a derived population, state what the walk cannot resolve and cross-check against an independent raw count.
7. **Regex rules could not be closed over shell text** — Recovery: sha256 pin of the composite and the credential job — Prevention: see Key Insight; ship the pin with the first guard when the guarded file is small and stable.
8. **Stop hook blocked two closings that stated a future action** — Recovery: explicit `<stop>BLOCKED:` statements — Prevention: end a waiting turn with the blocker, never with an intention.
9. **`rm -rf $var` and a stray `git stash list` were hook-blocked** — Recovery: literal paths; dropped the stash call — Prevention: use literal paths for scratch removal; never put `git stash` in a combined command.
10. **Plan phase could not Read the sharp-edges catalogue whole (forwarded from session-state)** — Recovery: searched it and read the relevant entries — Prevention: grep a catalogue for the nouns of the change instead of reading it whole.
11. **Case-count floor written as 26, real count 25** — Recovery: floor fired, corrected to 25 — Prevention: none needed; the floor worked as designed, now pinned by a row-name set as well as a count.
12. **Shell cwd reset between calls** — Recovery: `cd` into the worktree in each call — Prevention: chain `cd <worktree> &&` in every call.
13. **Planned a separate deferral issue for the audit author filter, then found it fit the inline bound (<=100 lines, 2 files, same subsystem)** — Recovery: fixed inline, one tracker issue only (#10068) — Prevention: run the cost-of-filing check at plan time, not after.
14. **Row list and case floor hand-synced in two places** — Recovery: the floor compares the set of row names against an independent literal — Prevention: derive the second list from the artifact, or assert set equality.

## Tags

category: workflow-patterns
module: ci-guards
