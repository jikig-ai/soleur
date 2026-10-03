import type { createClient } from "@/lib/supabase/client";
import type { ChatMessage } from "@/lib/chat-state-machine";

export type HeldCodexTurn = {
  clientTurnId: string;
  conversationId: string;
  authModeGeneration: number;
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
let activeScope: string | null = null;
let watchingAuth = false;

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
  for (const [key, entry] of turns) if (entry.expiresAt <= Date.now()) turns.delete(key);
}

function clear() {
  turns.clear();
  activeScope = null;
  for (const listener of invalidationListeners) listener();
}

export const codexHeldTurnCache = {
  clear,
  subscribe(listener: () => void) {
    invalidationListeners.add(listener);
    return () => { invalidationListeners.delete(listener); };
  },
  observeAuth(auth: ReturnType<typeof createClient>["auth"]) {
    if (watchingAuth) return;
    watchingAuth = true;
    // This single observer outlives chat mounts, so logout while all panels
    // are closed still erases their drafts. Reload naturally drops the cache.
    auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_OUT" || (activeScope !== null && tokenScope(session?.access_token ?? "") !== activeScope)) clear();
    });
  },
  acceptToken(token: string): string | null {
    const scope = tokenScope(token);
    if (scope !== activeScope) clear();
    activeScope = scope;
    return scope;
  },
  put(scope: string | null, turn: HeldCodexTurn): boolean {
    if (!scope || scope !== activeScope) return false;
    prune();
    const key = JSON.stringify([turn.conversationId, turn.clientTurnId]);
    const bytes = new TextEncoder().encode(JSON.stringify(turn)).length;
    const used = [...turns.values()].reduce((total, entry) => total + entry.bytes, 0) - (turns.get(key)?.bytes ?? 0);
    if ((!turns.has(key) && turns.size >= MAX_TURNS) || used + bytes > MAX_BYTES) return false;
    turns.set(key, { turn: { ...turn, message: { ...turn.message, delivery: "unsent" } }, bytes, expiresAt: Date.now() + TTL_MS });
    return true;
  },
  get(scope: string | null, conversationId: string): HeldCodexTurn[] {
    if (!scope || scope !== activeScope) return [];
    prune();
    return [...turns.values()].filter(({ turn }) => turn.conversationId === conversationId).map(({ turn }) => ({ ...turn, message: { ...turn.message, delivery: "unsent" } }));
  },
  remove(scope: string | null, conversationId: string, clientTurnId: string) {
    if (scope && scope === activeScope) turns.delete(JSON.stringify([conversationId, clientTurnId]));
  },
};
