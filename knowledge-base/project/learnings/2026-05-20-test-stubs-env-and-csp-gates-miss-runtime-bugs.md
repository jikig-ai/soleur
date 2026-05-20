# Learning: test stubs + HTML-only canaries miss env-var and CSP runtime bugs

## Problem

PR #4121 (#4115) added `/internal/github-app-init` — a server-rendered page that POSTs a manifest JSON to GitHub's App-create form. PM3 (#4171) deferred operator dogfood to post-merge. When PM3 finally ran (~2h post-merge), TWO production-class bugs surfaced:

1. **`APP_DOMAIN` env var missing in Doppler dev + prd.** The page's `resolveAppDomain()` calls `process.env.APP_DOMAIN`; missing → throws → 500. The page returned 500 on EVERY operator visit since #4121 merged.
2. **CSP `form-action 'self'` blocked the cross-origin POST to `https://github.com/settings/apps/new`.** Button click did nothing — silently blocked in console. The feature was non-functional in production.

Both shipped because all pre-merge gates passed:

- CI tests (28+ in `csp.test.ts`, 8 in `github-app-init-page.test.ts`): green
- Preflight Check 2 (security headers): doesn't probe `/internal/github-app-init` form-action specifically
- Layer 1 canary (`/health`, `/login`, `/dashboard`): HTML-only fetch; doesn't exercise form-POST
- Plan-time review (3 agents): plan referenced `process.env.APP_DOMAIN` but reviewers had no checklist linking "code reads env var" to "Doppler config has env var"

## Solution

**Bug 1 (APP_DOMAIN)**: Set in Doppler dev + prd, then `gh workflow run web-platform-release.yml` to redeploy. (`doppler secrets set APP_DOMAIN ... -p soleur -c prd` + same for dev.)

**Bug 2 (CSP)**: PR #4184 — `apps/web-platform/lib/csp.ts` adds optional `formActionExtra: string[]` parameter to `buildCspHeader`. Middleware passes `['https://github.com']` only when `pathname === '/internal/github-app-init'`. Defense-in-depth: extras must be in `FORM_ACTION_ALLOWLIST` (currently only `https://github.com`); unknown origins throw at build time.

## Key Insight

**Test stubs + HTML-only canaries are blind to two large defect classes:**

1. **Env-var contract drift**: `process.env.X` referenced in code; tests set `process.env.X = "..."` before exercising it. The test passes; the runtime (without the env var set in Doppler/secret-manager) fails fast. **The fix is not "remove the test stub" — tests legitimately need to stub env. The fix is to add an `## Env-Vars` deliverable section to the plan template that mirrors every `process.env.<X>` reference into a "must be set in Doppler <env>" task with concrete `doppler secrets set` command.**

2. **CSP/security-header runtime checks**: HTML-only canary probes (curl + grep for sentinel markers) cannot simulate browser-context security-policy enforcement. CSP `form-action`, `connect-src`, `frame-src` violations only fire in real browser sessions. **The fix is operator dogfood at PM-class follow-throughs — explicitly, every PR that adds a new cross-origin form POST, fetch(), or iframe MUST include a Playwright assertion in `apps/web-platform/test/e2e/` that exercises the path in a real browser context against the live CSP.**

## Process Pattern: PM-class follow-throughs as the gate-of-last-resort

PR #4121's `/ship` Phase 7 Step 3.5 filed 3 PM follow-throughs (#4169, #4170, #4171). PM1 caught the manifest-permissions miss (`secrets: write` absent — fixed in PR #4174). PM2 verified the drift-guard cron silence (manually triggered via `workflow_dispatch` since natural cron was delayed). **PM3 caught both bugs above** — bugs that no automated gate caught because they require an authenticated ADMIN_USER_IDS browser session against the live production deploy.

PM-class follow-throughs are the workflow's "operator dogfood" sentinel. Their value is asymmetric: low cost to file (one issue per ship), high probability of catching prod-class bugs that defied 12+ pre-merge gates. **The pattern: if a feature has any of (a) operator-only routes, (b) cross-origin requests, (c) Doppler-sourced env vars, (d) custom CSP needs, file a PM follow-through at ship time. Operator runs it in their next browser session.**

## Session Errors

1. **Doppler `APP_DOMAIN` was never set when #4121 merged.** Recovery: `doppler secrets set` in dev + prd, `gh workflow run web-platform-release.yml` redeploys with new env var. Prevention: extend `plan-issue-templates.md` to require an `## Env-Vars` deliverable section that mirrors every `process.env.*` reference into a Doppler-write task.

2. **CSP `form-action 'self'` blocked the feature's load-bearing POST.** Recovery: per-route extension in `middleware.ts` (PR #4184). Prevention: add a preflight Check 11 ("Cross-origin form-POST CSP check") that scans the diff for `<form action="https://..."` patterns and asserts a matching per-route CSP override exists. Cheapest fix: pre-merge Playwright e2e for any new cross-origin form surface.

3. **Playwright browser context closed repeatedly between MCP calls.** Recovery: re-issue `mcp__playwright__browser_navigate` to reopen. Prevention: keep the browser alive by chaining tool calls in tight sequence; avoid intermediate bash calls that exceed the session-context idle timeout.

4. **`Closes #N` in PR body when a verification follow-through still pending is risky.** PR #4174's `Closes #4169` auto-closed #4169 on merge, but PM3 (#4171) hadn't run yet — and surfaced two more bugs that needed PR #4184. If the dogfood had failed in a way that required reverting #4121, the auto-close would have been premature. **For follow-through-class issues (PM1/PM2/PM3), prefer `Ref #N` + manual close after the verification runs.** This is the `Closes-after-apply` pattern from `wg-use-closes-n-in-pr-body-not-title-to` — applied to PM-class verification follow-throughs.

## Tags

category: best-practices
module: github-app-manifest, csp, deploy-verification
related: 2026-05-20-manifest-authoring-must-snapshot-live-state-not-plan-time-memory
