# Decision Challenges — feat-one-shot-11647-rows-arm-debt

Planning pass for issue #11647 (epic #11556, mandated-by #11562). Rows below
are the design decisions needing a technical ruling; the Recommendation
column is the planning agent's proposed default, to be confirmed or
overturned by the ruling seat before `soleur:work`.

## Decision Classes

| # | Item | Class | Recommendation | Ruling |
|---|---|---|---|---|
| 1 | Enum spelling: `est` (issue title + AC "src=est or equivalent") vs `estimate` (issue body's `{measured, floor, estimate}` enum and the spelled-out house style `measured`/`floor`) | technical | `estimate` — the issue body is the binding text; `est` reads as shorthand | AGREE |
| 2 | Item-1 premise staleness: all **9** `-<letter>` arm rows (issue says 7) were re-priced to real medians in `fe6963786f` (#11718) — land the enum as mechanism only and restamp nothing, vs restamp the 9 rows `estimate` anyway | technical | enum as mechanism + runbook seeding rule; restamping real measurements would mislabel them — the inverse laundering | AGREE |
| 3 | Repeat-`--rows` semantics: normalize all four batteries to refuse (`exit 2`), vs preserve totality-mutations' last-wins behind a `ROWS_REPEAT=allow` knob | technical | normalize to refuse — last-wins is the unhardened original, not a deliberate variant: lint-orphan's comment (:82-83) names the exact coverage-hole it guards ("the tiling extractor would then assert a coverage the battery ignores"); issue's "ordinal enforcement optional arg" is the only sanctioned knob | AGREE |
| 4 | `rows_parse_args` signature: `rows_parse_args "$@"` reading the caller's file-scope `DECLARED_TOTAL` + optional `ROWS_UNIT`/`ROWS_REPEAT` env, vs explicit `rows_parse_args <total> [unit] -- "$@"` | technical | env-read — `DECLARED_TOTAL` must stay declared in each battery file anyway (totality guard `_DECL_READ_RE`, `DECL-PREFIX-READER` verbatim anchor), so a positional total is redundant; the lib must never spell `DECLARED_TOTAL=` (Direction-2 census) | AGREE |
| 5 | Counter-name unification: lib owns `_site_seq`/`EXECUTED`/`ROWS_LO`/`ROWS_HI`; totality-mutations renames `_row_seq`→`_site_seq` at :1016-1026 | technical | rename — `_site_seq` is the 3-of-4 spelling; end-gate references are the only touch points | AGREE — residual `_row_seq` refs are :1016-1017 after the def retires |
| 6 | `rows_parse_args` bounds-check placement: post-loop gated on `_seen_rows_flag` (B/C/D shape) vs totality-mutations' inline-in-case-arm (A shape) | technical | post-loop — semantically equivalent (the flag value is stored either way) and is the 3-of-4 shape | AGREE |
| 7 | `read_durations` return shape for item 1: 3-tuple `(weights, floor_labels, est_labels)` vs returning a per-label src map | technical | 3-tuple — minimal diff over the current 2-tuple; the single call site (:1142) builds `src_map` so `estimate` provenance survives `--durations` round-trips | AGREE |
| 8 | `estimate` rows in `drift_report_group`: join the `floor_labels` population for `DRIFT_ROW`/`FLOOR_UNMEASURED` vs a distinct row class | technical | join — an estimate that finally measures IS the drift event the probe exists to name; rename the emitted label to cover both src classes or keep `FLOOR_UNMEASURED` counting non-measured rows | AGREE — join the floor population, but the emitted `FLOOR_UNMEASURED` token stays LITERAL (`watch-shard-balance-11564.sh:138,196` parses it); docstring/runbook wording only |
| 9 | `estimate` in `drift_violations`: excluded from per-suite measured comparison; `estimate→measured` and `measured→estimate` emit named note lines (mirroring `floor→measured`); a new measured row over an est baseline counts toward total growth | technical | as stated — consistent with `floor→measured` treatment (:503-505); NOT gated in v1 | AGREE |
| 10 | Per-block floor map format for `test-all-affected`: central `ROWS_BLOCK_CASES` ordinal-indexed array beside `DECLARED_TOTAL` (comment maps ordinals to block letters) vs per-block declarations inside each `if in_range` block (lint-orphan `EXPECTED_ASSERTIONS` style, 38 edited sites) — and `>=` floors vs `==` equality | technical | central array + `>=` — several blocks emit loop-driven variable counts (header :332 "for-loops (q8/th census rows) stay inside their block"); equality false-fires on legitimate case growth | AGREE |
| 11 | totality-mutations end-gate `FAIL:` + `exit 1` at :1017-1034 — normalize to `FATAL:` + `exit 2` (they are shape-accounting aborts), vs leave since the issue names only lint-orphan + replay | technical | normalize — the doctrine is process-level (shape → 2, verdicts → 1); leaving it keeps the same inconsistency the item exists to close | AGREE |
| 12 | New `scripts/lib/rows-range.test.sh` unit suite (auto-globbed by `SUITE_GLOBS` :108) vs no dedicated suite — the four batteries already exercise the lib on every arm | technical | add it — cheap parse-edge coverage (repeat/bounds/ordinal/floor) the arm invocations can't reach; cost: `--incremental --write` TSV rows, possible PRODUCER_JOIN/fixture-assert/ratchet entries | AGREE — tasks 6.1 must pin the two census constraints: no literal `--rows <digits>-<digits>` outside `#`-comments (Direction-1 enumerates `scripts/lib`), no line-start `DECLARED_TOTAL=` spelling (Direction-2 is repo-wide) |
| 13 | `rows_gate_floor` scope: subsume `_site_seq == DECLARED_TOTAL` + `EXECUTED == expected` for all four batteries (extras stay battery-side) vs floor-only and batteries keep their own checks | technical | subsume — it is the third lib export the issue names; battery extras (conservation, census, OW floors, MIN_CASES) remain after it | AGREE |
| 14 | ADR placement + number: new `ADR-313` (next free ordinal — ADR-312 is top) in `knowledge-base/engineering/architecture/decisions/` + checklist into the sharding runbook vs `test-relevance-paths.sh` HOW-TO block | technical | ADR-313 + runbook — the convention is generator+guard load-bearing (ADR material), and the runbook already narrates every arm split; the HOW-TO block is relevance-gate-scoped | AGREE |
| 15 | Exit-code normalization as a "breaking change": any caller checking `rc == 1` vs `rc == 2` for these batteries | technical | not breaking — `suite_exit_class` (`test-all.sh:1539-1553`) collapses every nonzero rc to `failed`; no external rc-1-vs-2 branch found in tree; reviewer to re-verify | AGREE |
| 16 | `EXPECTED_BLOCK_CASES` values source: static `cases+=` counts per block vs measured typicals for loop-driven blocks | technical | static count where straight-line; structural minimum where loop-driven (declare the floor a hollow can't fake — `>=` not `==`) | AGREE |

| 17 | `floor_ms` in the `--durations` full-regen path: `measured = weights` (:1174) — post-S1, weights includes est labels — so `floor_ms = median(measured.values())` (:1207) would let estimates anchor the floor median, contradicting the stated invariant and the incremental path’s measured-only median (`read_durations_ms` :1025-1034) | technical | exclude `est_labels` from the floor-median population; empty measured set → `DEFAULT_SUITE_MS` + WARN (mirror :1026-1034); est labels still supply weight to packing and leg tallies | AGREE (added by ruling seat) Follow-up: plan S1 + tasks 1.2/1.3/1.7 must name :1207 and add a fixture case |

## Decisions that differ from what the issue text presumes

- **"7 arm rows" → 9, and all real measurements.** The issue's laundering
  example is stale post-#11718; the enum lands as mechanism with no restamp.
  (Row 2.)
- **"4 copies" confirmed but the third variant is three deltas, not one**:
  repeat-flag, ordinal, plus `_row_seq` naming/arg-style/bounds-placement —
  the plan catalogues each per battery verbatim with line anchors. (Rows 3, 5, 6.)
- **Item 4's gap is `test-all-affected` only** — lint-orphan already has
  `EXPECTED_ASSERTIONS` per-row floors, totality-mutations has
  `TOTAL == EXECUTED + 1`, replay has `MUT_RUN+OW_MUT_RUN == EXECUTED`. The
  lib's `rows_gate_floor` carries the floor machinery but only
  test-all-affected declares a block map. (Row 10.)
- **Even the "reference" battery isn't fully compliant**: test-all-affected's
  end gate exits 2 but its early FATALs (:92 missing-file ERROR, :109
  instrument self-test) exit 1 — the census covers all four batteries'
  process-level FATAL paths, not just the two the issue names. (Row 11
  companion.)
