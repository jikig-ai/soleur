# Tasks — fix(observability): HTTP 202 from Better Stack is not evidence of storage

Plan: `knowledge-base/project/plans/2026-09-04-fix-betterstack-202-is-not-storage-plan.md`
Issue: #7855 (`Closes #7855`). Threshold: `single-user incident` — CPO sign-off + `user-impact-reviewer`.

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Re-run the three reads in the plan's "Measured discriminators" table; transcribe fixtures from the fresh responses, never compose them.
- [ ] 0.2 Confirm `bs_absence_classify` still takes no arguments and returns 0/4/2, and that `scripts/zot-restart-loop-alarm.sh` is still its only production consumer.
- [ ] 0.3 Re-read `ANCHOR_SQL` in the capture; confirm the foreign-host predicate is unchanged.
- [ ] 0.4 Re-run the destination-pattern table against the current `scripts/betterstack-ingest-probe.sh`.

## Phase 1 — Capture control read (RED first)

- [ ] 1.1 Write Guard 1's six mutation rows + three harness rows + the run-33888071954 fixture into `tests/scripts/test-git-data-rung2-evidence-capture.sh`. Confirm RED.
- [ ] 1.2 Replace the `anchor_rc -ne 0` arm in `scripts/followthroughs/git-data-rung2-evidence-capture.sh`: source `scripts/lib/betterstack-absence.sh`, call `bs_absence_classify` with `BS_TABLE`/`BS_TABLE_S3` overridden to `t520508_soleur_inngest_vector_prd_3_logs` / `_s3`. Map `LIVE` / `INGEST_DARK` / `TRANSPORT_FAIL` to three sentences carrying the ClickHouse code as the reason. Keep the 0/1/2 (+64) contract; route through `transient()`.
- [ ] 1.3 Record the honest limit in code: `INGEST_DARK` cannot separate a refusing warehouse from every control producer stopping at once.
- [ ] 1.4 Add the `transient(` arm enumerator with a zero-arms floor reporting via `printf >&2` + `exit 1`, in the shape `scripts/guard-vacuity-floor.test.sh` derives.
- [ ] 1.5 Give `.github/workflows/git-data-rung2-rehearsal.yml` three differentiated step-summary sentences.

## Phase 2 — Probe verdict contract and destination pin

- [ ] 2.1 Rename the 2xx verdict token in `scripts/betterstack-ingest-probe.sh`; expand `detail=` to state what was not established; keep `--data-raw '[]'` and the no-payload prohibition; point at the round-trip follow-through.
- [ ] 2.2 Fix the destination assertion: extract the authority (strip `https://`, cut at first `/`, defensively at `?`) and match `*.betterstackdata.com`. Keep `--proto '=https'`; no `-L`.
- [ ] 2.3 Update `tests/scripts/test-betterstack-ingest-probe.sh`: renamed token, Guard 2 rows 1/3, Guard 3 row 3 + harness row (both real endpoints still accepted).
- [ ] 2.4 Change no ingest-URL literal.

## Phase 3 — Round-trip follow-through

- [ ] 3.1 Create `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` (one script, `set -euo pipefail`, `LC_ALL=C`).
- [ ] 3.2 Marker payload carries **no `host_name` key**; refuse any source whose positive control the marker could satisfy.
- [ ] 3.3 Distinct exit codes for `ROUNDTRIP_STORED` / `ROUNDTRIP_NOT_STORED` / `ROUNDTRIP_DARK` / `ROUNDTRIP_UNKNOWN`.
- [ ] 3.4 Interim deadline = stated multiple of ADR-172's 17 s; below-floor non-observation degrades to `ROUNDTRIP_UNKNOWN`. Claim the AP-024 carve-out explicitly in the header.
- [ ] 3.5 Create `tests/scripts/test-betterstack-roundtrip-latency.sh` with Guard 2 + Guard 3 matrices, argv-validating curl stubs.
- [ ] 3.6 Register the suite in `scripts/test-all.sh`; regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt` in the same commit.
- [ ] 3.7 Add `BETTERSTACK_LOGS_TOKEN` (+ `GIT_DATA_BETTERSTACK_LOGS_TOKEN`) to `.github/workflows/scheduled-followthrough-sweeper.yml` `env:` — required, not conditional.
- [ ] 3.8 File the follow-through tracker with the directive + `follow-through` label; the script records results in the tracker issue, never commits.
- [ ] 3.9 Record the blind-predicate risk in the script header.

## Phase 4 — ADR amendments

- [ ] 4.1 Amend ADR-192: composed reading + what it does not prove; narrowed writing rule; permanent-table-creation consequence; cite the capture decision this reverses.
- [ ] 4.2 Amend ADR-198 at its three occurrences; record the team-scoped-credential fact and the Sentry-correlation alternative. Leave the four cloud-init comments untouched.

## Phase 5 — Verification

- [ ] 5.1 Work through AC1–AC22 (pre-merge), recording the observed output for each.
- [ ] 5.2 Confirm both scope-boundary ACs (AC13, AC14) return the expected values.
- [ ] 5.3 Confirm `scripts/lint-diagnosis-claims.sh` passes and its `.highwater` has not moved.
- [ ] 5.4 Full battery at `/ship` Phase 4.
- [ ] 5.5 CPO sign-off + `user-impact-reviewer`.
