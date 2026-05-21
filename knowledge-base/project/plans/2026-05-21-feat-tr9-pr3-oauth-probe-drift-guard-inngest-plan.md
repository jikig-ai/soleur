---
title: "feat(runtime): TR9 PR-3 — migrate scheduled-oauth-probe to Inngest cron substrate"
date: 2026-05-21
type: feat
classification: ci-ops
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-tr9-pr3-oauth-probe-drift-guard-inngest-4211
issue: 4211
draft_pr: 4227
parent_umbrella: 3948
precedents: [3985, 4062]
prior_plan: knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md
prior_plan_status: superseded (immediate-relief via #4207); structural fix reactivated under this plan
prior_immediate_relief_pr: 4207
brainstorm: knowledge-base/project/brainstorms/2026-05-21-tr9-pr3-oauth-probe-drift-guard-inngest-brainstorm.md
spec: knowledge-base/project/specs/feat-tr9-pr3-oauth-probe-drift-guard-inngest-4211/spec.md
scope: oauth-probe only (drift-guard deferred to TR9 PR-4 per plan-review verdict)
related_workflows:
  - .github/workflows/scheduled-oauth-probe.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
related_runbooks:
  - knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md
  - knowledge-base/engineering/ops/runbooks/github-app-drift.md
related_issues: [3203]
followup_issue_to_file: chore(infra) — TR9 PR-4 — migrate scheduled-github-app-drift-guard to Inngest cron substrate (paired follow-up; same root cause, deferred per plan-review scope discipline)
sentry_issue_id: a94c4ec23f654101a7fc4491b16a560c
prior_learnings:
  - knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md
  - knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md
  - knowledge-base/project/learnings/bug-fixes/2026-05-20-inngest-heartbeat-doppler-env-injection.md
  - knowledge-base/project/learnings/2026-05-18-composite-action-extraction-inline-on-multi-file-rollout.md
  - knowledge-base/project/learnings/integration-issues/2026-05-18-infra-validation-pathspec-silent-zero-match.md
prior_prs: [3964, 3971, 3985, 4062, 4207]
---

# feat(runtime): TR9 PR-3 — migrate `scheduled-oauth-probe` to Inngest cron substrate

## Summary

The third migration in the TR9 (`cron lives in Inngest, not GH Actions`) sequence. Migrates the hourly OAuth-probe canary onto the self-hosted Inngest cron substrate (Hetzner VM), matching PR-1 (#3985 `cron-daily-triage`, MERGED) and PR-2 (#4062 `cron-follow-through-monitor`, MERGED). PR #4207's immediate-relief margin bump (30 → 360) is reverted; the monitor returns to 30-min margin + `failure_issue_threshold = 1` honest signal.

**Scope:** oauth-probe only. The sibling `scheduled-github-app-drift-guard` shares the same substrate-cadence regression and the same elevated threshold framing (its workflow header at lines 5-12 declares the identical "Brand-survival threshold: single-user incident" framing), but plan-review converged that bundling doubles the cutover blast radius under the elevated threshold. Drift-guard is filed as **TR9 PR-4** with the same plan pattern; this PR ships oauth-probe first as the canary-canary, then PR-4 ports drift-guard with the verified pattern.

**Brand-survival threshold: `single-user incident`** (elevated from the prior plan's `none`). The probe IS the canary detecting OAuth + GitHub-App auth regressions for founders — a botched migration silently disables detection. Elevation is a restoration of framing the drift-guard workflow's own header always had, not a new judgment.

One named scope addition retained from the brainstorm triad (CPO):

- **AC21 — Post-merge detection contract** (reshape of brainstorm's AC26): validates the canary still squawks, not just that it ticks. Runs against a non-prd surface; prd code path has zero fixture-injection plumbing.

Brainstorm AC27 (pre-deletion local `inngest dev` gate) and AC28 (Better Stack heartbeat timestamp in issue body) are **cut per plan-review verdict** — DHH + Code Simplicity converged that AC27 is theater (local dev doesn't exercise prd substrate) and AC28 is premature optimization for an unrealized failure mode. Their value is preserved via the runbook update (AC15) and the rollback contract (Risks #1).

CLO carry-forward: Article-30 PA 13 (self-hosted Inngest, PR-F #3244) already covers the substrate. No DPA addendum.

The prior deepened plan at `knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md` (status: superseded by PR #4207) is the architectural source for AC1–AC20 below; this plan absorbs those ACs with Kieran's plan-review factual corrections and adds AC21.

## User-Brand Impact

**If this lands broken, the user experiences:** an undetected OAuth auth regression. The probe is the early-warning system that surfaces auth breakage BEFORE a founder's sign-in fails. If the new Inngest function registers but doesn't fire, doesn't detect, or posts `?status=ok` heartbeats while the underlying auth surface is broken, the founder discovers the outage when their workflow breaks — not when the canary squawks. The recent recurring Sentry alert `a94c4ec23f654101a7fc4491b16a560c` was the GHA substrate degrading; the user-facing surface (`app.soleur.ai/login`, `api.soleur.ai/auth/v1/...`) is untouched by the migration — but the *detection layer* IS in scope.

**If this leaks, the user's data/workflow/money is exposed via:** N/A on data flow. The probe is a synthetic outbound HTTP check; no personal data is read, written, or processed. Article-30 register PA 13 already covers the Inngest substrate. The exposure surface is *detection-quality*, not data-confidentiality.

**Brand-survival threshold:** `single-user incident`.

- **threshold: single-user incident, reason:** silent detection-layer failure across the OAuth canary collapses the operator's earliest-warning signal for auth breakage. The prior plan declared `none` on a "no auth flow, no PII" rationale that missed the canary-detection surface as the load-bearing brand artifact. Elevation restores the framing the drift-guard workflow's own header has always had, applied here to oauth-probe by symmetry (both probes serve the same auth-canary class).

## Research Reconciliation — Spec vs. Codebase

| Claim (prior plan / brainstorm / spec) | Reality (grep + `gh` verified at plan time) | Plan response |
| --- | --- | --- |
| "Bundle oauth-probe + drift-guard in one PR" (brainstorm, spec FR1+FR2) | Plan-review (DHH + Code Simplicity converged) flagged bundling as doubling cutover blast radius under elevated threshold. Drift-guard is heavier (724 LoC vs 540, 12+ modes vs 8, JWT minting, manifest-diff shell-out). | **Plan reverts to single-probe scope.** Drift-guard filed as TR9 PR-4 paired follow-up (AC26). The brainstorm's bundling rationale (shared substrate, shared composite, shared cron-monitors.tf cleanup) was infrastructure-symmetry; risk-symmetry under elevated threshold favors split. Brainstorm doc updated post-plan-review (`[Updated 2026-05-21]` marker) to reflect the revision. |
| "AC27 — pre-deletion local `inngest dev` gate" (brainstorm) | Plan-review (DHH + Code Simplicity) converged: local dev verification doesn't exercise the prd substrate (different runtime, different deploy path, different env). The actual prd-substrate gate IS the post-merge first-fire (AC23). | **AC27 cut.** Rollback contract preserved in Risks #1: if AC23 misses by T+90 min, hotfix PR restores the YAML workflow. |
| "AC28 — Better Stack heartbeat in issue body" (brainstorm) | Plan-review (DHH + Code Simplicity) converged: premature optimization adding a third-party API call to the auth-broken hot path for an unrealized failure-mode. Cross-monitor correlation (Observability section) already disambiguates substrate-down via sibling Inngest monitors. | **AC28 cut.** Disambiguation moves to the runbook update (AC15): a one-line direction to check Better Stack `inngest-heartbeat` last_alive_at before debugging the probe code path. Zero new code, zero new dependency. |
| "AC4 + AC11 use existing `apps/web-platform/server/github/app-client.ts`" (brainstorm AC4) | Kieran plan-review: `app-client.ts` exists but is wrong-shaped — it's an installation-scoped factory (`createGitHubAppClient(installationId, founderId)`) that attaches an audit-writer hook writing `audit_github_token_use` rows for a `founderId`. The probe has no founder, no installationId, and writing to the audit ledger would pollute Article 30 PA-16's scope. | **AC4 prescribes a NEW `createProbeOctokit()` factory** at `apps/web-platform/server/github/probe-octokit.ts` that mints an app-level JWT via `@octokit/app`'s `App` constructor (already a transitive dep via `app-client.ts`), without `founderId` and without audit-writer attachment. Probe is not founder activity; the ledger stays clean. |
| "AC9 uses `jsonwebtoken` for JWT minting" (initial plan draft) | Kieran plan-review: `jsonwebtoken` is NOT in `apps/web-platform/package.json`. Only `@octokit/auth-app` is present (transitive from `@octokit/app`). | Drift-guard is deferred to TR9 PR-4, so AC9 is dropped from this plan. The PR-4 plan will prescribe `@octokit/app` `App` constructor for JWT minting (no new dep needed). |
| "AC3a — duplicate sentinel string literals deduplicated" (brainstorm AC3a) | Kieran plan-review: the test file `apps/web-platform/test/oauth-probe-contract.test.ts` ALREADY exports the sentinels as constants (`GITHUB_OAUTH_REDIRECT_URI_SENTINEL`, `GITHUB_APP_SUSPENDED_SENTINEL`). The "duplicate literals" framing is wrong — they're test-scoped exports. | **AC3a reworded as test→server promotion:** move the constants from `test/oauth-probe-contract.test.ts` to `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts`; re-export from the test file for backward compatibility (zero consumer-drift window). |
| "Inngest deterministic firing means 30-min margin is honest" (prior plan AC11) | Verified today (2026-05-21) via Sentry checkins API: `scheduled-daily-triage` checkin at 04:00:19Z (+19s past expected); `scheduled-follow-through` checkin at 09:00:08Z (+8s). Both sibling Inngest crons fire well inside 30-min margin. | Carry forward — oauth-probe monitor restored to `checkin_margin_minutes = 30`, `failure_issue_threshold = 1`. |
| "Brand-survival threshold = `none`" (prior plan User-Brand Impact line 112) | Brainstorm triad converged on elevation; drift-guard workflow's own header (lines 5-12) declares `single-user incident` explicitly. | **Threshold elevated to `single-user incident`. `requires_cpo_signoff: true`.** |

## Hypotheses

Not a network-outage diagnosis class. Phase 1.4 keyword scan does NOT match the feature description; no `provisioner "remote-exec"` block. Skipping Phase 1.4 silently.

Carry forward H1–H5 from the prior plan (`fix-scheduled-oauth-probe-recurrence-plan.md` lines 131–137): H1+H2 REJECTED, H3 CONFIRMED (GHA cron drift), H4 (Inngest substrate exists), H5 CONFIRMED (sister drift-guard same envelope — handled by TR9 PR-4 follow-up).

## Acceptance Criteria

### Pre-merge (PR)

**Code shape (Inngest function):**

- [ ] AC1 — A new file `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` exports `cronOauthProbe = inngest.createFunction({...}, [{ cron: "0 * * * *" }, { event: "cron/oauth-probe.manual-trigger" }], cronOauthProbeHandler)`. Handler wraps probe logic in `step.run("probe", ...)` (ADR-033 I1) and Sentry heartbeat in `step.run("sentry-heartbeat", ...)` matching `cron-daily-triage.ts:329-371` shape. Concurrency: `[{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` (literal-string-in-string is load-bearing per Architecture F7). Retries: 1.
- [ ] AC2 — Handler embeds probe logic from `.github/workflows/scheduled-oauth-probe.yml:71-422` translated to TypeScript: 8 failure modes preserved by name (`network_error`, `login_unreachable`, `google_authorize`, `github_authorize`, 5× `github_oauth_*`, `settings_*`, `callback_error_passthrough`); same curl forms with `--max-time 10` via `AbortSignal.timeout(10_000)` AND `fetch(url, { redirect: "manual" })` to capture 302s; same body-grep sentinels imported from `oauth-probe-sentinels.ts` (AC3a).
- [ ] AC3 — Handler reads `APP_HOST`, `API_HOST`, `SUPABASE_ANON_KEY`, `OAUTH_PROBE_GITHUB_CLIENT_ID`, `SUPABASE_PROJECT_REF` from `process.env` (Doppler `prd`). No new secret materialization. Hardcoded fallbacks `APP_HOST=app.soleur.ai`, `API_HOST=api.soleur.ai` match the GHA workflow envs.
- [ ] AC3a — **Sentinel module test→server promotion.** New file `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` exports the load-bearing failure-body constants currently exported by `apps/web-platform/test/oauth-probe-contract.test.ts` (`GITHUB_OAUTH_REDIRECT_URI_SENTINEL`, `GITHUB_APP_SUSPENDED_SENTINEL`, the `authenticity_token|Sign in to GitHub|Authorize [A-Z]` regex). The test file is updated in the SAME commit to import from the new server module (preserving its current export surface for any external consumer). Zero consumer-drift window.
- [ ] AC4 — Handler files/comments on `[ci/auth-broken] Synthetic OAuth probe failed` GitHub issue via a NEW helper at `apps/web-platform/server/github/probe-octokit.ts` exporting `createProbeOctokit()`. Helper uses `@octokit/app`'s `App` constructor (already in deptree via `app-client.ts`) to mint an app-level JWT from `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` (Doppler `prd`). NO `founderId`, NO audit-writer attachment, NO `audit_github_token_use` row (probe is not founder activity; the ledger stays clean). Three operations: list-open-by-title, create-or-comment, close-on-success. Labels (`ci/auth-broken`, `priority/p1-high`) verified via `gh label list --limit 200` at Phase 0.1.
- [ ] AC5 — Handler emits a `notify-ops-email`-shape POST to Resend's HTTP API directly (no helper extraction unless ≥2 callers materialize), matching `.github/actions/notify-ops-email/action.yml:33-44` payload verbatim. Wrapped in `step.run("notify-ops-email", ...)` so Resend HTTP failures get Inngest retry. Subject preserves `[Soleur Ops] OAuth probe failure: <fail_mode>`; body preserves the 4-line HTML format. `RESEND_API_KEY` sourced from Doppler `prd` (existing secret).
- [ ] AC6 — Auto-close-stale-issue branch matches GHA workflow lines 504-526: when `failure_mode == ""` AND an open `[ci/auth-broken]` issue exists, post the canonical green-comment AND close via the `createProbeOctokit()` helper.
- [ ] AC7 — Sentry heartbeat step matches `cron-daily-triage.ts:329-371` shape: `SENTRY_DOMAIN_RE` / `SENTRY_PROJECT_RE` / `SENTRY_PUBLIC_KEY_RE` env guards; `POST https://${domain}/api/${projectId}/cron/scheduled-oauth-probe/${publicKey}/?status=${ok|error}`; `AbortSignal.timeout(10_000)`; fallback to `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`. `SENTRY_MONITOR_SLUG = "scheduled-oauth-probe"` (continuity preserved).

**Substrate-side wiring:**

- [ ] AC8 — The new function is registered in `apps/web-platform/app/api/inngest/route.ts` (line 37 — verified at deepen-plan time; current array imports `cfoOnPaymentFailed`, `cronDailyTriage`, `cronFollowThroughMonitor`, `githubOnEvent`). Sentinel: `grep -nE 'cronOauthProbe' apps/web-platform/app/api/inngest/route.ts` returns ≥1.

**Workflow deletion + GHA-side cleanup:**

- [ ] AC9 — `.github/workflows/scheduled-oauth-probe.yml` is **deleted** in this PR. `git ls-files .github/workflows/scheduled-oauth-probe.yml` returns empty. TR9 I-13 hygiene precedent: when an Inngest cron supersedes a GHA-scheduled workflow, the GHA file is deleted in the same PR. No parallel firing (would double-charge Sentry rate-limit + double-file issues).
- [ ] AC10 — Shared composite action `.github/actions/sentry-heartbeat/action.yml` is **preserved unchanged** (still consumed by 7 sister daily/weekly workflows AND by `scheduled-github-app-drift-guard.yml` until TR9 PR-4 lands). The TS function inlines the heartbeat logic instead of calling the composite.

**Sentry monitor IaC (revert PR #4207's oauth-probe bump):**

- [ ] AC11 — `apps/web-platform/infra/sentry/cron-monitors.tf` `resource "sentry_cron_monitor" "scheduled_oauth_probe"`: `checkin_margin_minutes = 360 → 30`, `failure_issue_threshold = 2 → 1`. Other fields unchanged. Header comment block rewritten to declare Inngest-fired substrate, citing TR9 PR-1/PR-2 precedent + ADR-030 + ADR-033. Sentinel: `grep -nE 'Inngest-fired|cron-oauth-probe\.ts' apps/web-platform/infra/sentry/cron-monitors.tf` returns ≥1.
- [ ] AC12 — Joint-exception breadcrumb at cron-monitors.tf:24-37 updated: oauth-probe removed from the exception list; `scheduled_github_app_drift_guard` named as the SOLE remaining `failure_issue_threshold = 2` exception with a one-line reason "(still GHA-fired hourly; TR9 PR-4 follow-up tracks the migration)". The May 21 immediate-relief comment at lines 71-77 (above oauth-probe) is deleted. The May 21 comment at lines 91-99 above drift-guard is REVISED (not deleted) to drop the joint-bump reasoning and retain only the drift-guard-specific margin justification until TR9 PR-4. Sentinel: `grep -cE 'oauth-probe and github-app|Margin bumped 30 → 360' apps/web-platform/infra/sentry/cron-monitors.tf` returns 0.

**Operator-surface doc sweep:**

- [ ] AC13 — `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` updated per the prior plan's AC14 enumeration: 10 line-pair edits at lines 5, 16, 33, 34, 41, 228, 237, 489-501. Additionally, prepend a one-line substrate-disambiguation note to the troubleshooting section: "Before debugging the probe code path, check Better Stack `inngest-heartbeat` last_alive_at via the dashboard at `https://uptime.betterstack.com/team/.../heartbeats/inngest-heartbeat` — if >2 min ago, this issue is likely a substrate-down false-positive (cross-check sibling `scheduled-daily-triage` / `scheduled-follow-through` monitors)." (This replaces the brainstorm's AC28 inline-issue-body approach with a runbook line — zero code, zero new dependency.) Sentinel: `grep -cE 'gh run list.*oauth-probe|gh workflow run scheduled-oauth-probe|scheduled-oauth-probe\.yml' knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` returns 0.
- [ ] AC14 — `knowledge-base/engineering/ops/runbooks/github-app-drift.md` line 339 (`scheduled-oauth-probe.yml` cross-reference) updated to `cron-oauth-probe` Inngest equivalent. All other references in this runbook (to `scheduled-github-app-drift-guard.yml`) are left UNCHANGED — they will be updated by TR9 PR-4 when drift-guard migrates. Sentinel: `grep -nE 'scheduled-oauth-probe\.yml' knowledge-base/engineering/ops/runbooks/github-app-drift.md` returns 0.
- [ ] AC15 — Full operator-surface sweep for oauth-probe references: `grep -rEn 'scheduled-oauth-probe\.yml|gh workflow run scheduled-oauth-probe|gh run list.*scheduled-oauth-probe' knowledge-base/engineering/ apps/web-platform/ README.md CONTRIBUTING.md 2>/dev/null | grep -v archive/ | grep -v 'knowledge-base/project/\(plans\|specs\|learnings\)/' | wc -l` returns 0. Scope exclusion preserves historical project artifacts per the May 18 plan AC10 precedent.

**Verification gates:**

- [ ] AC16 — `terraform validate` passes on `apps/web-platform/infra/sentry/`. Invocation: `cd apps/web-platform/infra/sentry && terraform init -input=false -backend=false && terraform validate`.
- [ ] AC17 — `bun run typecheck` AND `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` both pass. The new test file (sibling cron-test path verified at deepen-plan time) covers: (a) happy-path `?status=ok` heartbeat, (b) per-failure-mode `?status=error` mapping for all 8 modes, (c) fork-PR fallback (`SENTRY_INGEST_DOMAIN` empty) — logs warning, exits without throw, (d) issue-filing branch via mocked Octokit (no real network). Test runner is vitest, NOT `bun test` — `apps/web-platform/bunfig.toml` has `[test] pathIgnorePatterns = ["**"]` per the 2026-05-20 learning.
- [ ] AC18 — `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` (line 39 glob `server/inngest/functions/cron-*.ts`) auto-extends to `cron-oauth-probe.ts`. Re-run via `./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts`. Confirms no BYOK violation (handler uses no Anthropic API key).
- [ ] AC19 — PR body uses `Closes #3203` (the trap-RETURN cleanup issue resolves via workflow deletion). PR body does NOT include `Closes #3236` (already closed by PR #3811 per prior plan AC21) and does NOT include `Closes #3750` (drift-guard stays GHA until TR9 PR-4 ships; cross-workflow JWT-mint dedup target only dissolves then). The TR9 PR-4 follow-up filing (AC26) cites #3750 as a candidate close-target for that PR's review.

**New scope addition (post-merge detection contract):**

- [ ] AC20 — **Post-merge detection contract.** Within 24h of merge, run ONE synthetic-failure injection against a **non-prd surface** to verify the dispatch path lights up end-to-end. Mechanism:
  1. Spin up a local Inngest dev server (`inngest dev`) on the operator's machine OR a feature-flagged preview deploy.
  2. Run the new TS function against a fixture URL (e.g., `https://httpbin.org/status/500` or a static-HTML fixture file) that returns a canonical failure-body sentinel — accomplished by **temporarily overriding `APP_HOST` via env-var in the dev shell** (`APP_HOST=https://httpbin.org bun run dev`), NOT via a handler input.
  3. Verify within 90s: (a) `?status=error` heartbeat to a Sentry dev project (or stubbed), (b) `[ci/auth-broken]` issue filed via Octokit against a test repo (or skipped if mocked), (c) Resend webhook captured.
  4. Operator records function-run ID + verification outcome in the PR body's post-merge checklist.

  **The prd handler has ZERO fixture-injection plumbing** — no `event.data.overrideHost` input, no in-handler prd-vs-dev branching. The override is purely env-var driven, scoped to the dev shell, and never reaches the prd Doppler config. This addresses Kieran's plan-review finding that the brainstorm's `overrideHost`/prd-rejection-gate design was incoherent.

  Verification CAN be automated post-deploy via `/soleur:ship` Phase 5.5; if /work-time agent can't access a local Inngest dev server, defer this verification to ship-time and document in PR body.

### Post-merge (auto + verification)

- [ ] AC21 — **Auto:** push to `main` triggers two auto-apply flows:
  1. `apps/web-platform/infra/sentry/cron-monitors.tf` change auto-applied via `.github/workflows/apply-sentry-infra.yml` (paths filter matches). The `sentry_cron_monitor.scheduled_oauth_probe` resource is updated in-place. **Pre-apply sanity gate** (per `2026-05-18-infra-validation-pathspec-silent-zero-match.md`): verify the apply-sentry-infra workflow actually ran on this PR's diff (`gh run list --workflow=apply-sentry-infra.yml --json conclusion,headBranch --jq '.[] | select(.headBranch == "main") | .conclusion'` returns `success`, NOT `skipped`).
  2. The new Inngest function is included in the Next.js production build and discovered by the Hetzner Inngest server via `/api/inngest` introspection on first POST-deploy boot. No operator action.
- [ ] AC22 — **Auto, T+90 min:** the first scheduled Inngest fire of `cron-oauth-probe` posts `?status=ok` to Sentry. Verification (per `hr-no-dashboard-eyeball-pull-data-yourself`): `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-oauth-probe/checkins/?limit=5" | jq -r '.[] | "\(.dateCreated) \(.status)"'` shows a recent `ok` check-in (≤90 min ago — covers the up-to-1-hour interval + Inngest's ≤2-min jitter). Today's verification proved this works for sibling Inngest monitors.
- [ ] AC23 — **Auto, T+24h:** recurring Sentry issue `a94c4ec23f654101a7fc4491b16a560c` auto-resolves on first successful check-in (`recovery_threshold = 1`). Verification: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/issues/a94c4ec23f654101a7fc4491b16a560c/" | jq -r '.status'` returns `resolved`.
- [ ] AC24 — **Operator (post-merge synthetic-failure injection per AC20):** within 24h of merge, the operator (or `/soleur:ship` post-merge step) runs the AC20 fixture injection and records function-run ID + Sentry-checkin verification timestamp in the PR body. If full automation is impossible without a local Inngest dev server, defer to ship-time and document accordingly.
- [ ] AC25 — **File TR9 PR-4 follow-up issue** within 48h of merge: `chore(infra): TR9 PR-4 — migrate scheduled-github-app-drift-guard to Inngest cron substrate`. Labels: `code-review`, `priority/p2-medium`, `domain/engineering` (verified via `gh label list --limit 200`). Body cites: (a) this PR's pattern as the template, (b) drift-guard's heavier surface (12+ failure modes vs 8, JWT minting via `@octokit/app`'s `App` constructor, manifest-diff via either TS reimplementation or `bin/diff-github-app-manifest.sh` shell-out, three label classes including `[security/leak-suspected]`), (c) candidate `Closes #3750` for that PR (mint-app-jwt extraction's cross-workflow dedup target dissolves once drift-guard moves off GHA), (d) the elevated brand-survival threshold inherited from drift-guard's own workflow header (lines 5-12 of `.github/workflows/scheduled-github-app-drift-guard.yml`).

### Pre-merge (#4116 cascade self-check)

Run the six self-check questions from `2026-05-19-inngest-substrate-five-bug-cascade.md` BEFORE marking the PR ready:

- [ ] **CQ1** — `PUBLIC_PATHS` includes `/api/inngest`. Verify via grep.
- [ ] **CQ2** — `INNGEST_SIGNING_KEY` Doppler value has prefix `signkey-prod-*` in prd config. Verify via `doppler secrets get INNGEST_SIGNING_KEY -p soleur -c prd --plain | head -c 14`.
- [ ] **CQ3** — Hetzner Inngest server's `inngest-server.service` systemd unit has `User=deploy` and file ownership matches.
- [ ] **CQ4** — `inngest-server.service` `ReadWritePaths=` includes the SQLite db path.
- [ ] **CQ5** — Env source-of-truth is Doppler `prd`.
- [ ] **CQ6** — Better Stack `inngest-heartbeat` monitor is **unpaused** before declaring GREEN.

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitors.tf` — AC11 + AC12 changes: revert PR #4207's oauth-probe bump; rewrite header comment; update joint-exception breadcrumb at lines 24-37; delete May 21 oauth-probe comment at lines 71-77; revise (not delete) the May 21 drift-guard comment at lines 91-99 to drop the joint-bump reasoning.
- `apps/web-platform/app/api/inngest/route.ts` — line 37 array extended to include `cronOauthProbe` import (per AC8).
- `apps/web-platform/test/oauth-probe-contract.test.ts` — refactor: import sentinel constants from the new `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` module instead of defining them inline; preserve existing export surface (AC3a).
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — AC13 (10 line-pair edits + Better Stack disambiguation note).
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md` — AC14 (line 339 only — oauth-probe cross-reference).

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — ~250 LoC (8 failure modes, heartbeat, Octokit issue, Resend email).
- `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` — ~20 LoC sentinel constants + regex.
- `apps/web-platform/server/github/probe-octokit.ts` — ~40 LoC: `createProbeOctokit()` factory using `@octokit/app`'s `App` constructor, no audit-writer attachment, no `founderId`.
- `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` — ~150 LoC, per AC17.

## Files to Delete

- `.github/workflows/scheduled-oauth-probe.yml` (540 LoC) — per AC9.

## Open Code-Review Overlap

Two open code-review issues touch the affected surfaces. Plan-time `gh issue list --label code-review --state open` + path grep:

- **#3203: review: extract trap RETURN cleanup pattern in scheduled-oauth-probe (P3)** — **Resolved by deletion.** The `trap RETURN` bash pattern lives in `scheduled-oauth-probe.yml` which is deleted by AC9. TS `try/finally` blocks in the Inngest handler handle equivalent cleanup. PR body adds `Closes #3203`.
- **#3750: review: Extract mint-app-jwt composite action (deduplicate ~85 LoC across drift-guard + ruleset-audit workflows)** — **Defer to TR9 PR-4.** Both consumers (drift-guard + ruleset-audit) remain on GHA in this PR; the cross-workflow dedup target is still relevant. AC25's TR9 PR-4 follow-up issue cites #3750 as a candidate close-target for that PR.
- **#4211 (this issue, parent)** — self-referential.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — all three fired in brainstorm Phase 0.5 per `USER_BRAND_CRITICAL=true`. Sales/Marketing/Finance/Support/Operations: NONE.

**Brainstorm-recommended specialists:** none beyond the triad.

**Plan-review applied:** DHH + Kieran + Code Simplicity reviewers all spawned post-plan-draft. Convergent verdict applied: scope reverted to single-probe (Code Simplicity), AC27 cut (DHH + Code Simplicity), AC28 cut (DHH + Code Simplicity), AC4/AC9 factual fixes (Kieran), AC3a reworded (Kieran). User selected "Full apply: split + cut AC27/28".

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward + plan-review reshape).
**Assessment:** Threshold elevation to `single-user incident` holds. AC20 (post-merge detection contract) retained from brainstorm's AC26 but reshaped per Kieran's plan-review finding: prd code path has zero fixture-injection plumbing; injection is env-var-driven in dev shell only. CPO sign-off REQUIRED at plan time before `/work` begins (per `requires_cpo_signoff: true` in frontmatter).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward + plan-review reshape).
**Assessment:**
- Brainstorm's AC27 (pre-deletion local `inngest dev` gate) **dropped** per plan-review verdict — local dev doesn't exercise the prd substrate. Real cutover gate is AC22 (first scheduled fire posts ok); rollback contract in Risks #1.
- Brainstorm's AC28 (Better Stack heartbeat in issue body) **dropped** per plan-review verdict — replaced by AC13 runbook line (zero new code, zero new dependency).
- Brainstorm's AC4 helper choice **corrected** per Kieran's plan-review — `app-client.ts` is wrong-shaped; new `createProbeOctokit()` factory at `apps/web-platform/server/github/probe-octokit.ts`.

Substrate-failure mode added: if Inngest server is down, the probe doesn't fire. Compensating signals: `inngest-heartbeat.timer` to Better Stack (60s), sibling Inngest monitors (`scheduled-daily-triage`, `scheduled-follow-through`) ALSO depend on substrate liveness. Substrate-vs-probe disambiguation in operator runbook (AC13).

Same-commit deletion safe: shadow-fire overlap would double-charge Sentry. Prior plan AC9 rationale stands.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** **Carry-forward only.** Article-30 register PA 13 covers the self-hosted Inngest substrate. The new `createProbeOctokit()` helper does NOT write to `audit_github_token_use` (probe is not founder activity); the audit ledger's Article 30 PA-16 scope is preserved. GDPR-gate non-triggered per Phase 2.7 analysis (see below).

## GDPR / Compliance Gate

**Phase 2.7 mechanical trigger fires** because brand-survival threshold is `single-user incident` (trigger (b)). **However:** CLO carry-forward at brainstorm Phase 0.5 verified the substrate change is data-flow-neutral. The probe processes no user data; credentials read are public-tier identifiers; Article-30 PA 13 already covers the substrate.

**Gate verdict:** Skip per CLO sign-off. The mechanical trigger is the right safety net but admits an explicit override here — consequence severity does not backfill a data-flow that doesn't exist. The new `createProbeOctokit()` helper explicitly omits audit-writer attachment, so the probe stays out of the audit ledger (Article 30 PA-16 scope preserved).

Phase 2.7 trigger taxonomy:
- Canonical regex: NO match (TS file under server/inngest, TF monitor resource, runbooks, workflow deletion).
- (a) LLM/external-API on operator data: NO.
- (b) Threshold `single-user incident`: YES (mechanical trigger fires).
- (c) Cron reads from learnings/specs: NO.
- (d) New artifact distribution: NO.

**Override rationale:** trigger (b) fires on consequence-severity; CLO verified data-flow is neutral. Skip gate explicitly.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`:
  - `sentry_cron_monitor.scheduled_oauth_probe`: `checkin_margin_minutes = 360 → 30`, `failure_issue_threshold = 2 → 1`. Header comment rewritten.
  - Joint-exception breadcrumb (lines 24-37): oauth-probe removed; drift-guard remains as sole `threshold = 2` exception until TR9 PR-4.
  - Transitional comment at lines 71-77 (May 21 oauth-probe bump): deleted.
  - Transitional comment at lines 91-99 (May 21 drift-guard bump): revised to drop joint-bump reasoning; retained drift-guard-specific until PR-4.

No new providers, no new sensitive variables, no new state-storage.

### Apply path

(a) pure Terraform state-update on the existing `scheduled_oauth_probe` resource. Apply path: `.github/workflows/apply-sentry-infra.yml` triggers on push-to-main with paths filter on `apps/web-platform/infra/sentry/**`. Expected change: one in-place attribute update. Expected downtime: 0.

### Distinctness / drift safeguards

- `dev != prd`: Sentry monitors in `web-platform` project only. N/A.
- `lifecycle.ignore_changes`: not applied.
- State-storage: R2 backend per `backend.tf`.

### Vendor-tier reality check

- Sentry billing: in-place update on existing seat. No PAYG impact.
- Inngest substrate: one new function on existing self-hosted server. No new vendor cost. Cron-platform concurrency cap extends (AC1).

## Observability

```yaml
liveness_signal:
  what: Sentry cron-monitor heartbeat for `scheduled-oauth-probe` slug
  cadence: every 1 h (matches Inngest cron `0 * * * *`)
  alert_target: Sentry monitor `scheduled-oauth-probe` (failure_issue_threshold=1, recovery_threshold=1) — recurring Sentry issue `a94c4ec23f654101a7fc4491b16a560c` auto-resolves on first ok; future drifts open new fingerprint
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (post-AC11)
error_reporting:
  destination: Sentry (via `reportSilentFallback` per cq-silent-fallback-must-mirror-to-sentry); secondary destinations = (a) `[ci/auth-broken] Synthetic OAuth probe failed` GitHub issue via createProbeOctokit (AC4), (b) Resend ops-email to ops@jikigai.com per AC5
  fail_loud: yes — `step.run("probe", ...)` errors bubble to Inngest's run-failure stream; ADR-033 I5 return shape deterministic so structural regressions surface at typecheck time
failure_modes:
  - mode: substrate-down (Inngest server unreachable)
    detection: inngest-heartbeat.timer Better Stack heartbeat miss within 60s + Sentry missed-checkin on `scheduled-oauth-probe` within 30-min margin; sibling Inngest monitors (`scheduled-daily-triage`, `scheduled-follow-through`) ALSO miss within their margins (substrate-down inferred from cross-monitor correlation)
    alert_route: Better Stack email + Sentry email; operator runbook (AC13) directs to Better Stack heartbeat dashboard for sub-60-min disambiguation
  - mode: probe-detection regression (real auth-flow failure)
    detection: handler returns failureMode != ""; createProbeOctokit files/comments `[ci/auth-broken] Synthetic OAuth probe failed`; Resend email; `?status=error` Sentry heartbeat
    alert_route: GitHub issue + Resend + Sentry
  - mode: Sentry heartbeat curl failure (e.g., revoked SENTRY_PUBLIC_KEY)
    detection: `reportSilentFallback` mirrors to Sentry under `feature: "cron-sentry-heartbeat"`; probe itself returned ok, but monitor shows missed-checkin
    alert_route: same Sentry monitor surface; silent-fallback breadcrumb reveals curl failure
  - mode: probe times out (>5 min)
    detection: `step.run("probe", { timeout: "5m" }, ...)` aborts; Inngest emits failure; `?status=error` heartbeat
    alert_route: same as probe-detection regression
logs:
  where: Inngest server `journalctl -u inngest-server.service` on Hetzner VM (per #4116 — no remote log aggregation yet; local-only)
  retention: systemd default (~7 days at current write rate)
discoverability_test:
  command: |
    curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
      "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-oauth-probe/checkins/?limit=5" \
      | jq -r '.[] | "\(.dateCreated) \(.status) (expected \(.expectedTime))"'
  expected_output: 5 most recent check-ins, each `ok` status, dateCreated within 1-2 min of expectedTime (Inngest deterministic firing, ≤2-min jitter validated today against `scheduled-daily-triage` and `scheduled-follow-through`)
```

## Test Strategy

1. **TypeScript unit tests** (AC17) — per-failure-mode `?status=error` mapping; happy-path `?status=ok`; fork-PR fallback; issue-filing branch via mocked Octokit. One new test file (~150 LoC) at `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts`. Run via vitest.
2. **Compile + register gate** (AC8, AC17) — `bun run typecheck` + grep on the function-registry. Without registration, the function is dead code.
3. **Cron-no-BYOK gate** (AC18) — glob auto-extends; enforces ADR-033 I2.
4. **`terraform validate`** (AC16) — covers cron-monitor schema changes.
5. **Post-merge synthetic-failure injection** (AC20, AC24) — non-prd verification of canary-still-squawks contract.
6. **First-post-merge fire as live contract** (AC22) — Sentry checkins API IS the assertion.

No new test infrastructure beyond the one new test file.

## Risks

1. **Inngest function registration fails post-deploy.** Build ships, Inngest server polls `/api/inngest`, function appears in registry. If discovery silently fails (route.ts typo, dead-code elimination, deploy cache miss), the probe is dark for up to 90 min until AC22 verification catches it. **Rollback contract:** if AC22 misses by T+90 min, hotfix PR restores `.github/workflows/scheduled-oauth-probe.yml` from `git show HEAD~1:.github/workflows/scheduled-oauth-probe.yml > .github/workflows/scheduled-oauth-probe.yml && git add . && git commit -m "Revert: TR9 PR-3 cutover; restore GHA fallback" && git push`. The PR-4 retry must reproduce the registration failure in `inngest dev` first.
2. **`createProbeOctokit()` helper diverges subtly from the existing `createGitHubAppClient()`.** The two helpers serve different scopes (probe vs founder); accidental import of the wrong one in a future change would either pollute the audit ledger (probe using founder factory) or break installation-scoped flows (founder using probe factory). **Mitigation:** distinct file paths (`probe-octokit.ts` vs `app-client.ts`), distinct factory names, jsdoc warnings on each.
3. **Substrate-cost.** Probe consumes ~1 min CPU per hour = trivial. No PAYG impact.
4. **`oauth-probe-contract.test.ts` refactor breaks tests.** AC3a moves sentinels from test→server. **Mitigation:** the test re-exports them from the new server module to preserve any external consumer; vitest re-run (AC17) catches any regression.
5. **TR9 PR-4 (drift-guard) doesn't ship promptly.** While drift-guard remains on GHA, its monitor stays at margin=360 / threshold=2 (decorative). Real auth-flow drift takes up to 6h to surface via Sentry but DOES surface via the existing `[ci/auth-broken]` issue path (workflow lines 424-490). **Acceptable** for the 1-2 week lead-time on PR-4.
6. **`apps/web-platform/server/github/app-client.ts` env names assumed.** AC4 specifies `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` from Doppler `prd`. Phase 0.1 verifies these exist in `doppler secrets list -p soleur -c prd`.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty or contains `TBD`/`TODO` will fail `deepen-plan` Phase 4.6.** This plan's section is filled.
- **Same-commit workflow deletion under elevated threshold is safe** because: (a) prior PRs #3985 + #4062 proved the cutover pattern, (b) AC22 first-fire verification covers the cutover window, (c) Risks #1 rollback contract has a 1-command revert. The brainstorm's AC27 pre-deletion gate was cut per plan-review — local `inngest dev` doesn't exercise prd substrate, so the gate was theater.
- **Brainstorm AC28 (Better Stack disambiguation in issue body) was cut per plan-review.** Replaced by AC13 runbook line: "Before debugging the probe code path, check Better Stack `inngest-heartbeat` last_alive_at." Zero code, zero new dependency. If a future incident proves substrate-vs-probe ambiguity actually bites at the issue-triage-time threshold, re-evaluate.
- **The brainstorm doc + spec.md committed earlier (2-of-3 reviewer-flagged ACs included) are now stale.** Brainstorm: update with `[Updated 2026-05-21]` marker reflecting the plan-review scope revision (single-probe + AC27/AC28 cut). Spec.md: update FR2 (drift-guard) to "deferred to TR9 PR-4 per plan-review verdict". /work-time agent: read THIS plan as source of truth; the brainstorm + spec inherit the revisions.
- **The TR9 PR-4 follow-up (AC25) preserves the drift-guard's "Brand-survival threshold: single-user incident" framing** explicitly in the issue body. /soleur:ship Phase 5.5 files this issue automatically if the operator hasn't done so manually.
- **`scheduled-cf-token-expiry-check.yml` (the "9th workflow" referenced at cron-monitors.tf:73-85) is NOT in scope.** Its `schedule:` block is commented out today; AC11 does not touch it.
- **Operator-surface doc sweep (AC15) excludes `knowledge-base/project/{plans,specs,learnings}/**` AND `**/archive/**`** per May 18 plan AC10 precedent — historical record retains references to the deleted workflow filename.
- **Cron concurrency cap key is `'"cron-platform"'` (literal-string-in-string).** Per `cron-daily-triage.ts:391`. AC1 includes verbatim. Typos here are silent (two cron-* fns running concurrently never throws but bypasses F7 OOM guard).
- **`infra-validation` workflow pathspec silent-zero-match.** AC21's sanity gate verifies the workflow actually ran on this PR's diff. If `validate: SKIPPED`, manually run `terraform plan` against the changed monitor.
- **`apps/web-platform/bunfig.toml` has `[test] pathIgnorePatterns = ["**"]`** per the 2026-05-20 learning. Test runs use `./node_modules/.bin/vitest run <path>`, NOT `bun test <path>`. AC17/AC18 invocation forms reflect this.
- **The `createProbeOctokit()` helper deliberately omits audit-writer attachment.** This is the load-bearing distinction from `createGitHubAppClient()`. Do not "fix" this at /work-time by adding the audit-writer back — it would pollute the audit ledger with synthetic-probe entries that Article 30 PA-16 does not authorize.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-21-feat-tr9-pr3-oauth-probe-drift-guard-inngest-plan.md. Branch: feat-tr9-pr3-oauth-probe-drift-guard-inngest-4211. Worktree: .worktrees/feat-tr9-pr3-oauth-probe-drift-guard-inngest-4211/. Issue: #4211. PR: #4227. Brand-survival threshold: single-user incident. requires_cpo_signoff: true. Scope: oauth-probe only (drift-guard deferred to TR9 PR-4 per plan-review). Plan absorbs prior deepened plan + 1 brainstorm-derived AC (AC20 — non-prd detection contract). Implementation next.
```
