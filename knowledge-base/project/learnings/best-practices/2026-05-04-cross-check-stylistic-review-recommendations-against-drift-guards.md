---
module: review skill
date: 2026-05-04
problem_type: process_issue
component: review-pipeline
symptoms:
  - "Architecture-review proposed cosmetic op-name rename"
  - "Partial-suite vitest passed, full-suite failed on drift-guard test"
  - "Required revert + re-commit"
root_cause: missing-pre-apply-validation
severity: medium
tags: [code-review, drift-guard, sentry, naming-discipline]
synced_to: []
---

# Cross-check stylistic review recommendations against existing drift-guard tests

## Problem

During multi-agent code review of PR #3126 (auth callback fix), the
`architecture-strategist` recommended renaming the four Sentry `op` values
in `apps/web-platform/app/(auth)/callback/route.ts` to a uniform
`callback_*` prefix, on the reasoning that "Sentry queries grouping by
`op startswith \"callback_\"` will miss two of four sites."

The recommendation looked clean and was applied:

```diff
- op: "exchangeCodeForSession"
+ op: "callback_exchange_error"
- op: "getUser_null_after_exchange"
+ op: "callback_get_user_null"
```

The targeted vitest suite (`test/lib/auth/ test/app/auth/`) still passed
(72/72). The full suite then failed on `test/auth/sentry-tag-coverage.test.ts`:

```
FAIL  app/(auth)/callback/route.ts: calls .exchangeCodeForSession() but
      missing op:"exchangeCodeForSession" in Sentry mirror
```

That test is a load-bearing drift-guard: it asserts every Supabase auth
verb call site mirrors to Sentry with `op: "<verb>"` matching the SDK
method name verbatim, because the alert rules in
`apps/web-platform/scripts/configure-sentry-alerts.sh` filter on those
exact tag values. Renaming for cosmetic uniformity would have silently
broken paging.

The rename was reverted; the original SDK-verb-keyed names shipped.

## Root Cause

Architecture-style review agents optimize for static legibility (uniform
naming, telegraphing structure) without modeling operational coupling
(alert rules, schema bindings, dashboard queries). A drift-guard test
exists to enforce the operational invariant — but the agent did not read
it, and partial-suite execution at the work boundary did not run it.

## Solution

Two-part fix:

1. **Run the full vitest suite (`npx vitest run` from the app root) before
   committing any review-driven rename.** Targeted runs at the work
   boundary (`vitest run <changed-area>`) catch local breakage but miss
   cross-cutting drift-guards in sibling test files.
2. **When a review agent prescribes a rename, search for drift-guards
   that reference the old name first.** Cheapest gate:

   ```bash
   rg -l '"<old-op-name>"' test/ apps/*/test/ 2>/dev/null
   ```

   Any hit is a load-bearing lock — the rename is operational, not
   stylistic, and the agent's recommendation must be evaluated against
   the existing invariant. Drift-guards typically live in
   `test/**/coverage*.test.ts` or `**-drift.test.ts` files.

## Key Insight

**Stylistic agent recommendations are warnings, not directives.**
Operational naming locks (alert rule matchers, schema bindings, FK
references, drift-guard tests) supersede uniformity. A naming
recommendation that has no concrete benefit beyond "it reads cleaner"
should never override an operational test failure.

The corollary: drift-guards exist precisely because cosmetic refactors
silently break alert paging. The test was added in PR #2994 specifically
because Sentry alert rules were configured against verbatim SDK method
names; the naming convention is not a convention, it's a contract.

## Prevention

- **Pre-merge gate (already in place):** `/work` Phase 3 runs the full
  test suite. Honor this — never commit after only running a targeted
  subset on review-driven changes.
- **Pattern for review-pipeline edits:** before applying a rename, grep
  for the old name across `test/` and `**-drift.test.ts` siblings.
- **Stylistic vs operational distinction:** when an agent justifies a
  rename with "uniformity" or "queryability," demand a concrete consumer
  the rename improves AND the consumer's failure mode if it stays the
  way it is. If the only failure mode is "the prefix isn't uniform," the
  recommendation is cosmetic and should be skipped.

## Session Errors

- **Sentry token scope (`org:ci`) blocked event-payload retrieval** for
  the demo-failure event `34d20156…`. Second occurrence (first was the
  2026-03-30 PKCE incident). Recovery: substituted runbook + Playwright
  reproduction for the live event payload. **Prevention:** widen
  `SENTRY_AUTH_TOKEN` scope to include `event:read` (file CTO-domain
  follow-up issue) OR add a `sentry-event-lookup.sh` helper that uses
  the per-session OAuth flow when `org:ci` is insufficient.
- **Next.js dev server crashed on first compile** with `MODULE_NOT_FOUND`
  on `vendor-chunks/lib/worker.js`. Recovery: `rm -rf .next && restart`.
  **Prevention:** Pre-existing Next 15 dev-mode flakiness, not a
  workflow gap; document the recovery in dev runbook if it recurs.
- **Architecture-review's stylistic op-rename conflicted with drift-guard**
  test. Recovery: reverted the rename, kept SDK-verb-keyed names. **Prevention:** see Solution / Prevention sections above — full-suite gate + grep-for-drift-guards before applying review renames.
- **Plain `Request` lacks `request.cookies.getAll()`** — initial test
  fixtures used standard `Request`; route required `NextRequest`.
  Recovery: switched to `new NextRequest(...)` from `next/server`.
  **Prevention:** when testing a Next.js App Router route handler that
  reads cookies, headers, or geolocation, instantiate fixtures with
  `NextRequest`, not `Request`.
- **Negative-space `.toLowerCase` test falsely matched the docblock**
  that mentioned the forbidden idiom in a comment. Recovery: added a
  comment-stripping helper before the regex match. **Prevention:** in
  source-regex tests that forbid an idiom whose name might appear in
  docblock prose, strip `//` and `/* */` comments before matching.
- **Workflow-edit security hook initially blocked** the probe edit
  despite safe env-var usage; succeeded on retry with same content.
  Recovery: re-attempted the same edit, second attempt landed.
  **Prevention:** the hook is advisory-flavor with intermittent
  blocking; if the diff genuinely uses only declared env vars (no
  `github.event.*`), retry once.
- **Bash CWD persistence intermittent** — sometimes required `cd && cmd`
  chaining. Recovery: chained when output indicated wrong CWD.
  **Prevention:** for any vitest/typecheck/build/curl invocation that
  must run from `apps/<name>/`, prefer the chained form
  `cd <abs-path> && <cmd>` regardless of prior CWD state. Same class as
  the pre-existing learning on bare-repo CWD drift.

## Related

- PR #3126 — fix(auth): classify provider OAuth errors before code-exchange branch
- PR #2994 — added the `sentry-tag-coverage.test.ts` drift-guard
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — governs the
  `reportSilentFallback` invocation pattern that holds the op-name lock
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` — the
  drift-guard
- `apps/web-platform/scripts/configure-sentry-alerts.sh` — the alert
  rules that consume the op-name lock
