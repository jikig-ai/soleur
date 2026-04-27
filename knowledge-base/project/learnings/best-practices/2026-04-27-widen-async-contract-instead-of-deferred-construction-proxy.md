---
module: cc-soleur-go
date: 2026-04-27
problem_type: integration_issue
component: typescript_module
symptoms:
  - "KeyInvalidError surfaced under op: \"consumeStream\" instead of op: \"queryFactory\""
  - "errorCode: \"key_invalid\" never reached client; users saw generic \"router unavailable\""
  - "200+ lines of Query proxy indirection (8 forwarded methods, as any cast, eager .catch swallow)"
root_cause: sync_async_contract_mismatch
severity: high
tags: [contract-design, async-await, observability, proxy-anti-pattern, sentry-tagging]
synced_to: []
---

# Widen the async contract — don't proxy a sync interface around async work

## Problem

PR #2901 (Stage 2.12 — bind real-SDK `queryFactory` in `cc-dispatcher`) needed the new factory to fetch async user data (BYOK API key, service tokens, workspace path from Supabase) before constructing an SDK `Query`. The existing `QueryFactory` type in `apps/web-platform/server/soleur-go-runner.ts` was synchronous:

```ts
export type QueryFactory = (args: QueryFactoryArgs) => Query;
```

The runner consumed it inside a try/catch tagged with `feature: "soleur-go-runner", op: "queryFactory"` — the load-bearing observability boundary for factory-time errors.

The shipped solution wrapped the async work in a "deferred-build" Query proxy whose first iterator `.next()` lazily resolved the inner `query()`. The proxy satisfied the sync return type but pushed all async errors out of the runner's `op: "queryFactory"` catch and into `consumeStream`'s `op: "consumeStream"` catch — silently regressing two acceptance criteria:

- **AC14:** `KeyInvalidError` from `getUserApiKey` was supposed to surface to `dispatchSoleurGo`'s catch, which mapped it to `errorCode: "key_invalid"` so the client could prompt the user to renew their BYOK key. After the proxy, the error was wrapped as a `WorkflowEnd { status: "internal_error" }` and the client only saw the generic `"Command Center router is unavailable"`.
- **R10:** Sentry tag attribution drifted. Sandbox-startup failures still tagged correctly inside the inner IIFE, but layered observability invariants were fragile.

The proxy was caught by 4 of 10 review agents (architecture-strategist, performance-oracle, pattern-recognition-specialist, code-quality-analyst) plus the implementer's own "Open Concerns" note. The fix-inline pass deleted ~200 lines.

## Solution

**Widen the contract instead of working around it.** One-line type change:

```ts
// Before
export type QueryFactory = (args: QueryFactoryArgs) => Query;

// After
export type QueryFactory = (args: QueryFactoryArgs) => Promise<Query> | Query;
```

The runner's `dispatch()` was already `async`; `await deps.queryFactory({...})` inside the existing try/catch fires the `op: "queryFactory"` tag for both sync and async errors. Sync factories (legacy + tests) keep working — they return a resolved Query, the await resolves immediately. Async factories (cc-soleur-go) return a Promise; errors propagate through `await` to the same catch.

The cc-dispatcher factory becomes a real async function that fetches credentials, builds, and returns the real Query — no proxy, no `as any`, no eager `void ensureInner().catch(() => {})`. `KeyInvalidError` flows naturally to `dispatchSoleurGo`'s catch and maps to `errorCode: "key_invalid"` end-to-end (verified by tests T8 + T19 + T19b).

## Key Insight

When a synchronous interface forces async work behind a proxy, **change the interface**. Proxies that defer construction silently move errors out of their original observability scope — the errors still happen, but their Sentry tags, error-code mappings, and try/catch boundaries shift to a downstream consumer that wasn't designed to handle them.

The cost of widening a contract from `T` to `Promise<T> | T` is one type change + one `await`. Existing sync callers don't break. The cost of proxying around the sync contract was 200 LoC, two regressed acceptance criteria, four review-agent findings, and a follow-up commit.

**Heuristic:** if your "deferred construction" needs an inner IIFE to preserve observability tags that the outer contract used to provide, the contract is wrong.

## Cross-cutting fixes that landed in the same review-fix pass

These were independent issues, but the review surfaced them together. Documented here as a checklist for future SDK-binding work:

1. **Cleanup-helper doc-comment promised behavior the code didn't wire.** `cleanupCcBashGatesForConversation`'s JSDoc claimed it ran from runner close paths (`closeConversation`, `reapIdle`), but no caller existed. Fix: added an `onCloseQuery` dep to `createSoleurGoRunner`, fired from every internal close path before `activeQueries.delete`. **Lesson:** when adding a cleanup helper, wire its caller in the same edit; doc-comments that promise behavior require a grep-verified caller.

2. **Removed a once-per-process Sentry gate without replacement.** The old stub had `_stubMirroredOnce` to prevent quota flood if the flag flipped on with broken BYOK. The refactor deleted it; the new factory had no rate limit. Fix: added `mirrorWithDebounce(err, ctx, userId, errorClass)` helper with a 5-min TTL Map keyed by `${userId}:${errorClass}`. **Lesson:** rate-limit gates on observability calls are load-bearing; track them like any other runtime invariant when refactoring.

3. **Sequential DB fetches on cold path.** Three independent SELECTs were chained instead of `Promise.all`'d. Fix: `Promise.all([fetchUserWorkspacePath, getUserApiKey, getUserServiceTokens])`. **Lesson:** when cold-path fetches multiple independent values, default to `Promise.all` parallelism.

4. **esbuild rejects literal U+2028/U+2029 in regex source.** The fix-inline agent's first attempt at adding Unicode line-separator coverage to a sanitizer regex used literal Unicode bytes:

   ```ts
   // Crashes esbuild parse
   .replace(/[\x00-\x1f\x7f
]/g, " ")

   // Works
   .replace(/[\x00-\x1f\x7f  ]/g, " ")
   ```

   esbuild treats literal U+2028/U+2029 as regex terminators. Always use `\u`-escapes for these inside character classes. **Lesson:** non-obvious build-tool gotcha; if you add Unicode line-separator coverage to any regex literal, escape it.

## Tags

category: best-practices
module: cc-soleur-go

## Session Errors

1. **Deferred-build Query proxy ships a sync contract around async work.** Recovery: widened `QueryFactory` to `Promise<Query> | Query`, deleted ~200 LoC of proxy. Prevention: when a sync interface forces async work, change the interface — not the call site.
2. **Doc-comment promised cleanup-on-reap behavior the code didn't wire.** Recovery: added `onCloseQuery` dep to `createSoleurGoRunner` fired from every close path. Prevention: when adding a cleanup helper, wire its caller in the same edit; grep that the caller exists before merging.
3. **Removed `_stubMirroredOnce` Sentry gate without replacement.** Recovery: added per-(userId, errorClass) 5-min TTL debounce. Prevention: removing a rate-limit gate in a refactor requires equivalent replacement; flag rate-limits as load-bearing in PR descriptions.
4. **Comment line-number anchors violated `cq-code-comments-symbol-anchors-not-line-numbers`.** Recovery: replaced with symbol anchors. Prevention: rule already exists; consider grep-based pre-commit hook for `\.ts:\d+` patterns inside `// ` comments (false-positive risk on legitimate Sentry breadcrumbs requires careful scoping).
5. **Sequential DB fetches on cold path (workspace path before BYOK Promise.all).** Recovery: wrapped all 3 in single `Promise.all`. Prevention: when cold-path fetches multiple independent values, default to parallel; sequential await is the special case requiring justification.
6. **esbuild rejects literal U+2028/U+2029 in regex source.** Recovery: used ` `/` ` escapes inside the character class. Prevention: documented in this learning; if it recurs, promote to AGENTS.md rule.

## See Also

- [`2026-04-15-plan-skill-reconcile-spec-vs-codebase.md`](2026-04-15-plan-skill-reconcile-spec-vs-codebase.md) — related class: contracts that look right in the spec but diverge in the codebase
- [`2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`](../2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md) — companion learning on Sentry tagging precedent for the cc-soleur-go path
- PR #2901, issue #2884
- Scope-out issues filed: #2918 (patchWorkspacePermissions atomicity), #2919 (BYOK v1→v2 race), #2920 (updateConversationStatus no-op), #2921 (Bash batching), #2922 (drift-guard expansion), #2923 (system prompt context-injection)
