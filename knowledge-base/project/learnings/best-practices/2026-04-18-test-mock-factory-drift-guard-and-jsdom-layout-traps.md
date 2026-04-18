---
module: web-platform
date: 2026-04-18
problem_type: best_practice
component: testing_framework
symptoms:
  - "Hand-rolled mock object literals duplicated across 7+ test files drift silently when wrapped hook return shape changes"
  - "Inline native-setter copy-paste for controlled-value events repeated in 3 files"
  - "jsdom test gated on layout values (clientWidth > 0) silently passes as no-op"
  - "Plan scoped to N files actually touches N+M files (incomplete adoption)"
  - "Code comments referencing other code via line numbers (~line 826) drift on refactor"
root_cause: inadequate_documentation
resolution_type: code_fix
severity: medium
tags: [testing, mocks, drift-resistance, jsdom, di-seam, code-comments, factory-pattern]
---

# Test Mock Factory Drift-Guard, DI Seams, and jsdom Layout Traps

## Problem

PR #2574 drained two review-backlog issues from PR #2347 (#2386 test quality, #2391 code comment + scaling note). Implementation extracted shared test infrastructure across 10 files and surfaced several reusable patterns plus three classes of latent test-design bugs.

## Environment

- Module: web-platform (Next.js 15 + React 19 + vitest + jsdom)
- Affected Components: KB chat sidebar, chat-input draft persistence, selection-toolbar, MarkdownRenderer
- Date: 2026-04-18
- Branch: `feat-one-shot-drain-review-backlog-2386-2391`

## Symptoms

- 7 sidebar test files defined hand-rolled `wsReturn` literals — adding a field to `useWebSocket`'s return would silently leave 7 mocks stale (no compile error)
- 3 files inline-copied 6-line `setControlledValue` native-setter helpers
- `kb-chat-sidebar-banner-misc.test.tsx` test gated `scrollWidth <= clientWidth` assertions on `pre.clientWidth > 0` — always false in jsdom → silent green
- Plan listed 7 files; pattern-recognition agent found 3 more (`chat-page.test.tsx`, `chat-page-resume.test.tsx`, `error-states.test.tsx`) using the same hand-rolled pattern
- Originally written `ws-handler.ts` comment said "~line 826 — WS_CLOSE code SUPERSEDED" — line numbers drift, symbol names don't

## What Didn't Work

**Direct solution:** First-attempt design held; the hand-rolled-literal pattern was caught during planning, the layout-gated jsdom test was caught by review agents (test-design-reviewer + code-quality), and the line-number comment was caught by pattern-recognition agent.

## Session Errors

**tsc drift-catch (expected): UsageData missing fields after factory typing tightened**
- **Recovery:** Added missing `inputTokens`/`outputTokens` to `UsageData` literal in `chat-surface-sidebar.test.tsx:91`.
- **Prevention:** Factory `satisfies` + `ReturnType<typeof useWebSocket>` worked as designed — this is the failure mode the pattern is meant to surface.

**Dangling `fireEvent` import after replacing inline setValue helper**
- **Recovery:** Re-added `fireEvent` import; line 71 of `chat-input-draft-key.test.tsx` still used `fireEvent.keyDown`.
- **Prevention:** Before deleting an import, grep the symbol's usages in-file: `rg "\bfireEvent\b" <file>` must return zero before removal.

**Flake in first full-suite run, isolated rerun passes 4/4**
- **Recovery:** Re-ran full suite, passed clean. Suspected cross-test state leakage covered by existing `cq-raf-batching-sweep-test-helpers`.
- **Prevention:** No new rule needed — existing one already covers this class.

**Review finding: incomplete factory adoption (P1) — plan scoped 7, reality was 10**
- **Recovery:** Pattern-recognition agent found 3 additional files; extended factory adoption inline during review step.
- **Prevention:** When a plan says "extract factory for N files", validate N during planning by running `rg '<pattern>' test/` — don't trust the issue's enumerated file list.

**jsdom no-op test: `pre.clientWidth > 0` gate always false in jsdom**
- **Recovery:** Replaced layout-gated assertion with structural `[data-narrow-wrap='true']` ancestor check on a `data-narrow-wrap` attribute hook added to MarkdownRenderer.
- **Prevention:** Never gate a jsdom test on layout values (`clientWidth`, `scrollWidth`, `offsetHeight`, `getBoundingClientRect`). Either assert structure / attribute hooks, or move the layout check to Playwright.

**Fragile line-pointer in code comment ("~line 826 — WS_CLOSE code SUPERSEDED")**
- **Recovery:** Replaced with stable symbol-search anchor: `WS_CLOSE_CODES.SUPERSEDED`.
- **Prevention:** Code comments referencing other code MUST use symbol-search anchors (function names, exported constants, type identifiers), never line numbers — refactors silently desync line-number pointers but break (or trivially update) symbol references.

**Compound route-to-definition writes landed at bare-root paths instead of worktree paths**
- **Recovery:** Detected via `git status --short` showing empty after edits. Confirmed bare-root files were stale-synced filesystem artifacts (not on any branch), restored bare-root copies from `git show main:<path>`, and re-applied edits at worktree-absolute paths.
- **Prevention:** Existing `hr-when-in-a-worktree-never-read-from-bare` covers this. Compound SKILL.md lines 280-285 prescribe worktree-absolute paths plus a `git status --short` post-edit verification — running that verification immediately after each Edit/Write would have caught the misroute on the first edit instead of after three.

## Solution

### Pattern 1: Type-safe mock factory with `ReturnType<typeof>` + `satisfies`

```typescript
// apps/web-platform/test/mocks/use-websocket.ts
import type { useWebSocket } from "@/hooks/use-websocket";

type UseWebSocketReturn = ReturnType<typeof useWebSocket>;

export function createWebSocketMock(
  overrides: Partial<UseWebSocketReturn> = {}
): UseWebSocketReturn {
  return {
    sendMessage: vi.fn(),
    readyState: WebSocket.OPEN,
    // ... all required fields
    ...overrides,
  } satisfies UseWebSocketReturn;
}
```

When `useWebSocket` adds a return field, the factory fails to compile (`satisfies` + `ReturnType<typeof>`), forcing a single-site update across all 10 consumers instead of 10 silent-stale mocks.

### Pattern 2: `setControlledValue` DOM helper

```typescript
// apps/web-platform/test/helpers/dom.ts
export function setControlledValue(
  el: HTMLInputElement | HTMLTextAreaElement,
  value: string,
  cursor?: number
) {
  const setter = Object.getOwnPropertyDescriptor(
    el.constructor.prototype,
    "value"
  )?.set;
  setter?.call(el, value);
  if (cursor !== undefined) el.setSelectionRange(cursor, cursor);
  el.dispatchEvent(new Event("input", { bubbles: true }));
}
```

Replaces 6-line inline copies in 3 files.

### Pattern 3: DI seam via module-level `let` + `__resetForTest` exports

```typescript
// components/kb/selection-toolbar.tsx
let readSelection = () => window.getSelection()?.toString() ?? "";

export function __setReadSelectionForTest(fn: () => string) {
  readSelection = fn;
}
export function __resetReadSelectionForTest() {
  readSelection = () => window.getSelection()?.toString() ?? "";
}
```

Mirrors existing `__resetXxxForTest` convention at `server/rate-limiter.ts`, `server/share-hash-verdict-cache.ts`, `app/api/analytics/track/throttle.ts`. Eliminates monkey-patching `Selection.toString` in tests.

### Pattern 4: `data-*` attribute hooks as test API

```tsx
<pre data-narrow-wrap={isNarrow ? "true" : "false"}>{children}</pre>
```

Test asserts `closest("[data-narrow-wrap='true']")` instead of Tailwind classname (`whitespace-pre-wrap break-words`). Acceptable when jsdom can't inspect computed styles.

### Pattern 5: Stable code-comment anchors

```typescript
// BAD: drifts on refactor
// See ~line 826 — WS_CLOSE code SUPERSEDED

// GOOD: refactor-resilient
// See WS_CLOSE_CODES.SUPERSEDED handling below
```

## Why This Works

1. **`ReturnType<typeof fn>` + `satisfies`** binds the mock factory's contract to the wrapped hook's actual signature. TypeScript treats them as one type — adding a field to the hook's return surfaces a type error at the factory definition, not at each consumer.
2. **DI seam over monkey-patch** keeps test setup co-located with the seam (no need to remember which jsdom global to patch and reset across `beforeEach`/`afterEach`).
3. **Attribute hooks bypass jsdom's layout limitations** while keeping the assertion meaningful (the attribute reflects component state).
4. **Symbol-search code comments** rely on grep-stable identifiers that fail loudly when renamed (review surfaces them) instead of failing silently when unrelated lines shift.

## Prevention

- For test mock factories of hooks with non-trivial return types: always use `ReturnType<typeof hook>` + `satisfies` to drift-proof against hook-shape changes.
- For "extract factory for N files" plans: validate N during planning with `rg '<distinguishing-pattern>' test/` before committing to a scope.
- Never gate a jsdom assertion on layout-engine output (`clientWidth`, `scrollWidth`, `offsetHeight`, `getBoundingClientRect`). Move layout checks to Playwright; assert structure or attribute hooks in jsdom.
- Code comments referencing other code locations MUST use symbol-search anchors (function/constant/type names), never line numbers.
- Before deleting an import, grep the symbol in-file to confirm zero remaining usages.

## Related Issues

- See also: `2026-04-15-signed-get-verify-step-tolerate-non-json-bodies.md` (similar pattern: pre-existing rule `cq-raf-batching-sweep-test-helpers` covers cross-test state leakage class)
- Related convention: `__resetForTest` DI seams at `server/rate-limiter.ts`, `server/share-hash-verdict-cache.ts`, `app/api/analytics/track/throttle.ts`, `components/kb/selection-toolbar.tsx`
