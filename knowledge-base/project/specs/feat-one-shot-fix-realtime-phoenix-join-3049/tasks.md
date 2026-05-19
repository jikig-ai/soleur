# Tasks — feat-one-shot-fix-realtime-phoenix-join-3049

Derived from `knowledge-base/project/plans/2026-05-11-fix-realtime-phoenix-join-verify-and-determinism-gate-plan.md`.

Closes #3049 + #3060 (auto-close fires only after PM1/PM2 verification — see plan §Risks R6, R7).

## Phase 1 — Re-verify contract holds locally (no code)

- [ ] 1.1 Run integration test against dev; paste output into PR body.
  - `cd apps/web-platform && doppler run -p soleur -c dev -- env SUPABASE_DEV_INTEGRATION=1 ./node_modules/.bin/vitest run test/conversations-rail-cross-tenant.integration.test.ts`
  - Expected: 3/3 green in <30s.
- [ ] 1.2 Run probe Mode A (default polyfill); paste output into PR body.
  - `doppler run -p soleur -c dev -- node apps/web-platform/scripts/realtime-probe.mjs`
  - Expected: SUBSCRIBED in <2.5s.
- [ ] 1.3 Run probe Mode B (`--no-polyfill`); paste output into PR body.
  - `doppler run -p soleur -c dev -- node apps/web-platform/scripts/realtime-probe.mjs --no-polyfill`
  - Expected: TIMED_OUT at ~10s — proves the bug is still latent without the polyfill.

## Phase 2 — Land nightly determinism gate (#3060)

### 2.0 Prerequisites (operator pre-merge — separate-terminal protocol)

- [ ] 2.0.1 Operator creates `dev_scheduled` Doppler config: `doppler configs create dev_scheduled --environment dev --project soleur`.
- [ ] 2.0.2 Operator creates service token: `doppler configs tokens create dev_scheduled_ci --config dev_scheduled --project soleur --plain` (capture in separate terminal).
- [ ] 2.0.3 Operator runs `gh secret set DOPPLER_TOKEN_DEV_SCHEDULED` in a separate terminal (NEVER via `!` prefix per `hr-never-paste-secrets-via-bang-prefix`).
- [ ] 2.0.4 Verify presence length-only: `gh secret list | grep DOPPLER_TOKEN_DEV_SCHEDULED`.
- [ ] 2.0.5 Verify scope: `doppler configs get dev_scheduled -p soleur --json | jq -r .environment` returns `dev`.

If 2.0.1-2.0.5 cannot be completed pre-merge, the workflow STILL merges — it gracefully degrades via `secret_unset` failure mode and files a precise tracking issue on first run telling the operator what to set.

### 2.1 Pre-flight checks (in-repo)

- [ ] 2.1.1 Identify Doppler CLI install pattern: `DopplerHQ/cli-action@014df23b1329b615816a38eb5f473bb9000700b1 # v3` (confirmed canonical via `scheduled-community-monitor.yml` line 81).
- [ ] 2.1.2 Confirm `actionlint` available locally; install via `go install github.com/rhysd/actionlint/cmd/actionlint@latest` if missing.
- [ ] 2.1.3 Resolve `actions/setup-node` pinned SHA via `gh api repos/actions/setup-node/git/refs/tags/v4.x.y` at workflow-author time.

### 2.2 Author workflow file

- [ ] 2.2.1 Create `.github/workflows/scheduled-realtime-probe.yml`.
- [ ] 2.2.2 Cron: `0 7 * * *` (07:00 UTC daily).
- [ ] 2.2.3 Permissions: `contents: read, issues: write`.
- [ ] 2.2.4 `timeout-minutes: 10`.
- [ ] 2.2.5 Sparse checkout: `apps/web-platform/scripts/realtime-probe.mjs`, `apps/web-platform/package.json`, `apps/web-platform/package-lock.json`, `.github/actions`.
- [ ] 2.2.6 Setup Node 21.7.3 with pinned `actions/setup-node` SHA.
- [ ] 2.2.7 Install Doppler CLI via the pinned action from 2.1.1.
- [ ] 2.2.7a Env: `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}` (NOT `DOPPLER_TOKEN_SCHEDULED` — that's prd-scoped).
- [ ] 2.2.7b Defensive scope assert: `doppler configs get dev_scheduled -p soleur --json | jq -r .environment` returns `dev`; else `record_failure "doppler_scope_drift" "..."`.
- [ ] 2.2.7c Inject dev secrets: `doppler secrets download --project soleur --config dev_scheduled --no-file --format env-no-quotes | while IFS= read -r line; do ... done` (mirror `scheduled-community-monitor.yml` lines 86-95 — handles base64-padded `=` trailing).
- [ ] 2.2.8 `npm ci` in `apps/web-platform/` (full lock-pinned install — see plan D2).
- [ ] 2.2.9 Probe step: 5× consecutive runs; capture stdout; assert `SUBSCRIBED` token + exit 0; fail on any miss.
- [ ] 2.2.10 strip_log_injection helper inline (verbatim from `scheduled-oauth-probe.yml`).
- [ ] 2.2.11 `failure_mode` outputs: `realtime_join_timeout`, `probe_contract_drift`, `secret_unset`, `network_error`.
- [ ] 2.2.12 "File or comment on tracking issue" step (mirror `scheduled-oauth-probe.yml` lines 420-486).
- [ ] 2.2.13 Pre-create `ci/realtime-broken` label idempotently in the same step (`gh label create ... 2>/dev/null || true`).
- [ ] 2.2.14 "Email notification" step (mirror `scheduled-oauth-probe.yml` lines 488-498).
- [ ] 2.2.15 "Auto-close stale issue (probe green)" step (mirror lines 500-522).
- [ ] 2.2.16 All `uses:` pinned to commit SHA + version comment.

### 2.3 Validate workflow

- [ ] 2.3.1 `actionlint .github/workflows/scheduled-realtime-probe.yml` — clean.
- [ ] 2.3.2 `yamllint .github/workflows/scheduled-realtime-probe.yml` — clean.
- [ ] 2.3.3 Per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`: do NOT use `bash -n <file.yml>`. To verify embedded shell soundness, extract the `run:` blocks and pipe via `bash -c '<snippet>'`.
- [ ] 2.3.4 `grep -E '\-c (prd|prod)' .github/workflows/scheduled-realtime-probe.yml` — must return zero (`hr-dev-prd-distinct-supabase-projects`).

## Phase 3 — Learning-file breadcrumb

- [ ] 3.1 Edit `knowledge-base/project/learnings/best-practices/2026-04-29-supabase-phx-join-handshake-shell-environment.md`.
- [ ] 3.2 Add one line under §Related pointing at the new workflow (plan Phase 3 quote).
- [ ] 3.3 Confirm no other content drift introduced by edit.

## Phase 4 — PR open

- [ ] 4.1 PR title: `chore(realtime): nightly determinism gate for cross-tenant isolation`.
  - No auto-close keywords (`close`/`fix`/`resolve` + `#N`) in title (plan R7).
- [ ] 4.2 PR body contains: Phase 1.1/1.2/1.3 outputs, Phase 2.3.1/2.3.2 outputs, link to plan, link to learning file.
- [ ] 4.3 PR body uses `Ref #3049` and `Ref #3060` (NOT `Closes`) until PM1 confirms green. Manual `gh issue close` after PM1/PM2.
- [ ] 4.4 `Ref #3052` + `Ref #3058` for context links.
- [ ] 4.5 Push branch; run `/soleur:review`; resolve P1/P2 findings inline.
- [ ] 4.6 `/soleur:qa` if any change emerges from review; otherwise skip (no UI).
- [ ] 4.7 `/soleur:compound` per `wg-before-every-commit-run-compound-skill`.

## Post-merge (operator/CI)

- [ ] PM1 `gh workflow run scheduled-realtime-probe.yml`; poll `gh run view <id> --json status,conclusion` until complete. Confirm `conclusion: success`.
- [ ] PM2 Comment the green run URL on #3049 and #3060; `gh issue close 3049 --reason completed`; `gh issue close 3060 --reason completed`.
- [ ] PM3 Confirm the workflow appears in the dashboard alongside `scheduled-oauth-probe.yml`.

## Re-evaluation

- 90-day nightly fire-rate review: if 3+ true-positive trips, escalate to pre-merge integration job (plan D1).
- On `@supabase/supabase-js`/`@supabase/realtime-js` bump: run Mode B locally — if `--no-polyfill` reaches SUBSCRIBED, the upstream race is resolved and the polyfill can be retired (file a follow-up).
