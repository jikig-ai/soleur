---
title: "feat(runtime): TR9 PR-4 — migrate scheduled-github-app-drift-guard to Inngest cron substrate"
date: 2026-05-22
type: feat
classification: ci-ops
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-tr9-pr4-drift-guard-inngest-4235
issue: 4235
draft_pr: 4303
parent_umbrella: 3948
precedents_prs: [3985, 4062, 4227]
precedents_issues: [3948, 4017, 4079, 4211]
sibling_pr: 4227
sibling_pr_status: MERGED 2026-05-21 (oauth-probe — the verified pattern this PR mirrors verbatim; closes parent issue #4211)
prs_resolved_at_deepen: |
  Plan body inadvertently cited issue numbers as "PR #N" in spots (#4211, #3187, #4115, #4179, #3244). At deepen-plan Phase 4 verification:
  - #4211 = ISSUE (CLOSED) — oauth-probe migration parent. Actual MERGED PR is #4227.
  - #3187 = ISSUE (CLOSED) — drift-guard parent. Actual MERGED PR is #3224.
  - #4115 = ISSUE (CLOSED) — manifest-as-IaC parent. Actual MERGED PR is #4121.
  - #4179 = ISSUE (CLOSED) — installation-grant diff parent. Actual MERGED PR is #4180.
  - #3244 = ISSUE (CLOSED) — Command Center umbrella. Actual MERGED PR is #3940 (PR-F substrate).
  - #3750 = ISSUE (OPEN) — mint-app-jwt composite extraction. Closes via this PR.
  - #3948 = ISSUE (OPEN) — TR9 umbrella. NOT closed by this PR.
  Throughout the plan, prose references to these as "PR #N" are corrected to "issue #N" where appropriate; "PR-3" / "PR-4" remain as PR labels because they refer to the TR9 sequence position, not a number.
brainstorm: knowledge-base/project/brainstorms/2026-05-21-tr9-pr3-oauth-probe-drift-guard-inngest-brainstorm.md
brainstorm_carry_forward: yes — same triad framing (CPO/CTO/CLO single-user-incident threshold) as PR-3 brainstorm; drift-guard scope explicitly deferred by PR-3 plan-review and re-activated here.
spec: knowledge-base/project/specs/feat-one-shot-tr9-pr4-drift-guard-inngest-4235/spec.md
scope: drift-guard only (oauth-probe shipped in PR #4227, closing parent issue #4211)
related_workflows:
  - .github/workflows/scheduled-github-app-drift-guard.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
  - .github/workflows/apply-sentry-infra.yml
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/github-app-drift.md
  - knowledge-base/engineering/operations/runbooks/github-app-provisioning.md
related_test_files:
  - apps/web-platform/test/github-app-drift-guard-contract.test.ts
  - apps/web-platform/test/github-app-manifest-drift-guard.test.ts
related_helpers:
  - bin/diff-github-app-manifest.sh
related_issues: [3750, 3187, 4115, 4179]
followup_close_target: 3750
prior_learnings:
  - knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md
  - knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md
  - knowledge-base/project/learnings/bug-fixes/2026-05-20-inngest-heartbeat-doppler-env-injection.md
  - knowledge-base/project/learnings/integration-issues/2026-05-18-infra-validation-pathspec-silent-zero-match.md
  - knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md
  - knowledge-base/project/learnings/best-practices/2026-04-18-drift-guard-self-silent-failures.md
prior_prs: [3985, 4062, 4207, 4211]
---

# feat(runtime): TR9 PR-4 — migrate `scheduled-github-app-drift-guard` to Inngest cron substrate

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** 4 (Research Reconciliation, Acceptance Criteria, Risks, Sharp Edges)
**Verification gates run:** Phase 4.6 (User-Brand Impact) PASS · Phase 4.7 (Observability) PASS · Phase 4.8 (PAT-shaped var) PASS · KB-ref live check PASS (spec.md is the only missing path; created by /work) · AGENTS.md rule citation check PASS (`cq-silent-fallback-must-mirror-to-sentry`, `hr-no-ssh-fallback-in-runbooks`) · GitHub label existence check PASS (7/7 labels exist).

### Key Improvements

1. **PR-vs-issue disambiguation applied** (per AGENTS.md learning `2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`). Frontmatter now distinguishes `precedents_prs` vs `precedents_issues`. Body retains TR9 PR-N labels but corrects 5 "PR #N" → "issue #N" attributions where the cited N is an issue.
2. **`@octokit/auth-app` JWT extraction shape verified** against installed `apps/web-platform/node_modules/@octokit/auth-app/dist-types/types.d.ts:101-105` (`AppAuthentication.token: JWT`). AC4 + AC6 now specify the exact call pattern: `const auth = await app.octokit.auth({ type: "app" }) as AppAuthentication; const jwt = auth.token;`.
3. **`jq` availability on Hetzner Inngest VM CONFIRMED** at `apps/web-platform/infra/cloud-init.yml:6` (cloud-init `packages:` list). AC0.2 dependency-gate is GREEN at plan-time; no Terraform edit required.
4. **Cron-monitors.tf line-range claims re-verified** against current state — header narrative lines 24-41, drift-guard resource at 107-117, joint-exception breadcrumb at lines 25-31. AC16/AC17/AC18 line ranges match.

### New Considerations Discovered

- **Leak-tripwire defense surface SHRINKS in the TS port, not just changes shape.** In GHA, the tripwire scanned `tee -a step-output.log` which captured EVERY echo/printf/openssl output inside the bash script. In Node.js, `assertNoLeak` only fires at emit-sites the developer routes through it — there is no implicit capture surface. The new defense is structurally narrower; the AC24(e) test must also cover the absence of any unguarded emission path. Added to Sharp Edges.
- **`reportSilentFallback` is the cited fallback per `cq-silent-fallback-must-mirror-to-sentry`.** Verified against `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts:33` — pattern is `import { reportSilentFallback } from "@/server/observability";` and used inside catch blocks for the heartbeat fetch. PR-4 inherits this pattern verbatim.
- **The `App.octokit.auth({ type: "app" })` call is async + factory-internal.** Returning `{ octokit, appJwt }` from `createAppJwtOctokit()` requires awaiting the auth call. The factory becomes `async`; consumers must `await createAppJwtOctokit()`. Clarified in AC4.
- **`@octokit/core` is NOT a direct dep of `apps/web-platform/package.json`** (only `@octokit/app` + `@octokit/auth-app`). `cron-oauth-probe.ts:31` imports `Octokit` from `@octokit/core` — this works because `@octokit/app` re-exposes it transitively. PR-4 handler should use the `app.octokit` instance returned by the factory rather than importing `@octokit/core` directly.

---

## Summary

The fourth migration in the TR9 (`cron lives in Inngest, not GH Actions`) sequence. Migrates the hourly GitHub-App drift-guard onto the self-hosted Inngest cron substrate (Hetzner VM), matching PR-1 (#3985 `cron-daily-triage`, MERGED), PR-2 (#4062 `cron-follow-through-monitor`, MERGED), and PR-3 (#4211 `cron-oauth-probe`, MERGED). PR #4207's immediate-relief margin bump (`scheduled_github_app_drift_guard`: 180 → 360, threshold 1 → 2) is reverted; the monitor returns to 30-min margin + `failure_issue_threshold = 1` honest signal — restoring the framing the drift-guard workflow's own header (lines 5-12) has always declared.

**Scope:** drift-guard only. oauth-probe shipped in PR #4227 (MERGED 2026-05-21, closing parent issue #4211); this PR ships the paired sibling using the verified PR-3 pattern. The PR-3 plan-review verdict that bundling doubles cutover blast radius under elevated threshold is honored — single-probe scope.

**Brand-survival threshold: `single-user incident`** (inherited from the drift-guard workflow's own header lines 5-12 verbatim, NOT a new judgment). A silent GitHub-App swap means every founder sign-in routes to a different App's consent screen — one user's broken sign-in IS the brand-ending incident. The drift-guard is the canary that detects that swap before founders see a broken consent screen.

**Heavier surface than oauth-probe** (per the issue body and PR-3 plan-review's scope-split rationale):

- 12+ failure modes vs PR-3's 8 (`missing_app_id`, `app_id_not_numeric`, `missing_expected_client_id`, `missing_private_key`, `pem_b64_decode_failed`, `pem_shape_invalid`, `jwt_mint_failed`, `jwt_mint_empty`, `github_api_network`, `github_app_401`, `github_api_http`, `github_api_invalid_json`, `github_api_missing_fields`, `app_id_mismatch`, `client_id_mismatch`, `permission_drift`, `permission_unexpected_grant`, `response_shape_unparseable`, `manifest_diff_unknown_mode`, `installation_api_http`, `installation_list_truncated`, `installation_list_shape_unparseable`, `installation_permission_drift`, `installation_unexpected_grant`, `installation_response_shape_unparseable`, `installation_diff_unknown_mode`).
- JWT minting via `@octokit/app`'s `App` constructor (already a transitive dep — no new package).
- Manifest-diff via `child_process.spawn` of the existing `bin/diff-github-app-manifest.sh` (reused verbatim; the contract test `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` exercises that script directly and SURVIVES this PR unchanged).
- **Three label classes** (vs PR-3's one): `[ci/auth-broken]` (drift detected), `[ci/guard-broken]` (guard malfunctioned), `[security/leak-suspected]` (log scan suggests credential leak).
- **Leak tripwire** has no analogue in oauth-probe — must be ported as a TS post-step controller scanning captured per-step output.

### Research Insights (added at deepen-plan)

**Best Practices:**

- The PR-3 plan-review at `knowledge-base/project/plans/2026-05-21-feat-tr9-pr3-oauth-probe-drift-guard-inngest-plan.md` is the authoritative pattern. PR #4227 (the merged execution) closed parent issue #4211 cleanly with no review-time fix-ups to the helper-boundary design — the pattern is verified.
- AGENTS.md learning `2026-05-20-plan-vs-shipped-reality-check-and-octokit-factory-audit.md` cautions: factory-boundary instrumentation (audit-writer hooks attached at `app-client.ts`'s factory) is the correct architectural place for audit-writes. The drift-guard MUST NOT inherit those hooks. The new `createAppJwtOctokit()` deliberately skips them.
- AGENTS.md learning `2026-05-20-manifest-as-iac-with-shared-diff-script-contract.md` validates the `child_process.spawn` choice over TS reimplementation: the script IS the contract; duplicating logic forces drift.
- AGENTS.md learning `2026-05-19-inngest-substrate-five-bug-cascade.md` — the six-question self-check (CQ1-CQ6) is mandatory before declaring GREEN.

**Edge Cases:**

- The `MANIFEST_DRIFT_SUPPRESS_UNTIL` regex (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`) MUST be ported byte-for-byte. The 30-day cap (`30 * 24 * 3600`) is load-bearing — without it, a compromised PR could ship `9999-12-31T23:59:59Z` and silently disable drift detection forever. The defense-in-depth check rejects timestamps beyond cap (loud warn + diff runs anyway).
- Installation iteration uses `?per_page=100`. Today's state is 1 install, so pagination is decorative — but `installation_list_truncated` MUST still fire on `Link: rel="next"` because installation count is unbounded over time. Octokit's `response.headers.link` provides the header verbatim.
- Octokit's `@octokit/auth-app` returns `AppAuthentication.token` as the raw JWT string. Verified at `apps/web-platform/node_modules/@octokit/auth-app/dist-types/types.d.ts:101-105`. The factory returns this JWT alongside the Octokit so the leak tripwire (AC6) can assert it is never echoed.

**References:**

- `apps/web-platform/node_modules/@octokit/app/dist-types/index.d.ts:9,53` — `App` constructor + `octokit` getter.
- `apps/web-platform/node_modules/@octokit/auth-app/dist-types/types.d.ts:69,101` — `AppAuthOptions` + `AppAuthentication` types.
- `apps/web-platform/infra/cloud-init.yml:6` — `jq` package install (AC0.2 pre-verified at deepen-plan).
- Sibling pattern: `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts:29-34` (probe-octokit imports + sentinel imports).

**Helper choice:** the PR-3 helper at `apps/web-platform/server/github/probe-octokit.ts` (`createProbeOctokit()`) is **NOT reused as-is**. It returns an installation-scoped Octokit; the drift-guard's primary surface is `GET /app` and `GET /app/installations` which require the **app-level JWT directly** (no installation token). A second factory `createAppJwtOctokit()` is added to the same file — same `@octokit/app` `App` constructor, but returns the app-level Octokit (`app.octokit`) without installation discovery, and additionally exposes the raw JWT for the leak-tripwire scan to assert it never appears in step output.

CLO carry-forward: Article-30 PA 13 (self-hosted Inngest, PR-F #3244) already covers the substrate; PA-16 (audit ledger) is preserved by the helper NOT attaching an audit-writer (mirror of PR-3 verdict). No DPA addendum.

## User-Brand Impact

**If this lands broken, the user experiences:** an undetected GitHub-App swap, an undetected permission-scope creep, or an undetected installation-grant divergence. The drift-guard is the early-warning system that surfaces App-level identity drift BEFORE a founder's sign-in routes to the wrong consent screen. If the new Inngest function registers but doesn't fire, doesn't detect, or posts `?status=ok` heartbeats while the underlying App identity has been swapped, the founder discovers the outage when their OAuth sign-in lands on a stranger's consent screen — not when the canary squawks. Three failure classes are in scope: identity-swap (`app_id_mismatch`, `client_id_mismatch`, `github_app_401`), manifest drift (`permission_drift`, `permission_unexpected_grant`), installation drift (`installation_permission_drift`, `installation_unexpected_grant`).

**If this leaks, the user's data/workflow/money is exposed via:** N/A on data flow. The drift-guard processes no user data; credentials read are the operator's GitHub App private key (already in Doppler `prd`, already a privileged secret). The exposure surface is *detection-quality + credential-leakage-via-log*, NOT data-confidentiality. The leak tripwire is a meta-defense: if the operator's PEM ever leaks into step output via a future refactor's `echo` mistake, the tripwire fires `[security/leak-suspected]` BEFORE the run log is archived publicly. This PR preserves that tripwire's load-bearing role.

**Brand-survival threshold:** `single-user incident`.

- **threshold: single-user incident, reason:** silent failure of the drift-guard collapses the operator's earliest-warning signal for App-identity regressions. A botched migration silently disables detection AND removes the leak tripwire — losing both an auth-canary AND a credential-leak detector in one cutover. The drift-guard workflow's own header (`.github/workflows/scheduled-github-app-drift-guard.yml` lines 5-12) declares this threshold explicitly; PR-4 inherits it verbatim.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body / brainstorm / sibling PR-3 pattern) | Reality (grep + `gh` verified at plan time) | Plan response |
| --- | --- | --- |
| "Reuse `createProbeOctokit()` from PR-3 verbatim" (issue body line: "the helper at `apps/web-platform/server/github/probe-octokit.ts` is reused (no audit-writer attachment)") | `createProbeOctokit()` returns an installation-scoped Octokit (`app.getInstallationOctokit(installation.id)`). Drift-guard's PRIMARY surface (`GET /app`, `GET /app/installations`) requires the **app-level JWT** directly. Installation-scoped Octokit cannot reach `/app`. | **Add a SECOND factory** `createAppJwtOctokit()` to the same file, exporting `{ octokit, appJwt }` (where `octokit = app.octokit` and `appJwt` is the raw JWT for leak-tripwire assertion). Reuses the existing `readEnv()` + env-name constants. Installation iteration uses `octokit.request("GET /app/installations")` — same JWT, no installation-token mint. This preserves the issue body's "reuse the helper file" intent while honoring the API-shape reality. The original `createProbeOctokit()` is preserved unchanged for the oauth-probe issue-filing path. |
| "Manifest-diff: either TS reimplementation OR `child_process.spawn` of `bin/diff-github-app-manifest.sh`" (issue body) | `bin/diff-github-app-manifest.sh` is 153 LoC, contract-tested by `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` (six-case matrix per the test header). Reimplementing in TS would duplicate the contract; spawning preserves single source of truth AND keeps the contract test unchanged. | **`child_process.spawn` chosen.** Handler spawns `bash bin/diff-github-app-manifest.sh` with `MANIFEST_FILE` + `RESPONSE_FILE` env vars, wraps in `step.run("manifest-diff", ...)` so spawn failures get Inngest retry. The contract test file `github-app-manifest-drift-guard.test.ts` is touched ONLY in its header comment (PR-4 reference); test body unchanged. **Sharp edge:** the Hetzner Inngest VM must have `jq` + `bash` installed; verified at Phase 0.4 via `ssh-less` Doppler/systemd inspection. If missing, Phase 0 task = file a Terraform `runcmd` line; do NOT prescribe a manual `apt install`. |
| "JWT minting via `@octokit/app`'s `App` constructor" (issue body) | `@octokit/app@^16.1.2` is in `apps/web-platform/package.json:24`. `App` constructor takes `{ appId, privateKey }`; auto-mints JWTs for app-level requests via `app.octokit`. No new dep. Verified by PR-3 already using it via `createProbeOctokit()`. | Carry forward — `createAppJwtOctokit()` uses the same constructor. Sentinel: `grep -n "@octokit/app" apps/web-platform/package.json` returns line 24. |
| "Three label classes: `[ci/auth-broken]`, `[ci/guard-broken]`, `[security/leak-suspected]`" (issue body) | All three labels exist (`gh label list --limit 200` — ci/auth-broken, ci/guard-broken, security/leak-suspected verified). PR-3 added the same `ci/auth-broken` label for oauth-probe. | Carry forward. AC4 handler files via the correct label per `record_failure`'s 3-output routing model. |
| "Closes #3750 (mint-app-jwt composite extraction): cross-workflow dedup target dissolves" (issue body) | #3750 is OPEN as of plan-time. Consumers of `mint-app-jwt` composite would have been `scheduled-github-app-drift-guard.yml` + `scheduled-ruleset-bypass-audit.yml`. After this PR, drift-guard is GONE — only `scheduled-ruleset-bypass-audit.yml` mints inline. Intra-workflow extraction has no second consumer → cross-workflow dedup is moot. | **PR body uses `Closes #3750`** — the cross-workflow dedup target the issue tracked is dissolved by this PR's deletion of the drift-guard workflow. Ruleset-audit's inline mint stays as the sole call site; extracting a single-caller composite would be ceremony. |
| "Sentry monitor IaC: revert PR #4207's margin/threshold bump (360 → 30, 2 → 1)" (issue body) | `apps/web-platform/infra/sentry/cron-monitors.tf:107-117` currently has `checkin_margin_minutes = 360, failure_issue_threshold = 2`. Pre-#4207 the values were `180 / 1` (per PR-3 plan's research; the immediate-relief PR bumped to `360 / 2` for both probes). The honest post-Inngest target per PR-1/PR-2/PR-3 sibling precedent is `30 / 1`. | **Revert to `30 / 1`** (matching siblings), not to `180 / 1` (pre-immediate-relief). Inngest fires deterministically with ≤2-min jitter; 30-min margin is honest. Sentinel: `grep -E 'checkin_margin_minutes\s*=\s*30' apps/web-platform/infra/sentry/cron-monitors.tf` returns ≥4 lines (oauth-probe, daily-triage, follow-through, drift-guard). |
| "Delete the joint-exception breadcrumb's drift-guard reference (now that PR-3's residual exception note is the sole remaining one — see `apps/web-platform/infra/sentry/cron-monitors.tf` post-#4211)" (issue body) | `cron-monitors.tf:24-31` currently names `scheduled_github_app_drift_guard` as "the remaining exception." After this PR, ALL hourly cron monitors are Inngest-fired with 30/1 — no exceptions remain. Comment block lines 24-31 + 28-29 ("TR9 PR-4 follow-up tracks migrating this last hourly monitor") become stale. | **Rewrite lines 24-31 + 33-41 + 66-77 + 98-117** to drop the "exception" language entirely and declare uniform 30/1 across all Inngest-fired monitors. Sentinel: `grep -cE 'remaining exception|TR9 PR-4 follow-up|hourly GHA-cron substrate' apps/web-platform/infra/sentry/cron-monitors.tf` returns 0. |
| "Reuse the `notify-ops-email` composite action" (PR-3 inherited TR6) | PR-3 inlined a direct Resend HTTP POST instead of calling the composite, because the composite was a YAML wrapper not callable from TS. Verified in `cron-oauth-probe.ts`. | Carry forward — drift-guard handler inlines the same Resend HTTP POST shape with a different subject/body. NO composite-action call. |
| "Sentry monitor slug remains `scheduled-github-app-drift-guard`" (continuity per PR-3 AC11 precedent) | PR-3 kept `scheduled-oauth-probe` slug for historical check-in continuity (sentry_cron_monitor resource id, `name` field, and slug all unchanged across substrate migration). | Carry forward — `SENTRY_MONITOR_SLUG = "scheduled-github-app-drift-guard"` in the new TS function. Terraform resource id `scheduled_github_app_drift_guard` stays. |
| "Leak tripwire scans captured step output for PEM/JWT shapes" (workflow lines 523-585) | In GHA the tripwire scans `$RUNNER_TEMP/step-output.log` (a tee-capture of the entire script run). In Inngest there is NO step-output capture surface — the handler runs inside Node.js without stdout/stderr ledger. The defense must move from "post-step grep" to "explicit string-set guard around the values the handler logs/emits." | **Tripwire ported as a TS pre-emission scanner.** Every string the handler may emit (Sentry breadcrumb, issue-filing body, Resend email body) is run through `assertNoLeak(s)` before emission. `assertNoLeak` greps for the same three regex alternations: PEM-block header (`/BEGIN [A-Z ]*PRIVATE KEY/`), base64-of-PEM (`/LS0tLS1CRUdJTi[A-Za-z0-9+/]/`), JWT segment (`/eyJ[A-Za-z0-9_-]{20,}/`). On match: throws (caught by outer `step.run`); the inner exception triggers `[security/leak-suspected]` issue filing + `?status=error` heartbeat. The contract test ports the existing regex assertions from `github-app-drift-guard-contract.test.ts:14-37` against the new TS module. |
| "MANIFEST_DRIFT_SUPPRESS_UNTIL timestamp gate" (workflow lines 304-343) | The suppression file lives at `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL`. Strict ISO-8601 UTC validation, 30-day cap. Used by operators after manifest widening to suppress the false-positive window. | Carry forward — handler reads the same file, applies the same strict regex `/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/`, same 30-day cap. Sentinel: `grep -nE 'MANIFEST_DRIFT_SUPPRESS_UNTIL' apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` returns ≥1. |
| "Installation pagination guard fires on `Link: rel=next`" (workflow lines 420-429) | Octokit's `request("GET /app/installations?per_page=100")` exposes response headers via `response.headers.link`. TS check: `(response.headers.link ?? "").includes('rel="next"')`. Same defense. | Carry forward — TS shape preserved. Sentinel: `grep -nE 'installation_list_truncated' apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` returns ≥1. |
| "`createProbeOctokit()` deliberately omits audit-writer attachment" (PR-3 Sharp Edge) | The new `createAppJwtOctokit()` MUST also omit the audit-writer attachment for the same Article-30 PA-16 reason. The drift-guard is platform-owned synthetic traffic; writing `audit_github_token_use` rows would pollute the founder-activity ledger. | Carry forward — `createAppJwtOctokit()` factory at the same path; jsdoc warning preserved. |

## Hypotheses

Not a network-outage diagnosis class. Phase 1.4 keyword scan does NOT match the feature description; no `provisioner "remote-exec"` block. Skipping Phase 1.4 silently.

Carry forward H3 (CONFIRMED) + H4 (substrate exists) from PR-3 plan. PR-3's H5 (sister drift-guard same envelope — handled by PR-4) is now THIS PR; framing converts from hypothesis to deliverable.

## Acceptance Criteria

### Pre-merge (PR)

**Phase 0 — preconditions (verified at /work-time before any code):**

- [ ] AC0.1 — Doppler `prd` secrets present (read-only probe, NOT a write): `doppler secrets get GH_APP_DRIFTGUARD_APP_ID -p soleur -c prd --plain | head -c 8`, same for `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` and `OAUTH_PROBE_GITHUB_CLIENT_ID`. All three MUST return non-empty. If any is empty, halt — the prd substrate cannot mint JWTs without them.
- [ ] AC0.2 — Hetzner Inngest VM has `bash` AND `jq` on PATH (the diff script's two dependencies). Verified at /work-time by reading the Terraform-managed cloud-init / systemd unit definition (`apps/web-platform/infra/inngest-server/*.tf` or sibling), NOT by SSH. If absent, file the missing-tool gap as a Phase 0 Terraform edit (cloud-init `runcmd: apt install -y jq`); do NOT prescribe a manual `ssh root@hetzner && apt install`.
- [ ] AC0.3 — `@octokit/app` is in `apps/web-platform/package.json` (already verified at plan-time: line 24 = `"@octokit/app": "^16.1.2"`). Re-verify at /work-time via `grep -n '@octokit/app' apps/web-platform/package.json`.
- [ ] AC0.4 — Labels exist: `gh label list --limit 200 | grep -E '^(ci/auth-broken|ci/guard-broken|security/leak-suspected|priority/p1-high|priority/p2-medium|domain/engineering|code-review)\b'` returns 7 lines.

**Code shape (Inngest function):**

- [ ] AC1 — A new file `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` exports `cronGithubAppDriftGuard = inngest.createFunction({...}, [{ cron: "0 * * * *" }, { event: "cron/github-app-drift-guard.manual-trigger" }], cronGithubAppDriftGuardHandler)`. Concurrency: `[{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` (literal-string-in-string per Architecture F7 — typo here is silent, two cron-* fns running concurrently never throws but bypasses OOM guard). Retries: 1. Handler wraps probe logic in `step.run("drift-check", ...)`, manifest-diff in `step.run("manifest-diff", ...)`, installation diff in `step.run("installation-diff", ...)`, and Sentry heartbeat in `step.run("sentry-heartbeat", ...)`.
- [ ] AC2 — Handler ports the 12+ failure modes from `.github/workflows/scheduled-github-app-drift-guard.yml:108-485` translated to TypeScript with the names preserved verbatim. Routing table in source-code comment mirrors workflow's `record_failure` 3-output model: `(mode, detail, label)` tuple per failure; first failure wins (idempotent against re-entry); enum of labels limited to `ci/auth-broken | ci/guard-broken` (security/leak-suspected is set ONLY by the tripwire branch at AC6).
- [ ] AC3 — Handler reads `GH_APP_DRIFTGUARD_APP_ID`, `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`, `OAUTH_PROBE_GITHUB_CLIENT_ID` from `process.env` (Doppler `prd`). No new secret materialization. Defensive guards mirror workflow lines 175-189 (`missing_app_id`, `app_id_not_numeric`, `missing_expected_client_id`, `missing_private_key`).
- [ ] AC4 — Handler files/comments/closes the `[ci/auth-broken] GitHub App drift-guard fired` AND `[ci/guard-broken] GitHub App drift-guard malfunctioned` GitHub issues (two distinct titles per workflow lines 601-617) via a NEW helper at `apps/web-platform/server/github/probe-octokit.ts` exporting `async function createAppJwtOctokit(): Promise<{ octokit: Octokit; appJwt: string }>`. Helper uses `@octokit/app`'s `App` constructor (no new dep) to mint an app-level JWT from `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY` (Doppler `prd`). The JWT extraction shape (verified against `apps/web-platform/node_modules/@octokit/auth-app/dist-types/types.d.ts:101-105` at deepen-plan time):
    ```typescript
    import { App } from "@octokit/app";
    import type { AppAuthentication } from "@octokit/auth-app";
    const app = new App({ appId: readEnv("GITHUB_APP_ID"), privateKey: readEnv("GITHUB_APP_PRIVATE_KEY") });
    const auth = (await app.octokit.auth({ type: "app" })) as AppAuthentication;
    return { octokit: app.octokit, appJwt: auth.token };
    ```
    NO `founderId`, NO audit-writer attachment, NO `audit_github_token_use` row (per Article 30 PA-16 scope). The JWT is returned alongside so the leak tripwire (AC6) can assert it never appears in handler-emitted strings. Sentinel: `grep -nE 'export async function createAppJwtOctokit' apps/web-platform/server/github/probe-octokit.ts` returns 1.
- [ ] AC5 — Handler emits a `notify-ops-email`-shape POST to Resend's HTTP API directly (no helper extraction), matching `.github/actions/notify-ops-email/action.yml:33-44` payload verbatim and the workflow's `if: steps.check.outputs.failure_mode != '' || steps.tripwire.outcome == 'failure'` gate (combined drift-vs-leak email subject). Wrapped in `step.run("notify-ops-email", ...)` so Resend HTTP failures get Inngest retry. Subject: `[Soleur Ops] GitHub App drift-guard: <failure_mode | 'leak-suspected'>`. Body preserves the 5-line HTML format from workflow lines 658-664. `RESEND_API_KEY` sourced from Doppler `prd` (existing secret).
- [ ] AC6 — **Leak tripwire ported as TS pre-emission scanner.** A new module-local function `assertNoLeak(label: string, s: string): void` runs three regex alternations against any string about to be emitted (Sentry breadcrumb arg, issue-body string, Resend body, log/console output). On match: throws `LeakDetectedError`. The outer handler catches `LeakDetectedError` specifically and: (a) files `[security/leak-suspected] GitHub App drift-guard log-leak tripwire` issue via `createAppJwtOctokit()` (title verbatim from workflow line 577), (b) marks `failureLabel = "security/leak-suspected"`, (c) emits `?status=error` Sentry heartbeat. Regexes verbatim from `apps/web-platform/test/github-app-drift-guard-contract.test.ts:28-37` (LEAK_TRIPWIRE_PEM_REGEX = `BEGIN [A-Z ]*PRIVATE KEY`, LEAK_TRIPWIRE_JWT_REGEX = `eyJ[A-Za-z0-9_-]{20,}`, LEAK_TRIPWIRE_PEM_B64_REGEX = `LS0tLS1CRUdJTi[A-Za-z0-9+/]`). The handler MUST pass `appJwt` from AC4 through `assertNoLeak` checks at every emission site (single-call gate, not opt-in).
- [ ] AC7 — Sentry heartbeat step matches `cron-daily-triage.ts:329-371` shape: `SENTRY_DOMAIN_RE` / `SENTRY_PROJECT_RE` / `SENTRY_PUBLIC_KEY_RE` env guards; `POST https://${domain}/api/${projectId}/cron/scheduled-github-app-drift-guard/${publicKey}/?status=${ok|error}`; `AbortSignal.timeout(10_000)`; fallback to `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`. `SENTRY_MONITOR_SLUG = "scheduled-github-app-drift-guard"` (continuity preserved). Status routing mirrors workflow line 721 verbatim: `ok` only when `failureMode === "" && !leakDetected`; otherwise `error`.
- [ ] AC8 — **Manifest-diff via `child_process.spawn`.** Handler writes the live `GET /app` response JSON to a `mkdtemp`'d temp file (cleaned in `finally`), spawns `bash bin/diff-github-app-manifest.sh` with `MANIFEST_FILE=apps/web-platform/infra/github-app-manifest.json` and `RESPONSE_FILE=<temp>`, captures stdout. Exit-0 = no drift; exit-1 = `<mode>:<detail>` on stdout (parsed via `output.split(":", 2)`); exit-2 = `[ci/guard-broken]` (`diff_script_failed`). Wrapped in `step.run("manifest-diff", ...)`. Same routing as workflow lines 351-369. The diff script and `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` are touched only in their header comments (PR-4 reference); test body unchanged.
- [ ] AC9 — **MANIFEST_DRIFT_SUPPRESS_UNTIL gate ported.** Same regex `/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/`, same 30-day cap (`30 * 24 * 3600` seconds). When `now < suppress_until`, the manifest-diff step emits a `console.warn(...)` AND SKIPS `record_failure` — preserves the operator's pre-merge widening window. When file is absent, gate is no-op. When timestamp is invalid OR exceeds cap, suppression is REJECTED (loud warn, diff runs normally) — same defense-in-depth as workflow lines 327-340.
- [ ] AC10 — **Installation-grant diff ported.** Handler calls `octokit.request("GET /app/installations", { per_page: 100 })`, asserts pagination guard (`response.headers.link?.includes('rel="next"')` → `installation_list_truncated`), asserts root is array (`Array.isArray(response.data)` → `installation_list_shape_unparseable`), iterates and for each install synthesizes `{permissions, events}` via `JSON.stringify({permissions: i.permissions, events: i.events})`, writes to a new temp file, spawns the diff script. Routing per workflow lines 454-481: `permission_drift` → `installation_permission_drift` + `ci/auth-broken`; `permission_unexpected_grant` → `installation_unexpected_grant` + `ci/guard-broken`; etc. All temp files cleaned in `finally`.

**Substrate-side wiring:**

- [ ] AC11 — The new function is registered in `apps/web-platform/app/api/inngest/route.ts`. Current array (verified at plan-time, line 41-44): `[cronDailyTriage, cronFollowThroughMonitor, cronOauthProbe, cfoOnPaymentFailed, githubOnEvent, workspaceReconcileOnPush]`. Add `cronGithubAppDriftGuard` import (line 23-area) and array entry. Sentinel: `grep -nE 'cronGithubAppDriftGuard' apps/web-platform/app/api/inngest/route.ts` returns ≥2 (one import, one array element).

**Workflow deletion + GHA-side cleanup:**

- [ ] AC12 — `.github/workflows/scheduled-github-app-drift-guard.yml` is **deleted** in this PR. `git ls-files .github/workflows/scheduled-github-app-drift-guard.yml` returns empty. TR9 I-13 hygiene precedent. No parallel firing.
- [ ] AC13 — `.github/CODEOWNERS:17` (`/.github/workflows/scheduled-github-app-drift-guard.yml @deruelle`) is **deleted** in the same commit. Stale codeowner entries silently widen the "fail-closed" check for renames. Sentinel: `grep -nE 'scheduled-github-app-drift-guard' .github/CODEOWNERS` returns 0.
- [ ] AC14 — Shared composite action `.github/actions/sentry-heartbeat/action.yml` is **preserved unchanged** (still consumed by 7+ sister daily/weekly workflows). The TS function inlines the heartbeat logic per AC7.
- [ ] AC15 — `.github/workflows/scheduled-ruleset-bypass-audit.yml` cross-references at lines 30-31 + 105-106 are updated: change `"scheduled-github-app-drift-guard.yml"` references to `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` (or drop entirely; the comments are prose-only documentation of the routing-pattern mirror — keeping the prose intact with the new path is the smallest change). The ruleset-audit workflow itself is NOT migrated in this PR (out of scope; cross-workflow mint-app-jwt dedup target dissolves per Closes #3750).

**Sentry monitor IaC (revert PR #4207's drift-guard bump + collapse the joint-exception breadcrumb):**

- [ ] AC16 — `apps/web-platform/infra/sentry/cron-monitors.tf` `resource "sentry_cron_monitor" "scheduled_github_app_drift_guard"`: `checkin_margin_minutes = 360 → 30`, `failure_issue_threshold = 2 → 1`. Other fields unchanged. Header comment block (lines 98-106 currently) rewritten to declare Inngest-fired substrate, citing TR9 PR-1/PR-2/PR-3 precedent + ADR-030 + ADR-033. Sentinel: `grep -nE 'Inngest-fired|cron-github-app-drift-guard\.ts' apps/web-platform/infra/sentry/cron-monitors.tf` returns ≥1 in the drift-guard-resource block.
- [ ] AC17 — **Joint-exception breadcrumb collapse.** Lines 24-31 + 33-41 of `cron-monitors.tf` (the "one remaining exception" + GHA-fired-substrate-jitter prose) are REWRITTEN to declare uniform 30 / 1 across all Inngest-fired monitors. Specifically:
    - Drop "One remaining exception (`scheduled_github_app_drift_guard`, set to 2) is still GHA-fired hourly..." (lines 25-29).
    - Drop "TR9 PR-4 follow-up tracks migrating this last hourly monitor off GHA; at that point the exception dissolves." (lines 28-29).
    - Drop "`checkin_margin_minutes` is sized per-substrate. GHA-fired monitors must accommodate observed GHA hourly-cron drift..." (lines 33-41) — this prose no longer has a referent.
    - Replace with: "All cron monitors are Inngest-fired and use 30-min margin + threshold=1 (honest signal under ≤2-min Inngest jitter). The TR9 substrate-migration sequence (PR-1 #3985, PR-2 #4062, PR-3 #4211, PR-4 #<this PR>) completed the move off GHA hourly cron."

    Sentinel: `grep -cE 'remaining exception|TR9 PR-4 follow-up|hourly GHA-cron substrate|Margin bumped|360 / 2' apps/web-platform/infra/sentry/cron-monitors.tf` returns 0.

- [ ] AC18 — `cron-monitors.tf:98-106` (the 2026-05-21 immediate-relief comment block above the drift-guard resource) is **deleted entirely** — it specifically narrates PR #4207's bump-and-revert lifecycle which this PR closes.

**Operator-surface doc sweep:**

- [ ] AC19 — `knowledge-base/engineering/operations/runbooks/github-app-drift.md` updated at every operator-facing `gh workflow run` / `gh run list` / `scheduled-github-app-drift-guard.yml` reference (verified at plan-time: lines 6, 16, 122, 124, 270, 271). Replacement contract:
    - `gh workflow run scheduled-github-app-drift-guard.yml` → `inngest send cron/github-app-drift-guard.manual-trigger --data '{}'` (the manual-trigger event name from AC1).
    - `gh run list --workflow=scheduled-github-app-drift-guard.yml --limit 1 --json conclusion` → the Sentry checkins API query (see Observability section's discoverability_test).
    - Path references to `.github/workflows/scheduled-github-app-drift-guard.yml` → `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`.

    Additionally, prepend the same Better Stack substrate-disambiguation note PR-3 added to oauth-probe-failure.md: "Before debugging the drift-guard code path, check Better Stack `inngest-heartbeat` last_alive_at — if >2 min ago, this issue is likely a substrate-down false-positive (cross-check sibling `scheduled-daily-triage` / `scheduled-follow-through` / `scheduled-oauth-probe` monitors)."

    Sentinel: `grep -cE 'gh workflow run scheduled-github-app-drift-guard|gh run list.*scheduled-github-app-drift-guard|scheduled-github-app-drift-guard\.yml' knowledge-base/engineering/operations/runbooks/github-app-drift.md` returns 0.

- [ ] AC20 — `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md` line 27, 94, 100, 188, 240 (verified at plan-time) cross-references to `scheduled-github-app-drift-guard.yml` updated to the new TS path. Sentinel: `grep -nE 'scheduled-github-app-drift-guard\.yml|gh workflow run scheduled-github-app-drift-guard' knowledge-base/engineering/operations/runbooks/github-app-provisioning.md` returns 0.
- [ ] AC21 — `apps/web-platform/infra/github-app.tf:28` cross-reference (`scheduled-github-app-drift-guard.yml: App-declared-vs-manifest`) updated to the new TS path. Sentinel: `grep -nE 'scheduled-github-app-drift-guard\.yml' apps/web-platform/infra/github-app.tf` returns 0.
- [ ] AC22 — Full operator-surface sweep: `grep -rEn 'scheduled-github-app-drift-guard\.yml|gh workflow run scheduled-github-app-drift-guard|gh run list.*scheduled-github-app-drift-guard' knowledge-base/engineering/ apps/web-platform/ .github/ bin/ README.md CONTRIBUTING.md 2>/dev/null | grep -v archive/ | grep -v 'knowledge-base/project/\(plans\|specs\|learnings\)/' | wc -l` returns 0. Scope exclusion preserves historical project artifacts per PR-3 AC15 precedent. Note `bin/snapshot-github-app.sh:5,52` cross-refs the workflow file in COMMENTS — those are updated to point at the new TS file. The contract test file `apps/web-platform/test/github-app-drift-guard-contract.test.ts` IS expected to remain referencing the deleted YAML file because the test is being **DELETED** in AC25.

**Test surface — port + delete:**

- [ ] AC23 — `apps/web-platform/test/github-app-drift-guard-contract.test.ts` is **deleted** in this PR. The test asserted YAML-shape invariants (regex constants in workflow file, concurrency group string, JWT mint correctness in the bash). With the YAML gone, the test points at nothing. The load-bearing assertions (regex constants, mint correctness) are re-anchored to the new TS module in AC24.
- [ ] AC24 — A new test file `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` (~200 LoC, sibling to `cron-oauth-probe.test.ts`) covers:
    - (a) happy-path `?status=ok` heartbeat (no drift, no leak, no installation mismatch).
    - (b) per-failure-mode `?status=error` mapping for all 12+ modes (mocked fetch returns for each; assert `failureMode` + `failureLabel` outputs).
    - (c) fork-PR fallback (`SENTRY_INGEST_DOMAIN` empty) — logs warning via `reportSilentFallback`, no throw.
    - (d) issue-filing branch via mocked Octokit (no real network).
    - (e) **Leak tripwire branch:** when `assertNoLeak` throws `LeakDetectedError`, handler emits `[security/leak-suspected]` issue + `?status=error` heartbeat. Three regex assertion cases (PEM header, base64-of-PEM, JWT segment) — load-bearing constants `LEAK_TRIPWIRE_PEM_REGEX`, `LEAK_TRIPWIRE_PEM_B64_REGEX`, `LEAK_TRIPWIRE_JWT_REGEX` re-exported from the new TS module so any future drift in the regex is caught by the test.
    - (f) `MANIFEST_DRIFT_SUPPRESS_UNTIL` gate: 3 cases (active suppression → diff skipped; expired → diff runs; invalid timestamp → diff runs with warn).
    - (g) Installation pagination guard: `Link: rel="next"` header → `installation_list_truncated`.
    - (h) Installation shape guard: non-array root → `installation_list_shape_unparseable`.

    Test runner: `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` (NOT `bun test`; `bunfig.toml` blocks bun test discovery — see Sharp Edges).

- [ ] AC25 — `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` is **preserved unchanged** in test-body (the script-contract test). Only its header comment is updated to add a "TR9 PR-4 (#4235) — script invocation now also via `cron-github-app-drift-guard.ts`" line. The six-case matrix continues to exercise `bin/diff-github-app-manifest.sh` directly via `spawnSync`. Sentinel: `git diff --stat apps/web-platform/test/github-app-manifest-drift-guard.test.ts` shows only header-comment line changes, no test-block changes.

**Verification gates:**

- [ ] AC26 — `terraform validate` passes on `apps/web-platform/infra/sentry/`. Invocation: `cd apps/web-platform/infra/sentry && terraform init -input=false -backend=false && terraform validate`. **Pre-apply sanity gate** (per `2026-05-18-infra-validation-pathspec-silent-zero-match.md`): the apply-sentry-infra paths filter must match this PR's diff. Verify at /work-time the workflow file at `.github/workflows/apply-sentry-infra.yml` contains `apps/web-platform/infra/sentry/**` in its paths filter (it does; verified at plan-time).
- [ ] AC27 — `bun run typecheck` AND `./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` both pass.
- [ ] AC28 — `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` (glob `server/inngest/functions/cron-*.ts`) auto-extends to `cron-github-app-drift-guard.ts`. Re-run via `./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts`. Confirms no BYOK violation (handler uses no Anthropic API key).
- [ ] AC29 — PR body uses `Closes #4235` AND `Closes #3750`. `#3750` closes because the cross-workflow mint-app-jwt dedup target dissolves once drift-guard moves off GHA (ruleset-audit's inline mint stays as the sole call site; intra-workflow extraction has no second consumer). PR body does NOT include `Closes #4211` (already closed by PR #4227's merge on 2026-05-21).

**Pre-merge (#4116 cascade self-check):**

Run the six self-check questions from `2026-05-19-inngest-substrate-five-bug-cascade.md` BEFORE marking the PR ready:

- [ ] **CQ1** — `PUBLIC_PATHS` includes `/api/inngest`. Verify via grep.
- [ ] **CQ2** — `INNGEST_SIGNING_KEY` Doppler value has prefix `signkey-prod-*` in prd config. Verify via `doppler secrets get INNGEST_SIGNING_KEY -p soleur -c prd --plain | head -c 14`.
- [ ] **CQ3** — Hetzner Inngest server's `inngest-server.service` systemd unit has `User=deploy` and file ownership matches.
- [ ] **CQ4** — `inngest-server.service` `ReadWritePaths=` includes the SQLite db path.
- [ ] **CQ5** — Env source-of-truth is Doppler `prd`.
- [ ] **CQ6** — Better Stack `inngest-heartbeat` monitor is **unpaused** before declaring GREEN.

### Post-merge (auto + verification)

- [ ] AC30 — **Auto:** push to `main` triggers two auto-apply flows:
    1. `apps/web-platform/infra/sentry/cron-monitors.tf` change auto-applied via `.github/workflows/apply-sentry-infra.yml` (paths filter matches `apps/web-platform/infra/sentry/**`; the workflow's targeted-apply list at line 171 already includes `sentry_cron_monitor.scheduled_github_app_drift_guard`). The resource is updated in-place. Verify via `gh run list --workflow=apply-sentry-infra.yml --json conclusion,headBranch --jq '.[] | select(.headBranch == "main") | .conclusion'` returns `success`, NOT `skipped`.
    2. The new Inngest function is included in the Next.js production build and discovered by the Hetzner Inngest server via `/api/inngest` introspection on first POST-deploy boot. No operator action.
- [ ] AC31 — **Auto, T+90 min:** the first scheduled Inngest fire of `cron-github-app-drift-guard` posts `?status=ok` to Sentry (assuming no real drift, which has been the baseline state for weeks). Verification: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-github-app-drift-guard/checkins/?limit=5" | jq -r '.[] | "\(.dateCreated) \(.status)"'` shows a recent `ok` check-in (≤90 min ago — covers the 1-hour interval + Inngest's ≤2-min jitter).
- [ ] AC32 — **Operator (post-merge synthetic-failure injection):** within 24h of merge, the operator (or `/soleur:ship` post-merge step) runs ONE synthetic-failure injection against a **non-prd surface** to verify the dispatch path lights up end-to-end. Mechanism (mirror of PR-3 AC20/AC24):
    1. Run the handler against a fixture: temporarily override `GH_APP_DRIFTGUARD_APP_ID` to a value that triggers `app_id_not_numeric` (e.g., `"not-a-number"`) via env-var in the dev shell — `GH_APP_DRIFTGUARD_APP_ID=not-a-number ./node_modules/.bin/vitest run apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts -t "app_id_not_numeric"`. This is the cheapest deterministic failure to inject.
    2. Verify within the test: (a) `failureMode === "app_id_not_numeric"`, (b) `failureLabel === "ci/guard-broken"`, (c) issue-filing branch called (mocked Octokit assertion), (d) Sentry heartbeat called with `?status=error`.
    3. **The prd handler has ZERO fixture-injection plumbing** — no `event.data.overrideAppId`, no in-handler prd-vs-dev branching. The override is purely env-var driven, scoped to the dev shell + test runner, and never reaches the prd Doppler config. Mirrors PR-3's resolution of Kieran's plan-review finding on incoherent prd-vs-fixture gates.
    4. Operator records function-run ID + verification outcome in the PR body's post-merge checklist.

- [ ] AC33 — **Operator (one-time cleanup, deferrable to /soleur:ship Phase 5.5):** verify `apps/web-platform/scripts/verify-required-secrets.sh:149-179` still asserts the shape of `GH_APP_DRIFTGUARD_APP_ID` + `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`. These secrets are now consumed by the Inngest TS function instead of the GHA workflow, but the shape assertions stay relevant. No edit required in this PR; the verification IS the AC.

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitors.tf` — AC16, AC17, AC18: revert PR #4207's drift-guard bump; rewrite header comments lines 24-41 + 98-106 to collapse the joint-exception breadcrumb; declare uniform Inngest-fired narrative.
- `apps/web-platform/app/api/inngest/route.ts` — line 23-area import added; line 41-44 array extended for `cronGithubAppDriftGuard` (AC11).
- `apps/web-platform/server/github/probe-octokit.ts` — AC4: add a second factory `createAppJwtOctokit()` exporting `{ octokit, appJwt }`. Existing `createProbeOctokit()` UNCHANGED.
- `.github/CODEOWNERS` — line 17 deletion (AC13).
- `.github/workflows/scheduled-ruleset-bypass-audit.yml` — lines 30-31 + 105-106: cross-reference prose updated to the new TS path (AC15).
- `apps/web-platform/infra/github-app.tf` — line 28 cross-reference (AC21).
- `bin/snapshot-github-app.sh` — lines 5, 52 comment references updated to the new TS file (AC22 noted exclusion path).
- `knowledge-base/engineering/operations/runbooks/github-app-drift.md` — AC19: lines 6, 16, 122, 124, 270, 271 + Better Stack disambiguation note prepended to troubleshooting section.
- `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md` — AC20: lines 27, 94, 100, 188, 240.
- `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` — header-comment only (AC25).

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts` — ~400 LoC (12+ failure modes + manifest-diff spawn + installation iteration + leak tripwire + heartbeat). Larger than PR-3's `cron-oauth-probe.ts` (~370 LoC actual) due to the installation-diff loop and the leak tripwire scanner.
- `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts` — ~200 LoC, per AC24.

## Files to Delete

- `.github/workflows/scheduled-github-app-drift-guard.yml` (724 LoC) — per AC12.
- `apps/web-platform/test/github-app-drift-guard-contract.test.ts` — per AC23 (YAML-shape contract test; the load-bearing constants are re-anchored to the new TS module by AC24).

## Open Code-Review Overlap

Plan-time `gh issue list --label code-review --state open` + path grep against the planned file list:

- **#3750: review: Extract mint-app-jwt composite action (deduplicate ~85 LoC across drift-guard + ruleset-audit workflows)** — **Closes (folded in).** Drift-guard workflow is deleted by AC12; ruleset-audit becomes the sole remaining JWT-mint workflow. Cross-workflow dedup target dissolves at the same moment as the workflow file. PR body uses `Closes #3750`.
- **#3187: ([id reference; closed]):** drift-guard's parent issue; referenced via `Tracks: #3187` in handler-emitted issue bodies. No action — the TS handler preserves the prose.
- **#4115 (closed):** manifest-vs-live permission diff origin. No action.
- **#4179 (closed):** installation-grant diff origin. No action.

No other open code-review issues touch the affected files.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — all three covered by the brainstorm carry-forward from PR-3 (same triad, same `USER_BRAND_CRITICAL=true` framing). Sales/Marketing/Finance/Support/Operations: NONE.

**Brainstorm-recommended specialists:** none beyond the triad. PR-3's brainstorm explicitly named PR-4 as the deferral target; the framing carries forward unchanged.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** Threshold elevation to `single-user incident` holds — drift-guard's own workflow header has declared this threshold since #3187. The detection-surface gap PR-3's CPO review surfaced for oauth-probe applies symmetrically here: a botched migration silently disables drift detection AND the credential-leak tripwire. AC32 (post-merge synthetic-failure injection via env-var override in dev shell) inherits PR-3's pattern verbatim. CPO sign-off REQUIRED at plan time before `/work` begins (per `requires_cpo_signoff: true`).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward + PR-3 verified pattern).
**Assessment:**

- PR-3's pattern is now MERGED and proven (oauth-probe Inngest cron firing within ≤2-min jitter, verified via Sentry checkins API). PR-4 inherits the substrate, the heartbeat shape, the issue-filing pattern, the Resend HTTP pattern, the `oauth-probe-sentinels.ts` module pattern (mirrored as inline TS constants here — the sentinels for drift-guard are regex constants, not body-substrings, so a separate module would be ceremony).
- **Helper choice** is the load-bearing CTO deviation: a second factory `createAppJwtOctokit()` at the same file path. App-level JWT is required for `GET /app` + `GET /app/installations` (installation-scoped Octokit cannot reach `/app`). Returning the raw JWT alongside the Octokit is necessary for the leak tripwire to assert the JWT never appears in handler-emitted strings.
- **Leak tripwire** is the load-bearing CTO addition: moving from "post-step grep of step-output.log" (a GHA-runner-specific surface) to "pre-emission assertion at every string-emit site" (a Node-runtime defense). Three regex alternations preserved verbatim; the contract test re-anchors them to the new TS module so a future regex weakening is caught.
- **Substrate-failure mode added:** if Inngest server is down, the drift-guard doesn't fire. Compensating signals: `inngest-heartbeat.timer` to Better Stack (60s), sibling Inngest monitors (oauth-probe, daily-triage, follow-through) ALSO depend on substrate liveness. Substrate-vs-probe disambiguation in operator runbook (AC19 prepended note).
- Same-commit deletion safe per PR-3 + PR-1 + PR-2 precedent. Rollback contract in Risks #1.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** **Carry-forward only.** Article-30 PA 13 covers self-hosted Inngest. PA-16 (audit ledger) is preserved by `createAppJwtOctokit()` deliberately NOT attaching the audit-writer — synthetic-probe traffic stays out of the founder-activity ledger. No new sub-processor, no new DPA, no LIA. GDPR-gate analysis: same as PR-3 — mechanical trigger (b) fires on `single-user incident` threshold, but data-flow is neutral; CLO override applies (see GDPR / Compliance Gate section).

## GDPR / Compliance Gate

**Phase 2.7 mechanical trigger fires** because brand-survival threshold is `single-user incident` (trigger (b)). **However:** CLO carry-forward at brainstorm Phase 0.5 verified the substrate change is data-flow-neutral. The drift-guard processes no user data; credentials read are operator-owned secrets (already in Doppler `prd`); Article-30 PA 13 already covers the substrate.

**Gate verdict:** Skip per CLO sign-off (mirror of PR-3 §GDPR Compliance Gate verdict). The mechanical trigger is the right safety net but admits an explicit override here — consequence severity does not backfill a data-flow that doesn't exist. The new `createAppJwtOctokit()` helper explicitly omits audit-writer attachment, so the probe stays out of the audit ledger (Article 30 PA-16 scope preserved).

Phase 2.7 trigger taxonomy:

- Canonical regex: NO match (TS file under server/inngest, TF monitor resource, runbooks, workflow deletion).
- (a) LLM/external-API on operator data: NO.
- (b) Threshold `single-user incident`: YES (mechanical trigger fires).
- (c) Cron reads from learnings/specs: NO.
- (d) New artifact distribution: NO.

**Override rationale:** trigger (b) fires on consequence-severity; CLO verified data-flow is neutral. Skip gate explicitly. Mirror of PR-3 verdict.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`:
    - `sentry_cron_monitor.scheduled_github_app_drift_guard`: `checkin_margin_minutes = 360 → 30`, `failure_issue_threshold = 2 → 1`. Header comment rewritten (AC16).
    - Joint-exception breadcrumb at lines 24-41 collapsed (AC17). Prose declares uniform Inngest-fired narrative across all monitors.
    - Transitional comment at lines 98-106 (May 21 drift-guard bump) deleted (AC18).

- **No changes to `.github/workflows/apply-sentry-infra.yml`** — its targeted-apply list at line 171 already names `sentry_cron_monitor.scheduled_github_app_drift_guard` (verified at plan-time). The resource will be applied in-place on push to main.

- **No changes to inngest-server Terraform root** (apps/web-platform/infra/inngest-server/ — assumed; verified at /work-time per AC0.2). If `jq` is missing from the cloud-init runcmd list, the Phase 0 task adds it; do NOT prescribe a manual `ssh root@hetzner && apt install`.

No new providers, no new sensitive variables, no new state-storage. No new vendor signup, no new vendor tier change.

### Apply path

(a) pure Terraform state-update on the existing `scheduled_github_app_drift_guard` resource. Apply path: `.github/workflows/apply-sentry-infra.yml` triggers on push-to-main with paths filter on `apps/web-platform/infra/sentry/**`. Expected change: one in-place attribute update on a single resource. Expected downtime: 0. Same pattern as PR-3's AC21.

### Distinctness / drift safeguards

- `dev != prd`: Sentry monitors in `web-platform` project only. N/A.
- `lifecycle.ignore_changes`: not applied.
- State-storage: R2 backend per `apps/web-platform/infra/sentry/backend.tf`.

### Vendor-tier reality check

- Sentry billing: in-place update on existing seat. No PAYG impact.
- Inngest substrate: one new function on existing self-hosted server. No new vendor cost. Cron-platform concurrency cap (`'"cron-platform"'`) extends from 4 functions to 5; no quota concerns.

## Observability

```yaml
liveness_signal:
  what: Sentry cron-monitor heartbeat for `scheduled-github-app-drift-guard` slug
  cadence: every 1 h (matches Inngest cron `0 * * * *`)
  alert_target: Sentry monitor `scheduled-github-app-drift-guard` (failure_issue_threshold=1, recovery_threshold=1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (post-AC16)
error_reporting:
  destination: Sentry (via `reportSilentFallback` per cq-silent-fallback-must-mirror-to-sentry); secondary destinations = (a) `[ci/auth-broken]` / `[ci/guard-broken]` / `[security/leak-suspected]` GitHub issues via createAppJwtOctokit (AC4, AC6), (b) Resend ops-email to ops@jikigai.com per AC5
  fail_loud: yes — `step.run("drift-check", ...)` errors bubble to Inngest's run-failure stream; LeakDetectedError caught only by the outer handler to route to security/leak-suspected (AC6); ADR-033 I5 return shape deterministic
failure_modes:
  - mode: substrate-down (Inngest server unreachable)
    detection: inngest-heartbeat.timer Better Stack heartbeat miss within 60s + Sentry missed-checkin on `scheduled-github-app-drift-guard` within 30-min margin; sibling Inngest monitors (oauth-probe, daily-triage, follow-through) ALSO miss within their margins (substrate-down inferred from cross-monitor correlation)
    alert_route: Better Stack email + Sentry email; operator runbook (AC19) directs to Better Stack heartbeat dashboard for sub-60-min disambiguation
  - mode: App identity-swap (app_id_mismatch / client_id_mismatch / github_app_401)
    detection: handler returns failureMode set + failureLabel=ci/auth-broken; createAppJwtOctokit files/comments `[ci/auth-broken] GitHub App drift-guard fired`; Resend email; `?status=error` Sentry heartbeat
    alert_route: GitHub issue + Resend + Sentry
  - mode: Manifest drift (permission_drift / permission_unexpected_grant)
    detection: bin/diff-github-app-manifest.sh exit-non-zero with `<mode>:<detail>` stdout; handler routes by mode per workflow lines 351-369
    alert_route: same as identity-swap, labels differ (permission_drift → ci/auth-broken; permission_unexpected_grant → ci/guard-broken)
  - mode: Installation grant drift (installation_permission_drift / installation_unexpected_grant)
    detection: per-installation diff via the same script; routing per workflow lines 454-481
    alert_route: same as manifest drift; failure_detail includes `installation_id=<id>`
  - mode: Leak tripwire fires
    detection: assertNoLeak throws LeakDetectedError at emission site; outer catch routes to security/leak-suspected
    alert_route: `[security/leak-suspected]` GitHub issue + Resend + `?status=error` Sentry heartbeat
  - mode: Sentry heartbeat curl failure
    detection: `reportSilentFallback` mirrors to Sentry under `feature: "cron-sentry-heartbeat"`; monitor shows missed-checkin
    alert_route: same Sentry monitor surface; silent-fallback breadcrumb reveals curl failure
logs:
  where: Inngest server `journalctl -u inngest-server.service` on Hetzner VM (per #4116 — no remote log aggregation yet; local-only)
  retention: systemd default (~7 days at current write rate)
discoverability_test:
  command: |
    curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
      "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-github-app-drift-guard/checkins/?limit=5" \
      | jq -r '.[] | "\(.dateCreated) \(.status) (expected \(.expectedTime))"'
  expected_output: 5 most recent check-ins, each `ok` status, dateCreated within 1-2 min of expectedTime (Inngest deterministic firing, ≤2-min jitter validated against PR-3 sibling)
```

## Test Strategy

1. **TypeScript unit tests** (AC24) — 12+ failure-mode coverage, leak-tripwire coverage, MANIFEST_DRIFT_SUPPRESS_UNTIL gate coverage, installation pagination/shape guards. One new test file (~200 LoC) at `apps/web-platform/test/server/inngest/cron-github-app-drift-guard.test.ts`. Run via vitest (NOT `bun test` — see Sharp Edges).
2. **Manifest-diff script contract** (AC25) — `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` preserved unchanged. The six-case matrix continues to exercise `bin/diff-github-app-manifest.sh` directly. Test body unchanged; only the header comment cites PR-4 in addition to the original #4115/#4179.
3. **Compile + register gate** (AC11, AC27) — `bun run typecheck` + grep on the function-registry. Without registration, the function is dead code.
4. **Cron-no-BYOK gate** (AC28) — glob auto-extends; enforces ADR-033 I2.
5. **`terraform validate`** (AC26) — covers cron-monitor schema changes.
6. **Post-merge synthetic-failure injection** (AC32) — env-var override in dev shell; validates the dispatch path lights up end-to-end without prd fixture plumbing.
7. **First-post-merge fire as live contract** (AC31) — Sentry checkins API IS the assertion.

No new test infrastructure beyond the one new test file. The deleted contract test (`github-app-drift-guard-contract.test.ts`) is replaced by the new handler-level test; the load-bearing regex constants are re-anchored.

## Risks

1. **Inngest function registration fails post-deploy.** Build ships, Inngest server polls `/api/inngest`, function appears in registry. If discovery silently fails (route.ts typo, dead-code elimination, deploy cache miss), the drift-guard is dark for up to 90 min until AC31 verification catches it. **Rollback contract:** if AC31 misses by T+90 min, hotfix PR restores `.github/workflows/scheduled-github-app-drift-guard.yml` from `git show HEAD~1:.github/workflows/scheduled-github-app-drift-guard.yml > .github/workflows/scheduled-github-app-drift-guard.yml && git add . && git commit -m "Revert: TR9 PR-4 cutover; restore GHA fallback" && git push`. Then re-restore `.github/CODEOWNERS:17` from the same HEAD~1, and revert the Sentry monitor change. Three-file rollback (workflow, CODEOWNERS, monitor) — slightly heavier than PR-3's single-file rollback because of the codeowner entry.
2. **`createAppJwtOctokit()` diverges subtly from `createProbeOctokit()`.** Two helpers at the same file path serve different scopes (app-level vs installation-scoped). Accidental import of the wrong one in a future change would either (a) attempt installation-scoped API on the drift-guard side (e.g., `/repos/owner/repo/issues` works only from installation Octokit; would 404 from app-level), or (b) attempt `/app` from the oauth-probe side (would 401). **Mitigation:** distinct factory names, distinct return shapes (`Promise<Octokit>` vs `Promise<{octokit, appJwt}>`), jsdoc warnings on each. The leak tripwire (AC6) raises the cost of dropping the wrong type into a string-emit site — `appJwt` going into an unguarded `console.log` would fire the tripwire on the next run.
3. **`bash` or `jq` missing from Hetzner Inngest VM.** Drift script depends on both. AC0.2 verifies at /work-time via Terraform-managed cloud-init inspection (no SSH). If absent, /work-time MUST file a Terraform `runcmd` edit and apply it via the existing apply path BEFORE the Inngest function deploys — otherwise the first `manifest-diff` step throws and the handler routes to `ci/guard-broken` every fire.
4. **Leak tripwire false-positive on legitimate PEM-shape content.** If a future failure_detail string ever contains the substring `BEGIN ... PRIVATE KEY` (e.g., an operator pastes a debug snippet into an error message), the tripwire fires `[security/leak-suspected]` instead of `[ci/auth-broken]`. **Acceptable** — false-positive on credential-leak detection is safer than false-negative. The runbook AC19 update notes this trade-off.
5. **Substrate-cost.** Drift-guard consumes ~2-5 min CPU per hour (longer than oauth-probe because of the installation iteration + manifest-diff spawn). Still trivial — no PAYG impact, no quota concerns.
6. **`bin/diff-github-app-manifest.sh` evolves under PR-4's nose.** The script is shared between this PR's TS handler (via spawn) and the unchanged `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` (via direct spawn). Any future edit to the script's exit-code contract or output format MUST update both consumers. **Mitigation:** the contract test exists; its six-case matrix catches contract drift.
7. **`apps/web-platform/scripts/verify-required-secrets.sh:149-179` continues to assert shape of GH_APP_DRIFTGUARD_* even though the GHA workflow is gone.** This is correct — the Inngest TS function now consumes the same secrets. AC33 verifies the shape-assertion stays useful (no edit required).

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty or contains `TBD`/`TODO` will fail `deepen-plan` Phase 4.6.** This plan's section is filled with concrete artifact + vector + threshold.
- **Same-commit workflow deletion under elevated threshold is safe** because: (a) PR-1, PR-2, PR-3 all proved the cutover pattern (PR-3 most recently — 2026-05-21 oauth-probe Inngest cron firing within ≤2-min jitter, verified via Sentry API), (b) AC31 first-fire verification covers the cutover window, (c) Risks #1 rollback contract has a documented 3-file revert.
- **The leak tripwire's defense surface SHRINKS in the TS port, not just changes shape.** In GHA the tripwire scanned `tee -a step-output.log` — an IMPLICIT capture of every echo/printf/openssl output inside the bash script (the bash `exec > >(tee ...)` line at workflow:106 is the load-bearing capture). In Node.js there is NO implicit capture. `assertNoLeak` is an EXPLICIT defense — it only fires at sites the developer routes through it. The new defense is structurally narrower; a future `console.error(detail)` or `Sentry.captureMessage(detail)` that bypasses `assertNoLeak` is silently unguarded. **Mitigation (added at deepen-plan):** (1) AC24 test (e) covers all three regex assertion cases against the new TS module; (2) the test ALSO asserts that every string-emit code path in the handler routes through `assertNoLeak` (use AST-walk via `@typescript-eslint/parser` OR a grep gate: `grep -nE 'console\.(log|error|warn|debug)|Sentry\.capture[A-Z]|\.captureException\(|app\.octokit\.request.*body' apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts | grep -v 'assertNoLeak(' MUST return empty`); (3) a `_exhaustive_check` block ensures the regex set matches `LEAK_TRIPWIRE_*` constants exactly.
- **`createAppJwtOctokit()` and `createProbeOctokit()` co-exist at `apps/web-platform/server/github/probe-octokit.ts`.** Distinct factory names + jsdoc warnings + distinct return shapes. Do not "rationalize" them at /work-time by merging into one factory; they have different audit-policy AND different API-surface requirements. The duplicate-app-construction cost (one `new App({...})` per call site) is acceptable — `App` construction is cheap, and the alternative (module-scope singleton) introduces a leak-by-process-survival risk that the existing PR-3 jsdoc explicitly disclaims.
- **`apps/web-platform/bunfig.toml` has `[test] pathIgnorePatterns = ["**"]`.** Test runs use `./node_modules/.bin/vitest run <path>`, NOT `bun test <path>`. AC27 / AC28 invocation forms reflect this.
- **`bin/diff-github-app-manifest.sh` requires `jq` AND `bash` on the Inngest VM.** AC0.2 verifies at /work-time via Terraform-managed cloud-init (NOT SSH per `hr-no-ssh-fallback-in-runbooks`). If missing, the Phase 0 task is a Terraform edit to the cloud-init `runcmd`, not a manual `apt install`.
- **The `MANIFEST_DRIFT_SUPPRESS_UNTIL` file's regex is byte-tight** (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`). `date -d` would otherwise accept "next decade" — silent indefinite suppression on an operator-typo'd file is the defense-in-depth target. Carry forward verbatim.
- **Cron concurrency cap key is `'"cron-platform"'` (literal-string-in-string).** Per `cron-daily-triage.ts:391` + PR-3's `cron-oauth-probe.ts`. AC1 includes verbatim. Typos here are silent (two cron-* fns running concurrently never throws but bypasses F7 OOM guard).
- **`infra-validation` workflow pathspec silent-zero-match.** AC30's sanity gate verifies the workflow actually ran on this PR's diff. If `validate: SKIPPED`, manually run `terraform plan` against the changed monitor.
- **`scheduled-cf-token-expiry-check.yml` (the "9th workflow" referenced at cron-monitors.tf:90-96) is NOT in scope.** Its `schedule:` block is commented out today; AC16/AC17 do not touch it. After this PR, the cron-monitors.tf header narrative simplifies to "all Inngest-fired" — the cf-token-expiry-check exception note (currently lines 90-96) is updated only insofar as the surrounding header rewrites; the resource gap itself stays.
- **Operator-surface doc sweep (AC22) excludes `knowledge-base/project/{plans,specs,learnings}/**` AND `**/archive/**`** per PR-3 AC15 + May 18 plan AC10 precedent — historical record retains references to the deleted workflow filename.
- **AC23 deletes `apps/web-platform/test/github-app-drift-guard-contract.test.ts`** entirely. This is the load-bearing source for the three leak-tripwire regex constants. AC24 (e) re-exports `LEAK_TRIPWIRE_PEM_REGEX`, `LEAK_TRIPWIRE_PEM_B64_REGEX`, `LEAK_TRIPWIRE_JWT_REGEX` from the new TS module so the contract is preserved. Do not delete the constants from history without confirming the test imports them by name.
- **`createAppJwtOctokit()` deliberately omits audit-writer attachment.** Mirror of PR-3 Sharp Edge for `createProbeOctokit()`. Do not "fix" this at /work-time by adding the audit-writer back — it would pollute the audit ledger with synthetic-probe entries that Article 30 PA-16 does not authorize.
- **The contract test `apps/web-platform/test/github-app-manifest-drift-guard.test.ts` continues to exercise the bash script directly via `spawnSync` (AC25).** The Inngest handler ALSO spawns the script via `child_process.spawn`. Two consumers of the same script; the contract test catches any contract drift before the handler is impacted. Keep the test body unchanged.
- **AC29's `Closes #3750` fires the cross-workflow dedup-target dissolution moment.** Be careful that the PR-body sentinel is `Closes #3750` (not `Refs #3750`) — the merge auto-close IS the resolution. If the issue's body is read after merge, the comment chain shows the path from "extract composite" → "single caller remains, no extraction needed" — that closure note is built by the auto-close, not by manual comment.
- **PR-3's `oauth-probe-sentinels.ts` module pattern is NOT mirrored here.** Drift-guard's sentinels are regex constants (PEM-block, base64-of-PEM, JWT) — three short literals. A separate module file would be ceremony for three module-scope constants when the new handler is the only consumer (the contract test imports them from the handler). PR-3's sentinel module existed because `apps/web-platform/test/oauth-probe-contract.test.ts` was a SEPARATE consumer with a different lifecycle — that separation does not exist here.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-22-feat-tr9-pr4-drift-guard-inngest-plan.md. Branch: feat-one-shot-tr9-pr4-drift-guard-inngest-4235. Worktree: .worktrees/feat-one-shot-tr9-pr4-drift-guard-inngest-4235/. Issue: #4235. PR: #4303. Brand-survival threshold: single-user incident (inherited from drift-guard workflow header lines 5-12). requires_cpo_signoff: true. Scope: drift-guard only (oauth-probe shipped in PR #4227 MERGED, closing parent issue #4211). Pattern source: PR-3 plan (knowledge-base/project/plans/2026-05-21-feat-tr9-pr3-oauth-probe-drift-guard-inngest-plan.md). Key deltas vs PR-3: 2nd factory createAppJwtOctokit(), 12+ failure modes vs 8, leak tripwire ported as pre-emission TS scanner, manifest-diff via spawn of bin/diff-github-app-manifest.sh, installation iteration loop. Closes #4235 + #3750. Implementation next.
```
