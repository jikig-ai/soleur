# Tasks: name the failing phase in the Inngest `selfgate_failed` event (#10934)

Plan: `knowledge-base/project/plans/2026-10-23-fix-inngest-selfgate-name-failing-phase-plan.md`
Issue: #10934 (epic #10205, item #10136, ADR-294). Stop before merge: no merge, no auto-merge, no flip dispatch, no Doppler or production write or read, no SSH.
Run every suite one at a time with stdin from `/dev/null`. Measurement evidence: `knowledge-base/project/specs/feat-one-shot-inngest-selfgate-phase/curl-w-measurements.md`.

## Phase 0: the corpus ratchet the plan already moved (first work commit)

- 0.1 `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 76 to 77 (re-read the live value after rebasing) with a PLACEMENT / TRUTH / NO SUBSTITUTE comment entry; never skip with `LEFTHOOK_EXCLUDE`

## Phase 1: the honest doubles (tests only)

- 1.1 create `apps/web-platform/infra/test-fixtures/curl-w-profiles.sh`: profile table (values copied from the evidence file, no `num_connects` column), raw profiles (`raw_empty`, `raw_garbage`, `raw_short3`, `raw_nonnum`, `ok200_comma_extra`), one printer that interprets `-w` from argv, prints no trailing newline, and on an unknown variable or profile prints to stderr, exits 99 and drops a sentinel file
- 1.2 `inngest-link-resolver.test.sh`: rebuild `$BIN/curl` on the shared file, per-attempt `FX_CURL_PROFILES`, keep `FX_CURL_FAIL_FIRST` (now prints `verify18`), `FX_CURL_ALWAYS_OK`, `FX_CURL_CODE`, `-k` and fingerprint behaviour, Sentry POST passes through silently, sentinel asserted absent after every row
- 1.3 `ci-deploy.test.sh`: unified mock `*"8443/health"*` route on the shared file with `MOCK_IL_SELFGATE_PROFILE` (default `ok200`), sentinel assertion

## Phase 2: rows, mutation rows, real-curl differential (tests only), then RED

- 2.1 resolver suite rows S1 to S9 (whole-line assertions; profiles by phase; S3b same times with rc 52, 56, 1; S4 sequence and flapping fixture; S5 anchored grammar on journald and Sentry sinks; S6 unknown arms and validated values; S7 variable allowlist; S8 and S8b non-canonical input and success-before-validation; S9 decode drift), the TLS-complete-but-not-200 row asserting `phase=status`
- 2.2 resolver suite H6 (real function against real curl and local python `ssl` servers, six scenarios, compare rc class, code, zero-ness of connect and appconnect, verify; skip counted locally with `ROWS+=N; SKIP+=N`, failure under `CI`), H7 (printer fidelity and sentinel), H8 (profiles ignored goes RED), H1 extended
- 2.3 resolver suite `kill_mut` rows M22a to M22f, M22h, M22i, M22m to M22p; register rows in `ROW_IDS`
- 2.4 `ci-deploy.test.sh`: one end-to-end row (`MOCK_IL_SELFGATE_PROFILE=req_reset`: non-zero exit, reason `inngest_link_selfgate_failed`, no `docker run`, anchored event line with `phase=request tcp=3 tls=3 verify=0`)
- 2.5 run both suites on UNMODIFIED `ci-deploy.sh`: the new rows RED, every old row GREEN (exact counters excluded); the RED commit stays local, pushed with the fix; FAIL lines in the commit message

## Phase 3: the fix

- 3.1 `ci-deploy.sh` inside the `inngest-link-resolver` markers: `_inngest_link_selfgate_phase`, new `-w`, parse with the verdict first, validation with regex variables, `tcp` / `tls` counters, `verify` coercion, `http=` from a validated token, event with the appended fields, header comment
- 3.2 re-anchor M18a to M18e and M05c on the new text
- 3.3 resolver suite and `ci-deploy.test.sh` GREEN; `bash -n` and `shellcheck` clean

## Phase 4: docs

- 4.1 `inngest-server.md`: `selfgate_failed` row and the "Reading `selfgate_failed`" decode table (every field and token, retry column, flapping rule, `unknown` decode, `verify` reading rule, proof limits, no SSH step)
- 4.2 `deploy-status-debugging.md`: one row for `inngest_link_selfgate_failed`
- 4.3 ADR-294 `Addendum (2026-10-23, the second flip attempt)`: 8 lines at most, measured facts only

## Phase 5: ratchets (each re-measured from a green run)

- 5.1 `MIN_ROWS` (exact) in the resolver suite; `CI_DEPLOY_ASSERT_FLOOR` in `ci-deploy.test.sh`
- 5.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh` (regenerate only if it reds, only rows this diff earned)
- 5.3 `bash .claude/hooks/grep-q-pipe-guard.test.sh` (`PJ_TRIPLES` / `PRODUCER_JOIN` only if a triple appeared)
- 5.4 `bash scripts/pre-push-ratchet-lane.sh`, `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash scripts/lint-orphan-test-suites.sh`

## Phase 6: CI userland, review, QA, stop

- 6.1 both changed suites once inside `docker run --rm -v "$PWD":/w ubuntu:24.04` after `apt-get install -y curl python3 openssl jq shellcheck`, recording curl and bash versions
- 6.2 `soleur:review` (user-impact-reviewer, observability-coverage-reviewer, test-design-reviewer), `soleur:qa`, green CI via Monitor
- 6.3 `soleur:ship` to the merge gate; PR body names the proof limits and #10856; end with a `Paused:` line asking for a typed go that names the merge and stating the third-flip preconditions (parity green on web-1 and web-2; idle check immediately before the merge, abort lever `[skip-deploy-fix-apply]`)
