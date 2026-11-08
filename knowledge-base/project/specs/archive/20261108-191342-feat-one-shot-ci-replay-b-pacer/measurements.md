# Measurements — feat-one-shot-ci-replay-b-pacer

Work-phase readings on the branch (local host, 2026-11-08). The pre-change
per-site figures are the plan's `/var/tmp/m12015/table.tsv` reading on tree
`f0c3bb8656`; post-change figures are this session's `--rows` walls, which
include the ~74 s unconditional head plus the pristine-run cache on the
first site of the row — they are span walls, not per-site seconds.

## Arm -b targeted spans (pre-#12412 ordinals)

| span | sites | pre-change gated site seconds | post-change span wall | verdict |
|------|-------|-------------------------------|------------------------|---------|
| 215–223 | 9 (per-length + 4 per-start C-call + 4 probe) | ~87 s incl. 219=47.3, 217=16.8, 218=15.4, 216=7.3 | 112 s (9/9 killed, 645 assertions) | ~>50% drop on the gated share |
| 175–178 | 4 (call-less class) | 175=12.5 + 3 | 88 s (all killed) | green |
| 224–227 | 4 (row_sym incl. read-opens-blocking) | 225=30.2 | 99 s (all killed; hang now bounded at 10 s not 30) | ~20 s/site saved on 225 |
| 85–89 | 5 (arm -a row_scan_ops) | — | 114 s (all killed) | green |
| 157 | 1 (start-regex-flat-alternation) | — | 88 s (killed) | green |

## Full arm -b (`--rows 159-316`)

- Post-change local wall: **177 s**, 794 assertions (FLOOR 1112 − 476 + 158
  = 794 consistent), **158/158 mutants killed**, 0 survived.
- `ctl-ops-traceback` still `crashed` (runs ungated in every span).
- Pre-change references: merge_group median ~226 s, gated site seconds
  188.6 (row_scan_ops 105.0, row_sym 35.4).

## Reshape effect on the four instrument legs (pristine)

- `row_scan_ops` pristine wall: ~4.8 s → ~3.3 s (RATIOS paths=0.20
  width=0.79 lengths=1.01 text=0.78 — all far under the 3x bounds).
- Text axis now 49152→786432 bytes (exact 16x window; small-leg pristine
  ~3.1 ms ≈ 3x FLOOR — measured blob() timings: 16384=1.03 ms too close to
  FLOOR, 32768=2.07, 49152≈3.1 chosen).
- Per-start C-call mutants at the text axis, post-change single-scan cost
  (killed): encode 6.2x, count 11.2x, re.search 10.3x, replace 14.1x
  per-byte over the 3x bound — all condemned, the dearest (replace) at
  ~8.5 s vs ~30 s at 1 MB.
- Line-event cap `40*len+20000` → `16*len+5000`: the ruled `12*len+5000`
  was measured WRONG at work time — pristine `hb` emits 485,001 events at
  40,000 bytes (12.125/byte), one event over the cap; 16*len+5000 is 2x
  the asserted bound and ~1.3x hb's pristine rate.
- `row_sym` `REPLAY_SUT_TIMEOUT=10`: the read-opens-blocking hang dies at
  10 s (pristine audit ~1 s); all other callers keep 30.
- Harness row added: stub-`timeout` argv log proves default/fallback =
  `30` and override `2` reaches argv, plus a real 2 s hang → rc 124; a
  declared-setter sweep pins every `REPLAY_SUT_TIMEOUT=` site.
- FLOOR_ASSERTIONS 1110 → 1112 (+2 unconditional rows); DECLARED_TOTAL 476
  unchanged; `grep -c '^mutate '` = 476.

## Item A ledger

- `scripts/suite-durations.tsv`: replay-a 1033094 → **160004** (`measured`)
  with a provenance comment naming runs 42447940669/42442159415/42439386564.
- `scripts/suite-weight-exemptions.tsv`: `-a` row (cap 1343022) deleted;
  `test-all-corpus-weight-budget.test.sh` green (14/14).
- `regenerate-shard-manifest.py --incremental --durations --write`: diff
  limited to the -a row + legs.tsv header stamps (generated-at,
  default-weight-ms 1261→1272); surgical fallback not needed.
- `scripts-shard-manifest.test.sh` green (50/50).

## Post-merge arm medians note

The committed `-a` price and the reshape target the next merge_group
reading: expected arm medians ≈ -a ~160 s (unchanged — already measured),
-b ~180-190 s wall on the merge-group host (local arm-b gated work dropped
~60-70 s), -c unchanged. Verify against the suite-timings artifact on the
first post-merge `merge_group` run; `-b`/`-c` committed prices stay stale
by design (#11679 umbrella owns that sweep).
