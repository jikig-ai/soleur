# Tasks: TR9 PR-3 — migrate scheduled-oauth-probe to Inngest cron substrate

Source plan: `knowledge-base/project/plans/2026-05-21-feat-tr9-pr3-oauth-probe-drift-guard-inngest-plan.md`
Issue: #4211 · Draft PR: #4227 · Branch: `feat-tr9-pr3-oauth-probe-drift-guard-inngest-4211`
Brand-survival threshold: `single-user incident` · `requires_cpo_signoff: true`

## Phase 0: Preconditions

- [x] 0.1 Verify file paths and patterns referenced in plan:
  - [x] 0.1.1 `apps/web-platform/app/api/inngest/route.ts:37` has the inngest functions array (4 existing entries).
  - [x] 0.1.2 `apps/web-platform/server/inngest/functions/cron-daily-triage.ts:329-371` shape matches the heartbeat reference.
  - [x] 0.1.3 `apps/web-platform/test/oauth-probe-contract.test.ts` exists; verified at /work-time Phase 0 to export THREE constants (NOT two as plan AC3a paraphrased): `GITHUB_REDIRECT_URI_ERROR_SENTINEL` (literal `"redirect_uri is not associated"`), `GITHUB_APP_SUSPENDED_SENTINEL` (literal `"Application suspended"`), `GITHUB_AUTHORIZE_PAGE_ANCHORS` (readonly array: `['name="authenticity_token"', "Sign in to GitHub", "Authorize"]`). All three move to `oauth-probe-sentinels.ts`; test file re-exports for backward compat. Also exports `GITHUB_REQUIRED_CALLBACK_URLS` (3 callback URLs for flow A/B/C) — leave in the test file (test-only domain knowledge, not consumed by the probe handler).
  - [x] 0.1.4 `apps/web-platform/server/github/app-client.ts` exists; confirm its installation-scoped + audit-writer-attached shape (do NOT reuse for probe).
  - [x] 0.1.5 `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts:39` glob is `server/inngest/functions/cron-*.ts`.
  - [x] 0.1.6 `apps/web-platform/infra/sentry/cron-monitors.tf` line numbers for the joint-exception breadcrumb (24-37), the May 21 oauth-probe comment (~71-77), and the May 21 drift-guard comment (~91-99) are correct on `main`. If drifted, adapt AC11/AC12 sentinel greps.
  - [x] 0.1.7 `@octokit/app` is in `apps/web-platform/package.json` (transitively or directly). Verify via `grep -E '@octokit/app' apps/web-platform/package.json apps/web-platform/bun.lockb` (or `bun.lock`).
  - [x] 0.1.8 Doppler `prd` secrets present: `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `SUPABASE_ANON_KEY`, `OAUTH_PROBE_GITHUB_CLIENT_ID`, `SUPABASE_PROJECT_REF`, `RESEND_API_KEY`, `APP_HOST`, `API_HOST`. Verify via `doppler secrets list -p soleur -c prd | grep -E '^(GITHUB_APP|SUPABASE_ANON|OAUTH_PROBE|RESEND|APP_HOST|API_HOST|SUPABASE_PROJECT_REF)\b'`.
- [x] 0.2 Verify operator-facing labels exist: `gh label list --limit 200 | grep -E '^(ci/auth-broken|priority/p1-high|priority/p2-medium|code-review|domain/engineering)\b'`.
- [x] 0.3 Confirm CPO sign-off recorded for the elevated threshold (per `requires_cpo_signoff: true`). Operator self-attest in PR body or CPO comment on #4211.

## Phase 1: Sentinel-module promotion (AC3a)

- [x] 1.1 Create `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` exporting the constants currently in `test/oauth-probe-contract.test.ts`.
- [x] 1.2 Refactor `apps/web-platform/test/oauth-probe-contract.test.ts` to import from the new server module; preserve existing export surface (re-export for backward compatibility).
- [x] 1.3 Run `./node_modules/.bin/vitest run test/oauth-probe-contract.test.ts` — green.

## Phase 2: Probe-Octokit helper (AC4)

- [x] 2.1 Create `apps/web-platform/server/github/probe-octokit.ts` exporting `createProbeOctokit()`.
  - [x] 2.1.1 Uses `@octokit/app`'s `App` constructor with `appId` + `privateKey` from `process.env.GITHUB_APP_ID` + `process.env.GITHUB_APP_PRIVATE_KEY`.
  - [x] 2.1.2 NO `founderId` parameter. NO audit-writer attachment. NO `audit_github_token_use` row insertion.
  - [x] 2.1.3 JSdoc header explicitly warns: "synthetic-probe Octokit factory; do NOT import in founder-activity flows — use `createGitHubAppClient()` instead."
- [x] 2.2 Write unit test stub at `apps/web-platform/test/server/github/probe-octokit.test.ts` covering: factory returns an Octokit instance; no DB call is made; JWT is valid RS256 (decode header). (Optional if /work-time scope is tight — the integration covered by AC17 implicitly tests this.)

## Phase 3: cron-oauth-probe Inngest function (AC1, AC2, AC3, AC5, AC6, AC7)

- [x] 3.1 Create `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`.
  - [x] 3.1.1 Export `cronOauthProbe = inngest.createFunction({...}, [{ cron: "0 * * * *" }, { event: "cron/oauth-probe.manual-trigger" }], cronOauthProbeHandler)`.
  - [x] 3.1.2 Concurrency: `[{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` (literal-string-in-string).
  - [x] 3.1.3 Retries: 1.
- [x] 3.2 Translate the probe logic from `.github/workflows/scheduled-oauth-probe.yml:71-422` to TypeScript:
  - [x] 3.2.1 8 failure modes preserved by name.
  - [x] 3.2.2 `fetch(url, { redirect: "manual", signal: AbortSignal.timeout(10_000) })` for each curl form.
  - [x] 3.2.3 Body-grep sentinels imported from `oauth-probe-sentinels.ts`.
  - [x] 3.2.4 `dig CNAME api.soleur.ai` → Node's `dns.promises.resolveCname()` (per prior plan Sharp Edge); strip `.supabase.co.?$`, take head -1.
- [x] 3.3 Wrap probe logic in `step.run("probe", { timeout: "5m" }, ...)` envelope.
- [x] 3.4 Implement issue-filing branch using `createProbeOctokit()` (AC4): list-open-by-title, create-or-comment, close-on-success. Title: `[ci/auth-broken] Synthetic OAuth probe failed`. Labels: `ci/auth-broken`, `priority/p1-high`.
- [x] 3.5 Implement auto-close-stale-issue branch matching GHA workflow lines 504-526.
- [x] 3.6 Implement Resend POST in `step.run("notify-ops-email", ...)` matching `.github/actions/notify-ops-email/action.yml:33-44` payload.
- [x] 3.7 Implement Sentry heartbeat in `step.run("sentry-heartbeat", ...)` matching `cron-daily-triage.ts:329-371` shape. `SENTRY_MONITOR_SLUG = "scheduled-oauth-probe"`. `reportSilentFallback` on curl failure.

## Phase 4: Register function (AC8)

- [x] 4.1 Edit `apps/web-platform/app/api/inngest/route.ts:37` to import and include `cronOauthProbe` in the functions array.
- [x] 4.2 Verify: `grep -nE 'cronOauthProbe' apps/web-platform/app/api/inngest/route.ts` returns ≥1.

## Phase 5: Sentry monitor IaC (AC11, AC12)

- [x] 5.1 Edit `apps/web-platform/infra/sentry/cron-monitors.tf` `resource "sentry_cron_monitor" "scheduled_oauth_probe"`: `checkin_margin_minutes = 360 → 30`, `failure_issue_threshold = 2 → 1`.
- [x] 5.2 Rewrite the header comment above the resource: declare Inngest-fired substrate; cite TR9 PR-1/PR-2 precedent + ADR-030 + ADR-033.
- [x] 5.3 Update joint-exception breadcrumb at lines 24-37: remove oauth-probe; retain drift-guard as sole exception with note about TR9 PR-4 follow-up.
- [x] 5.4 Delete May 21 oauth-probe comment at lines ~71-77.
- [x] 5.5 Revise May 21 drift-guard comment at lines ~91-99: drop joint-bump reasoning, retain drift-guard-specific margin justification.
- [x] 5.6 Run `cd apps/web-platform/infra/sentry && terraform init -input=false -backend=false && terraform validate` — passes.

## Phase 6: Workflow deletion (AC9, AC10)

- [x] 6.1 `git rm .github/workflows/scheduled-oauth-probe.yml` — delete the workflow file (540 LoC).
- [x] 6.2 Verify `.github/actions/sentry-heartbeat/action.yml` is preserved unchanged (still consumed by sister workflows including drift-guard).

## Phase 7: Runbook + cross-reference updates (AC13, AC14, AC15)

- [x] 7.1 Update `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` per the 10 line-pair edit list (lines 5, 16, 33, 34, 41, 228, 237, 489-501).
- [x] 7.2 Prepend a one-line substrate-disambiguation note to the troubleshooting section: "Before debugging the probe code path, check Better Stack `inngest-heartbeat` last_alive_at via the dashboard..."
- [x] 7.3 Update `knowledge-base/engineering/ops/runbooks/github-app-drift.md` line 339 (oauth-probe cross-reference only). Drift-guard self-references untouched (TR9 PR-4).
- [x] 7.4 Run AC15 sentinel grep: `grep -rEn 'scheduled-oauth-probe\.yml|gh workflow run scheduled-oauth-probe|gh run list.*scheduled-oauth-probe' knowledge-base/engineering/ apps/web-platform/ README.md CONTRIBUTING.md 2>/dev/null | grep -v archive/ | grep -v 'knowledge-base/project/\(plans\|specs\|learnings\)/' | wc -l` returns 0.

## Phase 8: Tests (AC17, AC18)

- [x] 8.1 Create `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` (~150 LoC).
  - [x] 8.1.1 Happy-path: probe returns `?status=ok` heartbeat.
  - [x] 8.1.2 Per-failure-mode (×8): correct failureMode + `?status=error` heartbeat.
  - [x] 8.1.3 Fork-PR fallback: `SENTRY_INGEST_DOMAIN` empty → warning logged, no throw.
  - [x] 8.1.4 Issue-filing: mocked Octokit; assert list-then-create-or-comment branches.
  - [x] 8.1.5 Mocked `fetch`; no real network calls.
- [x] 8.2 Run `./node_modules/.bin/vitest run test/server/inngest/cron-oauth-probe.test.ts` — green.
- [x] 8.3 Run `./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts` — green (glob auto-extends to `cron-oauth-probe.ts`).

## Phase 9: Pre-merge gates

- [x] 9.1 Run `cd apps/web-platform && bun run typecheck` — passes.
- [x] 9.2 Run #4116 cascade six self-check questions:
  - [x] CQ1: `PUBLIC_PATHS` includes `/api/inngest`.
  - [x] CQ2: `INNGEST_SIGNING_KEY` prefix is `signkey-prod-*` in prd.
  - [x] CQ3: `inngest-server.service` `User=deploy` matches file ownership.
  - [x] CQ4: `inngest-server.service` `ReadWritePaths=` covers SQLite db.
  - [x] CQ5: Env source is Doppler `prd`.
  - [x] CQ6: Better Stack `inngest-heartbeat` is unpaused.
- [x] 9.3 PR body uses `Closes #3203` (NOT `Closes #3236` already closed, NOT `Closes #3750` deferred to PR-4).
- [x] 9.4 PR body includes the User-Brand Impact section per plan §User-Brand Impact (carried into PR template).

## Phase 10: Mark PR ready

- [ ] 10.1 Run `gh pr ready 4227`.
- [ ] 10.2 Wait for required checks to pass; `/soleur:ship` merges via `gh pr merge --squash --auto`.

## Phase 11: Post-merge (auto + verification) (AC21, AC22, AC23)

- [ ] 11.1 **Auto:** `apply-sentry-infra.yml` runs on push to main. Verify: `gh run list --workflow=apply-sentry-infra.yml --limit 1 --json conclusion,headBranch,createdAt --jq '.[] | select(.headBranch == "main") | .conclusion'` returns `success` (NOT `skipped` per the pathspec-zero-match learning).
- [ ] 11.2 **Auto:** Next.js production build deploys; Inngest server discovers `cron-oauth-probe` via `/api/inngest`. No operator action.
- [ ] 11.3 **T+90 min verification:** `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-oauth-probe/checkins/?limit=5" | jq -r '.[] | "\(.dateCreated) \(.status)"'` shows recent `ok` check-in.
- [ ] 11.4 **T+24h verification:** Sentry issue `a94c4ec23f654101a7fc4491b16a560c` auto-resolves: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/issues/a94c4ec23f654101a7fc4491b16a560c/" | jq -r '.status'` returns `resolved`.
- [ ] 11.5 **Rollback contract:** if T+90 min check fails, restore workflow: `git show HEAD~1:.github/workflows/scheduled-oauth-probe.yml > .github/workflows/scheduled-oauth-probe.yml && git add . && git commit -m "Revert: TR9 PR-3 cutover; restore GHA fallback" && git push`.

## Phase 12: Post-merge synthetic-failure injection (AC20, AC24)

- [ ] 12.1 Spin up local Inngest dev server: `inngest dev` (or use a feature-flagged preview deploy).
- [ ] 12.2 Run `apps/web-platform` dev server: `bun run dev`. Override `APP_HOST` via env-var in the dev shell to point at a fixture URL serving a canonical failure-body sentinel (e.g., a static-HTML file or `https://httpbin.org/status/500`).
- [ ] 12.3 Fire `inngest send cron/oauth-probe.manual-trigger` against the local Inngest.
- [ ] 12.4 Verify within 90s: (a) `?status=error` heartbeat to Sentry dev project (or stubbed), (b) `[ci/auth-broken]` issue filed against a test repo (or mocked), (c) Resend webhook captured.
- [ ] 12.5 Record function-run ID + verification timestamp in PR body post-merge checklist.
- [ ] 12.6 If unable to run local Inngest dev, defer to `/soleur:ship` Phase 5.5 with explicit note in PR body.

## Phase 13: Follow-up filing (AC25)

- [ ] 13.1 Within 48h of merge, file TR9 PR-4 tracking issue:
  ```bash
  gh issue create --title "chore(infra): TR9 PR-4 — migrate scheduled-github-app-drift-guard to Inngest cron substrate" \
    --label "code-review,priority/p2-medium,domain/engineering" \
    --body "$(cat <<'EOF'
Paired follow-up to #4211 (TR9 PR-3, oauth-probe). Same substrate-cadence root cause (GHA hourly cron drift ~150-min median / 293-min max).

## Inherited framing
- Brand-survival threshold: `single-user incident` (declared in drift-guard's workflow header lines 5-12 verbatim).
- requires_cpo_signoff: true.

## Scope
Migrate `.github/workflows/scheduled-github-app-drift-guard.yml` (724 LoC, 12+ failure modes) to `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`.

## Heavier than oauth-probe (per PR-3 plan-review)
- 12+ failure modes vs 8 (`id_mismatch`, `client_id_mismatch`, `permission_drift`, `installation_permission_drift`, `bad_pem`, `jwt_mint_failure`, ...).
- JWT minting via `@octokit/app`'s `App` constructor (already in deptree).
- Manifest-diff: either TS reimplementation OR `child_process.spawn` of `bin/diff-github-app-manifest.sh`.
- Three label classes: `[ci/auth-broken]`, `[ci/guard-broken]`, `[security/leak-suspected]`.

## Pattern source
Mirror TR9 PR-3 (#4211) verbatim. New helper at `apps/web-platform/server/github/probe-octokit.ts` is reused (no audit-writer attachment).

## Candidate closes
- Closes #3750 (mint-app-jwt composite extraction): cross-workflow dedup target dissolves once drift-guard moves off GHA — ruleset-audit becomes the sole remaining GHA JWT-mint site, so cross-workflow dedup is moot; intra-TS dedup is via `@octokit/app`.

## Sentry monitor IaC
- `scheduled_github_app_drift_guard`: revert PR #4207's margin/threshold bump (360 → 30, 2 → 1).
- Delete the joint-exception breadcrumb's drift-guard reference (now that PR-3's residual exception note is the sole remaining one).
EOF
  )"
  ```
- [ ] 13.2 Cross-reference the new TR9 PR-4 issue # in the parent umbrella #3948.

## Notes on plan-review applied changes

Three reviewers (DHH, Kieran, Code Simplicity) ran on plan v1. Convergent verdict applied:
- **Scope reverted** from bundled (oauth-probe + drift-guard) to single-probe (oauth-probe only). Drift-guard → TR9 PR-4 follow-up (AC25).
- **AC27 (pre-deletion local `inngest dev` gate) cut** — local dev doesn't exercise prd substrate. Real cutover gate is AC22 (first scheduled fire) + Risks #1 rollback contract.
- **AC28 (Better Stack heartbeat in issue body) cut** — replaced by AC13 runbook line.
- **AC4 corrected**: new `createProbeOctokit()` helper at `apps/web-platform/server/github/probe-octokit.ts`, NOT the existing `createGitHubAppClient()` (wrong-shaped: installation-scoped + audit-writer-attached).
- **AC3a reworded** as test→server promotion (not duplicate-literal dedup — the test file already centralizes the constants as exports).

Brainstorm doc + spec.md are stale relative to this revision; THIS tasks file + the plan are the source of truth. /work-time agent reads this file as the ordered checklist.
