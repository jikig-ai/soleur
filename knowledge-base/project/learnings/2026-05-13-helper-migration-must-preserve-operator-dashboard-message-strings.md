---
module: apps/web-platform/server/observability
date: 2026-05-13
problem_type: integration_issue
component: typescript_helper_migration
symptoms:
  - "Operator dashboard queries keyed on pino message strings silently break after helper migration"
  - "Multi-agent review (data-integrity-guardian P1) catches what unit tests miss"
  - "Co-located unmigrated sites on the same route file slip past plan-inventory phase"
root_cause: helper_default_substitutes_original_message
severity: high
tags: [helper-migration, operator-dashboards, observability, sentry, pseudonymisation, plan-inventory, three-dot-diff, async-context, asynclocalstorage, withisolationscope, multi-agent-review, cost-of-filing-gate]
synced_to: []
---

# Helper-migration must preserve original logger message strings + plan-inventory blind spots

## Problem

PR-B of #3698 (`#3710`, PR `#3731`) migrated 11 sites from the
`logger.error({err, userId}, "<msg>") + Sentry.captureException(err, {tags,
extra})` two-channel pattern to the centralised `reportSilentFallback(err,
{feature, op, extra})` helper. Each site was additionally wrapped in
`Sentry.withIsolationScope(() => { setUser({id: hashUserIdValue(userId)});
... })` for symmetric Sentry-side pseudonymisation.

Three distinct problem classes surfaced at multi-agent review (5 P1s, 0
caught by the 4293-passing unit suite):

1. **9 of 10 sites silently dropped the original pino message string.**
   Pre-PR diagnostics like `"Failed to store service token"`, `"Repo clone
   failed"`, `"Workspace provisioning failed"` were replaced with the
   helper's default `"<feature> silent fallback"` because the caller didn't
   pass `message:`. The helper at `apps/web-platform/server/observability.ts:154`
   composes the pino log via `message ?? \`${feature} silent fallback\``, so
   an omitted `message` is structurally invisible at the call site — no
   typecheck, no test, no lint flag. Operator dashboards / Better Stack
   saved queries that match on the literal string would silently miss every
   occurrence post-merge.

2. **Plan inventory missed a co-located unmigrated site on the same route
   file.** The plan listed `accept-terms:73` (the captureMessage non-Error
   path) but missed `accept-terms:60-67` (the DB-error captureException
   path). The PA8 §(c) Article 30 register update then claimed
   "Authenticated request handlers bind setUser … inline at each of the ten
   helper-migration sites" — but a regulator grepping the same file would
   find a co-located unmigrated path that breaks the symmetry claim.

3. **Cross-artifact disclosure cited a PR number instead of a stable file
   path.** The Article 30 register said "(full inventory in PR #3731)".
   PR descriptions are immutable but not navigable from the canonical
   disclosure; if the inventory expands (extract-helper refactor),
   the legal disclosure becomes stale and the regulator-facing claim ages out.

The F3 isolation gate's initial test mock also broke under async callbacks:
modeling `Sentry.withIsolationScope` as synchronous save/restore via shared
`{current: User|null}` worked for sequential tests but produced a vacuous
green on concurrent `Promise.all` because the `finally { current = saved }`
fires synchronously after `fn()` returns the Promise (not after it resolves).

## Solution

Three inline fixes plus one mock rewrite:

**Fix 1 — Add `message:` to each helper call site:**

```typescript
// Before — message defaulted to "services silent fallback"
reportSilentFallback(dbError, {
  feature: "services",
  op: "store",
  extra: { userId: user.id, provider },
});

// After — original diagnostic string preserved
reportSilentFallback(dbError, {
  feature: "services",
  op: "store",
  message: "Failed to store service token",
  extra: { userId: user.id, provider },
});
```

**Fix 2 — Consolidate co-located accept-terms DB-error path (Shape A
migration applied at the missed site):**

```typescript
if (error) {
  Sentry.withIsolationScope(() => {
    Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });
    reportSilentFallback(error, {
      feature: "accept-terms",
      op: "record",
      message: "Failed to record acceptance",
      extra: { userId: user.id },
    });
  });
  return NextResponse.json({ error: "Failed to record acceptance" }, { status: 500 });
}
```

**Fix 3 — Canonical inventory comment block in `sentry-scrub.ts`:**

```typescript
// HOC binding (4 routes inherit setUser via with-user-rate-limit.ts):
//   - app/api/conversations/route.ts          (per withUserRateLimit)
//   - app/api/kb/search/route.ts              (per withUserRateLimit)
//   - app/api/kb/tree/route.ts                (per withUserRateLimit)
//   - app/api/chat/thread-info/route.ts       (per withUserRateLimit)
//
// Inline helper-migration sites (11 — each wraps reportSilentFallback in
// Sentry.withIsolationScope + setUser({id: hashUserIdValue(userId)})):
//   - app/(auth)/callback/route.ts            (auth-callback / user-upsert)
//   - app/(auth)/callback/route.ts            (auth-callback / workspace-provisioning)
//   - app/api/accept-terms/route.ts           (accept-terms / record — DB error)
//   - app/api/accept-terms/route.ts           (accept-terms / record — user row missing)
//   ...
```

Then update the Article 30 register to reference the file path instead of
PR #3731:

```markdown
... at each of the eleven helper-migration sites (canonical inventory:
header comment block in `apps/web-platform/server/sentry-scrub.ts`), each
wrapped in `Sentry.withIsolationScope(...)` ...
```

**Fix 4 — Async-faithful `withIsolationScope` mock via `AsyncLocalStorage`:**

```typescript
// Wrong — synchronous save/restore breaks under async callbacks
withIsolationScope: vi.fn(<T>(fn: () => T): T => {
  const saved = currentScope.current;
  currentScope.current = null;
  try { return fn(); }                // returns Promise immediately
  finally { currentScope.current = saved; }  // fires before async body resumes
}),

// Right — bind a per-scope cell to the async context
const sentryUserStore = new AsyncLocalStorage<{current: User|null}>();
withIsolationScope: vi.fn(<T>(fn: () => T): T => {
  const cell = { current: null };
  return sentryUserStore.run(cell, fn);
}),
```

## Key Insight

**Helper migrations alter operator-visible contracts even when the helper is
"behaviour-preserving" by type signature.** The `message?: string` optional
field passes typecheck and unit tests when omitted because the helper
substitutes a sensible default — but the default is NOT the value operator
dashboards have been scraping for months. A code-level "no behaviour change"
review can still produce a behaviour change at the operator-runbook boundary.

Three operationalisable rules:

1. **When migrating `logger.X({...}, "<msg>")` to any helper whose `message`
   is optional, plan-time AC must require explicit message preservation
   per site.** Treat the message string as part of the call-site's
   public contract, not as an implementation detail of the helper. Add to
   plan templates: "For each helper migration site, the AC must specify the
   `message:` value verbatim from the pre-migration log call."

2. **Plan-inventory phase must grep the migration-target file for sibling
   occurrences of the same primitive.** If `accept-terms/route.ts` has two
   `Sentry.captureException` sites and the plan migrates one, the other is
   a co-located scope-hazard. Sharp Edges for `/soleur:plan` and
   `/soleur:deepen-plan`: "When the plan inventory cites a specific
   file:line for migration, grep the file for ALL occurrences of the
   pre-migration primitive (`Sentry.captureException`,
   `Sentry.captureMessage`, `logger.error({...}, ...)`) and explicitly
   scope-in or scope-out each."

3. **Compliance disclosures must reference stable code paths, not PR
   numbers.** Legal documents under `knowledge-base/legal/**` outlive PR
   descriptions in operator memory. Cross-artifact contracts should resolve
   via committed file paths (`apps/web-platform/server/sentry-scrub.ts`
   header inventory) so post-merge readers find the canonical inventory by
   grep, not by GitHub archive access. Candidate hook: pre-commit lint
   flagging `PR #\d+` patterns in `knowledge-base/legal/**`.

For test mocks of SDK primitives that wrap async work: **default to
`AsyncLocalStorage` over closure-captured state.** A closure-only mock
passes single-test isolation but masks cross-promise bleed — the exact
regression class `Sentry.withIsolationScope` exists to prevent. The
production SDK (Sentry v10, OpenTelemetry, structured-logger) all use
AsyncLocalStorage / AsyncContextStrategy under the hood; modelling at the
same layer in tests survives SDK upgrades.

Bonus insight from the multi-agent review's cost-of-filing gate: filing
≤30-LOC / ≤2-file inline fixes was net cheaper than filing 5 scope-out
issues. Only TWO findings legitimately exceeded the gate (helper extraction
across 11 files; missing CI workflow with secret-provisioning) and were
filed `deferred-scope-out` with `code-simplicity-reviewer` CONCUR. The
default-to-inline-fix discipline kept the PR throughput net-positive
(closes #3710, opens 2 follow-ups).

## Tags

category: integration-issues
module: apps/web-platform/server/observability

## Session Errors

1. **Plan inventory missed co-located unmigrated Sentry sites on same route.**
   Recovery: migrated `accept-terms:60-67` inline during review-fix phase.
   Prevention: `/soleur:plan` + `/soleur:deepen-plan` must grep the
   migration-target file for ALL occurrences of the pre-migration primitive
   and scope-in/scope-out each (Sharp Edges addition).

2. **9 sites silently dropped original pino message strings.**
   Recovery: added `message: "<original>"` to each `reportSilentFallback`
   call.
   Prevention: plan-time AC template for any helper migration that takes
   `message?: string` must require explicit per-site message verbatim
   preservation.

3. **Article 30 register cited PR # instead of stable file path.**
   Recovery: added canonical inventory comment block in
   `sentry-scrub.ts`; updated register to reference the file path.
   Prevention: pre-commit hook on `knowledge-base/legal/**` flagging
   `PR #\d+` patterns.

4. **Referenced `sentry-post-merge-smoke.yml` workflow that doesn't exist.**
   Recovery: downgraded tasks.md §8.5 to manual; filed scope-out #3740.
   Prevention: plan/work-time check — every workflow path in tasks.md
   must `test -f .github/workflows/<file>` green.

5. **Initial F3 mock broke under async callbacks (synchronous save/restore
   pattern).** Recovery: switched to `AsyncLocalStorage`-based mock.
   Prevention: when mocking an SDK primitive supporting async contexts,
   default to `AsyncLocalStorage` over closure-captured state; closure-only
   mocks produce vacuous green on concurrent assertions.

6. **`sentry-scrub.ts` shipped with dead `userIdHashPreset` variable.**
   Recovery: auto-trimmed in tree by code-quality / code-simplicity
   reviewers (−2 LOC).
   Prevention: enable `noUnusedLocals` in `apps/web-platform/tsconfig.json`.

7. **Review prompt mis-tagged issue #3703 as PR.** Recovery: cosmetic —
   git-history-analyzer caught at review. Prevention: none required
   (one-off prompt error).

8. **Bash CWD reset across invocations forced absolute-path migration.**
   Recovery: switched to absolute paths from worktree root.
   Prevention: AGENTS rule already covers this
   (`hr-the-bash-tool-runs-in-a-non-interactive`); reinforce in skill
   prompts.

9. **`TaskUpdate` task #1 returned "Task not found" early in work phase.**
   Recovery: continued without it; cross-skill task context isn't
   preserved across skill invocations. Prevention: skill-level decision;
   no rule change needed.
