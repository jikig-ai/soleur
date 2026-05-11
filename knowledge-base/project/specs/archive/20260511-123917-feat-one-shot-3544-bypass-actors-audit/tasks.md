# Tasks: Periodic Audit of CI Required Ruleset `bypass_actors` (R15 follow-up D1)

Plan: `knowledge-base/project/plans/2026-05-11-ops-security-ruleset-bypass-audit-3544-plan.md`
Issue: #3544
Parent: #3542 (R15 mitigation), #2719 (origin)

## Phase 0 -- Preflight (no writes)

- [ ] 0.1 Verify label `compliance/critical` exists (`gh label list --limit 200 | grep -E '^compliance/critical\b'`)
- [ ] 0.2 Verify labels `ci/auth-broken`, `ci/guard-broken` exist
- [ ] 0.3 Capture live `bypass_actors` to `/tmp/live-bypass.json` for canonical authorship
- [ ] 0.4 Capture full ruleset state to `/tmp/live-ruleset.json` for Phase 5 diff
- [ ] 0.5 Detect test convention: `find apps/ scripts/ plugins/ -name '*.test.sh' -o -name '*.bats' | head`

## Phase 1 -- Canonical JSON + script refactor (contract-changing first)

- [ ] 1.1 Create `scripts/ci-required-ruleset-canonical-bypass-actors.json` (2-entry array, verbatim from live; `actor_id: null` explicit for OrganizationAdmin)
- [ ] 1.2 Refactor `scripts/create-ci-required-ruleset.sh` to inject `bypass_actors` from canonical JSON via `jq --slurpfile`
  - [ ] 1.2.1 Preserve R10 heredoc-then-`--input` pattern
  - [ ] 1.2.2 Add `--print-payload` mode for AC3 diff verification
- [ ] 1.3 Extend `scripts/update-ci-required-ruleset.sh` post-PUT verification to diff round-trip against canonical JSON (exit 2 on mismatch)

## Phase 2 -- Audit workflow (consumer)

- [ ] 2.1 Create `.github/workflows/scheduled-ruleset-bypass-audit.yml`
  - [ ] 2.1.1 Header: name, `schedule: '0 6 * * *'` + `workflow_dispatch`, concurrency, permissions, repo guard, timeout
  - [ ] 2.1.2 Step 1: sparse checkout (`scripts/` + `.github/actions/notify-ops-email`)
  - [ ] 2.1.3 Step 2: defensively create `compliance/critical`, `ci/auth-broken`, `ci/guard-broken` labels
  - [ ] 2.1.4 Step 3 (id: check): invoke `scripts/audit-ruleset-bypass.sh` (deepen-pass: logic moved to standalone script per Phase 2.5)
    - [ ] 2.1.4.a Workflow step is 3-line `bash scripts/audit-ruleset-bypass.sh` invocation under `set -uo pipefail` + `tee` log capture
    - [ ] 2.1.4.b All audit logic (curl, jq, record_failure, strip_log_injection, sanitized `$GITHUB_OUTPUT` echo) lives inside `scripts/audit-ruleset-bypass.sh` (Phase 2.5)
    - [ ] 2.1.4.c **jq canonicalization recipe (verified end-to-end by deepen-pass):** `map({actor_type, actor_id, bypass_mode}) \| sort_by(.actor_type, (.actor_id // "null" \| tostring), .bypass_mode)` — the `map({...})` projection is load-bearing for missing-key vs null-value equality
  - [ ] 2.1.5 Step 4 (id: tripwire): grep for gh_/ghp_/github_pat_ token shapes in step output
  - [ ] 2.1.6 Step 5: File or comment on tracking issue (de-dupe by label + title search)
    - [ ] 2.1.6.a Title routing by failure_label
    - [ ] 2.1.6.b Label set: `compliance/critical` + `ci/auth-broken` + `priority/p1-high` + `domain/legal` (for drift) OR `ci/guard-broken` + `priority/p1-high` (for malfunction)
    - [ ] 2.1.6.c Body references #2719, #3542, #3544, runbook link, run URL
  - [ ] 2.1.7 Step 6: `notify-ops-email` (`continue-on-error: true`)
  - [ ] 2.1.8 Step 7: Auto-close stale tracking issue on audit-green
- [ ] 2.2 Lint:
  - [ ] 2.2.1 `yamllint .github/workflows/scheduled-ruleset-bypass-audit.yml`
  - [ ] 2.2.2 `actionlint -no-color .github/workflows/scheduled-ruleset-bypass-audit.yml` (with shellcheck integration)
  - [ ] 2.2.3 NOT `bash -n` (Sharp Edge -- YAML header is not bash)
- [ ] 2.3 Document that `gh workflow run --ref feat-branch` will fail pre-merge (`workflow_dispatch` requires default branch)

## Phase 2.5 -- Standalone audit script (deepen-pass NEW)

- [ ] 2.5.1 Create `scripts/audit-ruleset-bypass.sh` containing all audit logic (curl + jq + record_failure + strip_log_injection)
- [ ] 2.5.2 Support `AUDIT_FETCH_OVERRIDE` test-only env var (skips curl, reads from file)
- [ ] 2.5.3 Document load-bearing literals in script header: title strings, failure_mode constants
- [ ] 2.5.4 `shellcheck scripts/audit-ruleset-bypass.sh` exits 0

## Phase 3 -- Unit tests for drift detection (REVISED by deepen-pass)

**Deepen-pass correction:** repo uses `tests/scripts/test-<name>.sh` (NOT `.test.sh`/`.bats`/`yq`). Template: `tests/scripts/test-rule-metrics-aggregate.sh`.

- [ ] 3.1 Create `tests/scripts/test-audit-ruleset-bypass.sh` per repo convention
- [ ] 3.2 Test cases:
  - [ ] 3.2.T1 Identity: live == canonical -> no failure_mode
  - [ ] 3.2.T2 Added entry: extra `RepositoryRole id=4` -> `bypass_actors_drift`, `ci/auth-broken`
  - [ ] 3.2.T3 Removed entry: missing OrganizationAdmin -> drift
  - [ ] 3.2.T4 Mode change: `bypass_mode: always` -> drift (most brand-damaging case)
  - [ ] 3.2.T5 Order-insensitive: reversed order -> NO drift
  - [ ] 3.2.T6 `actor_id: null` vs missing key -> NO drift (`map({...})` projection collapses both)
  - [ ] 3.2.T7 Canonical file missing/malformed -> `canonical_file_missing|invalid_json`, `ci/guard-broken`
  - [ ] 3.2.T8 Live API HTTP 503 -> `github_api_http`, `ci/guard-broken`
  - [ ] 3.2.T9 Log-injection sanitation: CRLF + U+2028 stripped before `$GITHUB_OUTPUT`
  - [ ] 3.2.T10 Unknown actor_type (`Integration`) -> drift detected (no allowlist)
  - [ ] 3.2.T11 Number vs string actor_id (`5` vs `"5"`) -> drift detected
- [ ] 3.3 Test harness invokes `scripts/audit-ruleset-bypass.sh` directly via `AUDIT_FETCH_OVERRIDE` env var. NO `yq`.
- [ ] 3.4 Wire `tests/scripts/test-audit-ruleset-bypass.sh` into `scripts/test-all.sh` after the `rule-metrics-aggregate` registration (line 57)

## Phase 4 -- Runbook + compliance-posture wiring

- [ ] 4.1 Author `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
  - [ ] 4.1.1 Pre-mutation gates (verify drift is real, check audit log)
  - [ ] 4.1.2 Triage path: drift = legitimate -> edit canonical JSON via PR with CPO sign-off
  - [ ] 4.1.3 Triage path: drift = unauthorized -> rotate, restore via update-ci-required-ruleset.sh, post-mortem
  - [ ] 4.1.4 Triage path: guard malfunction -> rate-limit/token/re-run via workflow_dispatch
  - [ ] 4.1.5 Green-recovery procedure (no manual close)
- [ ] 4.2 Amend `knowledge-base/legal/compliance-posture.md`
  - [ ] 4.2.1 Bump `last_updated: 2026-05-11`
  - [ ] 4.2.2 Add HTML-comment landed-record row
  - [ ] 4.2.3 Append "Daily audit (#3544) …" sentence to `#2719` row
- [ ] 4.3 Add comment block to `scripts/required-checks.txt` pointing to canonical JSON
- [ ] 4.4 Stub learning file at `knowledge-base/project/learnings/best-practices/` (filename with date at write time per Sharp Edge)

## Phase 5 -- Post-merge verification (operator-run)

- [ ] 5.1 Verify workflow on default branch via `gh api repos/.../contents/.../scheduled-ruleset-bypass-audit.yml?ref=main`
- [ ] 5.2 `gh workflow run scheduled-ruleset-bypass-audit.yml` then poll until conclusion=success
- [ ] 5.3 Smoke-test the drift path on a short-lived branch
  - [ ] 5.3.1 Edit canonical JSON on smoke branch
  - [ ] 5.3.2 `gh workflow run --ref smoke-branch`
  - [ ] 5.3.3 Verify `[compliance/critical]` issue filed with correct body
  - [ ] 5.3.4 Close smoke PR + smoke issue without merging
  - [ ] 5.3.5 Document smoke transcript URL in runbook
- [ ] 5.4 Update `compliance-posture.md` -- move D1 from deferred to landed
- [ ] 5.5 Close #3544 with smoke-transcript link
- [ ] 5.6 (AC19) Next-day verification: `gh run list --workflow=scheduled-ruleset-bypass-audit.yml --limit=2` shows green cron tick

## Documentation & Closure

- [ ] D1 Add a `## Changelog` section to the PR body summarizing artifacts
- [ ] D2 Apply `semver:patch` label (operator-tooling addition; no plugin behavior change)
- [ ] D3 Use `Ref #3544 / Ref #3542 / Ref #2719` in PR body (NOT `Closes`)
- [ ] D4 Declare brand-survival threshold `single-user incident` (carry-forward) + CPO sign-off note referencing #3543
