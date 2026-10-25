# Tasks: ship the Inngest TLS terminator's journald to Better Stack

Plan: `knowledge-base/project/plans/2026-10-25-feat-ship-terminator-journald-to-better-stack-plan.md`
Branch: `feat-one-shot-terminator-journald-shipping` (draft PR #10975). Issue refs: #10136, #10205, #10880 (Ref only).
Constraints in force: rebase onto `origin/main`, never merge main in; no git stash; one test suite at a time with stdin from `/dev/null`; nothing merged, armed or dispatched; no Doppler writes; production reads only through `scripts/betterstack-query.sh`; no SSH.

## Phase 0: preflight

- 0.1 Rebase onto `origin/main`; re-run the code-review overlap check on the final file list.
- 0.2 File the `user_data` trim issue (target at least 500 B offline; must merge before the replace go; CI-rendered margin at least 300 B).
- 0.3 File the `fetch_rc=93` issue (sequenced after the trim; states this journal will not explain it; not an acceptance gate).
- 0.4 Locate a Vector 0.43.1 binary or use `timberio/vector:0.43.1-alpine`; record how `vector test` is run locally.

## Phase 1: failing tests first

- 1.1 `apps/web-platform/test/infra/vector-admission.test.sh`: two-unit S1 and S2 pins; literal terminator corpus rows (PRIORITY 0, 3, 4, 5, 6); harness rows. Run alone; expect RED.
- 1.2 `apps/web-platform/test/infra/inngest-step-524-alert.test.sh`: update the shape pin (two units); replace the `inputs` regex with a `tomllib` parse asserting the filter's `inputs` and `pii_scrub_drop_userdata`'s `inputs` separately; update mutation V1; keep V2. Run alone; expect RED.
- 1.3 `scripts/vector-terminator-filter.test.sh` and `apps/web-platform/infra/vector-terminator-filter.test.toml`: structure half (`tomllib` wiring assertion) and `vector test` half with one `[[tests]]` case per class (`no_outputs_from` for the three dropped lines; kept classes; differently worded line; another unit's line with a drop prefix; message-less row; non-string `.message`). Run alone; expect RED.
- 1.4 Guard 1 (four rows) and Guard 2 (three rows) mutation rows as suite rows (each edits a temp copy of `vector.toml`; the Guard 2 rows run in the `vector test` half).

## Phase 2: vector.toml

- 2.1 Source 1 `include_units` gains `soleur-inngest-tls.service`; update the ADMISSION SEMANTICS header text.
- 2.2 Source 2 `exclude_units` gains the same unit.
- 2.3 Add `[transforms.inngest_terminator_filter]` (infallible VRL, fail-open drop-list on the three healthy-request prefixes: `string(.message) ?? ""`, `string(._SYSTEMD_UNIT) ?? ""`, `contains()` with literal strings).
- 2.4 Rewire `pii_scrub_drop_userdata` `inputs` to the filter output.
- 2.5 Comments: budget (400 per day before a flip, 8,000 after), second-drop rule, PRIORITY cannot split the lines, wording measured on stunnel 5.72 only; no dollar-variable text.

## Phase 3: validate (each alone)

- 3.1 `vector validate --no-environment` on `vector.toml` and its rendered `@@HOST_NAME@@` form.
- 3.2 `vector-admission.test.sh`, `vector-pii-scrub.test.sh`, `scripts/vector-terminator-filter.test.sh`, `inngest-step-524-alert.test.sh`, and `journald-config.test.sh` (run-only; edited only if it fails).
- 3.3 `cloud-init-inngest-bootstrap.test.sh`: only `vector.toml` drifted in Guard A (advisory); everything else green.
- 3.4 `inngest-userdata-budget.sh`: headroom unchanged (256 B).
- 3.5 `scripts/probe-inngest-524-count.sh` through Better Stack; record `unit_rows`.
- 3.6 `.github/workflows/validate-vector-config.yml`: run the new suite (blocking, `REQUIRE_VECTOR_TEST=1`), extend both `paths:` filters (files, not globs) and check `timeout-minutes: 5` still fits; confirm `lint-orphan-test-suites` accepts the new suite.

## Phase 4: docs

- 4.1 Runbook: the `request` row and the paragraph under the decode table (conditional on image tag; three decodes; omitted lines; budget; 24-hour check; stop rule kept).
- 4.2 ADR-294 addendum (dated 2026-10-25, one paragraph).
- 4.3 `model.c4`: one clause on the `inngest -> betterstack` edge; run `c4-code-syntax`, `c4-render` and `c4-count-parity`.
- 4.4 `python3 scripts/lint-infra-no-human-steps.py` over the changed docs.

## Phase 5: PR body

- 5.1 Lead with the plain-language ask (duration up to about 80 minutes, user-visible effects, that nothing is broken today, the cost of declining); then the host replace order, blast radius, precondition list and typed-go ask; `Ref #10136`, `Ref #10205`, `Ref #10880`; Guard A red window.

## Phase 6: review and ship (stop before merge)

- 6.1 `soleur:review` (single-user-incident panel).
- 6.2 `soleur:ship --stop-before-merge`: no merge, no dispatch; the PR stays draft unless the owner gives a typed merge go.
