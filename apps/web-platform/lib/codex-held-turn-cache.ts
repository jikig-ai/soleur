import type { createClient } from "@/lib/supabase/client";
import type { ChatMessage } from "@/lib/chat-state-machine";
import { reportSilentFallback } from "@/lib/client-observability";

export type HeldCodexTurn = {
  clientTurnId: string;
  conversationId: string;
  authModeGeneration: number;
  noticeNonce: string;
  authMode?: "api-key" | "managed";
  message: Extract<ChatMessage, { type: "text" }>;
};

// Browser-memory drafts only: no transcript, credential, storage, or network
// persistence. Bounds apply to the entire tab, not each mounted chat surface.
const MAX_TURNS = 32;
const MAX_BYTES = 256 * 1024;
const TTL_MS = 30 * 60 * 1000;
const turns = new Map<string, { turn: HeldCodexTurn; bytes: number; expiresAt: number }>();
const invalidationListeners = new Set<() => void>();
type ExpiryEvent = Readonly<{ scopeEpoch: number; conversationId: string; clientTurnId: string }>;
const expiryListeners = new Set<(event: ExpiryEvent) => void>();
let activeScope: string | null = null;
let activeScopeEpoch = 0;
let scopeTransition = false;
let transitionCancelled = false;
let watchingAuth = false;
let expiryTimer: ReturnType<typeof setTimeout> | null = null;

function reportListenerFailure(op: string) {
  try { reportSilentFallback(new Error("Held draft notification failed"), { feature: "codex-history-transfer", op }); }
  catch { /* Notification and cleanup must continue even if telemetry fails. */ }
}

/** Decoding identifies a candidate only; acceptToken is called after auth_ok. */
function tokenScope(token: string): string | null {
  try {
    const payload = token.split(".")[1];
    if (!payload || payload.length > 16384) return null;
    const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    const { sub, app_metadata: metadata } = claims;
    const workspaceId = metadata?.current_workspace_id;
    const orgId = metadata?.current_organization_id ?? null;
    if (typeof sub !== "string" || !sub || typeof workspaceId !== "string" || !workspaceId
      || (orgId !== null && (typeof orgId !== "string" || !orgId))) return null;
    return JSON.stringify([sub, workspaceId, orgId]);
  } catch {
    return null; // Missing/invalid scope disables cross-mount restoration.
  }
}

function prune() {
  const expired: ExpiryEvent[] = [];
  for (const [key, entry] of turns) {
    if (entry.expiresAt <= Date.now()) {
      turns.delete(key);
      expired.push(Object.freeze({ scopeEpoch: activeScopeEpoch, conversationId: entry.turn.conversationId, clientTurnId: entry.turn.clientTurnId }));
    }
  }
  for (const event of expired) for (const listener of [...expiryListeners]) {
    try { listener(event); }
    catch { reportListenerFailure("expiry-notification"); }
  }
}

function scheduleExpiry() {
  if (expiryTimer !== null) clearTimeout(expiryTimer);
  expiryTimer = null;
  if (turns.size === 0) return;
  const earliest = Math.min(...[...turns.values()].map((entry) => entry.expiresAt));
  // Browser suspension or timer throttling can delay cleanup; this timer is
  // best-effort and does not prove secure deletion of other in-memory copies.
  expiryTimer = setTimeout(() => {
    expiryTimer = null;
    prune();
    scheduleExpiry();
  }, Math.max(0, earliest - Date.now()));
  if (typeof expiryTimer === "object") expiryTimer.unref?.();
}

function invalidateScope() {
  turns.clear();
  scheduleExpiry();
  activeScope = null;
  activeScopeEpoch += 1;
  for (const listener of [...invalidationListeners]) {
    try { listener(); }
    catch { reportListenerFailure("scope-invalidation"); }
  }
}

function clear() {
  if (scopeTransition) {
    transitionCancelled = true;
    turns.clear();
    activeScope = null;
    scheduleExpiry();
    return;
  }
  scopeTransition = true;
  transitionCancelled = false;
  try { invalidateScope(); }
  finally { scopeTransition = false; }
}

function acceptToken(token: string): string | null {
  if (scopeTransition) { transitionCancelled = true; return null; }
  scopeTransition = true;
  transitionCancelled = false;
  try {
    const scope = tokenScope(token);
    if (scope !== activeScope) invalidateScope();
    if (transitionCancelled) { invalidateScope(); return null; }
    activeScope = scope;
    return scope;
  } finally { scopeTransition = false; }
}

export const codexHeldTurnCache = {
  clear,
  subscribe(listener: () => void) {
    invalidationListeners.add(listener);
    return () => { invalidationListeners.delete(listener); };
  },
  subscribeExpiry(listener: (event: ExpiryEvent) => void) {
    expiryListeners.add(listener);
    return () => { expiryListeners.delete(listener); };
  },
  scopeEpoch(scope: string | null): number | null {
    return scope && scope === activeScope ? activeScopeEpoch : null;
  },
  observeAuth(auth: ReturnType<typeof createClient>["auth"]) {
    if (watchingAuth) return;
    watchingAuth = true;
    // This single observer outlives chat mounts, so logout while all panels
    // are closed still erases their drafts. Reload naturally drops the cache.
    auth.onAuthStateChange((event, session) => {
      if (scopeTransition) { clear(); return; }
      if (event === "SIGNED_OUT" || (activeScope !== null && tokenScope(session?.access_token ?? "") !== activeScope)) clear();
    });
  },
  acceptToken,
  put(scope: string | null, turn: HeldCodexTurn): boolean {
    if (!scope || scope !== activeScope) return false;
    const epoch = activeScopeEpoch;
    prune();
    if (scope !== activeScope || epoch !== activeScopeEpoch) return false;
    const key = JSON.stringify([turn.conversationId, turn.clientTurnId]);
    const snapshot = structuredClone({ ...turn, message: { ...turn.message, delivery: "unsent" as const } });
    const bytes = new TextEncoder().encode(JSON.stringify(snapshot)).length;
    const used = [...turns.values()].reduce((total, entry) => total + entry.bytes, 0) - (turns.get(key)?.bytes ?? 0);
    if (turns.get(key)?.turn.message.delivery === "unresolved") return false;
    if ((!turns.has(key) && turns.size >= MAX_TURNS) || used + bytes > MAX_BYTES) return false;
    const expiresAt = turns.get(key)?.expiresAt ?? Date.now() + TTL_MS;
    turns.set(key, { turn: snapshot, bytes, expiresAt });
    scheduleExpiry();
    return true;
  },
  get(scope: string | null, conversationId: string): HeldCodexTurn[] {
    if (!scope || scope !== activeScope) return [];
    const epoch = activeScopeEpoch;
    prune();
    if (scope !== activeScope || epoch !== activeScopeEpoch) return [];
    return [...turns.values()].filter(({ turn }) => turn.conversationId === conversationId).map(({ turn }) => structuredClone(turn));
  },
  markUnresolved(scope: string | null, conversationId: string, clientTurnId: string): HeldCodexTurn | null {
    if (!scope || scope !== activeScope) return null;
    const epoch = activeScopeEpoch;
    prune();
    if (scope !== activeScope || epoch !== activeScopeEpoch) return null;
    const key = JSON.stringify([conversationId, clientTurnId]);
    const entry = turns.get(key);
    if (!entry || entry.turn.message.delivery === "unresolved") return null;
    const turn = structuredClone({ ...entry.turn, message: { ...entry.turn.message, delivery: "unresolved" as const } });
    const bytes = new TextEncoder().encode(JSON.stringify(turn)).length;
    const used = [...turns.values()].reduce((total, item) => total + item.bytes, 0) - entry.bytes;
    if (used + bytes > MAX_BYTES) return null;
    turns.set(key, { ...entry, turn, bytes });
    return structuredClone(turn);
  },
  setNoticeNonce(scope: string | null, conversationId: string, authModeGeneration: number, noticeNonce: string) {
    if (!scope || scope !== activeScope) return;
    const epoch = activeScopeEpoch;
    prune();
    if (scope !== activeScope || epoch !== activeScopeEpoch) return;
    scheduleExpiry();
    for (const [key, entry] of turns) {
      if (entry.turn.conversationId !== conversationId || entry.turn.authModeGeneration !== authModeGeneration) continue;
      const turn = { ...entry.turn, noticeNonce };
      turns.set(key, { ...entry, turn, bytes: new TextEncoder().encode(JSON.stringify(turn)).length });
    }
  },
  remove(scope: string | null, conversationId: string, clientTurnId: string) {
    if (scope && scope === activeScope) {
      turns.delete(JSON.stringify([conversationId, clientTurnId]));
      scheduleExpiry();
    }
  },
};
