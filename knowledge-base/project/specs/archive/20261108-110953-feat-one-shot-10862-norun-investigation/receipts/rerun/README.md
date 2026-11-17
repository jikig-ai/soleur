# Criterion-a evidence re-run — 2026-11-08

Authorized by the budget-owner go-ahead on #10862 (issue comment, 2026-11-07): the
`collect`/`ejections`/`aggregate`/`verdict` re-run on a fresh window. Criteria b, c
and d stayed `unmeasured` — the full go/no-go re-ruling is operator-reserved.

## Window

- Base: `origin/main` @ `f0c3bb86566231a41015e26ea91616b60356335c`, last 300
  first-parent commits.
- Ejection window: `2026-10-29T06:39:56Z..2026-11-08T04:43:01Z` (421 `merge_group`
  runs seen, 82 refused as units — see `ejections-window.json`).
- Commands + rc: `commands.txt`. Outputs: `replay-summary.txt` (full aggregate
  summary), `replay-summary.tsv` (per-unit), `histograms.txt` (`runs_via`, commit
  classes, ejection classes).

## Criterion-a result: FAIL (bound arm)

From `replay-summary.txt`, population `commits+ejections` (n=382):

- point: **0.52%** — under the ≤ 2% bar (passes)
- `cp95_upper_on_worst_case`: **19.10%** — over the < 12% bar (**fails**)

The failing arm is the worst-case bound, same arm as the original run (cp95
33.07%). `verdict --a fail --b unmeasured --c unmeasured --d unmeasured` printed
`computed=NO-GO reason=criterion-failed` (rc 0).

Against the prior window the bound tightened 33.07% → 19.10% and `no-run`
disappeared entirely: on this window every commit unit resolved through the
first `?head_sha=` read (`runs_via=head-sha`, 300/300 — see `histograms.txt`).
The index outage the cause receipt (H4) established was not present, so the new
corroboration path was not exercised by a live index drop here; it is exercised
by the suite's stub fixtures (`ci-pr-affected-replay.test.sh`, rows a–f) and by
the three corroboration mutation kills. The residual worst-case load is 58
`not-evaluable` + 2 `unverified` ejection units, dominated by `unclassified-job:
rule-body-lint` (20) and `unsettled-jobs: test-webplat` (19) — different failure
classes than the dropped listings this issue was about.

## Collection-integrity note

The interrupted prior session had already launched the same Phase-4 commands
into the same prescribed `$OUT=/var/tmp/s4-rerun-10862` and its `ejections`
process (PID 3248087, started 07:04) was still alive when this session's run
began (~08:10) — two writers on one JSONL. Its collect chunks had already
written most commit units; this session's collect runs resumed per unit
(`read_done`) and overlapped at the file tails. Consequence: 6 byte-identical
adjacent duplicate rows across `units-commits-{1,3}-of-4.jsonl` and 10 across
`units-ejections.jsonl`. `aggregate` refused the duplicates as designed ("two
chunk layouts in one directory?"); the stale process was killed (the sole
remaining writer was this session's ejections, rc 0) and the byte-identical rows
were deduplicated before aggregate — 306 → 300 commit units, 92 → 82 ejection
units. Pre-dedup files retained locally under `/var/tmp/s4-rerun-10862/raw/`.

## Phase-5 verification results

- `python3 -I scripts/ci-pr-affected-replay.py ratchet` → `exit=0 reason=pass
  live=0 baseline=0 accept=3165` on branch tip (after the accept row was folded
  into the commit that introduced the `CI_WORKFLOW_PATH` literal it covers —
  the ratchet judges HEAD^1..HEAD, so a standalone accept-row commit read as
  `accept-unattributed`).
- Live smoke: `collect --commits 2 --chunk 1/1 --base origin/main` resolved both
  units `clean` with `runs_via=head-sha` set (rc 0) — the live `gh` seam works
  end to end.
- `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` → 1122 passed,
  0 failed, 479/479 mutants killed.
