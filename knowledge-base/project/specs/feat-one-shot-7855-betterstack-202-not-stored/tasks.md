# Tasks — fix(observability): HTTP 202 from Better Stack is not evidence of storage

Plan: `knowledge-base/project/plans/2026-09-04-fix-betterstack-202-is-not-storage-plan.md`
Issue: #7855 (`Closes #7855`). Threshold: `single-user incident` — CPO sign-off + `user-impact-reviewer`.

## Phase 0 — Preconditions (no code)

- [x] 0.1 Re-run the three reads in the plan's "Measured discriminators" table; transcribe fixtures from the fresh responses, never compose them.
- [x] 0.2 Confirm `bs_absence_classify` still takes no arguments and returns 0/4/2, and that `scripts/zot-restart-loop-alarm.sh` is still its only production consumer.
- [x] 0.3 Re-read `ANCHOR_SQL` in the capture; confirm the foreign-host predicate is unchanged.
- [x] 0.4 Re-run the destination-pattern table against the current `scripts/betterstack-ingest-probe.sh`.

## Phase 1 — Capture control read (RED first)

- [x] 1.1 Write Guard 1's six mutation rows + three harness rows + the run-33888071954 fixture into `tests/scripts/test-git-data-rung2-evidence-capture.sh`. Confirm RED.
- [x] 1.2 Replace the `anchor_rc -ne 0` arm in `scripts/followthroughs/git-data-rung2-evidence-capture.sh`: source `scripts/lib/betterstack-absence.sh`, call `bs_absence_classify` with `BS_TABLE`/`BS_TABLE_S3` overridden to `t520508_soleur_inngest_vector_prd_3_logs` / `_s3`. Map `LIVE` / `INGEST_DARK` / `TRANSPORT_FAIL` to three sentences carrying the ClickHouse code as the reason. Keep the 0/1/2 (+64) contract; route through `transient()`.
- [x] 1.3 Record the honest limit in code: `INGEST_DARK` cannot separate a refusing warehouse from every control producer stopping at once.
- [x] 1.4 Add the `transient(` arm enumerator with a zero-arms floor in the shape `scripts/guard-vacuity-floor.test.sh` recognises: a bracket/arithmetic test with `-lt`/`-le`/`-ge` polarity against a counter the suite increments, reporting `printf >&2` + `exit 1` and NEVER through the suite's `fail()` helper.
- [x] 1.5 Give `.github/workflows/git-data-rung2-rehearsal.yml` three differentiated step-summary sentences.

## Phase 2 — Probe verdict contract and destination pin

- [x] 2.1 Rename the 2xx verdict token in `scripts/betterstack-ingest-probe.sh`; expand `detail=` to state what was not established; keep `--data-raw '[]'` and the no-payload prohibition; point at the round-trip follow-through.
- [x] 2.2 Fix the destination assertion: extract the authority (strip `https://`, cut at first `/`, defensively at `?`) and match `*.betterstackdata.com`. Keep `--proto '=https'`; no `-L`.
- [x] 2.3 Update `tests/scripts/test-betterstack-ingest-probe.sh`: renamed token, Guard 2 rows 1/3, Guard 3 row 3 + harness row (both real endpoints still accepted).
- [x] 2.4 Change no ingest-URL literal.

## Phase 3 — Round-trip follow-through

- [x] 3.1 Create `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` (one script, `set -euo pipefail`, `LC_ALL=C`).
- [x] 3.2 Marker payload carries **no `host_name` key**; refuse any source whose positive control the marker could satisfy.
- [x] 3.3 Map four verdicts onto the sweeper's THREE actions: `ROUNDTRIP_STORED`=0 (closes), `ROUNDTRIP_NOT_STORED`=1 (FAIL, stays open — the H5 decider), `ROUNDTRIP_DARK`=2 and `ROUNDTRIP_UNKNOWN`=3 (both TRANSIENT — the sweeper collapses all non-0/1 codes identically, so the stdout verdict token is what separates them). Record the asymmetry in the script header.
- [x] 3.3b Do NOT use `${VAR:?msg}` for required inputs (`scripts/lint-followthrough-varq-ban.sh` bans it — it exits 1, which the sweeper reads as FAIL). Use `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: <reason>" >&2; exit 2; fi`.
- [x] 3.4 Interim deadline = stated multiple of ADR-172's 17 s; below-floor non-observation degrades to `ROUNDTRIP_UNKNOWN`. Claim the AP-024 carve-out explicitly in the header.
- [x] 3.5 Create `tests/scripts/test-betterstack-roundtrip-latency.sh` with Guard 2 + Guard 3 matrices, argv-validating curl stubs.
- [x] 3.6 Register the suite in `scripts/test-all.sh` as `run_suite "<label>" bash tests/scripts/test-betterstack-roundtrip-latency.sh` — `scripts/lint-orphan-test-suites.sh` anchors on the COMMAND after `bash`, never the label. Regenerate the baseline in the same commit: `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`. Confirm `bash scripts/lint-orphan-test-suites.sh` passes.
- [x] 3.7 Add `BETTERSTACK_LOGS_TOKEN` (+ `GIT_DATA_BETTERSTACK_LOGS_TOKEN`) to `.github/workflows/scheduled-followthrough-sweeper.yml` `env:` — required, not conditional.
- [x] 3.8 File the follow-through tracker with the directive + `follow-through` label; the script records results in the tracker issue, never commits.
- [x] 3.9 Use the measured warehouse schema (`dt`, `raw` double-encoded, `_row_type=1`, `ingest_time`) for the readback; two-stage predicate (SQL `raw LIKE '%<MARKER>%'` prefilter, then `jq '.raw|fromjson|select(.message|startswith("<MARKER>"))'` field anchor per ADR-192 I-2); match presence of >=1 row, never an exact count. Record both wall-clock and `ingest_time - dt` latency. Note in the header that the `http`-platform table's schema is inferred, not verified.

## Phase 4 — ADR amendments

- [x] 4.1 Amend ADR-192: composed reading + what it does not prove; narrowed writing rule; permanent-table-creation consequence; cite the capture decision this reverses.
- [x] 4.2 Amend ADR-198 at its three occurrences; record the team-scoped-credential fact and the Sentry-correlation alternative. Leave the four cloud-init comments untouched.

## Phase 5 — Verification

- [ ] 5.1 Work through AC1–AC22 (pre-merge), recording the observed output for each.
- [x] 5.2 Confirm both scope-boundary ACs (AC13, AC14) return the expected values.
- [x] 5.3 Confirm `scripts/lint-diagnosis-claims.sh` passes and its `.highwater` has not moved.
- [ ] 5.4 Full battery at `/ship` Phase 4.
- [ ] 5.5 CPO sign-off + `user-impact-reviewer`.

## Verification log (Phase 5.1) — observed output, not asserted

| AC | Command | Observed |
|---|---|---|
| 1 | `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` | `73 passed, 0 failed`, rc=0 |
| 2,3 | Guard 1 battery, 7 rows one at a time | control GREEN; rows 1-7 all caught (rc=1); restore check clean |
| 4 | run-33888071954 fixture arm | one dark-warehouse sentence naming #7811; zero `unreachable or unauthorised` |
| 5 | `grep -rlE 'emit[[:space:]]+"INGEST_ACCEPTING"' scripts/ .github/` | 0 emit sites (the token survives only in comments explaining why it was wrong) |
| 6 | `grep -c -- "--data-raw '[]'" scripts/betterstack-ingest-probe.sh` | 1 |
| 7,8 | `bash tests/scripts/test-betterstack-ingest-probe.sh` | `cases=27 passed=28 failed=0`, rc=0 (main: 15 cases) |
| 9 | `bash tests/scripts/test-betterstack-roundtrip-latency.sh` | `22 passed, 0 failed (20 cases)`, rc=0 |
| 10 | GUARD1/H3b arm | a row with no `host_name` does not read as foreign-host liveness |
| 11 | orphan detector + baseline regen | `397 covered, 0 orphaned`; baseline unchanged (no new fixture-relative asserts) |
| 12 | sweeper `env:` | `BETTERSTACK_LOGS_TOKEN` + `GIT_DATA_BETTERSTACK_LOGS_TOKEN` present |
| 13 | ingest-URL literals vs merge-base | the probe's default at line 34 is untouched; only the *pattern* and comments changed |
| 14 | scope-boundary file grep | 0 |
| 15 | birth-readiness-gate / absence-classifier | `80 passed, 0 failed` / `cases=14 passed=15 failed=0` |
| 16 | `scripts/lint-diagnosis-claims.sh` | OK, 1 unmeasured claim (baseline 1) — `.highwater` not modified |
| 18 | `python3 scripts/lint-guard-contract.py` | scanned 1550 plans, 10 with a Guard Contract, 24 entries |
| 21 | `bash scripts/check-adr-ordinals.sh` | passes; no new ordinal claimed |

Tracker filed as **#7867** (`follow-through` label). Validated by running the sweeper's OWN
`parse_directive` awk against the live issue body rather than eyeballing the HTML comment: all
three fields resolve (`script`, `earliest`, `secrets`) and the script path is executable.

Still open: 5.4 (full battery at `/ship` Phase 4), 5.5 (CPO + user-impact-reviewer).
