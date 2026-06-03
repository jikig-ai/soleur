/**
 * Map a server reason code (from /api/workspace/accept-invite and
 * /api/workspace/decline-invite) to human-readable copy so a raw code
 * (e.g. `not_intended_invitee`) never leaks into the UI, even on the
 * defensive 403 path the server enforces.
 *
 * Every code the route + acceptWorkspaceInvitation / declineWorkspaceInvitation
 * can emit to the client as `data.error` is enumerated here. A code that hits the
 * `default` branch shows the generic "Something went wrong" — which is the exact bug
 * this module was extracted to fix: `rpc_failed`, `revoked`, and `unknown` were
 * previously unmapped and fell through to that branch, so a cancelled invite, a
 * transient backend error, and an RPC contract-drift were all indistinguishable from
 * an unknown failure. Keep this switch exhaustive over the emitted-code set (route +
 * server wrapper). `caller_not_authenticated` is mapped defensively only: the RPC
 * raises it as a P0001 exception that the wrapper catches and re-labels `rpc_failed`,
 * so it never reaches the client as a reason today — the mapping guards a future
 * contract change. `unauthorized` IS client-reachable (route 401 → `data.error`).
 */
export function reasonToMessage(reason: string | undefined): string {
  switch (reason) {
    // ---- terminal states the invitee can understand ----
    case "not_intended_invitee":
      return "This invitation isn't addressed to your account.";
    case "expired":
      return "This invitation has expired.";
    case "already_accepted":
    case "already_member":
      return "You've already joined this workspace.";
    case "already_declined":
      return "This invitation has already been declined.";
    case "invitation_not_found":
      return "This invitation is no longer available.";
    case "revoked":
      return "This invitation has been cancelled. Ask the workspace owner to send a new one.";

    // ---- auth state: the session lapsed; signing in again resolves it ----
    case "unauthorized":
    case "caller_not_authenticated":
      return "Your session has expired. Please sign in again.";

    // ---- transient / contract-drift backend error: retry is meaningful ----
    // `unknown` = the RPC resolved ok=false with no reason (contract drift,
    // mirrored to Sentry by the wrapper); treat it like a transient fault rather
    // than letting it fall through to the generic dead-end (the bug this fixes).
    case "rpc_failed":
    case "unknown":
      return "Something went wrong on our end. Please try again in a moment.";

    // ---- unmapped (incl. invalid_body/invalid_json client bugs) ----
    default:
      return reason ? "Something went wrong. Please try again." : "";
  }
}
