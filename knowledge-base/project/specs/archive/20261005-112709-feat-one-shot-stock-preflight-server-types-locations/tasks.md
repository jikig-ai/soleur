# Tasks — feat-one-shot-stock-preflight-server-types-locations

Derived from `knowledge-base/project/plans/2026-10-05-fix-stock-preflight-server-types-locations-plan.md`.
Lane: `single-domain`. Brand-survival threshold: `single-user incident` (CPO sign-off required before work).

## Phase 1 — RED first
- 1.1 Rewrite fixtures in `tests/scripts/test-stock-preflight-gate.sh` to the `server_types[].locations[]` shape (alpha33, beta22 with non-null deprecation, arm11, sing44, partial55).
- 1.2 Replace the `/datacenters` seam arm with a tripwire logging every path to `$TMP/calls.log` and serving the synthesized 410 body; refresh stale header/T4/T14 comments.
- 1.3 Add cases T1b, T6, T7d (table), T7f, T7i, T7j, T15-T19, T20 (loopback) per the plan.
- 1.4 Run against the unchanged lib; record the RED case ids.

## Phase 2 — GREEN
- 2.1 `_stock_fetch`: add `--fail-with-body`.
- 2.2 Add `_stock_verdict`; rewrite `_stock_eu_locations_for` (two args, jq-side EU intersection).
- 2.3 Rewrite `stock_preflight` (single fetch, `fetch_rc` capture, `verdict=$(...) || verdict=""`, exact-token `case`, blip message with reason, unchanged remediation menu).
- 2.4 Rewrite the lib header (presence vs available, 410 note, ADR-154 probe pointer, #7044 link); keep the EU default line byte-identical.
- 2.5 Raise `MIN_ASSERTIONS` to the measured count.

## Phase 3 — verify (targeted only; no dispatch, no live probe)
- 3.1 Run the suite, the EU parity suite, test-plan-gate-preamble, the two bun tests, shellcheck, lint-shell-capture-exit, lint-guard-contract.

## Phase 4 — mutation battery (scratch mirror of tests/scripts)
- 4.1 Execute every Guard Contract row (applied, bash -n, RED at the expected case id); paste the table in the PR body.

## Phase 5 — ship
- 5.1 PR body: Refs #9377, Refs #8609 (never Closes); no workflow parses /datacenters; issue-title mismatch; doc-derived `available` semantics, AC9 first live check; battery not committed.
