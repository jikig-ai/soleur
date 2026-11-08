# Tasks: Origin TLS follow-ups (Ref #10479, Ref #10205)

Plan: `knowledge-base/project/plans/2026-11-08-feat-origin-tls-followups-alert-retry-timeouts-p90-plan.md`
Hard limits: no apply, dispatch, merge, arm or mark-ready. `Ref` only; `closingIssuesReferences` must be `[]`.

## Phase 0: Sync

- 0.1 `git fetch origin main`; merge if behind; re-grep the 7 gitleaks + 1 actionlint `curl` lines; abort and re-plan if #12410 moved them
- 0.2 Re-derive the lowest unused `frequency_minutes` at or above 47 across `apps/web-platform/infra/sentry/*.tf`
- 0.3 Note the Node version used for the timeout checks (`.nvmrc` 22.23.4 if available)

## Phase 1: curl hardening (item 2)

- 1.1 RED: scanner arm (Test 5b) in `plugins/soleur/test/required-checks-canonical-parity.test.sh`
  - 1.1.1 scanner joins `\` continuations, scopes to gitleaks and actionlint release URLs, checks the 3 flags + `sha256sum -c`
  - 1.1.2 floors (gitleaks >= 7, actionlint >= 1) and scanner count == raw URL count
  - 1.1.3 in-suite mutation self-test (strip a flag in a temp copy) + order-swapped must-PASS variant
  - 1.1.4 behaviour arm: local 503,503,200 server; flagged curl exits 0 with the good body; bare curl exits 0 with the error body
  - 1.1.5 fix stale "three sites" / "all 4 sites" wording
- 1.2 GREEN: add `--fail --retry 5 --retry-all-errors` to the 8 `curl` lines only (ci.yml x3, secret-scan.yml x2, main-health-monitor.yml x2, action.yml x1)
- 1.3 Run `actionlint` on the touched files and the parity suite; confirm `git diff origin/main -- .github/workflows/ci.yml` is exactly 3 lines

## Phase 2: :80 timeouts (item 3)

- 2.1 RED: `apps/web-platform/test/http-timeouts.test.ts` (408 at the short header bound, in-window request answered, idle keep-alive survives, helper throws when headers > request, constants 60_000/300_000, source pins for `index.ts` wiring and `origin-tls.ts` absence)
- 2.2 RED: replace the exact-line pin for `server.headersTimeout = ... + 5_000;` in `apps/web-platform/test/origin-tls.test.ts` with the wiring pin; leave the :443 pins
- 2.3 GREEN: create `apps/web-platform/server/http-timeouts.ts`; wire `applyPlainHttpTimeouts(server);` in `index.ts` (keep the `keepAliveTimeout` line byte-identical); rewrite the `index.ts` comment; correct the `origin-tls.ts` comment only
- 2.4 Run the three vitest files (`http-timeouts`, `origin-tls`, `server-index-boot-pin-line`) and `tsc --noEmit`; grep `apps/web-platform/server/` for any other `createServer` site and record the result

## Phase 3: Sentry rule (item 1)

- 3.0 RED/GREEN: `exitAfterFlush` in `origin-tls.ts` (default `exit` flushes Sentry, bounded 2 s + hard timer) with six cases in `origin-tls.test.ts`; also rename the 'unchanged from main' test, fix the stale ~452 comment
- 3.1 RED: `apps/web-platform/test/sentry-origin-tls-alert-op-contract.test.ts` (derive feature + op set from `origin-tls.ts`; feature-only filter; 4 triggers; email route; root-unique frequency with a negative control; reference equals `.tf`; shutdown-suppression guard pinned)
- 3.2 GREEN: `sentry_alert.origin_tls_event` in `issue-alerts.tf`; key-sorted entry in `alert-reference.json` (`jq -S . f | diff - f`); README 57/57, 55 owned, issue list, subsection
- 3.3 Run the new test, the README census test (`sentry-git-data-pin-fault-alert-op-contract.test.ts`), `apps/web-platform/scripts/sentry-monitors-audit.test.sh`, `terraform fmt -check`

## Phase 4: Runbook (item 4, docs only)

- 4.1 Evidence table extended (16:35Z pair, server-wait vs apex, 11 restart pairs 01:05Z..16:17Z, probe and Better Stack facts)
- 4.2 Honest reading: n=30 spread, apex is a client-network control only, `/health` includes a Supabase round trip
- 4.3 Four candidates with predictions (all UNVERIFIED)
- 4.4 Isolation procedure Steps A, B, C (GraphQL query by hour; schema discovery first), interpretation table
- 4.5 Token prerequisite: `CF_API_TOKEN_ANALYTICS_READ`, wrapper-bound, no fallback, GraphQL POST exception, tracking issue
- 4.6 Marker ruling (no) with revival triggers; "Still unverified" list; update the Sentry and 502/520 "Open checks" rows

## Phase 5: ADR, issues, verification, PR body

- 5.1 ADR-321 (also: the three stale sentences — signals at container start, decision 7 'alert is still deferred', R-A 'unchanged in effect'; and the flush sentence): replace the item-11 "no committed Sentry alert rule" sentences; correct the keep-alive paragraph and R-A "pre-existing" sentence; add item 12 with the three CTO rulings (use the `architecture` skill)
- 5.2 File the two tracking issues (release-download curl class incl. crane; analytics token + wrapper subcommand) with roadmap milestones; link them
- 5.3 Verify: `c4-count-parity.test.sh`, `scripts/lint-guard-contract.py` on the plan, touched vitest files, bash suite, `git diff --stat origin/main` inside the Files lists
- 5.4 PR body: `Ref #10479`, `Ref #10205`, "merge applies the Sentry rule", Node cutoff + 30 s caveat, 31 s retry budget honesty; check `gh pr view 12434 --json closingIssuesReferences` prints `[]` before saving; stop (no ready, no merge, no dispatch)
