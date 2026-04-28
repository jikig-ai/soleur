---
date: 2026-04-27
title: Predicate-locked migration RPCs, atomic-write mutex, and drift-guard via canonical builder — six-issue cc/soleur-go cleanup
tags: [security, race-conditions, supabase-rpc, search-path-pinning, atomic-write, drift-guard, bash-approval, esbuild, regex, silent-fallback]
issues: [2918, 2919, 2920, 2921, 2922, 2923, 2954]
related-learnings:
  - 2026-03-18-stop-hook-toctou-race-fix.md
  - 2026-03-20-websocket-first-message-auth-toctou-race.md
  - 2026-04-15-gh-jq-does-not-forward-arg-to-jq.md
  - 2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md
---

# Predicate-Locked Migration RPCs, Atomic-Write Mutex, and Drift-Guard via Canonical Builder

PR #2954 closed six issues in one cleanup pass against the cc-dispatcher / soleur-go-runner / agent-runner stack. Several of the fixes share a deeper insight: **the right shape for "concurrent-safe one-shot mutation" is a predicate-locked UPDATE**, not an application-level lock — and HKDF-determinism on derived keys (not on AES-GCM ciphertext, which is IV-randomized per call) is what makes the lost-race caller's plaintext correct.

## Problem

Six concurrent issues in the agent-runner / cc-dispatcher / soleur-go layer:

- **#2918** Workspace-permission state file had a TOCTOU window: two concurrent `acquireWorkspacePermissions` calls could both observe "not yet granted", both ask, and the second writer could clobber the first writer's grant — and a partially-written JSON file could be observed by readers.
- **#2919** BYOK v1→v2 key-version migration ran client-side: two concurrent decrypt-then-re-encrypt-then-update flows would race the final UPDATE, with the loser silently overwriting the winner's ciphertext using the loser's IV. Worse, the UPDATE used `WHERE id = ...` (no version predicate), so the loser's stale view of `key_version = 1` was never re-checked.
- **#2920** `cc-dispatcher` advanced the conversation state machine but never wrote the corresponding row to `conversations.status` on each gate cycle, so the UI showed stale state until the next user-action write.
- **#2921** The Bash-approval `permission-callback` matched commands literally — every `git status`, `git diff`, `gh pr view` re-prompted, producing a UX cliff for batched agent runs.
- **#2922** `buildAgentQueryOptions` was duplicated between `agent-runner.ts` and `soleur-go-runner.ts`; the two copies drifted on `temperature`, `top_p`, and tool-list ordering.
- **#2923** `soleur-go-runner` system prompt was missing the artifact-context and active-workflow blocks that `agent-runner` injects, so cc-launched agents had degraded grounding vs. CLI agents.

## Solution

**#2918 — Workspace-permission lock + atomic write.** New `apps/web-platform/server/workspace-permission-lock.ts` exposes a Map-of-Promise mutex keyed by `${userId}:${workspaceId}`. Inside the critical section, the writer does open(O_WRONLY|O_CREAT|O_TRUNC) → write(JSON) → **`fdatasync`** → close → `rename(tmp, final)`. Both `fdatasync` (durability before rename) and the rename-into-place (atomic visibility) are load-bearing — readers see either the prior version or the new version, never a half-written file. The Map mutex serializes within a single Node process; the rename serializes across processes.

**#2919 — Predicate-locked v1→v2 RPC.** New migration `033_migrate_api_key_to_v2_rpc.sql` defines:

```sql
CREATE OR REPLACE FUNCTION public.migrate_api_key_to_v2(...)
RETURNS TABLE (rows_affected integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH updated AS (
    UPDATE public.api_keys
       SET encrypted_key = ..., iv = ..., auth_tag = ..., key_version = 2, ...
     WHERE id = ... AND user_id = ... AND provider = ...
       AND key_version = 1 AND is_valid = true
     RETURNING 1
  )
  SELECT COUNT(*)::INTEGER FROM updated;
$$;
```

Under PG read-committed, the second concurrent caller's UPDATE blocks on the row lock, then re-evaluates the WHERE clause after the first writer commits. `key_version = 1` no longer matches → zero rows updated → no-op. `RETURNS TABLE (rows_affected integer)` lets the application detect the lost-race and skip its own write path. The HKDF key-derivation is deterministic on the source-of-truth key, so the lost-race caller's plaintext re-encrypts correctly even though its ciphertext (which is what gets written) is discarded — the AES-GCM IV is randomized per call, so two callers' ciphertexts on the same plaintext differ; that doesn't matter because only one writes.

**#2920 — Status-write on gate cycle.** Each transition in cc-dispatcher now writes `{ conversation_id, status, updated_at }` to `conversations` so the UI's polling/realtime view reflects state in O(seconds) instead of O(next user message).

**#2921 — Prefix-vocabulary cache.** New `permission-callback-bash-batch.ts` keeps a per-conversation cache keyed by `(conversationId, prefix)` where prefix is the first whitespace-separated token (`git`, `gh`, `npm`, etc.). On approval, the prefix is cached with a TTL; future commands with the same prefix in the same conversation skip the prompt. The composite key keeps the existing blocklist precedence intact (blocklist matches by full command pattern, not prefix).

**#2922 — Canonical builder + drift-guard test.** Both runners now import a single `buildAgentQueryOptions(...)` from `apps/web-platform/server/agent-runner-query-options.ts`. A snapshot test pins the shape via `JSON.stringify(opts, Object.keys(opts).sort())` so any drift in field set or ordering fails the test, not production.

**#2923 — System-prompt parity.** `soleur-go-runner.ts` now invokes the same artifact-context + active-workflow injection helpers as `agent-runner.ts`, so cc-launched agents see the same grounding blocks as CLI agents.

## Key Insight

**Predicate-locked UPDATE is the correct shape for migration RPCs.** When the application-side flow is "read state, derive new state from a deterministic function of the read state, write new state", a SECURITY DEFINER `LANGUAGE sql` function with a predicate matching the pre-migration state on the WHERE clause turns a race into a no-op:

1. **Concurrency is correct under read-committed.** The second writer blocks on the row lock, then re-evaluates the WHERE after the first commits. The predicate fails. Zero rows updated. The application sees `rows_affected = 0` and skips its own follow-up writes.
2. **HKDF determinism on the key (not the ciphertext) is what makes the lost caller's plaintext correct.** The lost caller derived the same DEK from the same KEK input, so its plaintext is the canonical plaintext. AES-GCM ciphertext varies per call due to random IV — that's the variant that gets discarded, and that's fine.
3. **Defense in depth: search_path = public, pg_temp.** Listing `public` first defends against an attacker planting a same-named relation in `pg_temp` (their session-private schema) which a SECURITY DEFINER body would otherwise resolve before `public.api_keys`. The fully-qualified `public.api_keys` in the body is belt-and-suspenders.
4. **Application-level mutex + atomic write is the file-system analog.** For state on disk (workspace permissions), the same pattern applies: serialize within process via Map-of-Promise, serialize across process via fsync+rename — the in-memory mutex is fast, the rename is the load-bearing cross-process barrier.

The drift-guard pattern (#2922) is the same shape applied to cross-file invariants: extract the canonical thing, snapshot-test the shape, fail on drift.

## Session Errors

1. **`gh ... --jq` expression syntax error — escape-style quoting rejected.** Recovered by piping `gh ... --json | jq -r '...'` (jq run as a separate process). **Prevention:** existing learning `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` already covers this — `gh --jq` does not forward the expression to jq verbatim, it parses it through Go template syntax. Pipe to `jq` directly when you need real jq features (`select(...)`, `@sh`, alternation).

2. **Plan-spec drift on RPC permissioning (INVOKER vs DEFINER).** Initial plan said `SECURITY INVOKER`, which would have run the migration RPC under the caller's role and (a) failed because `authenticated` lacks UPDATE on `api_keys`, and (b) bypassed the row-lock semantics that make the predicate-lock approach race-safe. Deepen-plan corrected via precedent migration 027 (`sum_user_mtd_cost`). **Prevention:** filed compound: route-to-definition issue (below) for `soleur:plan` to add a "diff against sibling-precedent migrations/files" gate to deepen-plan when the plan prescribes RPC permissioning, atomic-write sequences, or other pattern-bound behaviors.

3. **Plan-spec gap: missing `fdatasync` in atomic-write sequence.** Initial plan said open → write → close → rename. Without `fdatasync` between write and close, a process crash post-rename but pre-fsync leaves the new pathname pointing at zero-length data on filesystems that decouple metadata-journal commit from data block flush (ext4 default `data=ordered` mostly mitigates this for renames, but not universally — and `fdatasync` is the documented contract). Deepen-plan added it. **Prevention:** same compound: route-to-definition issue covers the precedent-diff requirement during deepen-plan.

4. **Review surfaced P1: `search_path = public` lacks `pg_temp`.** The new migration 033 originally pinned `SET search_path = public`. Reviewer flagged that this leaves the SECURITY DEFINER body vulnerable to `pg_temp.<table>` shadowing — an authenticated attacker can create their own `pg_temp.api_keys` and the unqualified relation reference would resolve there. Fixed both 033 and the precedent migration 027 (which had the same gap) per `wg-when-fixing-a-workflow-gates-detection`. **Prevention:** new AGENTS.md rule (Code Quality section, applied this commit): SECURITY DEFINER functions MUST pin `SET search_path = public, pg_temp`, with the explicit `public` prefix on every relation in the body as belt-and-suspenders.

5. **Wrong cryptographic claim in code comment** ("deterministic re-encryption"). The migration's correctness rests on HKDF determinism on key derivation, not on AES-GCM ciphertext determinism — AES-GCM ciphertext varies per call due to random IV, by design. Comment was misleading and would have confused future readers (and security reviewers). Reviewer caught and corrected to "deterministic key derivation; ciphertext varies per call due to random IV". **Prevention:** learning file (this file) — discoverability via code review is sufficient; no AGENTS.md rule needed for "don't write incorrect crypto comments" (would not generalize).

6. **U+2028/U+2029 literals in regex source rejected by esbuild.** A regex source containing the literal Unicode line-separator characters (U+2028, U+2029) was rejected at build time with `unterminated regular expression` — esbuild and other JS parsers treat those as line terminators inside regex source even though the language spec allows them inside string literals. Recovered by using `  ` escape sequences. **Prevention:** learning file — discoverability via build error is immediate and unambiguous; the fix is well-documented and a one-time learning. No AGENTS.md rule needed.

7. **RPC errors silently discarded** at 2 call sites: `await supabase().rpc(...)` whose `{ data, error }` result was destructured to `data` only, dropping `error`. Caught at review. **Prevention:** existing rule `cq-silent-fallback-must-mirror-to-sentry` already covers this class — Supabase RPC errors that lead to a 4xx/5xx return or fallback continuation must be mirrored via `reportSilentFallback`. Filed an issue (below) to clarify the existing rule with an explicit Supabase-RPC example, since the current wording is generic and wasn't catching this in pre-merge review.

## Prevention

- **AGENTS.md rule added (this commit):** `cq-pg-security-definer-search-path-pin-pg-temp` — Postgres `SECURITY DEFINER` functions MUST pin `SET search_path = public, pg_temp` (in that order) and qualify every relation reference with `public.` in the body. The `pg_temp` element defends against attacker-planted shadow relations; the `public.` prefix is belt-and-suspenders.
- **Issues filed (this commit):**
  - `compound: route-to-definition proposal for plan` — add a deepen-plan Phase-N gate that diffs the plan's prescribed pattern (RPC permissioning, atomic-write sequence, lock acquisition) against any sibling-precedent file (e.g., migration 027 for migration 033). Closes the gap that produced session errors #2 and #3.
  - `compound: route-to-definition proposal for cq-silent-fallback-must-mirror-to-sentry` — clarify the existing rule with an explicit Supabase-RPC example: `await supabase().rpc(...)` results MUST destructure both `{ data, error }` and pass non-null `error` through `reportSilentFallback` per the existing rule.
- **Learning-only (no rule):** session errors #1 (already-existing rule), #5 (non-generalizable), #6 (clear build error makes it discoverable).

## Tags

`security`, `race-conditions`, `supabase-rpc`, `search-path-pinning`, `atomic-write`, `fdatasync`, `drift-guard`, `bash-approval-batching`, `esbuild`, `regex`, `silent-fallback`, `hkdf`, `aes-gcm`, `predicate-locked-update`, `mutex-pattern`
