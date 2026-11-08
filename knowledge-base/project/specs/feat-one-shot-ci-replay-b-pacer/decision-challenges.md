# Decision Challenges — feat-one-shot-ci-replay-b-pacer

Headless planning session (no Task/spawn tool in this environment): technical
rows are recorded `Ruled by CTO agent, 2026-11-08: adopt per-scan `give_up` inside `cpu()` + cheapest-condemner leg ordering + early `if bad` exits - give_up fires only between rep-blocks (:1048-1055), condemned mutants pay entire legs; corpus shrink barred by #10404 survivor record; rep cuts buy ~1.4s only. Binding: the give_up abort must return an over-bound value, never a pass
contract — a spawned CTO ruling may replace any of them before work commits to
the alternative.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Item B primary lever for `row_scan_ops` site cost: per-scan `give_up` inside `cpu()` + cheapest-condemner leg ordering + early `if bad` exits (vs. corpus shrink vs. rep cuts vs. moving property to another arm) | technical |  Ruled by CTO agent, 2026-11-08: adopt per-scan `give_up` inside `cpu()` + cheapest-condemner leg ordering + early `if bad` exits - give_up fires only between rep-blocks (:1048-1055), condemned mutants pay entire legs; corpus shrink barred by #10404 survivor record; rep cuts buy ~1.4s only. Binding: the give_up abort must return an over-bound value, never a pass |
| Text-axis fixture sizes: 64KB→1MB replaced by ~16KB→~256KB (same ~16x window, detection band preserved, ~1/16 mutant cost) vs. keeping 1MB | technical |  Ruled by CTO agent, 2026-11-08: replace 64KB->1MB with ~16KB->~256KB, preserving the ~16x window - per-byte-ratio assertion unchanged at ~1/16 mutant cost; invariant: small-leg pristine stays >= a few ms above FLOOR, sizes tuned at work time |
| Line-event cap `40*len+20000` tightening (bounds the cap-burn class, site 175 = 12.5s) | technical |  Ruled by CTO agent, 2026-11-08: tighten the cap to ~`12*len+5000` - cap only bounds runaway mutants under settrace; asserted bound is `ev <= 8*len`; 12*len+5000 stays ~1.5x above it, pristine (~<=2*len) never approaches either |
| `row_sym` per-invocation timeout mechanism + value (`REPLAY_SUT_TIMEOUT` override in run_sut:249, unset default 30s) | technical |  Ruled by CTO agent, 2026-11-08: parameterize run_sut's bound via `REPLAY_SUT_TIMEOUT` (default 30) and set 10 inside row_sym - env-knob precedent exists (:2458/:2487); row_sym is a subshell so scoping is free; invalid/empty values fall back to 30, the bound can never be disabled |
| Site 350 `row_rt_big_baseline` (31.2s, arm -c): reduce vs. leave | technical |  Ruled by CTO agent, 2026-11-08: leave `row_rt_big_baseline` unchanged - 60000-line quadratic survivor recorded in-code (:2499), pristine budget assert <25s, the 30s bound can't shrink below ~28s for ~3s gain against real flake risk |
| Item A write mechanism: `--incremental --durations` regen for provenance-honest headers vs. surgical two-line edit | technical |  Ruled by CTO agent, 2026-11-08: use `regenerate-shard-manifest.py --incremental --durations --write`, surgical edit as fallback on unrelated churn - generated-file header demands a real pass; stated fallback bounds the risk |
| `-a` re-price value | technical |  Ruled by CTO agent, 2026-11-08: re-price -a to 160004ms - median of green merge_group runs 42447940669/42442159415/42439386564 (160004/160670/156007); keep `measured` tag with provenance comment naming the run ids |
| -b/-c stale prices (399378/326172 vs measured ~226s/~166s) in the same diff | technical |  Ruled by CTO agent, 2026-11-08: keep -b/-c re-pricing out of scope - stale but violates no ledger invariant (only -a holds an exemption row); the #11679 umbrella owns the sweep |
| Whether a NEW `mutate` row is needed to prove any reshaped pin still kills | technical |  Ruled by CTO agent, 2026-11-08: add no new `mutate` row - 19 existing sites name row_scan_ops plus row_sym/row_rt_big_baseline coverage and the ctl-ops-traceback control; add only if a survivor appears |

## Notes

- `wg-block-pr-ready-on-undeferred-operator-steps`: no operator-attached items — all rows above are technical and carry assumed defaults; none is money/scope/priority/schedule/irreversible/legal/brand class.
- Plan-review panel could not be spawned in this environment; mechanical findings were self-applied (sharp-edges pass: discoverability probe executed live, ACs are post-condition checks, no `| head` truncation in verification greps, prescribed regen invocation dry-run-verified).
