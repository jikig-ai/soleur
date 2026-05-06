/**
 * BYOK lease — `AsyncLocalStorage`-scoped plaintext-key handler for the
 * server-side agentic runtime (PR-B #3244 §1.4).
 *
 * Contract:
 *   - `runWithByokLease(userId, fn)` opens an ALS scope, lazy-decrypts
 *     the founder's BYOK Anthropic key on first `lease.getApiKey()`
 *     call, and `zeroize`s the buffer in `finally` (success OR throw).
 *   - `lease.getApiKey()` is a function (NOT a property accessor) per
 *     type-design F3. A captured-and-leaked lease reference outside the
 *     ALS scope throws `ByokLeaseError {cause: "escape"}` — the load-
 *     bearing test that catches the silent-leak class.
 *   - `getCurrentByokLease()` reads the active lease from the ALS
 *     context. Returns `null` outside any scope; never throws.
 *
 * Resolution A (#3363) shape: the lease reads `api_keys` via the
 * tenant-scoped Supabase client (`getFreshTenantClient`) so RLS
 * isolates the row to the founder's own data. `decryptKey` returns a
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

import { decryptKey, decryptKeyLegacy, zeroize } from "./byok";
import { getFreshTenantClient } from "@/lib/supabase/tenant";

export type UserId = string;

/**
 * BYOK-domain error class. Distinct from `RuntimeAuthError` (auth) and
 * `RlsDenyError` (data) per plan §1.6 / type-design F4.
 *
 * Causes:
 *   - "fetch_failed": api_keys row read failed (DB error, RLS deny, missing row).
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

export interface ByokLease {
  /**
   * Return the plaintext API key as a string. Lazy-decrypts on first
   * call; subsequent calls within the same scope return the cached
   * plaintext.
   *
   * @throws {ByokLeaseError} cause="escape" if called outside the
   *   originating ALS scope (captured-reference leak).
   * @throws {ByokLeaseError} cause="fetch_failed" if the api_keys row
   *   could not be read.
   * @throws {ByokLeaseError} cause="decrypt_failed" if AES-GCM auth
   *   verification failed.
   */
  getApiKey(): string | Promise<string>;
}

interface LeaseSlot {
  userId: UserId;
  /** Lazy plaintext buffer — populated on first getApiKey call. */
  apiKeyBuffer: Buffer | null;
  /** Set false on scope exit. Lease.getApiKey() checks this. */
  alive: boolean;
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
  const tenant = await getFreshTenantClient(slot.userId);
  const { data, error } = await tenant
    .from("api_keys")
    .select("encrypted_key, iv, auth_tag, key_version")
    .eq("user_id", slot.userId)
    .eq("provider", "anthropic")
    .eq("is_valid", true)
    .limit(1)
    .single();

  if (error || !data) {
    throw new ByokLeaseError(
      "fetch_failed",
      "Authentication unavailable; retry shortly",
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
        : decryptKey(encrypted, iv, tag, slot.userId);
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
 *   1. Allocate `LeaseSlot { apiKeyBuffer: null, alive: true, userId }`.
 *   2. Run `fn(lease)` inside `als.run(slot, ...)`.
 *   3. On `finally`: zeroize the buffer (if allocated), null the slot
 *      reference, set `alive = false`. Subsequent escaped-reference
 *      calls throw `ByokLeaseError { cause: "escape" }`.
 *
 * Errors thrown by `fn` propagate after the cleanup runs.
 */
export async function runWithByokLease<T>(
  userId: UserId,
  fn: (lease: ByokLease) => Promise<T>,
): Promise<T> {
  const slot: LeaseSlot = {
    userId,
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
