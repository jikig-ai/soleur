# Learning: `mirrorWarnWithDebounce` debounces the pino stdout log too, not just the Sentry mirror

## Problem

PR (#4623) adopted `mirrorWarnWithDebounce` (`apps/web-platform/server/observability.ts`) to stop the
`workspace-reconcile-on-push` no-workspace-match skip from flooding Sentry alert rules. Both the plan
and the first-pass handler comment asserted: *"the per-occurrence `logger.warn` stdout signal is
unaffected, so the skip stays queryable in Better Stack on every occurrence."*

That claim is **false**. `data-integrity-guardian` caught it at review; `agent-native-reviewer`
independently made the OPPOSITE (also wrong) claim that pino is "retained on every skip."

## Root Cause

`mirrorWarnWithDebounce` gates the **entire** `warnSilentFallback` call behind the TTL claim:

```ts
export function mirrorWarnWithDebounce(err, ctx, key, errorClass): void {
  if (!_mirrorDebounce.tryClaim(`${key}:${errorClass}`, Date.now())) return; // <-- early return
  warnSilentFallback(err, ctx); // contains BOTH logger.warn AND Sentry.captureException
}
```

The pino `logger.warn` lives *inside* `warnSilentFallback` (`observability.ts:223`), BEFORE the Sentry
capture. So when the debounce claim fails (suppressed occurrence), `warnSilentFallback` is never
called — **neither** the stdout log **nor** the Sentry mirror fires. Both sinks are capped at ≤1 per
key per window. The mental model "debounce the Sentry mirror, keep the stdout log per-occurrence" does
not match the code.

## Solution

The behavior is actually fine (it's the same as the #4571 Flagsmith precedent — capping the redundant
stdout repetition is desirable). The fix was to correct the **documentation** to match reality:
the debounce caps both sinks, and the **first occurrence per `(key, errorClass)` per 5-min window**
still carries the full pino + Sentry signal, so a genuine drift case still surfaces as a fresh
first-in-window event. The diagnostic is preserved; only per-push repetition is suppressed.

## Key Insight

When adopting `mirrorWarnWithDebounce` / `mirrorWithDebounce` to "debounce the Sentry mirror," remember
it debounces the **whole** `(report|warn)SilentFallback` call — the pino stdout line is gated too.
Never write "the stdout signal stays per-occurrence" in a plan or comment for these helpers. If you
genuinely need per-occurrence stdout AND a debounced Sentry mirror, you must call `logger.warn`
yourself and debounce only the Sentry side — the existing helpers do not do that.

## Tags
category: integration-issues
module: observability
related: 2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md
