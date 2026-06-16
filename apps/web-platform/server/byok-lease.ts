/**
 * BYOK lease — `AsyncLocalStorage`-scoped plaintext-key handler for the
 * server-side agentic runtime (PR-B #3244 §1.4).
 *
 * Contract:
 *   - `runWithByokLease({ workspaceContextUserId, keyOwnerUserId }, fn)`
 *     opens an ALS scope, lazy-decrypts the `keyOwnerUserId`'s BYOK
 *     credential on first `lease.getRestApiKey()` /
 *     `lease.getAgentCredential()` call, and `zeroize`s the buffer(s) in
 *     `finally` (success OR throw). The lease exposes both userIds as sync
 *     properties for downstream cost-writers.
 *   - Two-row-by-provider model (feat-operator-cc-oauth): `getRestApiKey()`
 *     reads ONLY `provider='anthropic'` (raw-REST consumers, cannot return
 *     an oauth token by construction); `getAgentCredential()` prefers
 *     `provider='anthropic_oauth'` (gated) and returns `{ value, scheme }`.
 *   - The accessors are functions (NOT property accessors) per type-design
 *     F3. A captured-and-leaked lease reference outside the ALS scope
 *     throws `ByokLeaseError {cause: "escape"}` — the load-bearing test
 *     that catches the silent-leak class.
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
 * is wiped in `finally`. The string conversion happens at the accessor
 * (`getRestApiKey` / `getAgentCredential`) for SDK consumption — that
 * intern surface is documented in §3.6 ADR.
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
import type { AgentAuthScheme, AgentCredential } from "./agent-env";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("byok-lease");

export type UserId = string;

/**
 * feat-operator-cc-oauth — a SPENT date gate. It was gated to a predicted
 * 2026-06-15 Anthropic policy transition that Anthropic PAUSED (2026-06-16);
 * the date no longer corresponds to any policy change. The `oauth_token` path
 * still fails closed before this instant, but since the date has passed the
 * gate is a historical fail-closed artifact — the LIVE load-bearing gates are
 * the `CC_OAUTH_ENABLED` kill-switch + owner-only routing
 * (`OauthDelegationForbiddenError`). Legal basis: tolerated / metered
 * subscription use, owner-only no-share enforced in code, operator-borne
 * risk-acceptance. Full record (incl. the article text):
 * knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md. Retained as
 * the gate's single source of truth (the lease test derives its before/after
 * boundaries from it).
 */
export const CC_OAUTH_EFFECTIVE_DATE = Date.parse("2026-06-15T00:00:00Z");

/**
 * Kill-switch (plan §Phase 6.2). When unset/falsey the oauth read is never
 * attempted — the lease behaves exactly as the api_key-only path did, so
 * the whole feature is inert (AC8). Instant disable without a Flagsmith
 * round-trip. Read at call time so a deploy-time env flip takes effect on
 * the next lease without a process restart contract.
 */
function isCcOauthEnabled(): boolean {
  const v = process.env.CC_OAUTH_ENABLED;
  return v === "1" || v === "true";
}

/**
 * Raised when an `anthropic_oauth` credential is selected before
 * `CC_OAUTH_EFFECTIVE_DATE`. Fail-closed (the run does NOT silently fall back
 * to the api_key). The gated date is now spent (it has passed — see the
 * `CC_OAUTH_EFFECTIVE_DATE` note above), so this guard is historically inert,
 * but it is retained fail-closed rather than removed. Operator-only surface
 * (only the operator can hold an oauth row).
 */
export class OauthNotYetPermittedError extends Error {
  constructor() {
    // Date derived from the single-source constant so the message can never
    // drift from the gate it describes.
    super(
      `Claude Code subscription auth is not permitted before ${new Date(
        CC_OAUTH_EFFECTIVE_DATE,
      )
        .toISOString()
        .slice(0, 10)}`,
    );
    this.name = "OauthNotYetPermittedError";
  }
}

/**
 * The surviving load-bearing guardrail. Raised when an `anthropic_oauth`
 * credential would fund a run it does not own (delegated lease, or keyOwner ≠
 * workspace context). Enforces Anthropic's per-user / no-pooling / no-share
 * constraint — the real risk axis the "tolerated, owner-only" basis rests on.
 * The subscription token may fund ONLY its owner's own runs. Fail-closed.
 */
export class OauthDelegationForbiddenError extends Error {
  constructor() {
    super(
      "Claude Code subscription token may only fund its owner's own runs",
    );
    this.name = "OauthDelegationForbiddenError";
  }
}

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
  public readonly cause:
    | "fetch_failed"
    | "decrypt_failed"
    | "escape"
    | "subscription_limit";

  constructor(
    cause:
      | "fetch_failed"
      | "decrypt_failed"
      | "escape"
      | "subscription_limit",
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
): "key_invalid" | "subscription_limit" | undefined {
  switch (cause) {
    case "fetch_failed":
    case "decrypt_failed":
      return "key_invalid";
    case "subscription_limit":
      // feat-operator-cc-oauth FR5 — credit/rate-limit exhaustion on a
      // subscription (oauth_token) run is distinct from key_invalid so the
      // UI renders "subscription limit reached" copy, not a re-paste prompt.
      // NO PRODUCER YET: nothing constructs ByokLeaseError{cause:
      // "subscription_limit"} today — the SDK credit-signal classifier lands
      // in Phase 5 (plan §Phase 5, "defer to first real hit"). The
      // cause→code→WS→UI render path is pre-wired so that hit needs no
      // type/render change.
      return "subscription_limit";
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
   * Raw-REST plaintext API key. Queries ONLY `provider='anthropic'`, so it
   * is STRUCTURALLY incapable of returning an `oauth_token` (that secret
   * lives in a row this query never reads) — the oauth→`x-api-key` leak is
   * impossible by construction (plan § Deepen-Plan Resolution). Use from
   * every raw-REST consumer (`new Anthropic({apiKey})`, `x-api-key` fetch).
   * Lazy-decrypts on first call; cached for the scope.
   *
   * @throws {ByokLeaseError} cause="escape" if called outside the
   *   originating ALS scope (captured-reference leak).
   * @throws {ByokLeaseError} cause="fetch_failed" if the api_keys row
   *   read errored (DB error / RLS deny).
   * @throws {MissingByokKeyError} if the `keyOwnerUserId` has NO
   *   `provider='anthropic'` api_keys row (fail-closed; AC-D).
   * @throws {ByokLeaseError} cause="decrypt_failed" if AES-GCM auth
   *   verification failed.
   */
  getRestApiKey(): string | Promise<string>;
  /**
   * Agent-SDK credential. Prefers `provider='anthropic_oauth'` (the
   * subscription token) when the kill-switch is on; falls back to
   * `provider='anthropic'`. Returns `{ value, scheme }` so `buildAgentEnv`
   * injects exactly one auth var. The date (CLO G1), owner (CLO G2), and
   * kill-switch (AC8) gates fire ONLY on the oauth read.
   *
   * @throws {OauthNotYetPermittedError} if an oauth row is selected before
   *   `CC_OAUTH_EFFECTIVE_DATE` (fail-closed; no silent api_key fallback).
   * @throws {OauthDelegationForbiddenError} if an oauth row would fund a
   *   delegated / non-owner run (fail-closed).
   * @throws {ByokLeaseError} / {MissingByokKeyError} as `getRestApiKey`.
   */
  getAgentCredential(): AgentCredential | Promise<AgentCredential>;
}

interface LeaseSlot {
  workspaceContextUserId: UserId;
  keyOwnerUserId: UserId;
  /** Lazy plaintext for `provider='anthropic'` (raw-REST). */
  restApiKeyBuffer: Buffer | null;
  /** Lazy plaintext for the Agent-SDK credential (oauth or anthropic fallback). */
  agentCredentialBuffer: Buffer | null;
  /** Scheme of the cached agent credential; null until first resolution. */
  agentCredentialScheme: AgentAuthScheme | null;
  /** Set false on scope exit. Both accessors check this. */
  alive: boolean;
  /** BYOK Delegations PR-A (#4232). Threaded through to ByokLease. */
  delegationId?: string;
}

interface EncryptedRow {
  encrypted_key: string;
  iv: string;
  auth_tag: string;
  key_version: number;
}

const als = new AsyncLocalStorage<LeaseSlot>();

/**
 * Build a `ByokLease` whose accessors (`getRestApiKey` /
 * `getAgentCredential`) resolve the plaintext from the slot stored in ALS.
 *
 * Escape detection: each accessor call re-reads the current ALS
 * context and verifies it is the same slot the lease was bound to. A
 * captured reference outside the original scope sees a different (or
 * `undefined`) ALS context and throws.
 */
/**
 * Synchronous escape check (per type-design F3 — escape must be a sync
 * throw so `expect(() => lease.getRestApiKey()).toThrow(...)` catches it;
 * an async-only check would surface as a Promise rejection only).
 */
function assertLeaseAlive(slot: LeaseSlot): void {
  const current = als.getStore();
  if (!current || current !== slot || !slot.alive) {
    throw new ByokLeaseError(
      "escape",
      "Authentication unavailable; retry shortly",
    );
  }
}

function makeLease(slot: LeaseSlot): ByokLease {
  return {
    workspaceContextUserId: slot.workspaceContextUserId,
    keyOwnerUserId: slot.keyOwnerUserId,
    delegationId: slot.delegationId,
    getRestApiKey(): string | Promise<string> {
      assertLeaseAlive(slot);
      // Cache hit — return synchronously to keep hot-path callers off the
      // microtask queue.
      if (slot.restApiKeyBuffer) {
        return slot.restApiKeyBuffer.toString("utf8");
      }
      return fetchRestApiKeyIntoSlot(slot);
    },
    getAgentCredential(): AgentCredential | Promise<AgentCredential> {
      assertLeaseAlive(slot);
      if (slot.agentCredentialBuffer && slot.agentCredentialScheme) {
        return {
          value: slot.agentCredentialBuffer.toString("utf8"),
          scheme: slot.agentCredentialScheme,
        };
      }
      return fetchAgentCredentialIntoSlot(slot);
    },
  };
}

/**
 * Read the `is_valid` row for a single provider via the tenant-scoped
 * client. Returns `null` when no row exists (caller decides whether that is
 * a fail-closed MissingByokKeyError or a fall-through to another provider).
 */
async function fetchProviderRow(
  slot: LeaseSlot,
  provider: "anthropic" | "anthropic_oauth",
): Promise<EncryptedRow | null> {
  const tenant = await getFreshTenantClient(slot.keyOwnerUserId);
  const { data, error } = await tenant
    .from("api_keys")
    .select("encrypted_key, iv, auth_tag, key_version")
    .eq("user_id", slot.keyOwnerUserId)
    .eq("provider", provider)
    .eq("is_valid", true)
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new ByokLeaseError(
      "fetch_failed",
      "Authentication unavailable; retry shortly",
    );
  }
  return (data as EncryptedRow | null) ?? null;
}

/** Decrypt a fetched row into a plaintext Buffer (cause=decrypt_failed on auth-tag mismatch). */
function decryptRow(row: EncryptedRow, keyOwnerUserId: UserId): Buffer {
  try {
    const encrypted = Buffer.from(row.encrypted_key, "base64");
    const iv = Buffer.from(row.iv, "base64");
    const tag = Buffer.from(row.auth_tag, "base64");
    return row.key_version === 1
      ? decryptKeyLegacy(encrypted, iv, tag)
      : decryptKey(encrypted, iv, tag, keyOwnerUserId);
  } catch (_err) {
    throw new ByokLeaseError(
      "decrypt_failed",
      "Authentication unavailable; retry shortly",
    );
  }
}

/**
 * Re-check liveness after the fetch/decrypt await chain — a parallel
 * scope-end could have flipped `alive` between fetch and here. Zeroizes the
 * just-decrypted buffer before throwing so it never lingers.
 */
function assertAliveAfterDecrypt(slot: LeaseSlot, buf: Buffer): void {
  if (!slot.alive || als.getStore() !== slot) {
    zeroize(buf);
    throw new ByokLeaseError(
      "escape",
      "Authentication unavailable; retry shortly",
    );
  }
}

async function fetchRestApiKeyIntoSlot(slot: LeaseSlot): Promise<string> {
  const row = await fetchProviderRow(slot, "anthropic");
  if (!row) {
    // Phase 3.2 AC-D: legitimate "no key on file" — distinct from a DB
    // error. Triggers the configure-banner UI path, not the key-prompt.
    throw new MissingByokKeyError(
      slot.workspaceContextUserId,
      slot.keyOwnerUserId,
    );
  }
  const buf = decryptRow(row, slot.keyOwnerUserId);
  assertAliveAfterDecrypt(slot, buf);
  slot.restApiKeyBuffer = buf;
  return buf.toString("utf8");
}

async function fetchAgentCredentialIntoSlot(
  slot: LeaseSlot,
): Promise<AgentCredential> {
  // Prefer the subscription oauth token — but ONLY attempt the read when the
  // kill-switch is on, so a disabled feature behaves bit-for-bit like the
  // api_key-only path (AC8).
  if (isCcOauthEnabled()) {
    const oauthRow = await fetchProviderRow(slot, "anthropic_oauth");
    if (oauthRow) {
      // ---- Gates fire ONLY on the oauth read (plan §Phase 2.3) ----
      // CLO G1 — spent date gate. Fail-closed; NEVER silently fall back to the
      // api_key. (The gated date has passed; retained fail-closed, not removed.)
      if (Date.now() < CC_OAUTH_EFFECTIVE_DATE) {
        throw new OauthNotYetPermittedError();
      }
      // CLO G2 — owner-only routing. A delegated lease or a keyOwner that
      // differs from the workspace context is a cross-owner run.
      if (
        slot.delegationId != null ||
        slot.keyOwnerUserId !== slot.workspaceContextUserId
      ) {
        throw new OauthDelegationForbiddenError();
      }
      const buf = decryptRow(oauthRow, slot.keyOwnerUserId);
      assertAliveAfterDecrypt(slot, buf);
      slot.agentCredentialBuffer = buf;
      slot.agentCredentialScheme = "oauth_token";
      return { value: buf.toString("utf8"), scheme: "oauth_token" };
    }
  }

  // Fall back to the raw-REST api_key (scheme=api_key).
  const apiRow = await fetchProviderRow(slot, "anthropic");
  if (!apiRow) {
    throw new MissingByokKeyError(
      slot.workspaceContextUserId,
      slot.keyOwnerUserId,
    );
  }
  const buf = decryptRow(apiRow, slot.keyOwnerUserId);
  assertAliveAfterDecrypt(slot, buf);
  slot.agentCredentialBuffer = buf;
  slot.agentCredentialScheme = "api_key";
  return { value: buf.toString("utf8"), scheme: "api_key" };
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
    restApiKeyBuffer: null,
    agentCredentialBuffer: null,
    agentCredentialScheme: null,
    alive: true,
  };

  try {
    return await als.run(slot, async () => {
      const lease = makeLease(slot);
      return fn(lease);
    });
  } finally {
    if (slot.restApiKeyBuffer) zeroize(slot.restApiKeyBuffer);
    if (slot.agentCredentialBuffer) zeroize(slot.agentCredentialBuffer);
    slot.restApiKeyBuffer = null;
    slot.agentCredentialBuffer = null;
    slot.agentCredentialScheme = null;
    slot.alive = false;
  }
}

/**
 * Get the active BYOK lease for the current async context, or `null`
 * outside any scope. Does not throw.
 *
 * The returned lease's accessors perform the same escape check as
 * the one passed to `fn`, so capturing the return value and using it
 * later is safe within the same scope and unsafe outside it (per the
 * function-not-property contract).
 */
export function getCurrentByokLease(): ByokLease | null {
  const slot = als.getStore();
  if (!slot || !slot.alive) return null;
  return makeLease(slot);
}
