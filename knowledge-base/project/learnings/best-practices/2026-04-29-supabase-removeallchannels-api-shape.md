---
name: supabase-removeallchannels-api-shape
description: supabase-js v2 `client.removeAllChannels()` returns a single Promise<RealtimeChannelStatus[]>, not an array of Promises. Wrapping it in `Promise.all(...)` typechecks but iterates the resolved status array as if each element were a Promise — coercing strings to Promises silently. Caught at typecheck only when strict; sign-out paths that ignore the return slip through.
type: best-practice
tags: [supabase, realtime, typescript, sdk-shape, sign-out]
category: best-practices
module: apps/web-platform
---

# supabase-js removeAllChannels Returns One Promise, Not Many

## Problem

While implementing the Command Center conversation rail (plan
`2026-04-29-feat-command-center-conversation-nav-plan.md`, Phase 4
sign-out path), the deepen-plan prescribed:

```ts
await Promise.all(supabase.removeAllChannels());
```

This typechecks under non-strict settings and runs without error in the
happy path. It is also wrong. supabase-js v2's signature is:

```ts
removeAllChannels(): Promise<("ok" | "timed out" | "error")[]>
```

A single Promise resolving to an array of per-channel statuses. The
`Promise.all` wrapper:

1. Awaits the `Promise<string[]>` once,
2. Receives `["ok", "ok", ...]`,
3. Treats each string as a thenable (it isn't), so they pass through
   unchanged,
4. Resolves to the same `["ok", "ok", ...]` array.

The sign-out path appears to work. The bug is that the partial-failure
contract you *think* you have ("any one channel fails → the await
rejects") is not the contract you actually have — `removeAllChannels`
never rejects on a single-channel timeout; the per-channel result lives
inside the array.

## Why Mechanical Checks Missed It

- Vitest unit tests mock the supabase client and never exercise the
  return shape — the mock returned a stub Promise.
- TS strict caught it for us, but only because the project enables
  `strict: true`. Codebases that disable strict (or use `any` casts at
  the supabase boundary) get no signal.
- The plan's pseudo-code was copied verbatim from a deepen-plan agent
  that had not opened the supabase types.

## Solution

Use the await directly and inspect the status array if partial-failure
matters:

```ts
const statuses = await supabase.removeAllChannels();
if (statuses.some((s) => s !== "ok")) {
  // optional: log degraded teardown
}
```

For sign-out, the load-bearing contract is "user lands on /login" —
wrap the teardown in try/finally so a `removeAllChannels` rejection
(network error, not partial failure) does not strand the user logged
in:

```ts
try {
  await supabase.removeAllChannels();
} finally {
  await supabase.auth.signOut();
  router.push("/login");
}
```

## Prevention

When a plan/deepen-plan prescribes a Supabase SDK call, open
`@supabase/supabase-js` types BEFORE copying the snippet. Specifically
check:

- `removeAllChannels()` → `Promise<RealtimeChannelStatus[]>` (single)
- `removeChannel(ch)` → `Promise<RealtimeChannelStatus>` (single)
- `unsubscribe()` on a channel → `Promise<RealtimeChannelStatus>`

The pattern generalises: any SDK method that "removes everything"
should be suspected of returning one Promise of an array, not an array
of Promises. `Promise.all(...)` around a single Promise is a smell.

## Session Errors

- **Plan prescribed `.test.ts` for a hook test that needs renderHook (happy-dom)** — Recovery: renamed to `.test.tsx`. Prevention: plan/deepen-plan must check vitest project config (`unit` vs `component`) and align extensions; add a one-line note when a hook test crosses the boundary.
- **`Promise.all(supabase.removeAllChannels())` typecheck failure** — Recovery: changed to bare `await`. Prevention: this learning.
- **Cmd/Ctrl+B handler conflict between dashboard sidebar and rail** — Recovery: widened the existing pathname short-circuit in `(dashboard)/layout.tsx` to skip `/dashboard/chat/*`. Prevention: when adding a global keyboard shortcut, grep for the same key in the existing layout tree before binding.
- **`dashboard-sidebar-collapse.test.tsx` 11 failures from transitively-imported `useParams`** — Recovery: extended the `next/navigation` mock with `useParams` and the supabase client mock with `getUser`/`maybeSingle`/`channel`/`removeAllChannels`. Prevention: when a layout grows new children, grep for adjacent layout test mocks and align the contract; or factor the layout-shell mock into a shared helper.
- **Bash CWD does not persist between calls** — Recovery: used absolute paths or chained commands with `&&`. Prevention: never rely on a prior `cd` in a separate Bash call; either absolute paths or a single chained command.
- **Plan Non-Goals violation (drawer + Cmd+B widening)** — Recovery: amended the plan's Non-Goals to acknowledge mechanical scope expansion. Prevention: when implementation discovers an unavoidable adjacent edit, update the plan in-flight before review, not after.
- **Duplicate ConversationsRail mount across drawer + chat layout** — Recovery: gated drawer mount on `drawerOpen && pathname.startsWith("/dashboard/chat")`. Prevention: see companion learning `2026-04-29-duplicate-component-mount-across-layouts.md`.
- **DELETE assertion vacuously passes if REPLICA IDENTITY regresses** — Recovery: added a canary precondition asserting `payload.old.user_id` exists before applying the leak filter. Prevention: any test whose leak-filter depends on a column populated by REPLICA IDENTITY FULL must include a preflight assertion that the column is present.
- **E2E WS open-set assertion structurally vacuous against mock-supabase** — Recovery: removed the assertion; load-bearing isolation lives in Phase 5b integration test. Prevention: when a mock environment cannot exercise a side effect (WS upgrade), do not write an assertion that "passes vacuously" — write a comment explaining why the assertion lives elsewhere.
- **Multi-Edit chain lost target after first edit collapsed boundaries** — Recovery: re-read the file and targeted survivors. Prevention: chain Edit calls only when the second edit targets bytes outside the first edit's region; otherwise re-read.
- **`bun run lint` interactive prompt for ESLint config** — Recovery: skipped (pre-existing breakage, not introduced by this PR). Prevention: file a tracking issue if not already filed.
