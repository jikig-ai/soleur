/**
 * BYOK lease — `AsyncLocalStorage`-scoped plaintext-key handler for the
 * server-side agentic runtime (PR-B #3244 §1.4).
 *
 * Contract:
 *   - `runWithByokLease({ workspaceContextUserId, keyOwnerUserId }, fn)`
 *     opens an ALS scope, lazy-decrypts the `keyOwnerUserId`'s BYOK
 *     Anthropic key on first `lease.getApiKey()` call, and `zeroize`s
 *     the buffer in `finally` (success OR throw). The lease exposes
 *     both userIds as sync properties for downstream cost-writers.
 *   - `lease.getApiKey()` is a function (NOT a property accessor) per
 *     type-design F3. A captured-and-leaked lease reference outside the
 *     ALS scope throws `ByokLeaseError {cause: "escape"}` — the load-
 *     bearing test that catches the silent-leak class.
 *   - `getCurrentByokLease()` reads the active lease from the ALS
 *     context. Returns `null` outside any scope; never throws.
 *
 * Phase 3 (feat-team-workspace-multi-user) split — the lease accepts
 * TWO userIds:
 *   - `keyOwnerUserId`: whose `api_keys` row to read + HKDF context
 *     (per learning 2026-03-20-hkdf-salt-info-parameter-semantics).
 *   - `workspaceContextUserId`: the userId whose workspace the agent
 *     is acting upon. Threads into `audit_byok_use.workspace_id` via
 *     `persistTurnCost`. Under the N2 invariant (migration 053 §1.1.7),
 *     this also serves as the `workspaces.id` for backfilled solo +
 *     legacy workspaces; new post-backfill workspaces resolve via
 *     `workspace-resolver` at the call site.
 *
 * Resolution A (#3363) shape: the lease reads `api_keys` via the
 * tenant-scoped Supabase client (`getFreshTenantClient`) so RLS
 * isolates the row to the key owner's own data. `decryptKey` returns a
 * Buffer (PR-B §1.4.2 refactor); the buffer lives in the ALS slot and
 * is wiped in `finally`. The string conversion happens at
 * `getApiKey()` for SDK consumption — that intern surface is
 * documented in §3.6 ADR.
 *
 * Subprocess env-leak handling (CWE-526): see plan §1.5.7 and #3244.
 * The Anthropic Claude Agent SDK spawns a CLI subprocess that reads
 * `ANTHROPIC_API_KEY` from env. The lease itself does NOT mitigate
 * subprocess env exposure — kernel-level `prctl(PR_SET_DUMPABLE, 0)`
 * + bubblewrap `--proc/--tmpfs` are the load-bearing defenses, added
 * in §1.5. This module bounds the in-process Soleur-heap window only.
 */

import { AsyncLocalStorage } from "node:async_hooks";
import { createHash } from "node:crypto";

import * as Sentry from "@sentry/nextjs";

import { decryptKey, decryptKeyLegacy, zeroize } from "./byok";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("byok-lease");

export type UserId = string;

export interface ByokLeaseArgs {
  /**
   * The userId whose workspace the agent is acting upon. Used to tag
   * `audit_byok_use.workspace_id` so workspace co-members see this turn
   * in `workspace_cost_aggregate`. Under the N2 invariant this also
   * serves as the workspace_id (workspaces.id === owner_user_id for
   * backfilled solo workspaces; see migration 053 §1.1.7).
   */
  workspaceContextUserId: UserId;
  /**
   * The userId whose `api_keys` row is read + HKDF-derived for
   * decryption. For solo this equals workspaceContextUserId; for
   * future team workspaces this is the caller (per-member BYOK),
   * not the workspace owner.
   */
  keyOwnerUserId: UserId;
  /**
   * BYOK Delegations PR-A (#4232). Optional delegation row id when the
   * lease is acting on behalf of a grantor. When set, the cost-writer
   * routes to `check_and_record_byok_delegation_use` (cap + audit RPC)
   * instead of `write_byok_audit`, and audit rows attribute the cost
   * to `grantor_user_id` (or to the caller with
   * `attribution_shift_reason` on post-grace/expired paths). When
   * undefined, solo behavior is preserved bit-for-bit.
   */
  delegationId?: string;
}

/**
 * BYOK-domain error class. Distinct from `RuntimeAuthError` (auth) and
 * `RlsDenyError` (data) per plan §1.6 / type-design F4.
 *
 * Causes:
 *   - "fetch_failed": api_keys row read failed (DB error, RLS deny).
 *     Distinct from MissingByokKeyError — see below.
 *   - "decrypt_failed": ciphertext-to-plaintext conversion failed (auth tag
 *     mismatch, wrong user-derived key, etc.).
 *   - "escape": lease accessed outside its ALS scope (capture-and-leak
 *     pattern caught by the function-not-property contract).
 */
export class ByokLeaseError extends Error {
  public readonly cause: "fetch_failed" | "decrypt_failed" | "escape";

  constructor(
    cause: "fetch_failed" | "decrypt_failed" | "escape",
    message: string,
  ) {
    super(message);
    this.name = "ByokLeaseError";
    this.cause = cause;
  }
}

/**
 * Phase 3.2 (AC-D) — raised when the `keyOwnerUserId` has no
 * `api_keys` row at all (NOT an RLS deny or DB error). Triggers the
 * fail-closed UI path: dashboard banner "Configure your BYOK key to
 * run agents in this workspace" linking to /dashboard/settings/byok.
 * NEVER falls back to another user's key — the `byok_delegations`
 * table (#4232) is the future opt-in remediation.
 *
 * Kieran N4: catch-site emits an info-level Sentry breadcrumb with
 * `workspaceContextUserId` + `keyOwnerUserIdHash` (sha256:16) but
 * NEVER the raw `keyOwnerUserId` or key prefix.
 */
export class MissingByokKeyError extends Error {
  public readonly workspaceContextUserId: UserId;
  public readonly keyOwnerUserIdHash: string;

  constructor(workspaceContextUserId: UserId, keyOwnerUserId: UserId) {
    super("BYOK key not configured for this user");
    this.name = "MissingByokKeyError";
    this.workspaceContextUserId = workspaceContextUserId;
    this.keyOwnerUserIdHash = hashUserId(keyOwnerUserId);
  }
}

function hashUserId(userId: UserId): string {
  // 16-hex-char prefix of sha256: ~64 bits of entropy — plenty for
  // breadcrumb correlation, zero PII surface.
  return createHash("sha256").update(userId).digest("hex").slice(0, 16);
}

/**
 * Kieran N4: emit an info-level Sentry breadcrumb on every
 * `MissingByokKeyError` encounter. Captures `workspaceContextUserId`
 * and `keyOwnerUserIdHash` (sha256:16). NEVER the raw `keyOwnerUserId`
 * or any key prefix. Safe to call from any catch site.
 *
 * Per-feature errorClass `byok-lease:missing-key` so the AGENTS.md
 * silent-fallback registry stays disjoint.
 */
export function reportMissingByokKey(err: MissingByokKeyError): void {
  log.warn(
    {
      err,
      workspaceContextUserId: err.workspaceContextUserId,
      keyOwnerUserIdHash: err.keyOwnerUserIdHash,
    },
    "BYOK key not configured for user (fail-closed)",
  );

  try {
    if (typeof Sentry.addBreadcrumb === "function") {
      Sentry.addBreadcrumb({
        category: "byok",
        type: "info",
        level: "info",
        message: "MissingByokKeyError",
        data: {
          workspaceContextUserId: err.workspaceContextUserId,
          keyOwnerUserIdHash: err.keyOwnerUserIdHash,
        },
      });
    }
  } catch {
    // Sentry may be partially shimmed in non-prod bundles; pino is the
    // durable signal. Mirrors the try/catch pattern in
    // `server/observability.ts`'s `reportSilentFallback`.
  }
}

/**
 * Map a `ByokLeaseError.cause` to the WS `errorCode` the client uses to
 * trigger the BYOK-key-prompt UX. Returns `"key_invalid"` for the two
 * causes that legitimately mean "the founder's key on file is unusable"
 * (`fetch_failed` / `decrypt_failed`); returns `undefined` for `"escape"`
 * because that is a server-side capture-leak bug, not a key-invalid signal.
 *
 * Per `cq-union-widening-grep-three-patterns`: the exhaustive `switch` +
 * `: never` rail makes a future `cause` widening (e.g., `"expired"` for
 * #3363) a TS build break here rather than a silent fall-through to
 * `undefined` at every call site.
 */
export function mapByokLeaseCauseToErrorCode(
  cause: ByokLeaseError["cause"],
): "key_invalid" | undefined {
  switch (cause) {
    case "fetch_failed":
    case "decrypt_failed":
      return "key_invalid";
    case "escape":
      return undefined;
    default: {
      const _exhaustive: never = cause;
      return _exhaustive;
    }
  }
}

export interface ByokLease {
  /** The userId whose workspace this lease is acting upon (Phase 3). */
  readonly workspaceContextUserId: UserId;
  /** The userId whose `api_keys` row backs this lease (Phase 3). */
  readonly keyOwnerUserId: UserId;
  /**
   * BYOK Delegations PR-A (#4232). Present when the lease is funded by
   * an active delegation row; consumed by cost-writer to route the
   * audit RPC and attach `delegation_id` to the WORM audit row.
   */
  readonly delegationId?: string;
  /**
   * Return the plaintext API key as a string. Lazy-decrypts on first
   * call; subsequent calls within the same scope return the cached
   * plaintext.
   *
   * @throws {ByokLeaseError} cause="escape" if called outside the
   *   originating ALS scope (captured-reference leak).
   * @throws {ByokLeaseError} cause="fetch_failed" if the api_keys row
   *   read errored (DB error / RLS deny).
   * @throws {MissingByokKeyError} if the `keyOwnerUserId` has NO
   *   api_keys row (fail-closed; AC-D).
   * @throws {ByokLeaseError} cause="decrypt_failed" if AES-GCM auth
   *   verification failed.
   */
  getApiKey(): string | Promise<string>;
}

interface LeaseSlot {
  workspaceContextUserId: UserId;
  keyOwnerUserId: UserId;
  /** Lazy plaintext buffer — populated on first getApiKey call. */
  apiKeyBuffer: Buffer | null;
  /** Set false on scope exit. Lease.getApiKey() checks this. */
  alive: boolean;
  /** BYOK Delegations PR-A (#4232). Threaded through to ByokLease. */
  delegationId?: string;
}

const als = new AsyncLocalStorage<LeaseSlot>();

/**
 * Build a `ByokLease` whose `getApiKey()` resolves the plaintext from
 * the slot stored in ALS.
 *
 * Escape detection: each call to `getApiKey()` re-reads the current ALS
 * context and verifies it is the same slot the lease was bound to. A
 * captured reference outside the original scope sees a different (or
 * `undefined`) ALS context and throws.
 */
function makeLease(slot: LeaseSlot): ByokLease {
  return {
    workspaceContextUserId: slot.workspaceContextUserId,
    keyOwnerUserId: slot.keyOwnerUserId,
    delegationId: slot.delegationId,
    getApiKey(): string | Promise<string> {
      // Synchronous escape check (per type-design F3 — escape must be a
      // sync throw so `expect(() => lease.getApiKey()).toThrow(...)`
      // catches it; an async-only check would surface as Promise
      // rejection only).
      const current = als.getStore();
      if (!current || current !== slot || !slot.alive) {
        throw new ByokLeaseError(
          "escape",
          "Authentication unavailable; retry shortly",
        );
      }

      // Cache hit — return synchronously to keep hot-path callers
      // off the microtask queue.
      if (slot.apiKeyBuffer) {
        return slot.apiKeyBuffer.toString("utf8");
      }

      // Lazy fetch + decrypt — async path, callers must `await`.
      return fetchAndDecryptIntoSlot(slot);
    },
  };
}

async function fetchAndDecryptIntoSlot(slot: LeaseSlot): Promise<string> {
  const tenant = await getFreshTenantClient(slot.keyOwnerUserId);
  const { data, error } = await tenant
    .from("api_keys")
    .select("encrypted_key, iv, auth_tag, key_version")
    .eq("user_id", slot.keyOwnerUserId)
    .eq("provider", "anthropic")
    .eq("is_valid", true)
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new ByokLeaseError(
      "fetch_failed",
      "Authentication unavailable; retry shortly",
    );
  }
  if (!data) {
    // Phase 3.2 AC-D: legitimate "no key on file" — distinct from a DB
    // error. Triggers the configure-banner UI path, not the key-prompt.
    throw new MissingByokKeyError(
      slot.workspaceContextUserId,
      slot.keyOwnerUserId,
    );
  }

  let buf: Buffer;
  try {
    const encrypted = Buffer.from(data.encrypted_key, "base64");
    const iv = Buffer.from(data.iv, "base64");
    const tag = Buffer.from(data.auth_tag, "base64");
    buf =
      data.key_version === 1
        ? decryptKeyLegacy(encrypted, iv, tag)
        : decryptKey(encrypted, iv, tag, slot.keyOwnerUserId);
  } catch (_err) {
    throw new ByokLeaseError(
      "decrypt_failed",
      "Authentication unavailable; retry shortly",
    );
  }

  // Re-check liveness after the await chain — a parallel scope-end
  // could have flipped `alive` between fetch and here.
  if (!slot.alive || als.getStore() !== slot) {
    zeroize(buf);
    throw new ByokLeaseError(
      "escape",
      "Authentication unavailable; retry shortly",
    );
  }

  slot.apiKeyBuffer = buf;
  return buf.toString("utf8");
}

/**
 * Open an ALS scope and run `fn` with a freshly bound `ByokLease`.
 *
 * Lifecycle:
 *   1. Allocate `LeaseSlot { apiKeyBuffer: null, alive: true,
 *      workspaceContextUserId, keyOwnerUserId }`.
 *   2. Run `fn(lease)` inside `als.run(slot, ...)`.
 *   3. On `finally`: zeroize the buffer (if allocated), null the slot
 *      reference, set `alive = false`. Subsequent escaped-reference
 *      calls throw `ByokLeaseError { cause: "escape" }`.
 *
 * Errors thrown by `fn` propagate after the cleanup runs.
 */
export async function runWithByokLease<T>(
  args: ByokLeaseArgs,
  fn: (lease: ByokLease) => Promise<T>,
): Promise<T> {
  const slot: LeaseSlot = {
    workspaceContextUserId: args.workspaceContextUserId,
    keyOwnerUserId: args.keyOwnerUserId,
    delegationId: args.delegationId,
    apiKeyBuffer: null,
    alive: true,
  };

  try {
    return await als.run(slot, async () => {
      const lease = makeLease(slot);
      return fn(lease);
    });
  } finally {
    if (slot.apiKeyBuffer) zeroize(slot.apiKeyBuffer);
    slot.apiKeyBuffer = null;
    slot.alive = false;
  }
}

/**
 * Get the active BYOK lease for the current async context, or `null`
 * outside any scope. Does not throw.
 *
 * The returned lease's `getApiKey()` performs the same escape check as
 * the one passed to `fn`, so capturing the return value and using it
 * later is safe within the same scope and unsafe outside it (per the
 * function-not-property contract).
 */
export function getCurrentByokLease(): ByokLease | null {
  const slot = als.getStore();
  if (!slot || !slot.alive) return null;
  return makeLease(slot);
}
