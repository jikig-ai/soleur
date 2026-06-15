---
title: "A client-side replay/refetch gate added to fix a server false-positive must key on 'resource provably exists', not on session-kind"
date: 2026-06-15
category: best-practices
module: apps/web-platform (chat WS reconnect / observability severity)
tags: [observability, severity-calibration, websocket, reconnect, false-positive, rls, user-impact-review]
related_pr: "#5320"
related_issues: ["#5290 (ADR-059)", "#4816 (deferred-creation precedent)", "#5324 (deferred owned-by-another enumeration)"]
sentry_issue: 4bbd7379131f4399b784d0b8465fb2a7
---

# Severity-recalibration client gate must key on "resource provably exists," not on session-kind

## Problem

A production Sentry **error** — `feature=stream-replay`, `op=ownership-mismatch` — was paging ops for a **benign reconnect race**, not the cross-user attack the op was designed to flag. The `resume_stream` handler (ADR-059 replay buffer, introduced by #5290) re-verified ownership with an owner-scoped `(id, user_id).single()` lookup and mirrored *every* miss as error-level. Two benign conditions hit it:

- **Deferred-creation race:** conversations materialize lazily on the first chat message; a reconnect before the row persists → zero rows → error.
- **Transient `getCurrentRepoUrl` null:** a tenant-mint blip returned `null`, and `convRepoUrl !== null` was misread as a repo-scope mismatch.

## Solution

Recalibrate **severity by cause** (the #4816 pattern): keep genuine causes loud (`reportSilentFallback`/error: DB error/RLS, real cross-repo) and downgrade benign races to `warnSilentFallback`/warning with an `extra.cause` discriminator. Switch the lookup `.single()` → `.maybeSingle()` so a zero-row result (`{data:null,error:null}`) is distinguishable from a DB error by severity. Add a **client-side gate** so a fresh deferred conversation never *requests* replay of a non-existent row, plus downgrade the upstream `getCurrentRepoUrl` tenant-mint emit error→warning.

## Key Insight (the non-obvious one, surfaced by user-impact-review)

The natural first cut of the client gate was `sessionKind === "resumed"` — only request replay for a materialized, owned (sidebar-resumed) session. **That over-restricts.** A *fresh* conversation that has already streamed its first turn (sent ≥1 message → row materialized → live mid-turn agent) and then drops its socket would lose its disconnect-window gap frames, because `sessionKind` stays `"fresh"` forever (no `fresh→resumed` upgrade exists). The plan + 5 deepen agents all missed this; only `user-impact-reviewer` (fired by the `single-user incident` threshold) caught it, because it enumerates user-facing failure modes rather than verifying the gate matches the plan.

The fix: gate on **"the resource provably exists,"** not on the session's origin label. The materialization proof available client-side is **a rendered server-stamped frame** (`lastRenderedSeqRef.current >= 0`): the agent only streams after the row persists, so a rendered frame is proof the owner lookup will succeed. Final gate:

```ts
const replayEligible =
  kind === "resumed" ||
  (kind === "fresh" && lastRenderedSeqRef.current >= 0);
```

A not-yet-streamed fresh conv (`lastRenderedSeq === -1`) stays ineligible — preserving the false-positive fix — while a mid-stream drop recovers its gap frames. Generalizable: **when you add a client-side gate to suppress a server false-positive ("don't ask for X unless X exists"), the gate predicate must be the existence proof of X, not a proxy correlated with it (session origin, creation path, a status enum).** A proxy that's *usually* right ships green and silently breaks the correlated-but-distinct case.

## Secondary insight: RLS row-denial ≠ SQLSTATE 42501

When classifying DB errors by severity, do not assume an RLS denial surfaces as `42501`. If the role (`authenticated`) holds the table SELECT **grant** and visibility is enforced by **RLS policies**, a row owned by another user returns **zero rows**, not `42501 insufficient_privilege`. `42501` fires only on a *missing grant*. So a cross-user `conversationId` flows through the `!conv` (zero-row) branch, not the `convErr` branch — relevant when deciding which branch must stay loud. (Caught by silent-failure-hunter + security-sentinel cross-checking the migrations.)

## Prevention

- For any client gate that suppresses a server-side detection, ask: "what is the *existence proof* of the resource, and does my predicate test exactly that?" Enumerate the correlated-but-distinct cases (here: fresh-not-materialized vs fresh-materialized-mid-turn vs resumed).
- Run `user-impact-reviewer` on any `single-user incident` plan — it catches over-restriction the gate-correctness agents (which only verify the gate matches the plan) structurally miss.
- When classifying DB errors by SQLSTATE, verify the table's RLS model (policy vs grant) before assuming a denial code reaches a given branch.

## Session Errors

1. **Path-mangling on first Edit** to `current-repo-url.test.ts` (corrupted absolute path → "File does not exist"). Recovery: re-ran with correct path. **Prevention:** one-off typo; copy the path from a prior successful tool call rather than retyping.
2. **"File has not been read yet" on `ws-handler.ts` Edit** after earlier edits shifted lines. Recovery: re-read the target region, then edited. **Prevention:** expected harness behavior after multi-edit line drift; re-Read the region before editing a file edited several steps earlier.
3. **3 tsc type errors in the new test** (`as Record<...>` needed `as unknown as`; `data: null` needed `null as never`). Recovery: mirrored the existing test file's `null as never` convention. **Prevention:** when adding mock return overrides to an existing supabase-mock test, copy the file's existing cast idiom (`null as never`) rather than writing a bare literal.
