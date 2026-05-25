// In-process MCP tool: `auth_revocation_status` (#4440 follow-up to #4418).
//
// Wraps the founder-readable `getMyRevocationStatus(userId)` helper as an
// MCP tool so an agent in an authenticated session can self-diagnose
// revocation rather than getting an opaque `RuntimeAuthError`.
//
// The helper is fail-open by construction (returns null on RPC error,
// mirroring to Sentry inside `getMyRevocationStatus`). This wrapper
// preserves that semantic: null is a valid response.
//
// Discriminator for callers:
//   { revoked: true,  deniedAt, reason } → session JWT is on the deny-list
//   { revoked: false, deniedAt: null, reason: null } → not revoked
//   null → status check failed (transient — retry or assume not revoked)
//
// Factored out of `agent-runner.ts` following the `kb-share-tools.ts` /
// `conversations-tools.ts` precedent so the handler has a single call site
// and unit tests can exercise it via the
// `_setRevocationStatusTenantFnForTest` seam from PR #4418.

import { tool } from "@anthropic-ai/claude-agent-sdk";
import { getMyRevocationStatus } from "@/lib/supabase/tenant";

interface BuildAuthStatusToolsOpts {
  /** Captured in closure — prevents cross-user lookups. */
  userId: string;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

function textResponse(payload: unknown): ToolTextResponse {
  return {
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
}

export function buildAuthStatusTools(opts: BuildAuthStatusToolsOpts) {
  const { userId } = opts;
  return [
    tool(
      "auth_revocation_status",
      "Read the caller's JWT revocation status. Returns " +
        "{revoked, deniedAt, reason} or null. Use when authentication " +
        "errors are returned to discriminate session revocation from " +
        "transient errors. A `revoked: true` response means the caller's " +
        "JWT jti is on the deny-list and the session will fail at the " +
        "next tenant-data boundary; contact the operator who recorded " +
        "`reason`. A `revoked: false` response means the deny-list does " +
        "not contain this jti — the auth error is transient. A `null` " +
        "response means the revocation RPC itself failed (mirrored to " +
        "Sentry) — treat as transient and retry the original operation.",
      {},
      async () => {
        const status = await getMyRevocationStatus(userId);
        // `status` is `MyRevocationStatus | null` — JSON-serialize directly
        // so the wire shape mirrors the helper's typed return value.
        return textResponse(status);
      },
    ),
  ];
}
