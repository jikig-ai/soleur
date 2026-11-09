// proxy-hello.ts — the signed session-relay hello (#12289, ADR-323). Leaf module: node:crypto only.
//
// Wire format (proxying host → owner, first frame on the private-net wss leg):
//   {type:"proxy_hello", userId, workspaceId, ts, nonce, mac}
//   mac = HMAC-SHA256(key, "soleur-proxy-hello-v1\n" + userId + "\n" + workspaceId + "\n" + ts + "\n" + nonce)
// `ts` is Unix SECONDS as a decimal string, `nonce` 32 lowercase hex, `mac` 64 lowercase hex, both ids
// strict lowercase UUIDs. The key is a dedicated secret (PROXY_HELLO_HMAC_KEY), distinct from the TLS key.
//
// One canonical-string builder serves the sender and the verifier (no second copy to drift). The
// verifier is fail-closed on EVERY input and checks, in this order, the cheapest unauthenticated gates
// first: size → shape → MAC (constant time) → ts skew → replay. Only a hello that passed all of them
// reaches the caller's AP-2 membership lookup. A rejection reveals nothing to the peer: the caller maps
// every reason to the same close reason.

import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const HELLO_DOMAIN = "soleur-proxy-hello-v1";
/** Hard cap on the first frame, checked on the raw Buffer length before any string conversion. */
export const HELLO_MAX_BYTES = 1024;
/** Accepted clock difference, in seconds, in either direction. */
export const SKEW_S = 30;
/** Maximum live replay-cache entries; a full cache refuses rather than evicts. */
export const REPLAY_MAX = 4096;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TS_RE = /^[1-9][0-9]{9}$/; // 10 digits, no leading-zero aliases of one instant; valid until 2286
const NONCE_RE = /^[0-9a-f]{32}$/;
const MAC_RE = /^[0-9a-f]{64}$/;
const HELLO_KEYS = ["type", "userId", "workspaceId", "ts", "nonce", "mac"] as const;

type HelloRejection = "size" | "shape" | "mac" | "skew" | "replay" | "full";
type VerifyResult = { ok: true; userId: string; workspaceId: string } | { ok: false; reason: HelloRejection };

export function isCanonicalUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

/** The exact byte string the MAC covers. */
export function buildHelloMacInput(userId: string, workspaceId: string, ts: string, nonce: string): string {
  return HELLO_DOMAIN + "\n" + userId + "\n" + workspaceId + "\n" + ts + "\n" + nonce;
}

function computeMac(key: Buffer, userId: string, workspaceId: string, ts: string, nonce: string): Buffer {
  return createHmac("sha256", key).update(buildHelloMacInput(userId, workspaceId, ts, nonce)).digest();
}

/** Sign a hello for `userId`/`workspaceId`. Throws on a non-canonical id (the caller closes the client). */
export function signProxyHello(
  key: Buffer,
  userId: string,
  workspaceId: string,
  opts: { now?: () => number; nonce?: string } = {},
): string {
  if (!isCanonicalUuid(userId) || !isCanonicalUuid(workspaceId)) {
    throw new Error("proxy hello ids must be canonical lowercase UUIDs");
  }
  const ts = String(Math.floor((opts.now ?? Date.now)() / 1000));
  const nonce = opts.nonce ?? randomBytes(16).toString("hex");
  const mac = computeMac(key, userId, workspaceId, ts, nonce).toString("hex");
  return JSON.stringify({ type: "proxy_hello", userId, workspaceId, ts, nonce, mac });
}

export interface ReplayCache {
  /** Live entries after dropping the expired ones. */
  size(): number;
  /** Insert `nonce` (valid until `expiryS`, Unix seconds) unless it is live (`replay`) or the cache is full (`full`). */
  checkAndInsert(nonce: string, expiryS: number, nowS: number): "ok" | "replay" | "full";
}

export function createReplayCache(opts: { max?: number } = {}): ReplayCache {
  const max = opts.max ?? REPLAY_MAX;
  const entries = new Map<string, number>(); // nonce → expiry (Unix seconds)
  const purge = (nowS: number) => {
    for (const [n, exp] of entries) if (exp <= nowS) entries.delete(n);
  };
  return {
    size: () => entries.size,
    checkAndInsert(nonce, expiryS, nowS) {
      purge(nowS);
      if (entries.has(nonce)) return "replay";
      if (entries.size >= max) return "full";
      entries.set(nonce, expiryS);
      return "ok";
    },
  };
}

function toBuffer(data: unknown): Buffer | null {
  if (Buffer.isBuffer(data)) return data;
  if (Array.isArray(data)) return data.every(Buffer.isBuffer) ? Buffer.concat(data as Buffer[]) : null;
  if (data instanceof ArrayBuffer) return Buffer.from(data);
  return null;
}

/**
 * Verify the owner-side first frame. `data`/`isBinary` are the `ws` "message" arguments, `key` the loaded
 * hello key, `now` the owner's clock in ms (injected in tests; production passes Date.now).
 */
export function verifyProxyHello(
  data: unknown,
  isBinary: boolean,
  key: Buffer,
  cache: ReplayCache,
  now: () => number = Date.now,
): VerifyResult {
  const raw = toBuffer(data);
  if (!raw) return { ok: false, reason: "shape" };
  if (raw.length > HELLO_MAX_BYTES) return { ok: false, reason: "size" };
  if (isBinary) return { ok: false, reason: "shape" };

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.toString("utf8"));
  } catch {
    return { ok: false, reason: "shape" };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return { ok: false, reason: "shape" };
  const own = Object.keys(parsed as object);
  if (own.length !== HELLO_KEYS.length || !HELLO_KEYS.every((k) => own.includes(k))) return { ok: false, reason: "shape" };
  const h = parsed as Record<string, unknown>;
  if (h.type !== "proxy_hello") return { ok: false, reason: "shape" };
  const { userId, workspaceId, ts, nonce, mac } = h;
  if (
    !isCanonicalUuid(userId) ||
    !isCanonicalUuid(workspaceId) ||
    typeof ts !== "string" ||
    !TS_RE.test(ts) ||
    typeof nonce !== "string" ||
    !NONCE_RE.test(nonce) ||
    typeof mac !== "string" ||
    !MAC_RE.test(mac)
  ) {
    return { ok: false, reason: "shape" };
  }

  const expected = computeMac(key, userId, workspaceId, ts, nonce);
  if (!timingSafeEqual(Buffer.from(mac, "hex"), expected)) return { ok: false, reason: "mac" };

  const nowS = Math.floor(now() / 1000);
  const tsS = Number(ts);
  if (Math.abs(nowS - tsS) > SKEW_S) return { ok: false, reason: "skew" };

  // Each entry lives exactly as long as that hello could still pass the skew check (ts + SKEW_S), so the
  // cache can neither outlive nor undercut the skew window; the expiry is derived from `ts`, not receipt.
  const verdict = cache.checkAndInsert(nonce, tsS + SKEW_S + 1, nowS);
  if (verdict !== "ok") return { ok: false, reason: verdict };
  return { ok: true, userId, workspaceId };
}
