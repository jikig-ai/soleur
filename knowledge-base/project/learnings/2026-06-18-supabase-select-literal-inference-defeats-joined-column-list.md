# Learning: a runtime-joined column list defeats supabase-js `.select()` row-type inference

## Problem

During review of the frontend perf quick-wins PR (#5537), three review agents
(data-integrity-guardian, architecture-strategist, code-quality-analyst) all
recommended the same maintainability hardening for the M4 change: replace the
inline `.select("id, user_id, …")` string literal with a single-source
`CONVERSATION_COLUMNS` array guarded by `satisfies readonly (keyof Conversation)[]`
plus a compile-time exhaustiveness assertion, then feed it to the query via
`.select(CONVERSATION_COLUMNS.join(", "))`.

Applying it broke `tsc`:

```
hooks/use-conversations.ts(308,32): error TS2345: Argument of type
'(c: Conversation) => string' is not assignable to parameter of type
'(value: GenericStringError, index: number, array: GenericStringError[]) => string'.
```

## Root cause

`@supabase/supabase-js` infers the **result row type from the `.select()` string
literal at compile time** (it parses the literal as a type). When the argument is
a runtime-built `string` (e.g. `Array.join(", ")`), the parser can't see the
columns, so the result type degrades to `GenericStringError[]` and every
downstream `.map((c: Conversation) => …)` / `as Conversation` consumer fails to
typecheck.

So the clean single-source refactor is **fundamentally incompatible with the
typed client**: you can have the compile-time `keyof Conversation` guard OR the
row-type inference, not both. The only way to keep the join would be to cast the
result back to `Conversation[]`, which *trades away* the very row-level type
safety the literal provides — a net regression for an advisory improvement.

## Solution

Keep the explicit **string literal** in `.select(...)` (row-type inference
preserved) and document the sync obligation in a comment. The literal is the
correct shape; the "DRY it into a const" instinct is the trap.

```ts
// Must be a string LITERAL — supabase-js infers the row type from it, so a
// runtime-built/joined string degrades the result to an untyped error shape.
.select("id, user_id, domain_leader, …, visibility")
```

## Key Insight

When a reviewer (human or agent) recommends DRYing a supabase-js `.select()`
column list into a joined constant + `keyof` guard, **reject it**: the typed
client needs the literal. This is the data-layer analogue of the existing
"verify reviewer-prescribed CLI flags before applying" sharp edge — an advisory
improvement that is structurally infeasible against the tool's type model.
Verify with one `tsc --noEmit` before committing any such refactor.

Corollary (separate session error, same PR): when a render change causes a
client component to mount earlier (here, dropping `if (loading) return null` in
favor of a `contextPending` prop), any **new mount-time fetch** it carries
(`useActiveRepo`'s `/api/workspace/active-repo` poll) competes with sibling
fetch mocks. A shared single-`Response` mock + `mockResolvedValueOnce` then
fails with "Body has already been used" or a stolen `Once`. Fix: route the
fetch mock by URL (`urlOf(input)` helper) so each consumer gets its own
response — same class as the #5125 e2e-harness-mock-for-new-fetches learning.

## Session Errors

1. **M4 compile-time-guard refactor broke `tsc`** (TS2345, `GenericStringError`).
   Recovery: reverted to the explicit `.select()` literal + comment.
   Prevention: this learning + the routed note in `review/SKILL.md` sharp edges.
2. **M1 immediate-mount change broke 4 existing `chat-page.test.tsx` tests**
   ("Body has already been used"; active-repo poll stole the shared `*Once` mock).
   Recovery: URL-aware fetch mock (`kbResponder` + extracted `urlOf` helper).
   Prevention: when a render change makes a component mount earlier, sweep the
   sibling fetch mocks for shared-Response / `*Once` assumptions.
3. **Playwright `nav-states` webServer failed to start (exit 1)** on the local
   two-webServer harness; the dev server boots standalone. Recovery: degraded to
   the authoritative containerized CI `e2e` job (known #5009 local-env class).
   Prevention: none needed — documented degradation path.
4. **`pkill` exit 144** (SIGTERM on the grep pipeline). One-off; no action.

## Tags
category: build-errors
module: apps/web-platform/hooks
