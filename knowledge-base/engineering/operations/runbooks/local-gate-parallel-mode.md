# Local `test-all.sh` parallel mode (#8231)

## When to use which

| Situation | Use |
|---|---|
| `soleur:ship` / `soleur:work` affected gate (`plugins/soleur/scripts/affected-tests.sh`, local) | Nothing — since #12013 the gate hands the runner `SOLEUR_TEST_JOBS=4` itself (not for `--full`, not under `CI`, never over a width you set). A bare `bash scripts/test-all.sh` is still serial. |
| A long local `--full` or big affected run on a developer workstation with headroom | `SOLEUR_TEST_JOBS=auto bash scripts/test-all.sh --full` (or `--jobs=N`). |
| CI | Never — CI already parallelizes by shard (`SCRIPTS_SHARD`, `test-scripts N/8`). The `CI` env var forces the serial fallback; a local-style pool inside a shard would oversubscribe the runner. |
| Sharing the host with heavy work, or an unexplained flake you suspect is scheduling | `SOLEUR_TEST_JOBS=1` (or just unset it) — the serial fallback is always one knob away. |

## What parallel mode guarantees

- The suite set comes from the **same** `run_suite` registrations — no second list.
- Per-suite exit codes, `[FAIL]`/`[KILLED]`/`[ok]`/`[skip]` lines, per-suite log files, durable-log retention, `TEST_TIMING_LOG` rows, and the `=== N/M suites passed ===` epilogue are produced by the same code as serial mode — just ordered after a drain.
- Concurrency is capped from **measured** host capacity: `min(nproc, MemAvailable/512MB, 8)`, clamped further if you ask for more.
- Shared-resource suites serialize by resource token (`scripts/lib/test-suite-lanes.sh`); a `*` suite gets a drained pool.
- Launch order is a conservative **backfill** (#12013): a suite blocked on a token no longer idles free slots; a later suite launches only if it conflicts with no live suite and with nothing still queued ahead of it, so suites that share a token keep registration order and a queued `*` still blocks everything after it. `SOLEUR_PJ_FIFO=1` restores the previous strict FIFO (the A/B control of a timing measurement; not a tuning knob). Finished workers are reaped only when the pool saturates or at drain, so a stale token holder can delay later suites until then (known limit, tracked under #12013).
- A run goes wide **only while holding the repo-global advisory lock** — cross-worktree serialization is never weakened.

## Serial fallback — every way to get it

1. `SOLEUR_TEST_JOBS=1` / `--jobs=1` — explicit serial.
2. Unset the knob when calling the runner directly — the runner's own default stays serial (the #7376 interference diagnosis closed 2026-10-20; flipping the runner default is a separate decision with no tracker yet, so it stays serial). The affected gate in `affected-tests.sh` supplies width 4 itself; to opt that out, set `SOLEUR_TEST_JOBS=1` (an operator `--jobs` flag cannot reach the runner through that script).
3. Requested-but-denied conditions degrade automatically with a named banner (`[parallel] serial fallback — reason=...`): `CI` set, bash < 5.1, lane table missing, advisory lock not held, resolved width 1, or an unwritable capture dir.

## Tuning

- `SOLEUR_TEST_SUITE_MEM_MB` — per-suite memory budget for the width formula (default 512).
- `SOLEUR_TEST_JOBS_CAP` — absolute worker ceiling (default 8).

## Reading the output

- `[parallel] mode engaged — width=N (...)` — one banner at resolution.
- `[run] <label> started/done (rc=N, <ms>ms)` on stderr — in-flight liveness (#12013). A non-zero rc carries a `provisional, verdict at drain` marker (a 128+n rc: `signal-shaped, unresolved until drain`). It is not the verdict: the `[FAIL]`/`[KILLED]` lines and the exit code after the drain are. A poller should grep the log for `^\[run\] .* done \(rc=[1-9]` to see a red the moment it happens.
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
