# Tasks — TR9 PR-4 drift-guard → Inngest

Source: `knowledge-base/project/plans/2026-05-22-feat-tr9-pr4-drift-guard-inngest-plan.md`

## Phase 0 — preconditions

- [ ] T0.1 Verify Doppler prd secrets (AC0.1): GH_APP_DRIFTGUARD_APP_ID, GH_APP_DRIFTGUARD_PRIVATE_KEY_B64, OAUTH_PROBE_GITHUB_CLIENT_ID
- [ ] T0.2 Verify jq+bash on Inngest VM via cloud-init (AC0.2)
- [ ] T0.3 Verify @octokit/app in package.json (AC0.3)
- [ ] T0.4 Verify 7 labels exist (AC0.4)

## Phase 1 — code (factory + handler + registration)

- [ ] T1 RED: write cron-github-app-drift-guard.test.ts skeleton + happy-path test (AC24 a)
- [ ] T2 GREEN: add createAppJwtOctokit() factory to probe-octokit.ts (AC4)
- [ ] T3 GREEN: implement cron-github-app-drift-guard.ts handler scaffolding (AC1, AC3, AC7, AC11)
- [ ] T4 RED+GREEN: per-failure-mode mapping (AC2, AC24 b)
- [ ] T5 RED+GREEN: leak tripwire `assertNoLeak` + LeakDetectedError (AC6, AC24 e)
- [ ] T6 RED+GREEN: manifest-diff via spawn (AC8, AC24 f)
- [ ] T7 RED+GREEN: MANIFEST_DRIFT_SUPPRESS_UNTIL gate (AC9, AC24 f)
- [ ] T8 RED+GREEN: installation iteration + diff (AC10, AC24 g+h)
- [ ] T9 RED+GREEN: ops-email Resend POST (AC5)
- [ ] T10 RED+GREEN: fork-PR fallback test (AC24 c) + issue-filing branch (AC24 d)
- [ ] T11 Register cronGithubAppDriftGuard in app/api/inngest/route.ts (AC11)

## Phase 2 — workflow + CODEOWNERS + cross-refs

- [ ] T12 Delete .github/workflows/scheduled-github-app-drift-guard.yml (AC12)
- [ ] T13 Delete .github/CODEOWNERS:17 (AC13)
- [ ] T14 Update .github/workflows/scheduled-ruleset-bypass-audit.yml prose refs (AC15)
- [ ] T15 Update apps/web-platform/infra/github-app.tf:28 ref (AC21)
- [ ] T16 Update bin/snapshot-github-app.sh:5,52 comment refs (AC22 note)

## Phase 3 — Sentry monitor IaC

- [ ] T17 Revert cron-monitors.tf drift-guard bump 360→30, 2→1 (AC16)
- [ ] T18 Rewrite joint-exception breadcrumb lines 24-41 (AC17)
- [ ] T19 Delete lines 98-106 transitional comment block (AC18)

## Phase 4 — runbook sweep

- [ ] T20 Update github-app-drift.md operator surfaces + Better Stack note (AC19)
- [ ] T21 Update github-app-provisioning.md cross-refs (AC20)
- [ ] T22 Run AC22 grep sweep, verify 0

## Phase 5 — tests + deletion

- [ ] T23 Delete apps/web-platform/test/github-app-drift-guard-contract.test.ts (AC23)
- [ ] T24 Update github-app-manifest-drift-guard.test.ts header comment only (AC25)
- [ ] T25 Add cron-no-byok-lease-sweep coverage check (AC28)

## Phase 6 — verification gates

- [ ] T26 terraform validate (AC26)
- [ ] T27 bun run typecheck + vitest (AC27)
- [ ] T28 cron-no-byok-lease-sweep auto-extends (AC28)
- [ ] T29 CQ1–CQ6 substrate self-check
- [ ] T30 Emission-site grep gate (Sharp Edge #3 → AC24 e)

## Phase 7 — ship gating

- [ ] T31 GDPR gate (skip per CLO override documented in plan)
- [ ] T32 Full-suite exit gate scripts/test-all.sh
- [ ] T33 PR body uses Closes #4235 + Closes #3750 (AC29)
