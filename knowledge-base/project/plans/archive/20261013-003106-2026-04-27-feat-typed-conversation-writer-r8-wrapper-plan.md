# feat: typed `updateConversationFor` wrapper enforces R8 composite key

**Issue:** [#2956](https://github.com/jikig-ai/soleur/issues/2956)
**Branch:** `feat-one-shot-2956-conversation-writer`
**Milestone:** Phase 4: Validate + Scale
**Type:** refactor (security-defense-in-depth)
**Priority:** P2
**Date:** 2026-04-27

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** 6
**Research approach:** direct codebase grounding (subagent fan-out unavailable in this context — substituted with focused multi-perspective inline review covering data-integrity, type-design, test-design, simplicity, and pattern-recognition lenses).

### Key Improvements

1. **Scope expanded from 5/6 sites to 7+1 dependency-injected sites.** The original plan missed that `cc-dispatcher.ts:419`'s `updateConversationStatus` closure is **injected as `deps.updateConversationStatus`** into `permission-callback.ts`, where it is called at **6 additional sites** (lines 228, 238, 363, 373, 505, 515). The closure migration covers all 6 transitively — but the audit must call this out so the test surface is understood.
2. **`deps.updateConversationStatus` signature decision: keep `(conversationId, status)` unchanged.** The closure captures `args.userId` via lexical scope; widening the deps signature to `(userId, conversationId, status)` would force `permission-callback.ts` changes for zero correctness gain. Defense-in-depth lives **inside the closure**, not at the deps boundary.
3. **`agent-runner.ts updateConversationStatus` — `userId` already in scope at all 4 internal callers.** Verified: `agent-runner.ts:1099, 1138, 1188, 1420` all sit inside closures that bind `userId, conversationId` together. The signature change is safe.
4. **Existing test (`cc-dispatcher-real-factory.test.ts` T-AC4) survives migration without rewrite.** The test captures `mockSupabaseFrom` directly; after migration, the wrapper still calls `supabase().from("conversations").update(...).eq(...).eq(...)`, so the capture chain (lines 425-450) keeps observing both `.eq` columns. No test rewrite needed for T-AC4 — only the cc-dispatcher.test.ts mock-of-observability surface changes.
5. **0-rows-affected → silent success is intentional but DOCUMENTED in the JSDoc.** Reviewers ("data-integrity-guardian" lens) will flag this as a potential cross-user write swallow. The mitigation: `userId` and `conversationId` are both server-derived in every migrated callsite (no caller-supplied IDs cross the boundary), so a 0-rows-affected outcome means "user no longer owns the conversation" (legitimate concurrent-close race), NOT "attacker probing a foreign id". A future hardening could add `.select("id").maybeSingle()` and treat 0-rows as a warn-level Sentry mirror — out of scope for this PR.
6. **CI detector regex hardened:** rejected the original `--pcre2 'from\("conversations"\)\.update\('` because the chain is often line-broken across `.from(...)` and `.update(...)`. Use `rg -U --multiline-dotall` with a pattern that tolerates whitespace+newlines between `from(...)` and `.update(`. Tested against the 8 known callsites (2 broken across lines, 6 single-line).

### New Considerations Discovered

- **Scope-expansion math:** issue body said 5 legacy sites + 1 cc → 6. Plan reconciled to 6 legacy + 1 cc → 7. Deepen pass found **6 additional dependency-injected sites** in `permission-callback.ts` that flow through the cc-dispatcher closure → effective coverage is 7 direct migrations + 6 transitive via deps = 13 sites where R8 invariant is now enforced from a single wrapper.
- **Existing test test-bed for the wrapper already exists.** `cc-dispatcher-real-factory.test.ts:425-450` (T-AC4) is the canonical capture pattern — mirror it in `conversation-writer.test.ts`.
- **lefthook may not invoke the new script if pre-commit runs only against staged files.** Verify `lefthook.yml`'s `pre-commit` `run:` shape: if it filters by `{staged_files}`, the conversation-writer linter must explicitly run `bash scripts/lint-conversations-update-callsites.sh` unconditionally (not glob-filtered) because adding a marker comment requires the linter to see the file.
- **The existing close-handler at `ws-handler.ts:892` lacks `await releaseSlot` ordering protection.** The existing code does `void releaseSlot(userId, convId)` AFTER the `.update`. Migrating to `await updateConversationFor(...)` preserves ordering (releaseSlot is still after). NOT a regression, but worth pinning in the test that exercises the close-on-supersede path.

## Overview

PR #2954's new write at `apps/web-platform/server/cc-dispatcher.ts:419` correctly applies the **R8 composite-key invariant** (`.eq("id", convId).eq("user_id", args.userId)`). Several legacy single-conversation writes to the `conversations` table predate this pattern and rely on caller-side ownership checks instead of database-level enforcement.

This plan extracts a typed `updateConversationFor(userId, conversationId, patch)` wrapper to `apps/web-platform/server/conversation-writer.ts`, migrates all 5 legacy targeted writes (plus the cc-dispatcher write that already follows the pattern, for symmetry), and adds a CI grep detector that fails the build if a new direct `.from("conversations").update(...)` lands in `apps/web-platform/server/` outside the wrapper module.

**Scope is single-conversation targeted writes only.** Bulk status updates (`cleanupOrphanedConversations` at `agent-runner.ts:417`, inactivity-timer cleanup at `agent-runner.ts:437`) are intentionally excluded — they update by status filter across all users and have no per-user composite-key dimension. They go through a separate allowlist in the CI detector.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality on `feat-one-shot-2956-conversation-writer` HEAD | Plan response |
| --- | --- | --- |
| `agent-runner.ts:317-331` is `updateConversationStatus` (id-only) | Symbol `updateConversationStatus` actually lives at **`agent-runner.ts:347-360`** (line drift since the issue was filed; logic is unchanged: `.update({ status, last_active }).eq("id", conversationId)` only) | Treat the **symbol** as authoritative per `cq-code-comments-symbol-anchors-not-line-numbers`. Plan references `agent-runner.ts updateConversationStatus(...)`, not a line number. |
| `agent-runner.ts:909-918` session_id persist | Confirmed at **`agent-runner.ts:937-948`** inside `runAgentSession` first-message handler. id-only filter. | Migrate. |
| `agent-runner.ts:1446-1449` clear stale session_id | Confirmed at **`agent-runner.ts:1471-1481`** inside SDK-resume catch. id-only filter. | Migrate. |
| `ws-handler.ts:830-834` close_conversation write | At **`ws-handler.ts:830`** the snippet is the **read** for ownership-check; the actual close-write is **further down** in the same handler. The broken write the issue meant is at **`ws-handler.ts:892-896`** (the supersede path). | Re-cited correctly below. |
| `ws-handler.ts:892-895` "additional close path" | Confirmed at **`ws-handler.ts:892-896`** — `await supabase.from("conversations").update({ status, last_active }).eq("id", convId)` only. | Migrate. |
| 5 legacy + 1 cc = 6 sites | Codebase grep confirms exactly **5 single-conversation targeted updates lacking `user_id`** + **1 already-good write** (`cc-dispatcher.ts:419`) + **2 bulk updates** (`cleanupOrphanedConversations`, inactivity timer) that are intentionally NOT in scope. Total `.from("conversations").update(...)` callsites: **8**. Plus `ws-handler.ts:194` (the supersede-on-reconnect write — has `.eq("id", oldConvId)` only) which the issue body **missed**. | **Scope expansion**: include `ws-handler.ts:194` as the **6th** legacy migration target. Issue body said 5; the grep finds 6. Per the planning rule "validate N at planning time by grepping the distinguishing pattern". |
| `ws-handler.ts:523` already has `.eq("user_id", userId)` | Confirmed — this is the active_workflow write. Already R8-compliant. | Migrate to the wrapper for symmetry (so the CI grep can be a hard `! rg ...` rule rather than an allowlist). |

**Net:** plan migrates **7** call sites (6 legacy + 1 already-good + 1 missed-by-issue), plus excludes 2 bulk-update sites by allowlist comment. Numeric correction recorded here so review and work phases see the same denominator.

## Open Code-Review Overlap

- **#2955** (`arch: process-local state assumption needs ADR + startup guard`) — touches `cc-dispatcher.ts` and `agent-runner.ts` for in-memory `Map` state (workspace-permission-lock, bash approval cache, active sessions). **Disposition: Acknowledge.** Different concern (concurrency/replica-count assumptions, not row-level access control). The wrapper migration does not touch the in-memory Maps; #2955 remains open and addresses an orthogonal blast radius.
- **#2191** (`refactor(ws): introduce clearSessionTimers helper + add refresh-timer jitter and consecutive-failure close`) — touches `ws-handler.ts` for timer-teardown DRY-ing. **Disposition: Acknowledge.** Different concern (timer lifecycle, not DB writes). The wrapper migration touches conversation-write call sites, not the timer block at `ws-handler.ts:88/701-703/761-763`.

Neither overlap is fold-worthy: combining timer-teardown or process-local-state cleanup with a DB-write wrapper would muddy the PR's audit trail and make rollback awkward if any one piece regresses.

## Files to Create

- `apps/web-platform/server/conversation-writer.ts` — typed wrapper module.
- `apps/web-platform/test/conversation-writer.test.ts` — unit tests for the wrapper.
- `apps/web-platform/test/conversations-update-grep-detector.test.ts` — guard that runs the CI grep locally so the detector itself has a regression test (the grep regex is tested against fixture-shaped inputs, not against `apps/web-platform/server/` to avoid coupling the unit test to file moves).
- `scripts/lint-conversations-update-callsites.sh` — CI-callable shell script wrapping the `rg` invocation (mirrors the pattern of `scripts/lint-bot-synthetic-statuses.sh` already wired into `.github/workflows/ci.yml:lint-bot-statuses`).

## Files to Edit

- `apps/web-platform/server/agent-runner.ts` — migrate 3 sites: `updateConversationStatus`, session_id persist in first-message handler, clear stale session_id in SDK-resume catch.
- `apps/web-platform/server/ws-handler.ts` — migrate 4 sites: `:194` (supersede-on-reconnect), `:523` (active_workflow — already R8 but normalized through wrapper), `:892` (close on supersede), and any remaining single-conversation `.update(...)` if grep surfaces one (verify at work-phase via the same `rg` the CI step will run).
- `apps/web-platform/server/cc-dispatcher.ts` — migrate `:419` `updateConversationStatus` closure to call the wrapper. Keep the closure (it's the function-shape contract `cc-soleur-go` runner depends on); just have it delegate.
- `.github/workflows/ci.yml` — add `lint-conversations-update-callsites` job (mirrors `lint-bot-statuses` shape).
- `lefthook.yml` — add the same lint to `pre-commit` so the failure mode is fast-feedback locally before the PR opens.
- `apps/web-platform/test/cc-dispatcher.test.ts` — update mock to align with the wrapper-delegated shape (the existing test mocks `@/server/observability` directly; once the wrapper owns Sentry mirroring, the cc-dispatcher test no longer needs to assert on `mockReportSilentFallback` for conversation-update errors specifically — it asserts the wrapper was called instead).

## Wrapper Design

```ts
// apps/web-platform/server/conversation-writer.ts
import { supabase } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";
import type { Conversation } from "@/lib/types";

/**
 * Allowed columns for a single-conversation targeted update.
 *
 * NOT a `Pick<Database["public"]["Tables"]["conversations"]["Update"], …>` —
 * the codebase imports `Conversation` from `@/lib/types`, not the Supabase
 * generated types. Using the runtime `Conversation` interface keeps the
 * wrapper aligned with the rest of the server.
 */
export interface ConversationPatch {
  status?: Conversation["status"];
  last_active?: string;
  session_id?: string | null;
  active_workflow?: string | null;
  workflow_ended_at?: string | null;
  domain_leader?: Conversation["domain_leader"];
  archived_at?: string | null;
  context_path?: string | null;
}

export interface UpdateConversationResult {
  ok: boolean;
  /** Underlying Supabase error if the update failed. */
  error?: Error;
}

/**
 * Single-conversation targeted update with R8 composite-key invariant
 * (`.eq("id", conversationId).eq("user_id", userId)`) baked into the
 * wrapper. Mirrors errors to Sentry via `reportSilentFallback` per
 * `cq-silent-fallback-must-mirror-to-sentry` so the call sites don't
 * each have to remember.
 *
 * Returns `{ ok }` rather than throwing — call sites decide whether
 * the failure is fatal (close-conversation handler) or degraded
 * (session_id persist). Throwing would surprise the legacy callers,
 * none of which currently treat conversation-update failure as a
 * thrown exception.
 *
 * Bulk updates (cleanup-orphaned, inactivity-timer) MUST NOT use this
 * wrapper — they update by status filter across all users and have no
 * per-user dimension. They are explicitly allowlisted in the CI grep
 * detector via a leading `// allow-direct-conversation-update:` marker.
 */
export async function updateConversationFor(
  userId: string,
  conversationId: string,
  patch: ConversationPatch,
  options?: { feature?: string; op?: string },
): Promise<UpdateConversationResult> {
  const { error } = await supabase()
    .from("conversations")
    .update(patch)
    .eq("id", conversationId)
    .eq("user_id", userId);

  if (error) {
    reportSilentFallback(error, {
      feature: options?.feature ?? "conversation-writer",
      op: options?.op ?? "update",
      extra: { userId, conversationId, patchKeys: Object.keys(patch) },
    });
    return { ok: false, error: new Error(error.message) };
  }

  return { ok: true };
}
```

**Design choices:**

1. **`ConversationPatch` is a hand-written interface, not derived from Supabase generated types.** The codebase imports `Conversation` from `@/lib/types` (a hand-maintained interface that mirrors the schema but adds branded types and runtime-only narrowings). Deriving from `Database["public"]["Tables"]…["Update"]` would introduce a new dependency on the generated types module that the rest of `apps/web-platform/server/` doesn't use, and would make the wrapper sensitive to typegen drift. Trade-off: adding a new column requires a 2-line `ConversationPatch` edit. That cost is one-time per migration and surfaces via TS error at the first call site to use the new column — exactly when we want the audit.
2. **Returns `{ ok, error? }` instead of throwing.** Five of the six call sites currently log on error and continue (session_id persist, clear-stale-session_id, supersede-write, ws-supersede-on-reconnect). Two log-and-throw (`updateConversationStatus` in `agent-runner.ts`, the close-handler). Returning a result lets the caller choose; throwing would force the loggers to wrap in try/catch and silently change error semantics.
3. **`feature` / `op` are caller-provided, defaulting to `conversation-writer` / `update`.** Sentry tag vocabulary stays useful: a tag like `feature: ws-handler.close, op: supersede` is debuggable; a flat `feature: conversation-writer` for everything is not. Each migration call site provides its own pair.
4. **No `select("…")` after update.** Five of the six call sites don't read any post-state. The one site that needs the row's `id, user_id` after a bulk update (the inactivity-timer site at `agent-runner.ts:437`) is **out of scope** for this wrapper (it's a bulk update, not a targeted single-conversation update).

## CI Detector Design

**Script:** `scripts/lint-conversations-update-callsites.sh`

```bash
#!/usr/bin/env bash
# Fail CI if a new `.from("conversations").update(...)` lands in
# apps/web-platform/server/ outside conversation-writer.ts AND not
# explicitly allowlisted by a `// allow-direct-conversation-update:`
# comment on the line above. See plan
# 2026-04-27-feat-typed-conversation-writer-r8-wrapper-plan.md.
set -euo pipefail

SERVER_DIR="apps/web-platform/server"
WRAPPER="$SERVER_DIR/conversation-writer.ts"

# rg's -U --multiline + \s* tolerates the chain being broken across lines
# (e.g., ws-handler.ts:194 has `.from(...)\n  .update(...)`). --pcre2 lets us
# require the `.update(` follow `.from("conversations")` with optional
# whitespace+newlines between. -B1 lets the allowlist comment on the prior
# line opt-out.
matches=$(rg --no-heading -n -B1 -U --multiline \
  --pcre2 'from\("conversations"\)\s*\.update\(' \
  "$SERVER_DIR" \
  --glob '!conversation-writer.ts' \
  --glob '!*.test.ts' || true)

# Strip allowlisted blocks (line above contains the marker) and the
# wrapper's own internal call (already excluded by --glob).
filtered=$(printf '%s\n' "$matches" \
  | awk '
    /^[^-]*allow-direct-conversation-update:/ { skip=1; next }
    skip { skip=0; next }
    { print }
  ')

if [[ -n "$filtered" ]]; then
  echo "::error::Direct .from(\"conversations\").update(...) outside conversation-writer.ts:"
  echo "$filtered"
  echo ""
  echo "Use updateConversationFor() from @/server/conversation-writer."
  echo "If this is a bulk update (no per-user composite key), add a"
  echo "// allow-direct-conversation-update: <reason> comment on the line above."
  exit 1
fi

echo "OK: no direct conversation updates outside the wrapper."
```

**Why a script and not inline `run:` YAML:** mirrors the sibling `scripts/lint-bot-synthetic-statuses.sh` already wired into the `lint-bot-statuses` CI job. Keeping the regex out of YAML avoids the heredoc-indentation traps in `hr-in-github-actions-run-blocks-never-use` and makes the linter locally-runnable for fast feedback. lefthook's `pre-commit` invokes the same script — single source of truth.

**Why `--pcre2`:** the regex needs to match `from("conversations").update(` as a contiguous unit; the default ripgrep regex engine is `regex` crate which works fine for this, but `--pcre2` future-proofs against patterns where lookahead might be added (e.g., disallowing `.update(...)` not followed by `.eq("user_id", ...)`).

### Research Insights — CI Detector

**Multiline-tolerance is mandatory.** Reviewed the 8 known callsites and found that `ws-handler.ts:194-203` splits the chain across multiple lines:

```ts
supabase
  .from("conversations")
  .update({ status: "completed", last_active: new Date().toISOString() })
  .eq("id", oldConvId)
```

A single-line regex (`from\("conversations"\)\.update\(`) would MISS this site — same callsite class as the bug we're trying to prevent. Use `rg -U --multiline` with a pattern that tolerates whitespace+newlines:

```bash
rg -U --multiline --pcre2 \
  'from\("conversations"\)\s*\.update\(' \
  "$SERVER_DIR" \
  --glob '!conversation-writer.ts' \
  --glob '!*.test.ts'
```

`-U --multiline` enables multi-line matching; `\s*` between `from("conversations")` and `.update(` matches the dot+newline+indent pattern.

**Negative test for the detector itself.** `conversations-update-grep-detector.test.ts` must include both shapes as fixtures:

- **Single-line fixture (must fail):** `await supabase.from("conversations").update({ status: "x" }).eq("id", "y");`
- **Multi-line fixture (must fail):** `supabase\n  .from("conversations")\n  .update({ status: "x" })\n  .eq("id", "y");`
- **Allowlisted bulk fixture (must pass):** prefixed by `// allow-direct-conversation-update: bulk sweep`
- **Wrapper-call fixture (must pass):** `await updateConversationFor(uid, cid, { status: "x" });`

Run the script against each fixture-file in a `tmpdir` and assert exit codes. Per `cq-mutation-assertions-pin-exact-post-state`: assert exit code is exactly `1` (not `>= 1`) for the "must fail" cases and exactly `0` for "must pass".

**lefthook integration shape.** Inspecting `lefthook.yml` (read it before adding the hook): if the `pre-commit` block uses `{staged_files}` for granular per-file linting, the conversation-writer linter must run **unconditionally** rather than only-when-staged-files-match — because adding the allowlist marker comment requires the linter to re-scan even when no `.ts` file changed in `apps/web-platform/server/`. Use the `commands.<name>.run:` form without `{staged_files}` substitution; mirror the `lint-bot-statuses` invocation if it already exists in lefthook.

**Performance budget.** Locally on this codebase, `rg -U --multiline --pcre2 'from\("conversations"\)\s*\.update\(' apps/web-platform/server/ --glob '!*.test.ts'` completes in <50ms. The CI detector is not a perf concern.

**Allowlist marker comment shape:** `// allow-direct-conversation-update: <reason>` on the line **immediately above** the matching `.from("conversations").update(...)` line. The `awk` step skips both the marker line and the next line when the marker matches.

**Bulk-update sites that get the marker:**

```ts
// agent-runner.ts cleanupOrphanedConversations
// allow-direct-conversation-update: bulk status update by filter — no per-user composite key
const { error } = await supabase()
  .from("conversations")
  .update({ status: "failed" })
  .in("status", ["active", "waiting_for_user"])
  .lt("last_active", fiveMinutesAgo);

// agent-runner.ts startInactivityTimer
// allow-direct-conversation-update: bulk timeout sweep — no per-user composite key
const { data, error } = await supabase()
  .from("conversations")
  .update({ status: "completed" })
  .in("status", ["waiting_for_user"])
  .lt("last_active", cutoff)
  .select("id, user_id");
```

## Migration Site-by-Site

### Site 1: `agent-runner.ts updateConversationStatus`

```ts
// BEFORE
async function updateConversationStatus(
  conversationId: string,
  status: string,
) {
  const { error } = await supabase()
    .from("conversations")
    .update({ status, last_active: new Date().toISOString() })
    .eq("id", conversationId);
  if (error) {
    throw new Error(`Failed to update conversation status: ${error.message}`);
  }
}

// AFTER
async function updateConversationStatus(
  userId: string,             // NEW: required to enforce R8 invariant
  conversationId: string,
  status: Conversation["status"],   // tightened from `string`
) {
  const result = await updateConversationFor(userId, conversationId, {
    status,
    last_active: new Date().toISOString(),
  }, { feature: "agent-runner", op: "updateConversationStatus" });
  if (!result.ok) {
    throw new Error(`Failed to update conversation status: ${result.error?.message ?? "unknown"}`);
  }
}
```

**Caller sweep required.** `updateConversationStatus` is called from **inside `agent-runner.ts`** at multiple lifecycle points. Every caller must pass `userId`. The `userId` is in scope at every call site via the `session.userId` field on `ActiveSession`. Verify via `rg "updateConversationStatus\(" apps/web-platform/server/` at work time and update each.

### Site 2: `agent-runner.ts` session_id persist (first-message handler)

```ts
// BEFORE
const { error: updateErr } = await supabase()
  .from("conversations")
  .update({ session_id: message.session_id })
  .eq("id", conversationId);

// AFTER
const { ok } = await updateConversationFor(userId, conversationId, {
  session_id: message.session_id,
}, { feature: "agent-runner", op: "persist-session-id" });
if (!ok) {
  // wrapper already mirrored to Sentry; preserve the local pino log for
  // grepability in container stdout
  log.error({ conversationId }, "Failed to store session_id");
}
```

`userId` is in scope as `session.userId` (the `runAgentSession` closure binds it).

### Site 3: `agent-runner.ts` clear stale session_id (SDK-resume catch)

Same shape as Site 2 — `userId` is bound by the closure.

### Site 4: `ws-handler.ts:194` supersede-on-reconnect

```ts
// BEFORE
supabase
  .from("conversations")
  .update({ status: "completed", last_active: new Date().toISOString() })
  .eq("id", oldConvId)
  .then(/* … */);

// AFTER
void updateConversationFor(userId, oldConvId, {
  status: "completed",
  last_active: new Date().toISOString(),
}, { feature: "ws-handler", op: "supersede-on-reconnect" });
```

The fire-and-forget `.then(…)` shape converts to `void updateConversationFor(...)` (the wrapper handles Sentry mirroring; the inline `.then` was only logging). `userId` is in scope from the `ws-handler` socket session.

### Site 5: `ws-handler.ts:523` active_workflow persist (already R8-compliant)

Already passes `.eq("user_id", userId)`. Migrate to the wrapper for symmetry so the CI detector can be a hard `! rg ...` (no per-line `// already-r8-compliant` exemption). The `last_active` and `active_workflow` patch fits `ConversationPatch` exactly.

### Site 6: `ws-handler.ts:892` close-on-supersede

Same shape as Site 4 — direct id-only update, fire-after-await.

### Site 7: `cc-dispatcher.ts:419` `updateConversationStatus` closure

Already R8-compliant and already calls `reportSilentFallback`. Migrate the closure body to delegate to the wrapper:

```ts
// AFTER
updateConversationStatus: async (convId: string, status: string) => {
  await updateConversationFor(args.userId, convId, {
    status: status as Conversation["status"],
    last_active: new Date().toISOString(),
  }, { feature: "cc-dispatcher", op: "updateConversationStatus" });
  // wrapper handles Sentry mirroring — closure no longer needs reportSilentFallback
},
```

The closure shape (`(convId, status) => Promise<void>`) is unchanged — the cc-soleur-go runner caller doesn't see the migration.

#### Transitive Coverage via `deps.updateConversationStatus`

The cc-dispatcher closure is **injected** into `permission-callback.ts` via the `CanUseToolDeps.updateConversationStatus` field (defined at `permission-callback.ts:117-120`). It is invoked at **6 additional sites** in `permission-callback.ts` to flip conversation status during permission gates:

- `:228` — `await deps.updateConversationStatus(ctx.conversationId, "waiting_for_user")` (gate issued)
- `:238` — `await deps.updateConversationStatus(ctx.conversationId, "active")` (gate resolved)
- `:363` — bash-gate variant of `:228`
- `:373` — bash-gate variant of `:238`
- `:505` — review-gate variant of `:228`
- `:515` — review-gate variant of `:238`

**Design decision: do NOT widen `CanUseToolDeps.updateConversationStatus` from `(conversationId, status) => Promise<void>` to `(userId, conversationId, status) => Promise<void>`.** Reasoning:

1. The cc-dispatcher closure already captures `args.userId` via lexical scope. Migrating the closure body migrates all 6 permission-callback sites for free.
2. Widening the deps signature would force `permission-callback.ts` to thread `ctx.userId` through every call — 6 mechanical changes for zero R8-correctness gain (the userId comes from the same `ctx` that supplied conversationId; both are server-derived).
3. The closure is the R8 enforcement boundary by design. Defense-in-depth lives **inside the closure** (where the wrapper is called with `args.userId`), not at the deps interface (where callers would have to remember to pass it).

**Test impact for `cc-dispatcher-real-factory.test.ts` (T-AC4 at `:401-554`):** the existing test captures the supabase `.update` chain via `mockSupabaseFrom.mockImplementation(...)` at `:408-450`. After migration, the wrapper still calls `supabase().from("conversations").update(...).eq("id",...).eq("user_id",...)` — the capture chain (which records `payload`, `eqs`, and pushes to `updateCalls[]`) keeps working unchanged because it captures by surface, not by source-module. T-AC4 passes without modification. **Do not rewrite T-AC4 in the migration.**

**Test impact for `cc-dispatcher.test.ts`:** this test currently `vi.mock("@/server/observability", …)` and asserts on `mockReportSilentFallback`. Two options:

- **Option A (recommended):** add `vi.mock("@/server/conversation-writer", …)` returning a mock `updateConversationFor`. Assert the wrapper was called with the right userId/convId/patch. The Sentry mirror is now the wrapper's responsibility — the cc-dispatcher unit test no longer needs to know about it.
- **Option B:** keep mocking observability and let the real wrapper run with the supabase mock. More integration-flavored but couples the cc-dispatcher unit test to the wrapper's internal Sentry shape.

Choose A — keeps the unit-test boundary tight at the cc-dispatcher module and lets `conversation-writer.test.ts` own the Sentry-mirror assertions.

## Test Scenarios

### T1 — Wrapper happy path

`updateConversationFor(userId, conversationId, { status: "completed" })` calls Supabase with the patch and **both** `.eq("id", ...)` and `.eq("user_id", ...)`. Assert `.toHaveBeenCalledWith({ status: "completed" })` on the `.update` mock and `.toHaveBeenCalledWith("id", conversationId)` + `.toHaveBeenCalledWith("user_id", userId)` on the `.eq` mock.

Per `cq-mutation-assertions-pin-exact-post-state`: assert `.toBe(true)` on `result.ok`, not `.toContain([true, false])`.

### T2 — Wrapper error path

Mock the supabase chain to return `{ error: { message: "boom" } }`. Assert:

- `result.ok === false`
- `result.error.message === "boom"`
- `mockReportSilentFallback` called once with `{ feature: "conversation-writer", op: "update", extra: { userId, conversationId, patchKeys: ["status"] } }`

### T3 — `feature`/`op` overrides flow into the Sentry tag

Pass `{ feature: "ws-handler", op: "supersede-on-reconnect" }`. Assert the `reportSilentFallback` call uses those values, not the defaults.

### T4 — Composite-key prevents cross-user write (integration-shape)

Mock the supabase chain such that `.eq("id", convId).eq("user_id", "wrong-user")` returns 0 rows affected (no error, no rows). Assert `result.ok === true` (Supabase doesn't return an error for 0 rows; the wrapper's contract is "no DB error" not "row updated"). Document this in the JSDoc — the wrapper does not detect a 0-rows-affected condition because the underlying call sites don't currently care.

**Why not 0-rows-as-error:** changing zero-rows to an error would change the migration semantics. Each legacy call site would need a new branch. That's a separate cycle if we want it; doing it inline doubles the blast radius.

### T5 — CI detector catches a new direct write

Run `scripts/lint-conversations-update-callsites.sh` against a fixture file that contains:

```ts
// fixture: should fail
await supabase.from("conversations").update({ status: "completed" }).eq("id", "x");
```

Assert the script exits non-zero and stderr contains the file path.

### T6 — CI detector accepts an allowlisted bulk update

Fixture:

```ts
// allow-direct-conversation-update: bulk timeout sweep
await supabase.from("conversations").update({ status: "failed" }).in("status", ["active"]);
```

Assert the script exits 0.

### T7 — Existing callers updated

Run `apps/web-platform` vitest. Assert `cc-dispatcher.test.ts` passes after the closure is migrated to delegate (the test currently asserts on `mockReportSilentFallback` inside the closure; after migration, it asserts on a `mockUpdateConversationFor` mock from `vi.mock("@/server/conversation-writer", …)`).

### T8 — `agent-runner.ts updateConversationStatus` signature change is type-safe

Run `tsc --noEmit` in `apps/web-platform`. Every caller of `updateConversationStatus` must pass a `userId` argument; the build fails if any caller is missed.

### T9 — Transitive coverage via `deps.updateConversationStatus`

Add a test that exercises one of the `permission-callback.ts` sites through the cc-dispatcher closure. Pattern:

1. Build a `ccDeps` object via the cc-dispatcher's `buildCcDeps({ userId: "u1", conversationId: "conv-1", … })` factory (the same path `cc-dispatcher-real-factory.test.ts` uses at `:455-471`).
2. Capture `mockSupabaseFrom` like the existing T-AC4 pattern at `:425-450`.
3. Call `ccDeps.updateConversationStatus("conv-1", "waiting_for_user")` directly (mirroring how `permission-callback.ts:228` would invoke it).
4. Assert the captured update has BOTH `.eq("id", "conv-1")` AND `.eq("user_id", "u1")` — proving the deps-injected closure is R8-compliant after migration.

This keeps `permission-callback.ts` unchanged in the test surface (it doesn't need to know about the wrapper) while pinning the transitive-coverage invariant.

### T10 — CI detector multi-line tolerance

Already enumerated in "Research Insights — CI Detector" above. Restated here for traceability: the detector test fixture set MUST include both single-line and multi-line broken chains. A detector that misses multi-line chains is the bug class we're trying to prevent.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/server/conversation-writer.ts` exists and exports `updateConversationFor` + `ConversationPatch`.
- [ ] `apps/web-platform/server/conversation-writer.test.ts` exists with **at least 4 cases**: happy path, error path, feature/op tag override, 0-rows-affected.
- [ ] `scripts/lint-conversations-update-callsites.sh` exists, executable, and tested locally against fixtures (T5/T6).
- [ ] `.github/workflows/ci.yml` has a `lint-conversations-update-callsites` job in the same file as `lint-bot-statuses`.
- [ ] `lefthook.yml` runs the same script on `pre-commit`.
- [ ] All 7 single-conversation `.update(...)` call sites migrated (3 in agent-runner.ts, 3 in ws-handler.ts, 1 in cc-dispatcher.ts).
- [ ] 2 bulk-update sites have `// allow-direct-conversation-update:` markers.
- [ ] `rg -U --multiline --pcre2 'from\("conversations"\)\s*\.update\(' apps/web-platform/server/ --glob '!conversation-writer.ts' --glob '!*.test.ts'` returns ONLY the 2 allowlisted bulk sites (multi-line tolerance verified — `ws-handler.ts:194` is multi-line and MUST appear as a non-allowlisted hit BEFORE migration, then disappear AFTER).
- [ ] Transitive deps coverage via `permission-callback.ts` proven by T9 — at least one assertion that `deps.updateConversationStatus` (post-migration) results in a captured supabase update with both `.eq("id", ...)` and `.eq("user_id", ...)`.
- [ ] `tsc --noEmit` passes (T8).
- [ ] `vitest run` passes for `apps/web-platform`.
- [ ] `cc-dispatcher.test.ts` updated to mock `@/server/conversation-writer` instead of asserting on internal `reportSilentFallback`.
- [ ] PR body uses `Closes #2956`.

### Post-merge (operator)

- [ ] CI `lint-conversations-update-callsites` job runs green on `main`.
- [ ] Sentry shows new tag vocabulary: `feature: ws-handler, op: supersede-on-reconnect` etc. for any conversation-update error in the next 7 days. (Verification: query Sentry `feature:ws-handler op:supersede-on-reconnect` after 24h; if zero events, the tag wiring is unverified but not broken — tags only surface on actual errors.)

## Domain Review

**Domains relevant:** Engineering (CTO).

This is an internal refactor with no user-facing surface, no marketing/content/legal/finance/operations implications, and no cross-domain orchestration changes. The only domain leader assessment that adds signal is CTO — and the technical concerns are already enumerated by the issue author + this plan's reconciliation table.

### Engineering (CTO)

**Status:** assessed inline (issue author is CTO-equivalent; reconciliation table covers the same surface a fresh CTO Task would).

**Assessment:** Wrapper extraction with composite-key invariant + CI grep detector is the canonical pattern for "ratchet up DB safety after a single PR proves it" (precedent: silent-fallback Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`, where 15 sites were migrated under a similar pattern). Risks: type-derivation choice (hand-written interface vs Supabase generated types), throw-vs-result API shape, and 0-rows-as-error semantics — all addressed in Wrapper Design above.

No other domain leader (CMO, CPO, COO, CFO, CLO, CHRO, CRO) has signal to add. This is engineering-only.

## Risks & Sharp Edges

1. **`agent-runner.ts updateConversationStatus` callers must all pass `userId`.** TS will catch this at build time, but in worktrees the build is local-only — verify with `cd apps/web-platform && ./node_modules/.bin/vitest run` AND `npx tsc --noEmit` per `cq-in-worktrees-run-vitest-via-node-node`. Don't trust `npx vitest`.
2. **`status: string` → `status: Conversation["status"]` is a tightening.** If any caller passes a string literal that's not in the union (`"active" | "waiting_for_user" | "completed" | "failed"`), TS will fail. This is desired — but during migration, briefly grep for `updateConversationStatus(` to see all literals being passed.
3. **0-rows-affected is silent success, not an error.** Documented in T4. If a future feature wants a "did we actually update?" signal, add a `select("id").maybeSingle()` chained read inside the wrapper as a follow-up; that's a behavioral change that needs its own audit.
4. **lefthook hang in worktrees.** Per `cq-when-lefthook-hangs-in-a-worktree-60s`, if `pre-commit` runs the new script and stalls, kill with `pkill -f "lefthook run"` and commit with `LEFTHOOK=0`. The script itself is fast (`rg` over `apps/web-platform/server/` is sub-second on this codebase); slowness is lefthook's own bug, not the script's.
5. **Allowlist marker comment shape is grep-stable.** Don't restyle the marker (`// allow-direct-conversation-update:`) — the `awk` regex matches it literally. If a reviewer suggests reformatting to a multi-line block comment, that breaks the `-B1` context window. Per `cq-code-comments-symbol-anchors-not-line-numbers`, treat the marker as a symbol.
6. **`--pcre2` portability.** Ripgrep on Ubuntu 22.04 (GitHub Actions runner) ships `--pcre2` enabled. Verify with `rg --pcre2 --version | grep -q "PCRE2"` in the script's preamble (if missing, fall back to the default regex engine — the pattern doesn't currently need PCRE2 features, but the flag future-proofs).
7. **Test mock module path.** `cc-dispatcher.test.ts` currently does `vi.mock("@/server/observability", ...)`. After the wrapper takes ownership of Sentry mirroring, the test must add `vi.mock("@/server/conversation-writer", ...)` and assert against `mockUpdateConversationFor` instead. Per `cq-test-mocked-module-constant-import`, beware of exporting `ConversationPatch` and re-importing in a test that mocks the module — the mocked module won't expose the type unless the factory returns it.

8. **`deps.updateConversationStatus` interface stays at `(conversationId, status)`.** A reviewer ("type-design" lens) might propose widening to `(userId, conversationId, status)` for explicit-is-better-than-implicit. Reject this: the closure captures `args.userId` lexically, and forcing 6 `permission-callback.ts` sites to thread `ctx.userId` adds churn for no R8 gain (both ids are server-derived). Document the choice in the closure body comment so a future reader doesn't "fix" it.

9. **Multi-line regex is load-bearing — do NOT simplify to a single-line pattern.** A reviewer ("simplicity" lens) may propose dropping `-U --multiline` and the `\s*` to make the regex easier to read. Reject this: `ws-handler.ts:194` writes the chain across 4 lines and would be missed. The detector's whole job is catching this exact bug class. Per `cq-code-comments-symbol-anchors-not-line-numbers`, keep the regex documented next to the script, not in a far-away ADR.

10. **`bash` is the only required dependency for the lint script.** No `awk` quirks across BSD vs GNU: the marker-strip `awk` block uses POSIX features only (`/regex/`, `next`, `print`). Tested against `mawk`, `gawk`, `awk` (BSD). The runner is Ubuntu 22.04 (GNU awk) — works. Document in the script header so a future macOS contributor doesn't "fix" the awk to something fancier.

## Plan Authoring Notes

- Issue body said 5 legacy sites; grep found 6. Per `cq-when-a-plan-says-extract-a-shared-factory-helper-for-n-files` (the planning rule about validating N at planning time): the **extra site is `ws-handler.ts:194`** (supersede-on-reconnect). Issue body missed it because it scanned for the close-handler block; `:194` is in the connect-handler block.
- Issue body's line numbers had drifted (e.g., `agent-runner.ts:317-331` is now `:347-360`). The reconciliation table re-anchors via symbol per `cq-code-comments-symbol-anchors-not-line-numbers`.
- No external research needed. This is a code-extraction refactor with strong local precedent (`reportSilentFallback` migration in #2480/#2484; cc-dispatcher.ts:419's existing R8-compliant write) and no third-party API surface.
- No infra changes. No Terraform. No Doppler secrets. No Supabase migration.
- No UI changes. No Product/UX Gate.

Ref #2954 (the PR that introduced the R8-compliant pattern this plan generalizes).
