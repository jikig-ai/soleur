# Learning: a classifier run from the candidate tree can be forged by the diff it judges

## Problem

#12156 shipped a CI fast lane: an `oracle-selection` job runs `scripts/ci-oracle-lane.sh` to decide whether a
diff is oracle-only and may skip five heavy test legs. The first implementation ran the driver from the
*checkout of the candidate tree* — the merge ref on pull_request, the batch head on merge_group. The
security-sentinel seat flagged the P1: a same-repo PR could replace the driver with a 5-line script that
prints forged outputs (`oracle_only=true`, `active=true`, the event's own head_sha — all handed to the step
via `env:`), and every downstream consumer (leg `if:`s, the `ORACLE-ONLY-SKIP` aggregator arm, the lock
literal `ORACLE_LANE_LOCKED=1` *inside the replaced file*) would honor it. The dark-phase `would_skip`
telemetry — the blocking activation evidence — was equally forgeable. The precedent was already in the same
file: `shard-totality-mutations` sources its classifier via `git show "origin/${GITHUB_BASE_REF}:..."` with
the comment "a PR must not weaken the gate it is judged by". The new job failed to follow its own file's
recorded lesson.

Three sibling defects in the same review round, all "fail-open inside a component whose contract is
fail-closed":

- `git diff -U0` on a binary blob (one NUL byte) emits `Binary files … differ` and **zero hunks** — a
  hunk-walking extent check passed vacuously on a wholesale rewrite of the index.
- A `'+++'*|'---'*` skip arm intended for diff file headers also matched a *content* line whose payload
  began `++` (`+++$(evil)`), bypassing the element grammar entirely — skip arms must name the literal header
  shapes `'--- a/'`, `'+++ b/'`, `'--- /dev/null'`, `'+++ /dev/null'`.
- The "data file" being protected is *sourced bash*: a quoted array member `"$(evil)"` executes on source.
  The element grammar's first form (`"([^"\\]|\\.)*"`) accepted it; excluding `$` and backtick from the
  member class was required (`"([^"\\$\`]|\\.)*"`).

## Solution

Source the classifier from the BASE image, never the candidate: `git show HEAD^1:scripts/ci-oracle-lane.sh`
(pull_request; HEAD^1 is already SHA-validated) or `git show $MERGE_GROUP_BASE_SHA:` (merge_group). A base
that lacks the file (the introducing PR itself, any pre-#12156 tree) emits the fail-closed defaults plus a
`reason=no_base_driver` notice — the honest base driver then reads any driver edit as outside-surface, so a
PR touching the lane machinery always pays the full battery. The machinery's three files also joined both
`is_excluded_path` (defense in depth) and `RATCHET_ORACLE`/the observation probe's list/CODEOWNERS.

## Key Insight

Any check whose *outputs* authorize skipping work, and whose *code* runs from the tree under test, is a
self-judged gate: the edit that wants the skip can rewrite the judge. The rule is mechanical — when adding a
new selector/classifier job, grep the diff-under-test's trust boundary: does the executing code come from
the candidate checkout or from a base image? The repo already encoded this once (shard-totality); the
learning is that "the precedent exists" does not transfer — each new job must re-derive it, and review is
where that gap is caught. Companion rules: a `git diff` consumer that iterates hunks must guard the
zero-hunk shapes (`^Binary files`, mode-only flips) explicitly, and a "data-only" surface member whose file
is *evaluated* (sourced bash, YAML anchors, etc.) needs a content grammar, not just a position check.

## Tags
category: workflow-issues
module: ci-oracle-lane
