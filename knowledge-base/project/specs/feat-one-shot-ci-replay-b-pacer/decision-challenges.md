# Decision Challenges — feat-one-shot-ci-replay-b-pacer

Headless planning session (no Task/spawn tool in this environment): technical
rows are recorded `pending - assumed:` per the technical-ruling delegation
contract — a spawned CTO ruling may replace any of them before work commits to
the alternative.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Item B primary lever for `row_scan_ops` site cost: per-scan `give_up` inside `cpu()` + cheapest-condemner leg ordering + early `if bad` exits (vs. corpus shrink vs. rep cuts vs. moving property to another arm) | technical | pending - assumed: adopt give_up + ordering + early exits; corpus shrink is rejected on the recorded #10404 survivor evidence and rep cuts buy ~1.4 s of pristine time only |
| Text-axis fixture sizes: 64KB→1MB replaced by ~16KB→~256KB (same ~16x window, detection band preserved, ~1/16 mutant cost) vs. keeping 1MB | technical | pending - assumed: ~16KB→~256KB; the hard constraint is the small leg staying >= ~1ms of pristine time above FLOOR — exact sizes tuned against a local jitter check at work time |
| Line-event cap `40*len+20000` tightening (bounds the cap-burn class, site 175 = 12.5s) | technical | pending - assumed: tighten to ~`12*len+5000` (~1.5x above the asserted `ev <= 8*len` bound; ~3x less cap-burn) |
| `row_sym` per-invocation timeout mechanism + value (`REPLAY_SUT_TIMEOUT` override in run_sut:249, unset default 30s) | technical | pending - assumed: adopt, set to 10s inside row_sym's subshell (~10x headroom over the ~1s pristine audit); invalid values must fall back to 30, never disable the bound |
| Site 350 `row_rt_big_baseline` (31.2s, arm -c): reduce vs. leave | technical | pending - assumed: leave unchanged — mutant cost is pinned at the 30s timeout, the 150k fixture is load-bearing (recorded 60k survivor), and the bound cannot shrink below ~28s without eating the pristine 25s budget |
| Item A write mechanism: `--incremental --durations` regen for provenance-honest headers vs. surgical two-line edit | technical | pending - assumed: hand-edit + regen refresh (`python3 scripts/regenerate-shard-manifest.py --incremental --durations scripts/suite-durations.tsv --write` — dry-run verified 2026-11-08: 744 incumbents pin verbatim); fall back to the surgical edit if the regen produces unrelated churn |
| `-a` re-price value | technical | pending - assumed: 160004 ms — median of green merge_group runs 42447940669/42442159415/42439386564 per the archived measurements |
| -b/-c stale prices (399378/326172 vs measured ~226s/~166s) in the same diff | technical | pending - assumed: out of scope — violates no ledger invariant; belongs to the #11679 umbrella sweep (brief scopes Item A to the -a row) |
| Whether a NEW `mutate` row is needed to prove any reshaped pin still kills | technical | pending - assumed: none needed — the existing 16 sites are the kill evidence; add one only if the work phase finds a survivor among them |

## Notes

- `wg-block-pr-ready-on-undeferred-operator-steps`: no operator-attached items — all rows above are technical and carry assumed defaults; none is money/scope/priority/schedule/irreversible/legal/brand class.
- Plan-review panel could not be spawned in this environment; mechanical findings were self-applied (sharp-edges pass: discoverability probe executed live, ACs are post-condition checks, no `| head` truncation in verification greps, prescribed regen invocation dry-run-verified).
