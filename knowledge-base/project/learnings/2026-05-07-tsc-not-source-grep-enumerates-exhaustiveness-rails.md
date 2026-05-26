---
title: tsc --noEmit enumerates exhaustiveness rails — source-grep undercounts
date: 2026-05-07
category: best-practices
module: typescript-discriminated-unions
tags: [tsc, discriminated-union, exhaustiveness, plan-drift, work-skill]
related_pr: "#3419"
related_issue: "#3269"
---

## Problem

The plan for #3269 (WS `context_reset` lifecycle event family) prescribed
**4 WSMessage exhaustiveness sites**. The deepened plan even claimed to have
found "2 missing" sites a prior version had missed (`ws-known-types.ts`,
`chat-state-machine.ts`).

When `tsc --noEmit` ran during Phase 6 verification, it failed with TS2322
errors at **two further sites the deepened plan still missed**:

1. `apps/web-platform/server/ws-handler.ts:1640` — the server-side switch over
   inbound `WSMessage["type"]` for client→server frames (its
   `default: const _exhaustive: never = msg` rejects unknown types with an
   `error` reply).
2. `apps/web-platform/test/chat-message-exhaustiveness.test-d.ts:38` — a
   compile-time `.test-d.ts` gate over `ChatMessage` that had to also widen
   when `ChatContextResetMessage` was added.

Total actual sites: **5 over `WSMessage` + 2 over `ChatMessage`**, not 4.

## Root cause

Source-grep for `_exhaustive: never` against `apps/web-platform/{lib,server,
components}/` (the path scope written into the plan) misses two classes:

- `apps/web-platform/test/**` files like `*.test-d.ts` — type-only gates that
  are not part of `lib|server|components` but DO compile under the same
  `tsc --noEmit` and DO need to widen with the union.
- `apps/web-platform/server/ws-handler.ts:1640` IS in `server/` so should have
  been caught — but the plan's prose anchor "4 sites" capped expectations and
  the writer didn't widen the grep beyond the listed files.

The plan also misclassified `chat-state-machine.ts:277 applyStreamEvent` as
"the actual reducer site (TS exhaustive switch lives here, not in
`ws-client.ts`)". That switch is exhaustive over **`StreamEvent`** —
`Extract<WSMessage, { type: "stream_start" } | { type: "stream" } | ...>` —
not over `WSMessage` directly. Both `ws-client.ts:657` and
`chat-state-machine.ts:778` carry `_exhaustive: never` rails; the plan named
one as "the" canonical site.

## Solution

Trust the compiler. After widening a discriminated union, the canonical
enumerator of every `: never` rail is `tsc --noEmit` itself — every TS2322
"X is not assignable to never" pinpoints a rail that must be updated. Run it
**before** verifying the test suite and **before** trusting any prescribed
site count from the plan.

```bash
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit 2>&1 | grep -E "TS2322.*not assignable to.*never"
```

Each hit is an exhaustiveness rail to update. Path scope for the source-grep
should be `apps/web-platform/` (no `{lib,server,components}` filter) so
`test/**.test-d.ts` files surface.

Time cost: one full-app tsc pass (~30s on this codebase) versus the alternative
of grep-prescribing site counts in the plan and discovering missed rails at
review time.

## Key insight

**Plans that prescribe a site count are inherently fragile to grep-scope drift.
The compiler doesn't drift.** Replace "N sites listed at file:line" plan
prescriptions with "verify all rails widen via `tsc --noEmit`, fix every
TS2322 from the run". The site list still has value as a reading guide, but
it cannot be treated as the load-bearing exhaustiveness contract.

This generalizes beyond TypeScript: any compile-time totality check
(Rust `match` non-exhaustive warnings, OCaml `match` warnings, Scala
`MatchError` with `-Xfatal-warnings`) is the canonical enumerator. A
hand-prescribed list of pattern-match sites is documentation, not a gate.

## Session Errors

- **Plan exhaustiveness-site count was 4; actual was 5+2.** Recovery:
  added `context_reset` to `ws-handler.ts:1641` and
  `chat-message-exhaustiveness.test-d.ts:38` after `tsc --noEmit` flagged
  TS2322 at both sites. Prevention: this learning file (already discoverable
  via tsc; per `wg-every-session-error-must-produce-either` discoverability
  exit, no AGENTS.md rule needed).

- **Bash `cd` does not persist across tool calls.** Mid-session a chained
  `./node_modules/.bin/tsc` invocation failed with "No such file or
  directory" because the prior cd state was reset. Recovery: chained
  absolute path in a single Bash call. Prevention: already enforced by the
  existing constitution rule on shell-state non-persistence; brief slip,
  not novel.

## Cross-references

- PR #3419 — implementation
- Issue #3269 — context-reset signal (parent)
- Issue #3263 — original prefill-guard landing
- ADR-025 — WS lifecycle-notice event family
- AGENTS.md `cq-union-widening-grep-three-patterns` — the if-ladder side of
  union widening (covers `\.kind === "` consumers; this learning covers the
  `: never` rails that the rule's grep alone doesn't pinpoint)
