// Non-routable internal leader id reserved for the cc-soleur-go path's
// audit-log attribution and UI presentation as the "Soleur Concierge".
//
// Lives in `@/lib/*` (client-safe) so client components can import it
// without dragging the server-only dependencies of `@/server/cc-dispatcher`
// (pino logger, Supabase service client, fs/promises) into the browser
// bundle. The server-side authoritative copy is re-exported from
// `cc-dispatcher.ts` — this module is the source of truth and cc-dispatcher
// re-exports for backwards compatibility.
export const CC_ROUTER_LEADER_ID = "cc_router" as const;
