# Decision Challenges — feat-one-shot-9729-s4-evidence-rerun

| Item | Class | Ruling |
|------|-------|--------|
| ADR-276 amendment appended with the re-ruling (parent brief lists receipts + §2 line only) | technical | pending - assumed: append per Decision-3(g) convention — every prior re-ruling (2026-11-07, both 2026-11-08) recorded the verdict as a dated amendment, and the gate's verdict= prerequisite reads the receipt path from the ADR's `Go/no-go receipt:` line; flagged `inferred` in the plan's Scope Check |
| `gh issue comment 9729` with the verdict (not in the parent's deliverable list) | technical | pending - assumed: post the comment per R2/R3 convention — it keeps the parked epic's record complete and closes nothing |
| Receipt `ruled=` token on the `SOLEUR_PR_AFFECTED_VERDICT` line | technical | pending - assumed: `ruled=confirmed` once the parent's batched CTO spawn confirms the computed verdict; write `ruled=pending` if confirmation is declined — the gate accepts both spellings but `confirmed` is the prior-receipt form |
| Disposition on a non-zero pinned audit (stale/gap/unaudited rows) | technical | pending - assumed: record the rows verbatim and rule criterion (b) `fail` — never drain inside this PR; the drain rubric makes drains separate `s4-drain`-labelled PRs |
| `--chunk` factor for collect (4-way parallel legs) | taste | K=4, matching the 2026-11-08 rerun — identical output to serial collect with per-unit resumability; ~40 min wall vs ~2.5 h |
