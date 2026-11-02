# Learning: the crash handler was faithful to a contract the runtime stopped keeping

## Problem

The `next` 16.3.8→16.4.x bump (#11772) produced a deterministic e2e dev-server death: `⨯ uncaughtException: Error: aborted`, `code: ECONNRESET`, `e2e-webserver: exited rc=1`. Nothing in the diff was wrong — the runtime changed what reaches `process.on('uncaughtException')`.

Three compounding facts:

1. **An upstream library regression can relocate a benign event across your fatal boundary.** Next's proxy/middleware body-clone path (`getCloneableBody().finalize()` → `replaceRequestBody`, vercel/next.js #49587) copies `_events` onto the `IncomingMessage` and wipes its `'error'` listeners. A routine inbound client disconnect — which stock Next logs `⨯` and continues past — instead reached our `uncaughtException` handler, and our ADR-062 capture→close→exit contract killed the process for the one signature that is benign by origin.

2. **A fatal policy at a process boundary must classify by origin, not by event type.** Widening to "any ECONNRESET" would have masked outbound resets ("socket hang up") and code-less `Error("aborted")` producers (`dsar-export.ts`, 48 abort-signal arms) — the fatals the contract exists for. The ruling held to the exact pair `Error` + `message === "aborted"` + `code === "ECONNRESET"` (Node's `connResetException` shape, minted only by the inbound socket layer); a live `http.Server` + `socket.destroy()` vitest arm pins the real minted pair so internal Node drift can't silently re-fatal the class.

3. **An unauthenticated-triggerable emit is a quota dial on every other signal.** The settled sink (`warnSilentFallback` per abort) emitted a Sentry warn envelope per inbound reset — and the trigger is a one-line socket script. Review's three-seat consensus caught what a single-seat pass would have shipped: undebounced Sentry volume at ~8.6M events/day (100 aborts/s) trips org spike protection and drops EVERY other error signal exactly during an attack. The fix is asymmetric: per-abort pino `log.warn` (full-fidelity burst count, the detection signal, cheap sink) + `mirrorWarnWithDebounce`-bounded Sentry arm (≤1 envelope/5min/process, constant `crash-handlers`/`client-abort` key). Bound the sink that has quota, never the sink that carries the count.

## Solution

`server/crash-handlers.ts` › `isBenignClientAbort` + `classifyAbortOrFatal`: exact-pair → `log.warn` + `mirrorWarnWithDebounce` (`feature:crash-handlers`, `op:client-abort`, `tags:{kind}`) and return; everything else keeps `reportFatalAndExit`. Applied in both `uncaughtException` and `unhandledRejection`, dev AND prod (same bundle, same body-clone surface, unauthenticated restart-DoS is the prod shape). ADR-062 Deliverable C records the carve-out + rejected alternatives; `#11783` carries the re-evaluation contract for a released upstream fix (keep as defense-in-depth — the exemption is benign-by-origin, not bug-specific).

## Key Insight

When a process-boundary fatal contract meets a signature that is benign *by origin*, the remediation is a classifier at that boundary — not a workaround at the trigger site (a middleware restructure cannot stop redirects from cloning), not a respawn wrapper (masks the defect, fixes nothing), and not a vendored patch (regen-fragile, invisible to review). The secondary lesson is about emit-side economics: a warn mirror is only free until the trigger is unauthenticated — then the debounce boundary belongs exactly at the sink that bills per envelope, with the un-billed sink keeping the full-fidelity count.
