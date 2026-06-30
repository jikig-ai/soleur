import type { ClientSession } from "./ws-handler";

// Module-level Map so modules that need the count (/health, session-metrics)
// don't have to import the full ws-handler graph (Supabase client, Sentry,
// agent-runner) just to read `.size`. ws-handler re-exports this same Map.
//
// Holds the live WebSocket — host-local by definition (epic #5274). The
// disconnect-grace owning-host guard (ws-handler `runDisconnectGraceAbort`,
// ADR-068 §5) reads this to detect a same-host reconnect before aborting.
export const sessions = new Map<string, ClientSession>();
