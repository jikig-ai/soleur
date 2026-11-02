# Local `test-all.sh` parallel mode (#8231)

## When to use which

| Situation | Use |
|---|---|
| Everyday pre-commit / local affected run | Nothing — the default serial path runs `--affected` scoped to your diff. |
| A long local `--full` or big affected run on a developer workstation with headroom | `SOLEUR_TEST_JOBS=auto bash scripts/test-all.sh --full` (or `--jobs=N`). |
| CI | Never — CI already parallelizes by shard (`SCRIPTS_SHARD`, `test-scripts N/8`). The `CI` env var forces the serial fallback; a local-style pool inside a shard would oversubscribe the runner. |
| Sharing the host with heavy work, or an unexplained flake you suspect is scheduling | `SOLEUR_TEST_JOBS=1` (or just unset it) — the serial fallback is always one knob away. |

## What parallel mode guarantees

- The suite set comes from the **same** `run_suite` registrations — no second list.
- Per-suite exit codes, `[FAIL]`/`[KILLED]`/`[ok]`/`[skip]` lines, per-suite log files, durable-log retention, `TEST_TIMING_LOG` rows, and the `=== N/M suites passed ===` epilogue are produced by the same code as serial mode — just ordered after a drain.
- Concurrency is capped from **measured** host capacity: `min(nproc, MemAvailable/512MB, 8)`, clamped further if you ask for more.
- Shared-resource suites serialize by resource token (`scripts/lib/test-suite-lanes.sh`); a `*` suite gets a drained pool.
- A run goes wide **only while holding the repo-global advisory lock** — cross-worktree serialization is never weakened.

## Serial fallback — every way to get it

1. `SOLEUR_TEST_JOBS=1` / `--jobs=1` — explicit serial.
2. Unset the knob — serial is the default while the #7376 interference diagnosis is open.
3. Requested-but-denied conditions degrade automatically with a named banner (`[parallel] serial fallback — reason=...`): `CI` set, bash < 5.1, lane table missing, advisory lock not held, resolved width 1, or an unwritable capture dir.

## Tuning

- `SOLEUR_TEST_SUITE_MEM_MB` — per-suite memory budget for the width formula (default 512).
- `SOLEUR_TEST_JOBS_CAP` — absolute worker ceiling (default 8).

## Reading the output

- `[parallel] mode engaged — width=N (...)` — one banner at resolution.
- `[run] <label> started/done (rc=N)` on stderr — in-flight liveness.
- `--- <label> ---` + verdict lines print in **registration order** after the pool drains — the report looks like a serial run's tail.
- `[UNACCOUNTED] <label>` — a dispatched suite that was never measured (e.g. an interrupted pool); the run exits 1 and the suite is never silently counted.
- `tmp_delta=unattributed` in the timing log — the suite shared its window with a sibling; a suite that ran alone keeps its numeric delta.

## Evidence

`knowledge-base/project/plans/2026-10-27-fix-8231-parallel-testall-plan.md` records the design, the lane classifications with reasons, and the benchmark numbers. `scripts/test-all-parallel-benchmark.test.sh` reproduces a measurement on demand.

## Committed-weight anti-regrow guards (#11662, ADR-312)

Four committed-weight guards keep the battery from silently regrowing:

- **Regen drift gate** — `python3 scripts/regenerate-shard-manifest.py --incremental --write`
  refuses (exit 2) when a `src=measured` row grows >1.5x AND >10s, or total
  measured weight grows >10% vs merge-base. Re-run with `--allow-growth` to
  acknowledge; the ack is recorded as a `# growth-acked=<digest>` stamp scoped
  to that violation set — a different violation set needs its own ack.
- **Corpus budget** — every committed weight <=600s or exempted in
  `scripts/suite-weight-exemptions.tsv` (reason must cite a #NNN; cap <=~1.3x
  current weight; a row whose suite fits the default cap reds).
- **Always-on ledger** — every `ALWAYS_ON_SUITES` member needs a row in
  `scripts/always-on-justifications.tsv`; non-live membership is capped at
  `NON_LIVE_CAP=95` in `scripts/always-on-ledger.test.sh` (raise it as a
  deliberate ack-edit, never a `_MIN_ALWAYS_ON_DECLARED` bump — that floor is
  the f1 pin-vs-list band, a different property).
- **Dead-registration census** — `lint-orphan-test-suites.sh` surface 7 reds a
  `run_suite` whose argv target no longer exists.

New suites get floor rows via `--incremental` (G1 reports count growth on
the landing commit — floor rows are excluded from the drift predicates).
`suite-durations*.tsv` and `suite-shard-legs.tsv` are generated artifacts —
hand-edits are an accepted v1 hole ADR-312 names, rate-limited not prevented.
