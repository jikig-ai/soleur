# Decision Challenges — feat-one-shot-10865-constraint-scaffold-pairs

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Brand-survival threshold for a CI affected-index metadata diff | technical | pending - assumed: `none` — worst case is a wrong suite-selection set on a still-advisory check; no user-facing surface reachable |
| Rebase onto origin/main before declaring (vs. declaring the foreign pairs' edges in this diff) | technical | pending - assumed: rebase — #12212 merged 2026-11-06T07:52Z and already declares both foreign pairs; duplicating its declarations would double-declare |
| Edge granularity: dir-honest entries (`scripts/`, `references/`, `test/fixtures/`) vs per-file enumeration | technical | pending - assumed: dir-honest — the suite `cp -R`s `scripts/`+`references/` wholesale (:142) so every member feeds the verdict; parity sibling already uses `references/` dir form |
| Exclude `apps/web-platform/` paths from the declared block and accept-row them as mentions | technical | pending - assumed: exclude — suite :8 "the real apps/web-platform tree is never touched"; literals at :129/:368 are fixture writes into scratch `$BASE`/`$FX` repos |
| Carry `plugins/soleur/test/lib/git-fixture-env.sh` from derived edges into the declared block | technical | pending - assumed: carry — declared block REPLACES derived edges and the suite sources it at :96; dropping it would un-select a real input |
| Rebase-ORDER vs flag-risk of sibling accept.tsv churn (`feat-one-shot-bun-pair-ratchet-accept-cleanup` live on same files) | technical | pending - assumed: rebase first, verify ratchet again on merged tree pre-arm and after every sibling merge while queued (2026-10-26 learning) |
