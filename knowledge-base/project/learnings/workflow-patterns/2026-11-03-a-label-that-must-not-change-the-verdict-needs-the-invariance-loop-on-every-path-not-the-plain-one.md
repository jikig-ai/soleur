# Learning: a label that must not change a verdict needs an invariance loop over every verdict path, and a decision table needs its order pinned

## Problem

PR-A of #12011 added an optional `Method: tty-ack` label to the standing-delegation record and a 5-row decision table in `approval-card.md`. Review found two structural gaps, not five separate bugs:

1. The claim "the label never changes the verdict" was tested only on the plain accept path. The parser counted the label with a narrow pattern, so hidden, fenced, indented, quoted and lowercase claims of the label slipped past the count while the verdict stayed green.
2. The decision table (legal/irreversible/money rows first, first match wins) was prose-only. Reordering rows, or dropping the headless note on rows 1 and 2, kept every test green.

## Solution

- Parser: `P_METHOD_N` is a broad count (`grep -ciE '^[[:space:]>]*\*\*method:'`) and `P_METHOD` the canonical value; any disagreement is the new reason token `method-unknown`.
- Test arm 5b runs a verdict-invariance loop: for each of 11 non-plain scenarios (`s_edited s_app s_bot s_nonadmin s_noconfirm s_exclinc s_noexp s_toolong s_expired s_closed s_noscope`) the verdict with and without the label must be identical.
- `approval-card-wording.test.sh` pins the table by row index and column (order, outcome message per row, the headless note), and pins the verifier's `= tty-ack` accept sites at exactly two.
- Mutants added for each guard: `method`, `method-parse`, `render-method`, `method-skip-edited`, `method-skip-excluded`; floors set to the measured counts (`CALLS_FLOOR=2991; RESULTS_FLOOR=1883`).

## Key Insight

An invariance claim ("X never changes the outcome") is a claim over every outcome class, so the test must be a loop over the classes, with the plain path as only one member. And a first-match-wins table is an ordered program: test it by row position, or the order is decoration.

## Session Errors

1. **First session-start Bash call was rejected by the user** — Recovery: re-ran as split calls. **Prevention:** keep session-start probes as separate simple calls.
2. **First RED run overlapped my own edits and was invalid** — Recovery: killed it, re-ran on a settled tree. **Prevention:** never start a battery while edits are pending (already the ship rule "start on the FINAL tree").
3. **Missing scratchpad dir broke `gh issue edit --body-file`** — Recovery: created the dir. **Prevention:** `mkdir -p` the scratchpad subdir before writing body files.
4. **CTO delegation returned an empty result** — Recovery: re-requested via SendMessage. **Prevention:** treat an empty agent result as a failure, never as "no objection".
5. **Wording test failed on prose wrapped across lines and on a floor mismatch** — Recovery: flattened text before matching and set exact floors. **Prevention:** match prose against a whitespace-flattened copy; set a new floor in the same edit that adds the assertion.
6. **Write refused after the file changed on disk** — Recovery: re-read, then wrote. **Prevention:** re-read before overwriting a file another step touched.
7. **Long local affected gate could not finish; user asked to rely on CI** — Recovery: stopped the local run, CI is the merge gate (ADR-183). **Prevention:** run only the suites that reference changed files locally; leave the sharded battery to CI.
8. **Secret-scan commit block on the identifier `fileToken`** — Recovery: renamed the identifier. **Prevention:** avoid token-shaped identifier names in docs and fixtures.

## Tags
category: workflow-patterns
module: soleur-plugin/standing-delegation
