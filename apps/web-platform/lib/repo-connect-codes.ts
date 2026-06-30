// feat-repo-connect-block-offer-join — single source of truth for the repo-connect
// 409 outcome codes. The PRODUCER (server/repo-connect-guard.ts + the
// app/api/repo/setup route that passes the guard's `code` through) and the CONSUMER
// (components/connect-repo/failed-state.tsx ERROR_COPY keys) both import from here,
// so a rename on either side is a tsc error rather than a silent ERROR_COPY miss that
// renders the generic "Project Setup Failed" copy. This module is isomorphic (plain
// string constants, no server-only imports) so the "use client" failed-state can import it.
//
// CROSS-CHANNEL NOTE: `workspace_switch_required` is ALSO emitted by the WS dispatch
// path (server/cc-dispatcher.ts) with a DIFFERENT payload shape — `{ errorCode,
// switchToWorkspaceId }` over the WebSocket vs this HTTP-409 `{ code, existingWorkspaceId }`.
// They are distinct transport contracts for the same concept; do NOT assume the
// payloads are interchangeable. If/when an agent (Concierge/MCP) connect-flow entry
// point is added, unify the two contracts (and expose an agent-callable switch
// primitive — the switch ACTION currently lives only in the React component).
export const REPO_CONNECT_BLOCKED_CODE = "repo_connect_blocked" as const;
export const WORKSPACE_SWITCH_REQUIRED_CODE = "workspace_switch_required" as const;
