# Decision Challenges — feat-one-shot-12478-merge-group-escape-evidence

Headless one-shot pipeline: technical forks are recorded as `pending - assumed:` rows for the
parent's batched technical-ruling-gate CTO (see technical-ruling-delegation.md). Operator-ruled
items are recorded as ruled, not pending.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| For a merged qualifying PR whose merge commit lacks a `push` run: (A) fall back to the `merge_group` CI run on that commit and apply the same gated `test-scripts*` jobs classifier, vs (B) bucket queue-merged PRs as a distinct `queued`/`no-push-run` class reported in the note line, like `unrelated` | technical | Ruled by CTO agent, 2026-11-09: Arm A — fall back to the `merge_group` ci.yml run on the merge commit and apply the shared gated `test-scripts*` jobs classifier (fallback only when the push event is inconclusive; one classifier parameterized by event; full 40-char head_sha) - merge_group is ADR-276's full-battery authority and runs the battery unconditionally on the exact sha that landed (verified live: 3/3 pending merge commits carry mg runs, zero push runs; #12445's red mg run fails only non-gated `lint-bot-statuses` → `unrelated`); Arm B would discard real escape evidence the queue already produced. |
| Report merge_group-sourced verdicts on a `via_mg` note line vs fold them silently into `ok` | technical | Ruled by CTO agent, 2026-11-09: via_mg note line — count merge_group-sourced `ok` verdicts and print `note: N qualifying PR(s) verified via merge_group run(s) on their merge commit` - the probe's note-line vocabulary (`dropped`/`open`/`unrelated`) exists to keep evidence-source provenance auditable on a public tracker; zero extra reads, zero verdict impact, mirrors the #12360 precedent. |
| `need_min` API-budget model: bump `3 * MAX_RUNS` to `4 * MAX_RUNS` vs leave unchanged | technical | Ruled by CTO agent, 2026-11-09: `4 * MAX_RUNS` - the mg read's worst case is +1 read per qualifying run (all queue-merged), and `need_min` is the honest worst-case preflight floor; the red-mg jobs read rides the same rare red-run-only carve-out as the red-push jobs read, so the bound is 4, not 5. |
