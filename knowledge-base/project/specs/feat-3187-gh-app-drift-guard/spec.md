---
feature: gh-app-drift-guard
issue: 3187
related_issues: [3181, 3183, 1784, 2887]
brand_survival: single-user-incident
status: spec
date: 2026-05-05
brainstorm: knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md
---

# Spec: GitHub App Drift-Guard

## Problem Statement

The existing `scheduled-oauth-probe.yml` (PR #3181) detects user-impact OAuth
failures by body-grepping the GitHub `/login/oauth/authorize` response for
each of the 3 registered callback URLs. It catches the H_C-class failure
where a callback URL is removed from the textarea (`redirect_uri is not
associated`).

It does NOT catch a stricter H_C class: an attacker (or accidental
mis-configuration) replaces the entire GitHub App with a different App that
registers the same 3 callback URLs. The OAuth probe stays GREEN. Users
continue to sign in — but to an attacker-controlled OAuth flow → user
credential exfiltration.

The threshold for shipping defensive credential infrastructure moved after
incident #2887 (dev/prd Doppler config collapse, brand-survival event,
2026-05-03). Founder cohort recruitment in Phase 4 hits GitHub OAuth on
first signin; a swap incident during recruitment is brand-ending.

## Goals

- **G1:** Detect App-identity drift within 1 hour of occurrence (MTTD ≤ 60min).
- **G2:** Distinguish drift detection (`ci/auth-broken`) from guard
  malfunction (`ci/guard-broken`) so triagers don't conflate the two.
- **G3:** Make any accidental PEM/JWT leak in workflow logs operator-visible
  within the same run (GDPR Article 33 72h notification clock survivability).
- **G4:** Zero supply-chain dependency on third-party Actions — the guard
  cannot rely on the same trust class it exists to detect.
- **G5:** Add Doppler to `compliance-posture.md` vendor DPA table (it now
  holds a brand-survival credential).

## Non-Goals

- **NG1:** Auto-escalation of `scheduled-oauth-probe.yml` on drift detection.
  Drift-guard fires → human triage → human decides if user-probe escalates.
- **NG2:** Real-time alerting via Sentry breadcrumb mirror. Deferred to
  follow-up (covered by `cq-silent-fallback-must-mirror-to-sentry` for the
  Pino-only case; this guard is workflow-only and email-notified).
- **NG3:** Pre-written user-communication template for confirmed compromise.
  Deferred to follow-up issue.
- **NG4:** Doppler RBAC review (confirm secret-readers are limited to CI
  service token + named admins). Deferred to follow-up; document current
  state in compliance-posture entry.
- **NG5:** Installation-level guard (unexpected installations of our App).
  Different concern; file separately if priority increases.

## Functional Requirements

- **FR1:** A scheduled workflow at `.github/workflows/scheduled-github-app-drift-guard.yml`
  runs hourly via `cron: '0 * * * *'` and on `workflow_dispatch:` (operator
  manual run only — not invocable from forks).
- **FR2:** Workflow loads `GITHUB_APP_PRIVATE_KEY_B64`, decodes to
  `$RUNNER_TEMP/app.pem` with `umask 077`, validates shape via
  `openssl rsa -in $KEY_FILE -check -noout`, masks via `::add-mask::` on the
  decoded content, fails fast with `ci/guard-broken` issue on shape error.
- **FR3:** Workflow mints an RS256 App JWT with 10-minute expiry using inline
  `openssl dgst -sha256 -sign` (no third-party Action). Header + payload
  built via `printf` + base64url encoding. JWT masked via `::add-mask::`
  immediately on materialization.
- **FR4:** Workflow calls `gh api /app` with the JWT. On HTTP error (401,
  403, 5xx), files/updates a `ci/guard-broken` issue with the HTTP status
  and a redacted excerpt.
- **FR5:** Workflow asserts response `client_id` matches secret
  `OAUTH_PROBE_GITHUB_CLIENT_ID` AND response `id` matches secret
  `GITHUB_APP_DATABASE_ID`. Both expected and actual values undergo presence
  checks (non-empty) BEFORE comparison. Mismatch fires a `ci/auth-broken`
  issue with the observed vs expected (redacted appropriately).
- **FR6:** On any failure path, the existing `notify-ops-email` composite
  action is invoked (same pattern as `scheduled-oauth-probe.yml`).
- **FR7:** Issue file/update logic uses dedup key `github-app-drift` (separate
  from `oauth-probe` dedup). Existing PR #3181 dedup pattern is the reference.
- **FR8:** A final post-step greps the rendered run log for `BEGIN .* PRIVATE KEY`
  and `eyJ` (JWT prefix). If found → fail the run AND file/update a
  `ci/guard-broken` issue labeled additionally with `security/leak-suspected`.
  This step runs `if: always()`.
- **FR9:** Workflow ends with `shred -u "$RUNNER_TEMP/app.pem"` (best-effort —
  failure here logs a warning but does not fail the run; ephemeral runner
  filesystem is destroyed regardless).

## Technical Requirements

- **TR1:** Workflow `on:` block contains ONLY `schedule:` and
  `workflow_dispatch:`. NEVER `pull_request_target`, `workflow_run`, or
  `pull_request`. Plan-time review must verify.
- **TR2:** Workflow-level `permissions:` is `contents: read` AND
  `issues: write`. NO `id-token`, NO `actions: write`, NO `pages`, NO others.
- **TR3:** `actions/upload-artifact` is forbidden in this workflow. Plan-time
  review and the test in TR8 must enforce.
- **TR4:** `set -x` is forbidden in any step that has `GITHUB_APP_PRIVATE_KEY_B64`
  or the JWT in env. Plan-time review must verify.
- **TR5:** All third-party Actions used MUST be SHA-pinned (matching
  `scheduled-oauth-probe.yml` pattern). New SHA pins flagged at plan-time.
- **TR6:** A CODEOWNERS entry on `.github/workflows/scheduled-github-app-drift-guard.yml`
  requires both engineering and legal/security review for any future
  modification.
- **TR7:** Doppler `prd` config gains `GITHUB_APP_PRIVATE_KEY_B64` (base64 of
  the App's PEM private key). Sync to GitHub workflow secret via `gh secret
  set GITHUB_APP_PRIVATE_KEY_B64` from Doppler. (Note: `GITHUB_*` prefix
  workflow-secret restriction does NOT apply to org or repo secrets that
  start with `GITHUB_APP_*` — verify at plan time per learning
  `2026-05-04-github-secrets-cannot-start-with-github-prefix.md`.)
- **TR8:** Vitest contract test (`apps/web-platform/test/github-app-drift-guard-contract.test.ts`
  or repo-level test under `test/`) locks the load-bearing invariants:
  trigger surface (schedule + workflow_dispatch only), permissions block,
  presence of leak-tripwire step, presence of presence-checks before
  comparison, dedup key, label set, no `actions/upload-artifact`, no `set -x`
  with PEM/JWT in env. Pattern: `oauth-probe-contract.test.ts` from PR #3181.
- **TR9:** `verify-required-secrets.sh` (or equivalent) gains shape checks
  for `GITHUB_APP_PRIVATE_KEY_B64` (base64-decodable, decodes to a PEM
  beginning with `-----BEGIN`) and `GITHUB_APP_DATABASE_ID` (numeric, length
  6-12). Same warn-not-error + override env-var pattern as the
  `OAUTH_PROBE_GITHUB_CLIENT_ID` shape check from PR #3181.
- **TR10:** Add Doppler row to `knowledge-base/legal/compliance-posture.md`
  vendor DPA table with current state. File a follow-up issue if DPA
  verification is needed.
- **TR11:** New runbook `knowledge-base/engineering/ops/runbooks/github-app-drift.md`
  covering: triage flow on `ci/auth-broken` vs `ci/guard-broken`, how to
  rotate the private key if leak is suspected, decision tree for escalating
  the user-facing OAuth probe, template for the post-incident retro.

## Acceptance Criteria

- [ ] AC1 (issue): GitHub App private key in Doppler `prd` as `GITHUB_APP_PRIVATE_KEY_B64`
- [ ] AC2 (issue): `GITHUB_APP_PRIVATE_KEY_B64` workflow secret set
- [ ] AC2a: `GITHUB_APP_DATABASE_ID` workflow secret set (added during spec)
- [ ] AC3 (issue): Hourly workflow that mints JWT, calls `gh api /app`,
      asserts `client_id` AND `id` match expected (modified from issue's
      "daily" cadence per CTO recommendation)
- [ ] AC4 (issue): Failure path files an issue with `ci/auth-broken` (drift)
      or `ci/guard-broken` (malfunction) — three-way label split added
- [ ] AC5 (CLO): Workflow `on:` is schedule + workflow_dispatch only
- [ ] AC6 (CLO): `permissions:` minimal; `actions/upload-artifact` forbidden
- [ ] AC7 (CLO): Leak tripwire post-step (greps logs for
      `BEGIN .* PRIVATE KEY` and `eyJ`) blocks the run if either present
- [ ] AC8 (CLO): CODEOWNERS entry for the new workflow file
- [ ] AC9 (CLO): Doppler row added to `compliance-posture.md`
- [ ] AC10 (CTO): Vitest contract test locks all load-bearing invariants
- [ ] AC11 (CTO): `verify-required-secrets.sh` shape checks for both new
      secrets (warn-not-error + override env-var pattern)
- [ ] AC12: Runbook `github-app-drift.md` published
- [ ] AC13: Manual `workflow_dispatch` run on main is GREEN with both
      assertions passing
- [ ] AC14 (PR-time): `user-impact-reviewer` agent sign-off (per
      `hr-weigh-every-decision-against-target-user-impact`,
      `single-user incident` threshold)

## Out-of-Scope (Follow-ups to file at plan time)

- Sentry breadcrumb mirror for JWT-mint + `gh api /app` response hash
- Pre-written user-comm template `knowledge-base/legal/incident-templates/github-app-compromise.md`
- Doppler RBAC review (limit `GITHUB_APP_PRIVATE_KEY_B64` readers)
- Installation-level guard (detect unexpected installations of our App)

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-05-github-app-drift-guard-brainstorm.md`
- Reference workflow: `.github/workflows/scheduled-oauth-probe.yml` (PR #3181)
- Reference contract test: `apps/web-platform/test/oauth-probe-contract.test.ts` (PR #3181)
- Composite action: `.github/actions/notify-ops-email`
- Drift-guard self-silent-failure learning: `knowledge-base/project/learnings/best-practices/2026-04-18-drift-guard-self-silent-failures.md`
- GitHub App callback URL learning: `knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md`
- GitHub secrets `GITHUB_*` prefix learning: `knowledge-base/project/learnings/integration-issues/2026-05-04-github-secrets-cannot-start-with-github-prefix.md`
- AGENTS.md rules: `hr-weigh-every-decision-against-target-user-impact`,
  `cq-silent-fallback-must-mirror-to-sentry`, `cq-test-fixtures-synthesized-only`
- Brand-survival precedent: incident #2887 (2026-05-03)
