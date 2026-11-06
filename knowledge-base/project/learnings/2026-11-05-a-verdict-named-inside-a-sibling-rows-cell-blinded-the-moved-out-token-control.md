# Learning: a verdict-name literal inside another row's cell text breaks the "moved-out token is reported missing" contract control

## Problem

PR #12153 (work phase). `apps/web-platform/infra/key-rotate-workflow.test.sh`'s B22 contract block verifies that every verdict token the script prints under `--print-contract` appears as a backticked cell in the runbook's Refusals/Verdicts table rows (`rb_rows` + `rb_missing`, `key-rotate-workflow.test.sh:429-435`). Control B22e mutates a runbook copy so `rotate_ok` is moved out of its own table row, and asserts the token is still reported missing. It went red: the new `vector_restarted` row's prose cell named `` `rotate_ok` `` in backticks ("the terminal green is still `rotate_ok`"), so after the mutation the token still matched inside a sibling row — `rb_missing` reported nothing missing, and the control that exists to prove the grep sees row-moves was blinded by the runbook's own wording.

## Solution

Reword the `vector_restarted` cell to describe the verdict instead of naming its literal — "the terminal green is still the rotate-complete verdict above" — so `` `rotate_ok` `` appears in the table exactly once, in its own row (runbook `knowledge-base/engineering/operations/runbooks/key-rotation.md`; suite back to 628/0, then 639/0 after the approve-fails rows).

## Key Insight

When a contract test greps a table for a backticked literal, EVERY cell is a potential match site — including prose cells of sibling rows. In a verdict table read by contract, do not name a sibling verdict in backticks inside another row's cell; refer to it by role ("the rotate-complete verdict"). The general rule: before adding a literal to a row under a token-presence contract, grep the table section for where else that literal lands and ask which control row consumes each hit.

## Session Errors

1. **The runbook's `vector_restarted` row was authored with a sibling verdict literal in its cell** — discovered by the B22e control going red, fixed by rewording. **Prevention:** this learning's key insight; grep the contracted section for the literal before adding it to a cell.
2. **`lint-shell-capture-exit` FAIL on the new restart-vector test rows** (`x=$(grep -oE ... | head -1)` under `set -e` dies on no-match) — Recovery: `|| true` inside the substitution (commit 534cfb640d). **Prevention:** already enforced by the existing lint.

## Tags
category: test-failures
module: knowledge-base/engineering/operations/runbooks/key-rotation.md, apps/web-platform/infra/key-rotate-workflow.test.sh
