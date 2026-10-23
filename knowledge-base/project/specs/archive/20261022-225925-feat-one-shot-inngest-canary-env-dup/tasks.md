# Tasks: fix Inngest TLS canary inspect failure (duplicated env entry, no cause)

Plan: `knowledge-base/project/plans/2026-10-22-fix-inngest-canary-inspect-duplicate-env-plan.md`
Issue: #10136 (epic #10205, ADR-294). Stop before merge: no merge, no auto-merge, no workflow dispatch, no Doppler or production write, no SSH.
Run every suite one at a time with stdin from `/dev/null`.

## Phase 1: RED first

- 1.1 ci-deploy.test.sh: make the `apparmor-trace` mock env-file-aware (per-run `${MOCK_IL_RUN_LOG}.eff<N>`, `inspect` prints the canary's file then `MOCK_IL_INSPECT_EXTRA`, `MOCK_IL_INSPECT_FAIL`)
- 1.2 ci-deploy.test.sh: `IL_SNAP_EXTRA`, clear `.eff*` in `il_deploy`, the `.scrub.`-keyed `mktemp` shim in `create_base_mocks`, `il_effective_clean`
- 1.3 ci-deploy.test.sh: rows T1 (flag on and off, sentinel assertion), T3, T5, T6, T8a, T8b
- 1.4 inngest-link-resolver.test.sh: stub modes `duphttp dupca badca empty many`; E3 and E7 exact lines per mode, anchored-regex row, reason assertions
- 1.5 inngest-link-resolver.test.sh: scrub rows L1 to L6, wiring row L7 (unique anchor, count 1)
- 1.6 inngest-link-resolver.test.sh: update ANCH_B1..B3 and their `kill_mut` rows, add the Guard Contract `kill_mut` rows, `ROW_IDS`, `MIN_ROWS` exact
- 1.7 Run both suites on unmodified ci-deploy.sh, one at a time; commit tests only as "test: red" with the FAIL lines in the commit message (required RED and NOT-red sets in the plan, Phase 1.5)

## Phase 2: the fix

- 2.1 ci-deploy.sh resolver block: regex constant and `inngest_link_scrub_env_file` (`LC_ALL=C grep -a`, `mktemp "$1.scrub.XXXXXX"` in `_gak_tmp`, conservation, recount on the temp file, then `mv -f`, byte-identical on every failure)
- 2.2 ci-deploy.sh deploy site: call after the resolver handling, strict abort with `inngest_env_scrub_failed`, non-strict event and continue
- 2.3 ci-deploy.sh `inngest_link_canary_check`: `irc`, ordered cause evaluation, extended event, reason split, header comment
- 2.4 Run the resolver suite, ci-deploy.test.sh, docker-run-tuple.test.sh, docker-run-tuple.py, lint-trap-tempfile-ownership.py, guard-vacuity-floor.test.sh, c4-count-parity.test.sh, shellcheck

## Phase 3: docs, ADR, ratchet

- 3.1 canary-probe-set.md: grammar, decode per cause, reason literals, canary-only proof limit
- 3.2 inngest-server.md: `canary_failed` row, `env_scrubbed` and `env_scrub_failed` rows, per-host flip read, no-allowlist-change note; no SSH step
- 3.3 ADR-294 addendum `## Addendum (2026-10-22, #10136 canary inspect)`
- 3.4 preflight-discoverability-test.test.ts: raise `BASELINE_DECLARED_PROBES` to the live value plus one with its comment entry; run the suite

## Phase 4: real-Docker confirmation (local only)

- 4.1 `docker create` with and without the scrubbed file (and a padded-name line), record the entry counts for the PR description

## Phase 5: review, QA, CI, stop

- 5.1 `soleur:review`, `soleur:qa`, green CI
- 5.2 `soleur:ship` to the merge gate; PR body with the proof limits and the second-flip target date (no later than 2026-11-05, on #10205)
- 5.3 End with a `Paused:` line asking for a typed go that names the merge
