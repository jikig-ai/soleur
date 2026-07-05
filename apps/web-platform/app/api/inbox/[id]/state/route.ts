import { inboxStateHandler } from "@/server/inbox-state-handler";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

/**
 * POST /api/inbox/[id]/state — transition an inbox_item (read | acted |
 * archived). Thin HTTP-only export (cq-nextjs-route-files-http-only-exports);
 * the full contract (auth posture, RPC error mapping, response table) lives in
 * `server/inbox-state-handler.ts`.
 */

export const dynamic = "force-dynamic";

export const POST = withUserRateLimit(inboxStateHandler, {
  perMinute: 60,
  feature: "inbox.state",
});
