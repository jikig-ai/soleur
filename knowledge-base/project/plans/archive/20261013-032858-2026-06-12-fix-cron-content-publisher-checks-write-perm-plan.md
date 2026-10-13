---
type: bug-fix
classification: ops-remediation
brand_survival_threshold: aggregate pattern
lane: cross-domain
status: ready
created: 2026-06-12
branch: feat-one-shot-cron-publisher-checks-write-perm
sentry_id: 17933ec40d934b62909f8238bd504d3e
release: web-platform@0.122.10
---

# 🐛 fix: grant GitHub App `checks: write` so cron synthetic check-runs stop 403-ing

## Enhancement Summary

**Deepened on:** 2026-06-12
**Research agents used:** repo-research-analyst, learnings-researcher, architecture-strategist, code-simplicity-reviewer (+ verify-the-negative live API probes)

### Key Improvements (from deepen-plan)
1. **Live-verified the load-bearing facts:** installation ID `122213433` and live `checks` grant
   = `read` confirmed via `gh api`. The fix is necessary and the IDs in the post-merge ACs are current.
2. **Proved the drift window is unavoidable by sequencing.** Read `manifest-diff.ts:79-110`: any
   shared-key value mismatch routes to `permission_drift` in BOTH directions, so re-accept-first
   does not skip the suppress file. The reviewers' proposed reorder was investigated and correctly
   rejected — documented as a Sharp Edge so it isn't re-attempted.
3. **Corrected the drift-window anchor from merge→re-accept to DEPLOY→re-accept** — the guard reads
   the container filesystem, so suppression sizing is relative to deploy, not merge.
4. **Added the fail-open failure mode:** a forgotten suppress file blinds the hourly guard
   GLOBALLY; deletion is now a tracked, close-gating step, and the mode is in `## Observability`.
5. **Hard-gated issue closure on the `gh api` grant-verify**, not Playwright's apparent success.
6. Trimmed 1 non-load-bearing AC (`cron-safe-commit.test.ts still passes` — this diff doesn't touch it).

### Gates run
4.4 precedent/scheduled-work (no new cron — pass), 4.6 User-Brand Impact (present, threshold valid),
4.7 Observability (5 fields, no-SSH discoverability), 4.8 PAT-shaped (none), 4.9 UI-wireframe (no UI surface),
2.7 GDPR (skip — no regulated-data surface, no new data-movement).

## Overview

The Inngest cron `cron-content-publisher` (fnId `soleur-runtime-cron-content-publisher`)
logs an `HttpError: Resource not accessible by integration` on every run when it tries to
POST a synthetic GitHub check-run. The error is **caught and Sentry-mirrored** (handled=yes,
`pino-mirror` tag) — it does not crash the cron, but it (a) floods Sentry on a daily cadence
and (b) means the synthetic checks required by the `CI Required` ruleset are never posted, so
the bot PRs these crons open cannot satisfy required checks / auto-merge cleanly.

**Root cause (verified):** the GitHub App manifest
`apps/web-platform/infra/github-app-manifest.json:21` declares `"checks": "read"`. Creating a
check-run via `POST /repos/{owner}/{repo}/check-runs` requires `checks: write`. The
installation token minted from this App therefore lacks the scope.

**Failure site:** `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts:683` —
`safeCommitAndPr` posts one check-run per `SYNTHETIC_CHECK_NAMES` entry, gated by
`config.syntheticChecks`. The `catch` at line 693 routes the 403 to `reportSilentFallback`
(op `safe-commit-check-run-failed`), which is the exact `handled=yes` / `pino-mirror`
signature in the Sentry event.

**Blast radius is broader than the one cron in the title.** Five crons pass `syntheticChecks`
through this helper and all currently 403 on the check-run POST:

| Cron | File | Sentry monitor slug |
|------|------|---------------------|
| cron-content-publisher | `apps/web-platform/server/inngest/functions/cron-content-publisher.ts:322` | scheduled-content-publisher |
| cron-compound-promote | `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` | (per file) |
| cron-content-vendor-drift | `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` | (per file) |
| cron-rule-prune | `apps/web-platform/server/inngest/functions/cron-rule-prune.ts` | (per file) |
| cron-weekly-analytics | `apps/web-platform/server/inngest/functions/cron-weekly-analytics.ts` | (per file) |

The single manifest change fixes all five.

**The fix is two-plane** (the documented #4173 / #4189 pattern):

1. **Code plane** (this PR): change `"checks": "read"` → `"checks": "write"` in the manifest
   JSON, and add a parity-test value assertion so a regression to `read` fails CI.
2. **Live-grant plane** (automated post-merge via Playwright MCP): widen the App permission +
   re-accept the installation through the GitHub UI. There is **no GitHub API** to widen App
   permissions or accept an installation permission update — but per
   `hr-never-label-any-step-as-manual-without` and learning
   `workflow-patterns/2026-06-10-oauth-consent-screens-are-playwright-automatable-not-operator-only.md`,
   the consent click inside an already-authenticated session is a DOM interaction Playwright
   MCP performs. This is therefore automated in-session, NOT punted to the operator.

## Research Reconciliation — Spec vs. Codebase

| Premise (from issue) | Reality (verified) | Plan response |
|----------------------|--------------------|---------------|
| Cron calls `create-check-run` directly | Call is in shared helper `safeCommitAndPr` (`_cron-safe-commit.ts:683`), not the cron body | Fix the manifest (single source); no cron-body edit needed |
| Token "likely GITHUB_TOKEN or App token" | App installation token only (`mintInstallationToken` → `_cron-shared`); `hr-github-app-auth-not-pat` enforced, no PAT path | Keep App auth; only the App's `checks` scope is wrong |
| Affects one cron | Five crons share the `syntheticChecks` path | Manifest fix covers all five; tests/observability scoped to the shared helper + manifest |
| Manifest is the live source | Manifest JSON is the *declarative* source; live App + installation grant are *separate planes* that must be re-accepted via UI (no API/Terraform) | Add automated Playwright re-acceptance + drift-suppress sequencing |

## User-Brand Impact

**If this lands broken, the user experiences:** content scheduled in
`knowledge-base/marketing/distribution-content/` is published by the cron, but the
status-update bot PR cannot auto-merge (synthetic required checks never post), so the
distribution-status metadata silently drifts and the daily Sentry error keeps firing —
degrading operator trust in the cron fleet's green/red signal.

**If this leaks, the user's data/workflow is exposed via:** N/A — this widens a *write* scope
on an App that already holds `contents: write` / `pull_requests: write` / `issues: write`.
`checks: write` only lets the App post check-runs on its own repo; it grants no read access to
new data surfaces. No regulated-data surface is touched.

**Brand-survival threshold:** aggregate pattern — the failure is a recurring observability/
auto-merge degradation across the cron fleet, not a single-user data incident. No per-PR CPO
sign-off required; the section is present per the gate.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/infra/github-app-manifest.json` `default_permissions.checks` equals
      `"write"` (grep: `jq -r '.default_permissions.checks' apps/web-platform/infra/github-app-manifest.json` returns `write`).
- [x] `apps/web-platform/test/github-app-manifest-parity.test.ts` contains a test asserting
      `m.default_permissions?.checks` toBe `"write"` (mirrors the existing `administration` /
      `issues` value-assertion convention at lines 110-121), and the suite passes:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-app-manifest-parity.test.ts`.
- [x] `default_permissions` key SET is unchanged — only the `checks` *value* changes — so
      `github-app-manifest-parity.test.ts` "exact-key-set" test (line 175) still passes with no
      edit to `EXPECTED_PERMISSION_KEYS` (`checks` is already in the key set at line 64).
- [x] `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` is created with a strict ISO-8601
      UTC timestamp anchored to expected **deploy** time + ~24h (NOT merge — the drift guard reads
      the manifest + suppress file from the running container's filesystem, so the drift window
      opens at DEPLOY, not merge; ≤ 30-day cap enforced by drift-guard `SUPPRESS_MAX_WINDOW_MS`).
      Suppresses the self-inflicted `installation_permission_drift` alert in the deploy→re-accept
      window. (Verified mechanism: `cron-github-app-drift-guard.ts:235-275`; the suppress gate at
      `:407` short-circuits BOTH the App-level and per-installation diffs.)
- [x] Typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] PR body uses `Ref #<tracking-issue>` (NOT `Closes`) for the live-grant tracking issue —
      the fix is not complete until the post-merge re-acceptance succeeds
      (`wg-use-closes-n-in-pr-body-not-title-to`, ops-remediation `Ref` rule).

### Post-merge (automated, in-session)

- [ ] **Live App permission widen + installation re-accept via Playwright MCP** (NOT operator-only —
      see `Automation` note). Navigate to the App permissions settings
      (`https://github.com/organizations/jikig-ai/settings/apps/soleur-ai/permissions`), raise
      Checks to Read & write, save; then accept the installation update banner at
      `https://github.com/organizations/jikig-ai/settings/installations/122213433`
      ("Review request" → "Accept new permissions"). Per runbook
      `knowledge-base/engineering/operations/runbooks/github-app-provisioning.md` Step 2.1.
      `Automation: feasible — authenticated-session consent click is Playwright-MCP-driven
      (hr-never-label-any-step-as-manual-without; learning 2026-06-10-oauth-consent-screens-are-playwright-automatable-not-operator-only.md).`
- [ ] **Verify the grant (read-only, no SSH) — this is the HARD GATE on closure, not Playwright's
      apparent success:**
      `gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.checks'`
      returns `write`. A Playwright run that appears to succeed but did not persist the grant
      must NOT mark the step done — this `gh api` read is the source of truth.
- [ ] **Force a drift-guard re-check** to confirm both planes are in sync and the suppress file
      is no longer needed: trigger `cron/github-app-drift-guard.manual-trigger`; confirm it
      returns green (no `installation_permission_drift`).
- [ ] **Remove `MANIFEST_DRIFT_SUPPRESS_UNTIL`** (delete-commit) once the grant verifies `write`
      AND the drift guard is green. A stale suppress file is fail-open: while present it blinds the
      hourly guard to ALL permission drift on ALL installations (the gate at `:407` is global, not
      scoped to `checks`), bounded only by the 30-day cap. Track the deletion via the same `Ref #N`
      issue so it cannot be silently forgotten.
- [ ] **Confirm the original error stops:** after the next `cron-content-publisher` run (or a
      `cron/content-publisher.manual-trigger`), the Sentry `safe-commit-check-run-failed` op no
      longer fires for the run; check-runs post `completed/success`.
- [ ] Close the tracking issue (`gh issue close <N>`) only after grant-verify (`write`) +
      drift-green + suppress-file-deleted all pass (ops-remediation: issue closes post-remediation,
      not at merge).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

1. Confirm `github-app-manifest.json:21` currently reads `"checks": "read"`.
2. Confirm the parity test value-assertion convention exists (lines 110-121 assert
   `administration`/`issues` === `"write"` with the "exact-key-set test only checks keys"
   comment at line 117) and that `EXPECTED_PERMISSION_KEYS` already contains `"checks"` (line 64)
   — so the change is value-only, no key-set edit.
3. Confirm the drift-suppress file path + ISO-8601/30-day-cap validation
   (`cron-github-app-drift-guard.ts:70,235-275`) and the global short-circuit at `:407`.

### Phase 1 — Manifest fix (the one-line root cause)

- Edit `apps/web-platform/infra/github-app-manifest.json`: `"checks": "read"` → `"checks": "write"`.
- Keep alphabetical key order (it already sits between `administration` and `contents`).

### Phase 2 — Regression test (write the assertion that would have caught this)

- In `apps/web-platform/test/github-app-manifest-parity.test.ts`, add (next to the existing
  `issues === "write"` test at line 121):

```ts
// apps/web-platform/test/github-app-manifest-parity.test.ts
test("default_permissions.checks === 'write' (synthetic check-run POST requires it)", () => {
  const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
  // _cron-safe-commit.ts:683 POSTs /check-runs; checks:read 403s with
  // "Resource not accessible by integration" (Sentry 17933ec4…). Lock the
  // value so a regress to read fails CI, not production.
  expect(m.default_permissions?.checks).toBe("write");
});
```

- Run the suite to confirm RED-before / GREEN-after (the test fails against the unedited
  manifest, passes after Phase 1).

### Phase 3 — Drift-suppress sequencing file

- Create `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` containing a single strict
  ISO-8601 UTC timestamp set at create-time to **expected deploy time + ~24h** (the literal
  `2026-06-13T18:00:00Z` is an EXAMPLE — the implementer computes it relative to the actual
  deploy, NOT merge: the guard reads the suppress file + manifest from the running container's
  filesystem, so both the `checks:write` declaration and the suppression only take effect after
  the web-platform deploy ships, and they ride the SAME deploy atomically). This prevents the
  hourly drift-guard from filing a `ci/auth-broken` issue in the deploy→re-accept window where the
  manifest declares `checks: write` but the live installation still grants `checks: read`.
- **Order is arbitrary, not load-bearing (do NOT attempt a "re-accept first to skip the suppress
  file" reorder).** The drift diff (`manifest-diff.ts:79-110`) classifies ANY shared-key value
  mismatch as `permission_drift` in BOTH directions (a shared key with differing values populates
  `sharedKeysWithDiff`, and `driftCount` counts it regardless of which side is higher). So
  re-accepting live=`write` while the manifest still says `read` fires `permission_drift` exactly
  as the merge-first order does. The suppress file is required either way; merge-first is chosen
  because the manifest PR is the gating artifact.

### Phase 4 — Post-merge live-grant automation (Playwright MCP)

- Widen the App's Checks permission to Read & write in App settings, save.
- Accept the installation permission-update banner.
- Verify via `gh api … .permissions.checks` == `write`.
- Manual-trigger the drift guard; confirm green.
- Open a follow-up commit/PR to delete `MANIFEST_DRIFT_SUPPRESS_UNTIL` once green.

## Files to Edit

- `apps/web-platform/infra/github-app-manifest.json` — `checks: read` → `write` (the fix).
- `apps/web-platform/test/github-app-manifest-parity.test.ts` — add `checks === "write"` value
  assertion (regression lock).

## Files to Create

- `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL` — temporary ISO-8601 UTC suppress
  timestamp (deleted post-merge after re-acceptance verifies green).

## Open Code-Review Overlap

None. (Queried `gh issue list --label code-review --state open`; no open scope-out names
`github-app-manifest.json`, `_cron-safe-commit.ts`, or `github-app-manifest-parity.test.ts`.)

## Infrastructure (IaC)

No Terraform change. App permissions are NOT Terraform-managed: `github-app.tf` provisions only
Doppler secrets + the webhook `random_id`; the manifest JSON is the declarative permission
source, and the live grant is a GitHub-UI-only plane (no API/Terraform — vendor limit, runbook
Step 2.1). The drift-suppress file is a plain text marker read by the existing drift-guard cron,
not infra provisioning. Skipping the `## Infrastructure (IaC)` heading-contract subsections is
correct here — no server, secret, vendor, or persistent runtime process is introduced.

## Observability

```yaml
liveness_signal:
  what: cron-content-publisher (+4 sibling crons) Sentry cron monitors check in on each run
  cadence: daily (content-publisher 14:00 UTC); siblings per their schedules
  alert_target: Sentry cron monitor "scheduled-content-publisher" (+ siblings); github-app drift-guard hourly
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf:686; cron-github-app-drift-guard.ts
error_reporting:
  destination: Sentry via reportSilentFallback (op safe-commit-check-run-failed) — pre-fix this fires daily; post-fix it goes silent
  fail_loud: yes — the 403 is Sentry-mirrored (handled=yes); the FIX is that it stops firing
failure_modes:
  - mode: manifest declares checks:write but live installation still grants checks:read (the merge→re-accept window)
    detection: cron-github-app-drift-guard installation_permission_drift
    alert_route: GitHub issue label ci/auth-broken (SUPPRESSED via MANIFEST_DRIFT_SUPPRESS_UNTIL during the window)
  - mode: re-acceptance never completed → check-runs keep 403-ing after suppress window expires
    detection: Sentry op safe-commit-check-run-failed resumes + drift-guard fires ci/auth-broken once suppress expires
    alert_route: ci/auth-broken issue auto-filed by the hourly drift guard
  - mode: parity test regression (someone flips checks back to read)
    detection: github-app-manifest-parity.test.ts checks-value assertion fails in CI
    alert_route: CI red on PR (pre-merge)
  - mode: suppress file forgotten after re-acceptance succeeds (Phase 4 delete-commit skipped) — fail-open global drift blindness
    detection: MANIFEST_DRIFT_SUPPRESS_UNTIL still present after gh-api verify returns checks=write; drift guard emits a visible ::warning:: "Manifest drift suppressed until <ts>" each run
    alert_route: tracked via the Ref #N issue (deletion gated on close); 30-day cap bounds the blind window
logs:
  where: Sentry (handled events, op=safe-commit-check-run-failed, fn=cron-content-publisher); Inngest run logs
  retention: Sentry default project retention
discoverability_test:
  command: gh api /orgs/jikig-ai/installations --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions.checks'
  expected_output: write
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling permission fix. The change is a
single GitHub App scope widen + regression test; no user-facing surface, no product/marketing/
legal/finance implication. (Mechanical UI-surface override did not fire: no path under
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` is touched.)

## Hypotheses

- **H1 (confirmed):** `checks: read` in the manifest is the root cause — `POST /check-runs`
  requires `checks: write`. Verified against the manifest (`:21`) and the GitHub REST docs cited
  in the error URL (`/rest/checks/runs#create-a-check-run`).
- **H2 (rejected):** "wrong token type (GITHUB_TOKEN vs App)". The path uses an App installation
  token exclusively (`mintInstallationToken`); `hr-github-app-auth-not-pat` forbids a PAT
  fallback. The token *type* is correct; only its *scope* is wrong.
- **H3 (confirmed broader):** five crons, not one, share the failing `syntheticChecks` path —
  the manifest fix resolves all five.

## Risks & Mitigations

- **Self-inflicted drift alert in the merge→re-accept window.** Manifest declares `checks:write`
  while the live installation still grants `checks:read` → drift guard would file `ci/auth-broken`.
  *Mitigation:* `MANIFEST_DRIFT_SUPPRESS_UNTIL` (~24h, ≤30-day cap), removed post-merge once green.
- **Re-acceptance forgotten / Playwright run fails.** *Mitigation:* `Ref #N` tracking issue stays
  open; the suppress file expiry makes the drift guard resume `ci/auth-broken` (loud), and the
  Sentry `safe-commit-check-run-failed` op resumes — the failure is self-announcing, not silent.
- **Over-grant concern.** `checks: write` is the *minimum* scope for `POST /check-runs`; it does
  not widen read access to any new data surface (the App already holds broader `contents`/`pull_requests`/`issues` write).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold = aggregate pattern.)
- The fix is **two-plane**. Merging the manifest PR alone does NOT stop the error — the live
  installation grant must be re-accepted. Do not close the tracking issue at merge; close it only
  after `gh api … .permissions.checks == write` and the drift guard returns green.
- The synthetic check NAMES are load-bearing for the `CI Required` ruleset (`infra/github/ruleset-ci-required.tf`).
  This PR changes a *permission value only* — it must NOT touch `SYNTHETIC_CHECK_NAMES` or any
  check name (renaming a check silently un-requires it; see learning
  `2026-06-11-pipeline-consolidation-behavior-preserving-migration-traps.md`).
- Do not flip `checks` back to `read` "to be safe" — the parity test (Phase 2) now fails CI on
  that regression by design.
- **The drift window cannot be sequenced away.** The drift diff (`manifest-diff.ts:79-110`) routes
  ANY shared-key value mismatch to `permission_drift` in both directions, so neither merge-first nor
  re-accept-first avoids a self-inflicted `ci/auth-broken` alert during the transition. The
  `MANIFEST_DRIFT_SUPPRESS_UNTIL` file is the only mitigation; it is load-bearing, not ceremony.
- **The drift window is anchored to DEPLOY, not merge.** The guard reads the manifest + suppress
  file from the running container filesystem; both the `checks:write` value and the suppression go
  live only after the web-platform deploy ships. Size the suppress timestamp from expected deploy
  time, and remember the suppress file blinds the guard GLOBALLY (all installations) while present —
  delete it promptly post-re-acceptance.
