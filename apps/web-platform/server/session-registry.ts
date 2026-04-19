import type { ClientSession } from "./ws-handler";

// Module-level Map so modules that need the count (/health, session-metrics)
// don't have to import the full ws-handler graph (Supabase client, Sentry,
// agent-runner) just to read `.size`. ws-handler re-exports this same Map.
export const sessions = new Map<string, ClientSession>();
