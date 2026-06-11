import { makeEmailTriageStatusHandler } from "@/server/email-triage/email-triage-status-handler";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

/**
 * POST /api/inbox/emails/[id]/acknowledge — operator saw a triage item.
 *
 * Verb-subresource per the codebase's lifecycle-transition family
 * (precedent: dashboard/today/[id]/cancel — POST-on-verb, never
 * PATCH /status). Sibling: .../archive (keep both files in lockstep).
 *
 * Thin HTTP-only export (cq-nextjs-route-files-http-only-exports) — the
 * full contract (auth posture, RPC error mapping, response table) lives in
 * `server/email-triage/email-triage-status-handler.ts`.
 */

export const dynamic = "force-dynamic";

export const POST = withUserRateLimit(
  makeEmailTriageStatusHandler("acknowledged"),
  {
    perMinute: 60,
    feature: "inbox.emails.acknowledge",
  },
);
