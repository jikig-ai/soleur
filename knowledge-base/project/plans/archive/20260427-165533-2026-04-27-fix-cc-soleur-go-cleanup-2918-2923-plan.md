# Plan — cc-soleur-go cleanup: drain code-review backlog #2918-#2923

**Branch:** `feat-one-shot-fix-2918-2923`
**Type:** fix (multi-issue cleanup)
**Created:** 2026-04-27
**Deepened:** 2026-04-27
**Issues closed:** #2918, #2919, #2920, #2921, #2922, #2923
**Origin PR:** all 6 issues are review findings from PR #2901 (Stage 2.12 cc-soleur-go SDK binding)

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** 7 (Files to Create, Files to Edit, Phase 1, Phase 3, Phase 4, Phase 5, Test Scenarios)

**Key Improvements from deepen pass:**

1. **#2919 RPC permissioning corrected** — initial plan said `SECURITY INVOKER`, but precedent migration 027 (`sum_user_mtd_cost`) uses `SECURITY DEFINER` + `REVOKE FROM authenticated/anon` + `GRANT TO service_role`. `getUserApiKey` is called server-side via the service-role supabase client; INVOKER would misroute the auth check. **Switched to DEFINER + service-role grant.**
2. **#2918 atomic-write fsync gap** — initial plan used `writeFileSync` + `renameSync` but missed the `fsync(fd)` on the temp file before rename, which on some filesystems can leave a zero-byte file post-crash. Added explicit `fdatasync` step.
3. **#2918 settings.permissions undefined edge** — current `patchWorkspacePermissions` does `settings.permissions.allow = filtered` AFTER asserting `Array.isArray(settings?.permissions?.allow)` — safe. Atomic-write rewrite must preserve this guard.
4. **#2921 Bash gate AbortSignal** — `permission-callback.ts:312` Bash branch uses `options.signal` (per-tool-use), not `ctx.controllerSignal` (per-session). The batching cache MUST be checked BEFORE the gate (no signal needed for cache hit) — confirmed in plan.
5. **#2922 hooks.SubagentStart payload divergence** — legacy uses `[\r\n]` strip; cc uses `[\x00-\x1f\x7f  ]` strip + `ccPath: true` flag. These are intentionally different. Added clarifying note: `args.subagentStartPayloadOverride?: { logFields?: object; sanitizer?: (v) => string }`.
6. **#2920 `last_active` field parity** — legacy `agent-runner.ts:303` writes `{ status, last_active: new Date().toISOString() }`. The cc version should match for parity (same conversation status field).
7. **#2919 second-caller plaintext correctness** — re-encryption is deterministic on plaintext + userId (HKDF-derived key), so the first-caller's stored ciphertext decrypts to the same plaintext the second caller already has. Helper just returns its own decrypted plaintext — no re-decrypt needed. Added explicit AC.

### New Considerations Discovered

- The `migrate_api_key_to_v2` function should also be `LANGUAGE sql` (not `plpgsql`) since it's a single UPDATE with no control flow — matches migration 027 precedent and is faster.
- The drift-guard test for `#2922` should use `JSON.stringify(opts, Object.keys(opts).sort())` for stable serialization across Node versions.

## Overview

PR #2901 bound the real `@anthropic-ai/claude-agent-sdk` `query()` inside
`realSdkQueryFactory` (`apps/web-platform/server/cc-dispatcher.ts`). Six review
findings were filed `deferred-scope-out` because each needed its own design
pass. The cc-soleur-go path is gated behind `FLAG_CC_SOLEUR_GO=0` in prod —
none of these are user-visible regressions today, but **#2920 (no-op status
write) and #2923 (minimal system prompt) are Stage 6 acceptance gates** that
must close before the flag flips to `true` in prod.

This plan bundles all six into one cleanup PR. The fixes are surgical, share
the same code area (`apps/web-platform/server/agent-runner.ts`,
`cc-dispatcher.ts`, `soleur-go-runner.ts`, `permission-callback.ts`), and
benefit from a single round of review + QA.

**Scope discipline:** This plan does NOT expand to the broader code-review
backlog (e.g., #2231, #2244, #2348). Six issues, one PR.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality | Plan response |
|---|---|---|
| #2918 suggests `lib/server/workspace-permission-lock.ts` | Repo has no `apps/web-platform/lib/server/` directory; server-side modules live at `apps/web-platform/server/`. | Place the new helper at `apps/web-platform/server/workspace-permission-lock.ts`. |
| #2918 suggests `proper-lockfile` OR Map-of-AsyncMutex | Neither `proper-lockfile`, `async-mutex`, nor `async-lock` is in `package.json`. The repo has prior in-process Map-keyed locking patterns (e.g., `pending-prompt-registry.ts`, `cc-cost-caps.ts`). | Use a zero-dependency in-process Map-of-`Promise` mutex keyed on `workspacePath`. Multi-process coordination is out-of-scope (single Next.js server process per container; cold-Query construction is rare per user). |
| #2922 suggests `agent-runner-query-options.ts` | Sibling `agent-runner-sandbox-config.ts` already exists for the same drift-guard reason; precedent is `<feature>-config.ts`. | Use `agent-runner-query-options.ts` (issue's suggested name aligns with precedent). |
| #2919 suggests `SELECT ... FOR UPDATE` within a transaction | Supabase JS client does NOT support transactions or `FOR UPDATE` directly; the codebase uses `supabase().rpc(...)` (see `agent-runner.ts:1036`) for atomic ops. v1 → v2 migration is idempotent on plaintext; the danger is only the UPDATE write conflict. | Use a Postgres function (RPC) `migrate_api_key_to_v2(p_id, p_user_id, p_provider, p_encrypted, p_iv, p_tag)` that wraps the UPDATE with `WHERE key_version = 1` (predicate-locked: second concurrent caller's UPDATE no-ops because key_version is now 2). New migration `033_migrate_api_key_to_v2_rpc.sql`. |
| #2922 says "4 files materially related" | Verified: `agent-runner.ts startAgentSession query({...})` (lines 814-893) and `cc-dispatcher.ts realSdkQueryFactory sdkQuery({...})` (lines 401-477). Plus a new helper module + a new drift-guard test. ✓ | Match — proceed as scoped. |
| #2920 dispatcher OR runner ownership | The dispatcher synthesizes the `AgentSession` (only place in cc path) and owns the BYOK/workspace fetches. It is the natural owner of conversation status writes mediated through `canUseTool`. The runner owns workflow lifecycle (`onWorkflowEnded`) — that is a SEPARATE write surface (status `failed`/`completed`), not the gate-cycle flips. | Dispatcher path: replace the no-op `ccDeps.updateConversationStatus` with a direct `supabase().from("conversations").update({status}).eq("id",...).eq("user_id",...)`. User-id is composite-key invariant per R8 (cc-dispatcher.ts:244). |
| #2921 "≤3 distinct prompts on /soleur:work" | Realistic. /soleur:work fires `git status`/`git diff`/`rg`/`bun test`/`npx tsc` etc. — most are a small command-prefix vocabulary. | Keep AC at "≤3 prompts on a small-repo /soleur:work fixture" with a documented test recipe. |
| #2923 says minimal prompt may produce mis-routes | Verified: `buildSoleurGoSystemPrompt()` returns 5 lines (router introduction + narration directive + dispatch instruction + injection-fence). Legacy `agent-runner.ts buildSystemPrompt` injects: workspace path semantics, current artifact (`context.path`/`context.content`), connected services list, KB-share announcement, conversations announcement. Of these, **routing-relevant** = workspace context (current artifact path, sticky-workflow); **sub-skill-relevant** = connected services, KB share, conversations announcements. | Inject ONLY routing-relevant context: (1) current artifact path (when `args.context?.path` is provided), (2) sticky-workflow signal (when `args.currentRouting.kind === "soleur_go_active"`). Sub-skill-relevant context flows to the routed sub-skill via its own SDK options. Add `context` and `routing` to `QueryFactoryArgs`/`buildSoleurGoSystemPrompt(args)` signatures. |

## Hypotheses

This is a fix-the-known-defects PR, not a diagnostic one — no hypotheses needed.

## Open Code-Review Overlap (summary)

Per Phase 1.7.5, a path-by-path search over open `code-review`-labeled issues against the planned `Files to Edit` returns ONLY the six in-scope issues. **Disposition:** all six are folded in. Zero acknowledge / zero defer. Full path-mapped table at §"Open Code-Review Overlap" near the bottom of this plan.

## Files to Create

1. **`apps/web-platform/server/workspace-permission-lock.ts`** — fix #2918.
   In-process Map-keyed mutex around `patchWorkspacePermissions` + atomic
   write-then-rename helper. Keyed on canonicalized `workspacePath`.

2. **`apps/web-platform/server/agent-runner-query-options.ts`** — fix #2922.
   Exports `buildAgentQueryOptions(args)` and `AgentQueryOptionsArgs` type.
   Returns the canonical `Options` object both call sites currently inline.
   Consumes `buildAgentSandboxConfig` internally so the precedent stays one
   layer of indirection. Per-call overrides expressed as input fields, not
   post-build patches (keeps the canonical shape immutable).

3. **`apps/web-platform/supabase/migrations/033_migrate_api_key_to_v2_rpc.sql`**
   — fix #2919. Postgres function `migrate_api_key_to_v2(...)` with a
   predicate-locked UPDATE (`WHERE id = $1 AND user_id = $2 AND key_version = 1`).
   Concurrent callers serialize via PG row locks; second-writer's UPDATE
   matches zero rows (no-op). `SECURITY INVOKER` so RLS still applies.

4. **`apps/web-platform/server/permission-callback-bash-batch.ts`** — fix #2921.
   Per-(userId, conversationId) command-prefix allowlist with TTL + revoke.
   `getBashApprovalCache(userId, convId)` → `{ allow: (cmd) => boolean, grant: (prefix) => void, revoke: () => void }`.
   The grant surface adds an extra option to the Bash review-gate options
   array: `["Approve", "Approve all <prefix>", "Reject"]`. Selecting the
   batched option grants the prefix for the rest of the conversation
   (or until WS reconnect / explicit revoke).

5. **`apps/web-platform/test/workspace-permission-lock.test.ts`** —
   contract tests for #2918: serialization invariant + atomic-rename
   crash-safety.

6. **`apps/web-platform/test/agent-runner-query-options.test.ts`** —
   drift-guard for #2922. Asserts both call sites' built options are
   structurally equivalent modulo per-call overrides
   (`leaderId`, `mcpServers`, `allowedTools`, `maxTurns`, `maxBudgetUsd`,
   `hooks`, `canUseTool`, `prompt`, `resume`, `systemPrompt`).

7. **`apps/web-platform/test/permission-callback-bash-batch.test.ts`** —
   #2921 batching semantics: TTL-gated allowlist, prefix matching,
   revoke-clears-cache, no cross-conversation leak (R8 composite-key).

8. **`apps/web-platform/test/agent-runner-byok-migration.test.ts`** —
   #2919: assertion against the RPC's predicate-lock semantics. Mocks
   the supabase client; verifies that two concurrent v1→v2 callers each
   issue ONE rpc call, and that the helper handles the
   "second writer's UPDATE matched zero rows" return path without
   throwing.

## Files to Edit

1. **`apps/web-platform/server/agent-runner.ts`**
   - **#2918:** wrap `patchWorkspacePermissions` body in
     `withWorkspacePermissionLock(workspacePath, () => { ... })`. Replace
     `writeFileSync(settingsPath, ...)` with the atomic write-then-rename
     helper.
   - **#2919:** replace the inline `.update({...})` + `.eq("id", data.id)` block
     in `getUserApiKey` (lines 188-198) with a single `supabase().rpc("migrate_api_key_to_v2", { ... })`
     call. Mirror in `getUserServiceTokens` (lines 248-259) — same race lives
     there; folding in is a 5-LoC delta and avoids a phantom #2919-bis.
   - **#2922:** replace the `query({ options: {...} })` literal at lines 814-893
     with `query({ options: buildAgentQueryOptions({ ...args }) })`. Per-call
     overrides (`maxTurns: 50`, `maxBudgetUsd: 5.0`, `mcpServers: mcpServersOption`,
     `allowedTools`, `prompt`, `resume`, `systemPrompt`, `hooks.SubagentStart`,
     `canUseTool`) flow through the args object.

2. **`apps/web-platform/server/cc-dispatcher.ts`**
   - **#2918:** the `patchWorkspacePermissions(workspacePath)` call at line 365
     now goes through the lock automatically (the lock is INSIDE
     `patchWorkspacePermissions`, not at the call site). Verify no behavior
     change at the call site.
   - **#2920:** replace the no-op `ccDeps.updateConversationStatus` (lines 394-397)
     with a real write that **mirrors legacy `agent-runner.ts:303`**
     (also writes `last_active` so idle-reaper sees fresh activity):
     ```ts
     updateConversationStatus: async (convId, status) => {
       const { error } = await supabase()
         .from("conversations")
         .update({ status, last_active: new Date().toISOString() })
         .eq("id", convId)
         .eq("user_id", args.userId);   // R8 composite-key invariant
       if (error) {
         reportSilentFallback(error, {
           feature: "cc-dispatcher",
           op: "updateConversationStatus",
           extra: { userId: args.userId, conversationId: convId, status },
         });
       }
     },
     ```
     Parity with legacy is load-bearing — both paths feed the same
     `conversations` table and the same idle-reaper logic.
   - **#2921:** wire `getBashApprovalCache(args.userId, args.conversationId)`
     through `ccDeps` (new dep field `bashApprovalCache?: BashApprovalCache`).
     The lock must be drained when the conversation closes — extend
     `cleanupCcBashGatesForConversation(userId, convId)` to also call
     `bashApprovalCache.revoke()`.
   - **#2922:** replace the `sdkQuery({ options: {...} })` literal at lines 401-477
     with `sdkQuery({ prompt, options: buildAgentQueryOptions({ ...ccArgs }) })`.
     Per-call overrides (`leaderId: CC_ROUTER_LEADER_ID`,
     `disallowedTools: ["WebSearch","WebFetch"]`, `mcpServers: {}`,
     `permissionMode: "default"`, `model: "claude-sonnet-4-6"`,
     `systemPrompt`, `prompt`, `resume`, `canUseTool`, `hooks`) flow through
     args. The cc factory's `hooks.SubagentStart` payload (with `ccPath: true`)
     stays cc-specific — pass via `args.hooksOverrides`.

3. **`apps/web-platform/server/soleur-go-runner.ts`**
   - **#2923:** widen `buildSoleurGoSystemPrompt(args?: { artifactPath?: string; activeWorkflow?: WorkflowName | null })`.
     When `args.artifactPath` is non-empty, append:
     ```
     The user is currently viewing: <path>. Treat routing decisions as scoped to this artifact when the message references "this", "the document", "this file", etc.
     ```
     When `args.activeWorkflow` is non-null, append:
     ```
     A <workflow> workflow is active for this conversation. Continue dispatching to /soleur:<workflow> unless the user explicitly resets routing.
     ```
   - **`QueryFactoryArgs`:** add `artifactPath?: string` and
     `activeWorkflow?: WorkflowName | null` (already passed through
     `dispatch(args)` — currentRouting is in scope at line 738-741, just
     wire it through to the factory).
   - **`DispatchArgs`:** add `artifactPath?: string` (the dispatcher already
     receives `currentRouting`).

4. **`apps/web-platform/server/permission-callback.ts`**
   - **#2921:** the Bash review-gate (lines 282-348) needs to consult the
     per-conversation cache before emitting the gate, and offer the batched
     option in the gate options.
     - Before `randomUUID()`, check `deps.bashApprovalCache?.allow(command)`
       — if true, log + auto-approve.
     - Augment `options: ["Approve", "Reject"]` to
       `[ "Approve", "Approve all <derived-prefix>", "Reject" ]` when
       `deps.bashApprovalCache` is wired (legacy runner without it stays
       at the 2-option shape — opt-in).
     - On `selection === "Approve all <prefix>"`, call
       `deps.bashApprovalCache.grant(prefix)` then allow.
     - **Prefix derivation** (deterministic, in-module helper
       `deriveBashCommandPrefix(command)`): take the first
       whitespace-delimited token; if it is `git`, take the first two
       tokens (`git status`, `git diff`, `git log`); if it starts with
       `npx`/`bun`/`npm`, take the first three tokens
       (`npm run lint`, `bun test`, `npx tsc`); otherwise the first token.
       Conservative — favors granting too narrow a prefix over too broad.

5. **`apps/web-platform/test/agent-runner-helpers.test.ts`**
   - Add a test that `buildAgentQueryOptions(legacyArgs)` (legacy path) and
     `buildAgentQueryOptions(ccArgs)` (cc path) produce options whose shared
     fields (`cwd`, `model`, `permissionMode`, `settingSources`,
     `includePartialMessages`, `disallowedTools`, `sandbox`, `plugins`,
     `hooks.PreToolUse[0].matcher`) are deep-equal. Per-call divergent
     fields are NOT asserted equal (different `mcpServers`, `allowedTools`,
     etc.) but their PRESENCE/SHAPE in both paths is asserted.

6. **`apps/web-platform/test/cc-dispatcher-real-factory.test.ts`**
   - Update existing T4/T17 to assert the helper-mediated shape rather
     than inline-literal asserting the sandbox object.
   - Add T-AC4: `updateConversationStatus` invocation hits the supabase
     mock with the right `(id, status)` pair AND `.eq("user_id", args.userId)`
     gate (composite-key R8).

7. **`apps/web-platform/test/cc-dispatcher-bash-gate.test.ts`**
   - Add a multi-Bash test: 5 sequential `git status` invocations on a
     conversation where the first one was approved with the batched option
     produce ZERO additional gates.
   - Negative test: a `git status` grant does NOT auto-approve a `git push`
     in the same conversation (prefix-match strictness).
   - Cross-conversation isolation: a grant in conversation A does NOT leak
     to conversation B.

8. **`apps/web-platform/test/soleur-go-runner.test.ts`**
   - Add a test for the new system-prompt args branches: artifact-path
     present produces the artifact-aware sentence; activeWorkflow="work"
     produces the sticky-workflow sentence.

## Implementation Phases

### Phase 1 — `#2918` workspace-permission lock + atomic write (RED → GREEN)

**Why first:** lowest blast radius; bare-metal helper everyone else will
either use or step around.

1. RED — write `apps/web-platform/test/workspace-permission-lock.test.ts`:
   - T1: two concurrent `withWorkspacePermissionLock(path, fn)` calls on
     the SAME path serialize (second `fn` runs only after first resolves).
   - T2: same with DIFFERENT paths run concurrently (no false serialization).
   - T3: `atomicWriteJson(<path>, <obj>)` writes to `<path>.tmp` then
     renames; if rename throws, no partial file at `<path>`.
   - T4: `withWorkspacePermissionLock` propagates throw from `fn` to
     caller without leaking the lock (next call resolves).
2. GREEN — implement `workspace-permission-lock.ts`:
   - `_locks = new Map<string, Promise<void>>()` keyed on
     `path.resolve(workspacePath)`.
   - `withWorkspacePermissionLock(path, fn)` chains a new promise off
     the existing entry; on resolve/reject it deletes the entry IF it
     is still the tail.
   - `atomicWriteJson(path, obj)` — durability-correct sequence:
     1. `openSync(path + ".tmp", "w")` → fd
     2. `writeSync(fd, json)`
     3. `fdatasyncSync(fd)` — flush data to disk before rename so a
        crash between rename and journal flush doesn't leave a zero-byte
        file (POSIX rename is atomic, but only after the data is durable).
     4. `closeSync(fd)`
     5. `renameSync(path + ".tmp", path)`
     6. On any throw at steps 1-5: best-effort
        `try { unlinkSync(path + ".tmp"); } catch {}` — never let cleanup
        mask the original error.
     **Per-tmp-file collision avoidance:** include `process.pid` and
     `randomUUID().slice(0, 8)` in the suffix (`<path>.<pid>.<rand>.tmp`)
     so two concurrent same-process writers (impossible here due to the
     mutex, but defense-in-depth) and any stale `.tmp` from a crashed
     prior run never collide.
3. REFACTOR — wrap `patchWorkspacePermissions` body in
   `withWorkspacePermissionLock`. Replace `writeFileSync` with
   `atomicWriteJson`. Verify the existing `cc-dispatcher-real-factory.test.ts`
   T10 still passes (`patchWorkspacePermissions` fires once per factory).

### Phase 2 — `#2922` extract `buildAgentQueryOptions` (RED → GREEN)

**Why second:** the largest mechanical refactor; fixing it before the cc
behavioral changes (#2920, #2921, #2923) means those changes land on the
helper-mediated path, not on the literal-inline path.

1. RED — write `agent-runner-query-options.test.ts`:
   - T1: minimum-args call returns the canonical shape (cwd, model,
     permissionMode, settingSources, includePartialMessages, sandbox,
     plugins, hooks.PreToolUse).
   - T2: `args.allowedTools` is wired through verbatim.
   - T3: `args.systemPrompt` is wired through verbatim.
   - T4: drift-guard — assert against a frozen snapshot of the canonical
     shape (sentinel test fails LOUDLY when the helper drifts; updates
     require an explicit snapshot bump).
2. GREEN — implement `agent-runner-query-options.ts`:
   ```ts
   export interface AgentQueryOptionsArgs {
     workspacePath: string;
     pluginPath: string;
     apiKey: string;
     serviceTokens: Record<string,string>;
     systemPrompt: string;
     model?: string;            // default "claude-sonnet-4-6"
     permissionMode?: string;   // default "default"
     resumeSessionId?: string;
     mcpServers?: Record<string, unknown>;
     allowedTools?: string[];
     disallowedTools?: string[];  // default ["WebSearch","WebFetch"]
     maxTurns?: number;
     maxBudgetUsd?: number;
     hooks?: { /* SDK shape */ };
     canUseTool: CanUseTool;
   }
   export function buildAgentQueryOptions(args: AgentQueryOptionsArgs): SDKOptions { ... }
   ```
   Internally calls `buildAgentSandboxConfig(args.workspacePath)` and
   `buildAgentEnv(args.apiKey, args.serviceTokens)`.
3. REFACTOR — replace both call-site literals.
4. Update `cc-dispatcher-real-factory.test.ts` T4/T17 to assert via the
   helper rather than the inline literal.

### Phase 3 — `#2919` BYOK race RPC (RED → GREEN)

**Why third:** the migration is independent; lands cleanly between
helper extraction and the cc-only behavioral fixes.

1. RED — write `agent-runner-byok-migration.test.ts`:
   - T1: when `key_version === 1` is read, helper calls
     `supabase().rpc("migrate_api_key_to_v2", {...})` exactly once with
     the encrypted/iv/tag tuple.
   - T2: when the RPC returns `{ data: { rows_affected: 0 } }` (second
     concurrent caller), the helper still returns the plaintext (the
     re-encrypt was already done by the first caller; we trust the
     plaintext we just decrypted).
   - T3: when `key_version === 2`, no RPC is called.
2. GREEN — write the migration `033_migrate_api_key_to_v2_rpc.sql`.
   **Pattern aligned to migration 027 (`sum_user_mtd_cost`):**
   `LANGUAGE sql`, `SECURITY DEFINER`, `SET search_path = public`,
   explicit `REVOKE FROM authenticated/anon` + `GRANT TO service_role`.
   `getUserApiKey` runs server-side under the service-role client, so
   DEFINER + service-role-only is the right scope (matches the BYOK
   threat model — RLS on `api_keys` already prevents cross-user reads
   via authenticated keys; the RPC must not expose a new vector).
   ```sql
   -- 033_migrate_api_key_to_v2_rpc.sql
   -- Predicate-locked v1 → v2 BYOK migration. Concurrent callers serialize
   -- via PG row locks on api_keys; the second writer's UPDATE matches
   -- WHERE key_version = 1 with zero rows (no-op). See #2919 + plan
   -- 2026-04-27-fix-cc-soleur-go-cleanup-2918-2923-plan.md.
   --
   -- LANGUAGE sql (not plpgsql) — single UPDATE, no control flow.
   -- SECURITY DEFINER — `getUserApiKey` invokes via service-role client
   -- (apps/web-platform/server/agent-runner.ts). REVOKE from authenticated
   -- and anon defends against accidental client-side calls slipping in.
   CREATE OR REPLACE FUNCTION public.migrate_api_key_to_v2(
     p_id        uuid,
     p_user_id   uuid,
     p_provider  text,
     p_encrypted text,
     p_iv        text,
     p_tag       text
   ) RETURNS TABLE (rows_affected integer)
   LANGUAGE sql
   SECURITY DEFINER
   SET search_path = public
   AS $$
     WITH updated AS (
       UPDATE public.api_keys
          SET encrypted_key = p_encrypted,
              iv            = p_iv,
              auth_tag      = p_tag,
              key_version   = 2,
              updated_at    = NOW()
        WHERE id            = p_id
          AND user_id       = p_user_id
          AND provider      = p_provider
          AND key_version   = 1
        RETURNING 1
     )
     SELECT COUNT(*)::INTEGER FROM updated;
   $$;

   COMMENT ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) IS
     'Service-role-only v1 → v2 BYOK re-encryption. Predicate-locked '
     'UPDATE serializes concurrent callers via PG row locks. See #2919.';

   REVOKE EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) FROM PUBLIC;
   REVOKE EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) FROM authenticated;
   REVOKE EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) FROM anon;
   GRANT  EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) TO   service_role;
   ```
   Then replace the inline UPDATE in `getUserApiKey` and
   `getUserServiceTokens` with `supabase().rpc("migrate_api_key_to_v2", {...})`.

   **Plaintext-correctness note for the second concurrent caller:**
   re-encryption is deterministic on (plaintext, userId) via HKDF — both
   callers decrypt to the SAME plaintext. The second caller's UPDATE
   no-ops (rows_affected=0); the helper still returns its OWN decrypted
   plaintext (no re-fetch needed). The DB row may be the first caller's
   ciphertext — that's correct because both ciphertexts decrypt to the
   same plaintext under the user's HKDF-derived key.

   Verify the migration runs in a single transaction (no `CREATE INDEX
   CONCURRENTLY` — `LANGUAGE sql` function body is metadata-only DDL,
   fine inside a tx).

3. Apply migration to dev FIRST, then prd, per
   `wg-when-a-pr-includes-database-migrations`. Closure of #2919 happens
   AFTER the prd apply, not at merge.

### Phase 4 — `#2920` cc dispatcher status writes (RED → GREEN)

1. RED — extend `cc-dispatcher-real-factory.test.ts`:
   - T-AC4a: when canUseTool fires AskUserQuestion, the supabase client is
     called with `.update({status: "waiting_for_user"}).eq("id", convId).eq("user_id", userId)`.
   - T-AC4b: when the gate resolves, supabase is called with
     `.update({status: "active"})`.
   - T-AC4c: `.eq("user_id", args.userId)` is present on every status
     update (R8 composite-key invariant — cross-user blast radius
     defense).
2. GREEN — implement the real `updateConversationStatus` in
   `cc-dispatcher.ts`. Use `reportSilentFallback` on `error` per
   `cq-silent-fallback-must-mirror-to-sentry`. The `permission-callback.ts`
   already calls `await deps.updateConversationStatus(...)` at lines 206
   and 216 (AskUserQuestion gate) and 307/317 (Bash gate) — wiring is
   automatic.

### Phase 5 — `#2921` Bash batching (RED → GREEN)

1. RED — write `permission-callback-bash-batch.test.ts`:
   - T1: `getBashApprovalCache(uA, cA).grant("git status")` then
     `.allow("git status")` returns true.
   - T2: ditto, `.allow("git status -s")` returns true (prefix match).
   - T3: ditto, `.allow("git push")` returns false (different prefix).
   - T4: `.revoke()` clears the cache.
   - T5: cross-conversation isolation
     `getBashApprovalCache(uA, cA)` and `(uA, cB)` are independent.
   - T6: cross-user isolation `(uA, c)` and `(uB, c)` are independent.
   - T7: TTL — after `now() + 60min`, allow returns false (stale grant
     auto-expires).
2. GREEN — implement `permission-callback-bash-batch.ts`:
   ```ts
   const _bashAllowlist = new Map<string, { prefix: string; expiresAt: number }>();
   export function getBashApprovalCache(userId: string, conversationId: string) {
     const key = `${userId}:${conversationId}`;
     return {
       allow(command: string) { ... },          // prefix-match + TTL check
       grant(prefix: string) { ... },           // 60min TTL
       revoke() { _bashAllowlist.delete(key); },
     };
   }
   export function deriveBashCommandPrefix(command: string): string { ... }
   ```
3. Wire into `permission-callback.ts` Bash branch.
   **AbortSignal note:** the cache check is synchronous (Map lookup) and
   precedes the gate; no AbortSignal needed for the cache hit. The
   existing `options.signal` (per-tool-use) is still used for the gate
   itself when a cache miss occurs. Do NOT swap to `ctx.controllerSignal`
   — the per-tool-use signal is the right scope (a tool-use can be
   cancelled mid-flight without aborting the whole session).
4. Update `cc-dispatcher.ts realSdkQueryFactory` to inject the cache via
   `ccDeps.bashApprovalCache = getBashApprovalCache(args.userId, args.conversationId)`.
5. Wire revocation into `cleanupCcBashGatesForConversation`.
6. RED → GREEN dispatcher Bash-gate test
   `cc-dispatcher-bash-gate.test.ts` — verify the modal-cliff scenario
   collapses to one prompt for the prefix.

### Phase 6 — `#2923` cc system-prompt parity (RED → GREEN)

1. RED — extend `soleur-go-runner.test.ts`:
   - T1: `buildSoleurGoSystemPrompt({})` (no args) produces the
     pre-existing 5-line baseline (preserves PR #2901 contract).
   - T2: `buildSoleurGoSystemPrompt({ artifactPath: "vision.md" })`
     contains the artifact sentence.
   - T3: `buildSoleurGoSystemPrompt({ activeWorkflow: "work" })` contains
     the sticky-workflow sentence with `/soleur:work`.
   - T4: both args together produce both sentences.
2. GREEN — widen `buildSoleurGoSystemPrompt` signature, thread args
   through `dispatch` → `queryFactory` → `realSdkQueryFactory` →
   `buildSoleurGoSystemPrompt(args)`.
3. Update `QueryFactoryArgs` and `DispatchArgs` interfaces.

### Phase 7 — Whole-suite verification

1. Run the targeted test files:
   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run \
     test/workspace-permission-lock.test.ts \
     test/agent-runner-query-options.test.ts \
     test/agent-runner-byok-migration.test.ts \
     test/cc-dispatcher-real-factory.test.ts \
     test/cc-dispatcher-bash-gate.test.ts \
     test/permission-callback-bash-batch.test.ts \
     test/soleur-go-runner.test.ts \
     test/agent-runner-helpers.test.ts
   ```
2. Run the full app-level suite to detect regressions in adjacent tests:
   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run
   ```
3. Migration verification (dev FIRST, then prd):
   ```bash
   bash plugins/soleur/skills/postmerge/scripts/run-migrations.sh
   ```
   Verified by querying `migrate_api_key_to_v2` directly via Supabase REST.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **#2918:** `withWorkspacePermissionLock` serializes concurrent
      `patchWorkspacePermissions` calls on the same workspace path. Atomic
      `<path>.tmp` → rename. Tests at
      `apps/web-platform/test/workspace-permission-lock.test.ts` pass.
- [x] **#2918:** both call sites (`agent-runner.ts startAgentSession` and
      `cc-dispatcher.ts realSdkQueryFactory`) inherit the lock automatically
      because the lock lives INSIDE `patchWorkspacePermissions`. Verified
      by absence of new lock plumbing at the call sites.
- [x] **#2919:** the v1→v2 migration UPDATE is now an RPC call to
      `migrate_api_key_to_v2`. Concurrent callers serialize via PG row
      locks; second-writer's UPDATE matches `WHERE key_version = 1` with
      zero rows; helper handles `rows_affected = 0` as success.
      `getUserApiKey` AND `getUserServiceTokens` both use the RPC.
- [x] **#2920:** cc-dispatcher's `ccDeps.updateConversationStatus` issues
      a real `supabase.update().eq("id",...).eq("user_id",...)` (R8
      composite-key). Errors flow to `reportSilentFallback` per
      `cq-silent-fallback-must-mirror-to-sentry`.
- [x] **#2921:** `getBashApprovalCache` per-conversation in-memory
      allowlist with 60-min TTL + revoke. `permission-callback.ts`
      consults the cache before issuing the Bash gate, augments the
      options array with `Approve all <prefix>`, calls `grant` on
      selection. Cross-user + cross-conversation isolation verified.
- [x] **#2921:** `cleanupCcBashGatesForConversation` also revokes the
      bash approval cache (no leak across conversation lifecycles).
- [x] **#2922:** `buildAgentQueryOptions(args)` is the single source of
      truth for both call sites. Drift-guard test at
      `agent-runner-helpers.test.ts` asserts shared fields are deep-equal
      between legacy and cc paths.
- [x] **#2923:** `buildSoleurGoSystemPrompt(args?)` injects artifact-path
      and active-workflow sentences when args are provided. Default-args
      call preserves the pre-existing 5-line baseline (contract
      preservation).
- [x] All targeted tests green (`./node_modules/.bin/vitest run` for the
      8 test files listed in Phase 7).
- [x] Full app-level vitest run (`apps/web-platform`) passes.
- [x] PR body contains `Closes #2918`, `Closes #2919`, `Closes #2920`,
      `Closes #2921`, `Closes #2922`, `Closes #2923` (one per line).
- [ ] No version-file edits (`plugin.json`, `marketplace.json`).

### Post-merge (operator)

- [ ] **#2919 migration:** `033_migrate_api_key_to_v2_rpc.sql` applied to
      Supabase **dev** project (`mlwiodleouzwniehynfz.supabase.co`)
      successfully. Verify via Supabase REST (note: SECURITY DEFINER
      function granted only to `service_role` — the call MUST use the
      service-role key, not the anon key):
      ```bash
      doppler run -p soleur -c dev -- bash -c '
        curl -sf "$NEXT_PUBLIC_SUPABASE_URL/rest/v1/rpc/migrate_api_key_to_v2" \
          -X POST \
          -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
          -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
          -H "Content-Type: application/json" \
          -d "{\"p_id\":\"00000000-0000-0000-0000-000000000000\",\"p_user_id\":\"00000000-0000-0000-0000-000000000000\",\"p_provider\":\"anthropic\",\"p_encrypted\":\"x\",\"p_iv\":\"x\",\"p_tag\":\"x\"}"
      '
      ```
      Expected: `[{"rows_affected":0}]` (function exists, signature OK,
      no real row updated by sentinel UUIDs). A 401/403 means the grant
      didn't apply correctly; a 404 means the migration didn't run.
- [ ] **#2919 migration:** same applied to Supabase **prd** project per
      `wg-when-a-pr-includes-database-migrations`.
- [ ] **#2918/#2920/#2921/#2922/#2923:** code-only fixes; no operator
      action beyond the merge.
- [ ] After both Supabase projects show the function, close #2919 with
      a comment linking the deploy run.
- [ ] Stage 6 acceptance gate (cc-soleur-go in prod) is unblocked re:
      #2920 + #2923 — note in the cc-soleur-go follow-up issue (#2853)
      that those gates are now satisfied.

## Test Scenarios

| Scenario | Test file | Issue |
|---|---|---|
| Concurrent `patchWorkspacePermissions` on same workspace serialize | `workspace-permission-lock.test.ts` T1 | #2918 |
| Different workspaces don't false-serialize | `workspace-permission-lock.test.ts` T2 | #2918 |
| Atomic write: rename failure leaves no partial file | `workspace-permission-lock.test.ts` T3 | #2918 |
| Lock releases on `fn` throw | `workspace-permission-lock.test.ts` T4 | #2918 |
| `getUserApiKey` v1 → v2 routes through RPC | `agent-runner-byok-migration.test.ts` T1 | #2919 |
| RPC `rows_affected: 0` → helper returns plaintext (no throw) | `agent-runner-byok-migration.test.ts` T2 | #2919 |
| `getUserServiceTokens` v1 row also routes through RPC | `agent-runner-byok-migration.test.ts` T1b | #2919 |
| AskUserQuestion gate writes `waiting_for_user` then `active` (cc path) | `cc-dispatcher-real-factory.test.ts` T-AC4 | #2920 |
| Status update includes `.eq("user_id", args.userId)` | `cc-dispatcher-real-factory.test.ts` T-AC4c | #2920 |
| Status update error → `reportSilentFallback` | `cc-dispatcher-real-factory.test.ts` T-AC4d | #2920 |
| `git status` granted-as-batch suppresses subsequent gates | `cc-dispatcher-bash-gate.test.ts` | #2921 |
| `git status` grant does NOT auto-allow `git push` | `cc-dispatcher-bash-gate.test.ts` | #2921 |
| Cross-conversation grant isolation | `permission-callback-bash-batch.test.ts` T5 | #2921 |
| Cross-user grant isolation | `permission-callback-bash-batch.test.ts` T6 | #2921 |
| TTL expiry | `permission-callback-bash-batch.test.ts` T7 | #2921 |
| Helper-mediated options identical to legacy literal | `agent-runner-helpers.test.ts` (drift-guard) | #2922 |
| Helper-mediated options identical to cc literal | `agent-runner-helpers.test.ts` (drift-guard) | #2922 |
| Default-args `buildSoleurGoSystemPrompt()` preserves baseline | `soleur-go-runner.test.ts` T1 | #2923 |
| Artifact-path branch injects artifact sentence | `soleur-go-runner.test.ts` T2 | #2923 |
| Active-workflow branch injects sticky-workflow sentence | `soleur-go-runner.test.ts` T3 | #2923 |

## Risks

- **Migration latency (#2919):** Supabase migrations are wrapped in a
  transaction; the function body is short and uses no concurrent-DDL
  constructs. Low risk. Verified by reading sibling migrations 027/032
  (no CONCURRENTLY usage in either).
- **Lock blast radius (#2918):** in-process Map mutex is bounded by the
  number of concurrent cold-Query constructions on the same user
  (currently ≤2: legacy + cc paths). Worst-case wait is the time to
  read+rewrite a small `.claude/settings.json` (single-digit ms). Out of
  scope: multi-process coordination — single Next.js server per
  container; if we ever scale to multiple workers per container, an
  on-disk advisory lock will be needed (V2 issue if Stage 6 capacity
  planning surfaces it).
- **Bash batching false-grant risk (#2921):** prefix-derivation is
  conservative (favors narrow). The first token of an attacker-controlled
  command is itself approved-by-user — the worst case is "user already
  approved `git status` once, agent now runs `git status -s`" which is
  benign. The blocklist (`BLOCKED_BASH_PATTERNS`) STILL APPLIES to every
  Bash command (the cache check happens AFTER the blocklist), so
  `curl|wget|nc|sh -c|eval|sudo` cannot be batched.
- **System-prompt token cost (#2923):** added artifact-path sentence is
  ≤200 chars; sticky-workflow sentence is ≤150 chars. Per-turn token
  delta < 50; well within the cc-router cost budget
  (`DEFAULT_COST_CAPS.default = $2/conversation`).
- **#2922 drift-guard staleness:** if a future PR adds a new field to
  the canonical options object only at one call site, the drift-guard
  fails LOUDLY at test time (assertion mismatch). This is the desired
  behavior — the test exists to prevent silent drift.

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a backend code-quality cleanup PR with no user-facing surface
changes. The cc-soleur-go path stays gated behind `FLAG_CC_SOLEUR_GO=0`
in prod. No CPO/CMO/COO involvement needed. CTO assessment carried
forward from PR #2901 review (the six issues exist because CTO-class
review caught them).

### Engineering (CTO)

**Status:** reviewed (carry-forward from PR #2901 review pipeline)

**Assessment:**

- All six issues meet `code-review` + `deferred-scope-out` labels via the
  PR #2901 review-fix-inline gate; bundling them is the natural next step.
- The fixes share one code area (`apps/web-platform/server/agent-runner.ts`,
  `cc-dispatcher.ts`, `soleur-go-runner.ts`, `permission-callback.ts`) —
  one PR is the right unit of review.
- The migration (#2919) introduces a new Postgres function. Verified
  against migration siblings 025/027/032 — no
  `CREATE INDEX CONCURRENTLY`, no `ALTER SYSTEM`, no other
  non-transactional DDL. Safe inside the migration runner's transaction.
- No new npm dependencies (zero-dep mutex per Research Reconciliation
  table) — `cq-before-pushing-package-json-changes` does not apply.
- The Bash batching surface (#2921) is opt-in via the
  `bashApprovalCache` dep field; the legacy runner does NOT wire it,
  preserving the legacy 2-option Bash gate. cc-soleur-go gets the
  3-option gate. Asymmetry is intentional — legacy already runs
  trusted-prompt domain leaders; cc routes operator natural language.

## Open Code-Review Overlap

X open scope-outs touch these files (all in-scope):

- #2918 (`agent-runner.ts`, `cc-dispatcher.ts`) — fold in
- #2919 (`agent-runner.ts`) — fold in
- #2920 (`cc-dispatcher.ts`) — fold in
- #2921 (`cc-dispatcher.ts`, `permission-callback.ts`) — fold in
- #2922 (`agent-runner.ts`, `cc-dispatcher.ts`, `agent-runner-sandbox-config.ts`) — fold in
- #2923 (`soleur-go-runner.ts`) — fold in

No additional overlap — six issues, one PR, scope discipline maintained.

## Non-Goals / Deferred

- **Multi-process advisory file lock for `#2918`** — only relevant if a
  container ever runs multiple Next.js workers. Not the case today.
  V2 issue if Stage 6 capacity planning needs it.
- **Schema migration to delete `key_version = 1` rows entirely
  (#2919 long-term).** The race only exists while v1 rows exist; once
  all are migrated, the race surface is gone. A backfill migration is
  TRACKED in the issue body's `Re-Eval Trigger` (existing).
- **UX wireframes for the batched-approval surface (#2921 ux-design-lead).**
  The current 3-option gate `["Approve", "Approve all <prefix>", "Reject"]`
  is functional but minimal. A dedicated UX review for the
  cc-soleur-go modal cliff (chat-UI redesign) is tracked separately
  in the cc-soleur-go follow-up backlog (#2853 V2 issues). This PR
  closes the engineering scope-out; UX polish is its own cycle.
- **Routing-accuracy corpus test for `#2923`.** Adding a fixed-corpus
  test that asserts the cc router routes correctly to brainstorm/plan/work
  given typical user inputs requires building the corpus (own design
  pass). The minimal context-injection in this PR is the unblocker for
  Stage 6; the corpus test is a Stage 6.5 item.

## PR Body

```
## Summary

Drains six `code-review` + `deferred-scope-out` issues filed during PR #2901
(Stage 2.12 cc-soleur-go SDK binding) review:

- #2918 — atomic + locked `patchWorkspacePermissions`
- #2919 — v1 → v2 BYOK re-encryption via Postgres RPC (predicate-locked UPDATE)
- #2920 — real `updateConversationStatus` writes from cc-dispatcher
- #2921 — per-session Bash command-prefix batching for /soleur:work
- #2922 — `buildAgentQueryOptions` drift-guard helper for legacy + cc
- #2923 — cc system-prompt context-injection parity (artifact + sticky-workflow)

Stage 6 acceptance gates for #2920 and #2923 are now satisfied. The path
remains gated behind `FLAG_CC_SOLEUR_GO=0` in prod.

Closes #2918
Closes #2919
Closes #2920
Closes #2921
Closes #2922
Closes #2923

## Test plan

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` — all green
- [ ] Migration `033_migrate_api_key_to_v2_rpc.sql` applies clean to dev
- [ ] (Post-merge) Migration applies clean to prd
- [ ] (Post-merge) Verify RPC exists via Supabase REST sentinel call
- [ ] (Post-merge) Close #2919 after prd verification

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## Sharp Edges

- **Migration must apply to dev FIRST.** Per `wg-when-a-pr-includes-database-migrations`,
  the migration cannot ship unverified — but unlike code-only PRs, the
  migration apply happens post-merge for prd. Plan AC splits pre-merge
  vs post-merge accordingly.
- **#2922 drift-guard test** must use a frozen JSON snapshot of the
  canonical options shape. Updating the canonical shape requires an
  explicit snapshot bump in the test — this is the desired loud-failure
  mode (per `cq-mutation-assertions-pin-exact-post-state` analogue).
- **#2920 supabase mock in `cc-dispatcher-real-factory.test.ts`** must
  return a chainable mock (`.from().update().eq().eq()`). The existing
  test mocks `from()` and `select()` chains; extend to `update().eq().eq()`.
- **#2921 cache lifecycle:** the cache MUST be cleared on:
  (a) explicit `cleanupCcBashGatesForConversation` (already in scope),
  (b) container restart (in-memory Map is naturally process-local — no
  action), (c) WS reconnect (V2 — Stage 6 acceptance refines this).
- **#2923 `currentRouting.kind` mapping:** the runner only has
  `currentRouting` at `dispatch` time, not at re-dispatch. Active
  workflow flows through the system prompt only on COLD Query
  construction. Re-dispatched warm Queries don't re-issue the system
  prompt (SDK behavior). Acceptable — the directive is
  routing-influence, not authoritative state.
- **Per #2922, the `agent-runner.ts` change is large** (replacing the
  ~80-line `query({ options: {...} })` literal). Review will see a
  big diff in that file; the helper test must be the load-bearing
  evidence that the shape didn't drift.
- **Per `cq-code-comments-symbol-anchors-not-line-numbers`,** any code
  comments added in this PR must reference symbols
  (`buildAgentQueryOptions`, `withWorkspacePermissionLock`,
  `migrate_api_key_to_v2`) — never line numbers — so future refactors
  don't desync the breadcrumbs.

## Research Insights

### Postgres function patterns (#2919)

**Best practices applied:**

- Single-statement functions use `LANGUAGE sql`, not `plpgsql` — faster planning, no PL/pgSQL overhead. Precedent: `sum_user_mtd_cost` (migration 027).
- `SECURITY DEFINER` for service-role-only functions; explicit `REVOKE FROM PUBLIC, authenticated, anon` + `GRANT TO service_role`. The DEFINER role inherits the function-creator's permissions; without REVOKE, any role with `EXECUTE ON FUNCTION` (default `PUBLIC`) escalates.
- `SET search_path = public` to prevent schema-injection via temp-schema function shadowing (well-known PG hardening pattern).
- `WITH updated AS (... RETURNING 1) SELECT COUNT(*)` is the idiomatic way to return rows-affected from a `LANGUAGE sql` function — `GET DIAGNOSTICS ROW_COUNT` only works in `plpgsql`.

**Edge case handled:**

The second concurrent caller's UPDATE matches `WHERE key_version = 1` with zero rows after the first caller commits. Postgres row-locks serialize the two updates (PG's MVCC + READ COMMITTED default isolation): the second writer sees the post-update row and the predicate fails, producing rows_affected=0. The helper treats this as success — both callers decrypt the same plaintext under the same HKDF key, so even if the second caller's `reEncrypted` ciphertext differs (random IV per call), both are valid valid-decryption inputs for the same plaintext.

### Atomic file write patterns (#2918)

**Durability sequence:** open → write → fdatasync → close → rename.

`fdatasync` (vs `fsync`) flushes data without metadata — sufficient because the rename will create the metadata entry afterward. Skipping the sync risks: machine crash between rename and journal flush leaves a zero-byte file at `<path>` (the new dir entry, but no data blocks committed). On most modern filesystems (ext4 default `data=ordered`) this is unlikely but not guaranteed.

**References:**

- POSIX `rename(2)` atomicity: <https://man7.org/linux/man-pages/man2/rename.2.html> ("If newpath exists, it is atomically replaced.")
- `fdatasync` rationale: <https://lwn.net/Articles/322823/>

### In-process Map mutex pattern (#2918)

**Pattern:** chained-Promise mutex keyed on a string identifier.

```ts
const _locks = new Map<string, Promise<void>>();
export async function withWorkspacePermissionLock<T>(
  key: string,
  fn: () => Promise<T> | T,
): Promise<T> {
  const tail = _locks.get(key) ?? Promise.resolve();
  let release!: () => void;
  const next = new Promise<void>((r) => { release = r; });
  _locks.set(key, tail.then(() => next));
  try {
    await tail;
    return await fn();
  } finally {
    release();
    // Garbage-collect: only delete if we're still the tail
    if (_locks.get(key) === tail.then(() => next)) {
      _locks.delete(key);
    }
  }
}
```

Zero deps, ≈25 LoC, deterministic FIFO ordering. Limit: in-process only — multi-worker would need OS file lock or DB advisory lock. Out of scope per Risks §.

### Bash command-prefix derivation (#2921)

**Conservative grammar:**

| Token form | Prefix |
|---|---|
| `git status` / `git diff` / `git log` | `git <verb>` (2 tokens) |
| `npm run lint` / `npm run test` / `npm run build` | `npm run <script>` (3 tokens) |
| `bun test` / `bun run <script>` | `bun <verb>` (2 tokens) or `bun run <script>` (3 tokens) |
| `npx tsc --noEmit` / `npx vitest run` | `npx <tool>` (2 tokens) |
| `ls` / `pwd` / `cat <file>` | first token only |

The first token is always the binary name (post-blocklist filter). `git <verb>` widening is intentional — a /soleur:work session typically fires `git status`, `git diff`, `git log`, `git show`, `git rev-parse` and the user clicking "Approve all `git`" is reasonable. We DO NOT widen to plain `git` (one token) because `git push` should NOT be batched with read-only verbs.

**Test fixture for `/soleur:work` ≤3-prompt AC:**

A small-repo /soleur:work run typically fires (in order):
1. `git status` — first prompt; user picks "Approve all `git status`".
2. `bun test` (from a learning-path) — second prompt; user picks "Approve all `bun test`".
3. `npx tsc --noEmit` — third prompt.

Subsequent `git status -s`, `git diff HEAD~1`, etc., hit the cache (zero gates).

### TypeScript SDK Options shape (#2922)

The cc path passes `mcpServers: {}` and the legacy path passes `{ soleur_platform: ... }` (when platform tools register) or omits it. The drift-guard test asserts the *presence* of `mcpServers` on both, but accepts any value — the field shape is "optional record". Same applies to `allowedTools` (legacy: array; cc: omitted/empty). The shared invariant is:

```ts
{ cwd, model, permissionMode, settingSources, includePartialMessages,
  disallowedTools, sandbox, plugins,
  hooks: { PreToolUse: [{ matcher: <regex>, hooks: [<sandbox-hook>] }], ... },
  canUseTool: <function>,
  // legacy adds: maxTurns, maxBudgetUsd, allowedTools, mcpServers (optional)
  // cc adds: mcpServers: {} explicitly, no maxTurns/maxBudgetUsd
}
```

The drift-guard asserts the SHARED keys produce identical values for the same `workspacePath`/`pluginPath` inputs, ignoring the divergent keys. Fields that legitimately differ (per-call overrides) are NOT asserted.

## Citations

- Issues: #2918, #2919, #2920, #2921, #2922, #2923 (all open, verified
  via `gh issue view --json state` 2026-04-27).
- Origin PR #2901 (`feat(stage-2-12): real SDK query factory binding`)
  — merged; review-fix-inline filed all six scope-outs.
- Sandbox-config drift-guard precedent:
  `apps/web-platform/server/agent-runner-sandbox-config.ts`,
  `apps/web-platform/test/agent-runner-helpers.test.ts`.
- Composite-key invariant R8: `apps/web-platform/server/cc-dispatcher.ts`
  (`makeCcBashGateKey`, `resolveCcBashGate`).
- AGENTS.md rules consulted:
  - `wg-when-a-pr-includes-database-migrations` — dev-then-prd order
  - `wg-use-closes-n-in-pr-body-not-title-to` — PR body Closes
  - `cq-silent-fallback-must-mirror-to-sentry` — error mirroring
  - `cq-code-comments-symbol-anchors-not-line-numbers` — comment style
  - `cq-mutation-assertions-pin-exact-post-state` — assertion patterns
  - `rf-review-finding-default-fix-inline` — drives the bundling decision
