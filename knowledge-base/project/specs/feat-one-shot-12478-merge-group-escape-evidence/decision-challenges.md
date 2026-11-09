# Decision Challenges — feat-one-shot-12478-merge-group-escape-evidence

Headless one-shot pipeline: technical forks are recorded as `pending - assumed:` rows for the
parent's batched technical-ruling-gate CTO (see technical-ruling-delegation.md). Operator-ruled
items are recorded as ruled, not pending.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| For a merged qualifying PR whose merge commit lacks a `push` run: (A) fall back to the `merge_group` CI run on that commit and apply the same gated `test-scripts*` jobs classifier, vs (B) bucket queue-merged PRs as a distinct `queued`/`no-push-run` class reported in the note line, like `unrelated` | technical | pending - assumed: Arm A (merge_group fallback, shared classifier) - the queue ran the full battery on the exact commit that landed, so a red `merge_group` run on a gated leg is equivalent escape evidence; Arm B is self-assessed weaker in #12478 (drops real escape evidence the mg run already provides) and ADR-276 already names `merge_group` the full-battery authority. Verified live 2026-11-09: all 3 pending merge commits carry `merge_group` ci.yml runs (`42532979741` failure-on-`lint-bot-statuses`-only, `42493927928` success, `42472568357` success) and zero `push` runs; the mg run's `head_sha` equals the PR `merge_commit_sha` (full-40-char query required — a 10-char prefix returns an empty list). No subagent spawn was available in the planning seat; Phase 1 step 1 re-verifies against the parent's batched ruling gate and re-scopes to the strictly-smaller Arm B bucket if re-ruled. |
| Report merge_group-sourced verdicts on a `via_mg` note line vs fold them silently into `ok` | technical | pending - assumed: count `via_mg` and print a note line (`N qualifying PR(s) verified via merge_group run(s) on their merge commit`) — preserves Arm B's visibility instinct (queue merges named on the note line) at zero extra reads and zero verdict impact; matches the file's `dropped`/`open`/`unrelated` note vocabulary. |
| `need_min` API-budget model: bump `3 * MAX_RUNS` to `4 * MAX_RUNS` vs leave unchanged | technical | pending - assumed: `4 * MAX_RUNS` — the mg read's worst case is +1 read per qualifying run (all of them queue-merged); the preflight floor must model the bound honestly or the sweep starves through a different door. |
