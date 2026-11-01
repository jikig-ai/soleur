# Agent-Native Architecture Review — PR #11780 (#11772)

**Scope:** `git diff origin/main...HEAD` — crash-handler classifier (`isBenignClientAbort`), `next ~16.3.8 → ~16.4.1` bump, dependabot-drain guard constants, ADR-062 carve-out, KB spec artifacts. Report-only.

## Summary

This PR touches **no agent-accessibility surface**: no UI actions, no agent tools, no system-prompt construction, no shared-workspace boundaries, no skill/command/agent definitions. The only new agent-observable behavior is a warn-level event emitted via `warnSilentFallback` on the benign client-abort path — and it preserves full queryability. The action-parity and context-parity checklists are vacuously satisfied (nothing user-facing was added).

## Capability Map

| UI Action | Location | Agent Tool | Prompt Ref | Status |
|-----------|----------|------------|------------|--------|
| (none added/changed) | — | — | — | N/A |

## Agent-Observable Surface Check (warn event tag shape)

The new emit site — `apps/web-platform/server/crash-handlers.ts` `installCrashHandlers()` — calls `warnSilentFallback(err, { feature: "crash-handlers", op: "client-abort" })`. Verified against `apps/web-platform/server/observability.ts:287-334`:

- `feature` and `op` are **promoted to reserved Sentry tags** (lines 294-295), so the event is searchable as `feature:crash-handlers op:client-abort` — low-cardinality, directly queryable by agents and on-call.
- The pino mirror (`logger.warn({ err, feature, op, ... })`, line 316) carries the same structured fields — durable signal even if the Sentry namespace is shimmed (line 330-332).
- `redactErrorForEmit` runs before any sink (line 292), and the error message is the static string `"aborted"` — no PII/secret-leak surface.
- Consistent with `cq-silent-fallback-must-mirror-to-sentry` and the ADR-062 observability contract: the non-fatal classification is *observable*, not silent. This is the correct shape — an agent triaging restarts can distinguish benign aborts (warn events) from real fatals (capture-close-exit path, unchanged tag `fatal:*`).

## Findings

### Critical (P1) — none

### Warnings (P2) — none

### Observations (P3)

1. **Un-debounced warn emission on an unauthenticated trigger**: the abort fires per inbound client reset, so a hostile or flaky client can generate a burst of warn-level Sentry events. `mirrorWarnWithDebounce` exists (`observability.ts:588`) for exactly this burst shape. Flagged for awareness only — the settled ruling pins `warnSilentFallback`; queryability is unaffected (burst increases event count, not tag cardinality), and the alternative (debounce) would trade queryability for quota.

## What Settled Rulings Were Verified (not re-litigated)

- **Exact-pair scope**: `isBenignClientAbort` requires `message === "aborted"` AND `code === "ECONNRESET"`; tests pin both near-misses (code-less `Error("aborted")`, wrong-message `ECONNRESET`) to the fatal path. ✓
- **Prod-wide**: classifier is in `installCrashHandlers()`, not env-gated. ✓
- **`warnSilentFallback`**: correct sink; tags promoted and queryable (see above). ✓
- **Defense-in-depth**: ADR-062 carve-out records re-evaluation trigger (#11783, upstream `body-streams` fix). ✓
- **`team_names` deferral**: not present in this diff; nothing contradicts it. ✓

## What's Working Well

- The carve-out keeps the fatal contract intact for every non-benign shape — no silent-action anti-pattern; the process-state change (not exiting) is mirrored to a queryable warn event rather than swallowed.
- ADR-062 amendment is in the shared KB the agents read — context parity for future sessions is maintained.

## Agent-Native Score

- **N/A capabilities added; 0 agent-accessible surfaces regressed**
- **Verdict: PASS**
