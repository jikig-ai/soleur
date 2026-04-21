// Opt-in debug logging for permission-layer bisection (#2336).
//
// The SDK permission chain has 5 steps (hooks → deny rules → permission
// mode → allow rules → canUseTool). When a prod allow/deny seems wrong,
// the operator sets `SOLEUR_DEBUG_PERMISSION_LAYER=1` and reproduces.
// Each layer calls `logPermissionDecision(...)` so the trail shows which
// step decided — without forcing allocation/serialization of the payload
// when the flag is unset.
//
// Pino stdout is the destination (not Sentry): these are expected-state
// decisions, not silent fallbacks. `cq-silent-fallback-must-mirror-to-
// sentry` explicitly excludes expected states.

import { createChildLogger } from "./logger";

const log = createChildLogger("permission");

export type PermissionLayer =
  | "sandbox-hook"
  | "canUseTool-file-tool"
  | "canUseTool-agent"
  | "canUseTool-safe"
  | "canUseTool-review-gate"
  | "canUseTool-platform-auto"
  | "canUseTool-platform-gated"
  | "canUseTool-platform-blocked"
  | "canUseTool-plugin-mcp"
  | "canUseTool-deny-default";

export function logPermissionDecision(
  layer: PermissionLayer,
  toolName: string,
  decision: "allow" | "deny",
  reason?: string,
): void {
  // Early return — unset flag must not allocate an object literal.
  if (process.env.SOLEUR_DEBUG_PERMISSION_LAYER !== "1") return;
  log.debug(
    { sec: true, layer, tool: toolName, decision, reason },
    "permission-decision",
  );
}
