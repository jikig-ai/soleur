// Away-user approval landing page (#4672, wireframe 07). Server component: cookie-session auth gate, an RLS read of the
// one row (the Owner-only `approval_request_owner_select` policy), then the shared card.
//
//   - Signed out: bounced to sign-in with `redirectTo` (the login form re-validates it through safeReturnTo and returns
//     here after sign-in and MFA). No request content is read or rendered before authentication.
//   - A non-Owner, an unknown id and a malformed id all end in the SAME notFound(): the page never confirms that a
//     request exists (wireframe 07c/07e). There is no member landing variant.
//   - Renders any existing row REGARDLESS of the `approval-queue` flag: turning the flag off never strands a request.
//   - The card text is rebuilt from the stored canonical action and re-hashed against the row's bound hash before it is
//     shown; a row that does not verify renders no Approve/Deny (fail closed), a scrubbed row renders "Details removed".
//   - The page shows the server-built view only, never agent-authored prose.

import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { reportApprovalOp } from "@/server/approval/ops";
import { isVerifiedRequester } from "@/server/approval/card-visibility";
import { createRequesterLabeler } from "@/server/approval/requester-label";
import { readStoredApproval, type StoredApprovalRowWithRequester } from "@/server/approval/view-model";
import { ApprovalLanding } from "@/components/approvals/approval-landing";
import { APPROVAL_LANDING_COPY, REQUESTER_SELF } from "@/lib/approval-copy";
import { isUuid } from "@/lib/is-uuid";

export const dynamic = "force-dynamic";

const ROW_COLUMNS =
  "id, workspace_id, conversation_id, tool_name, action_sha256, status, expires_at, created_at, decided_at, decided_by, consumed_at, revoked_at, requested_by_user_id, canonical_action";

export default async function ApprovalPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect(`/login?redirectTo=${encodeURIComponent(`/dashboard/approvals/${id}`)}`);

  const { data, error } = await supabase.from("approval_request").select(ROW_COLUMNS).eq("id", id).maybeSingle();
  if (error) {
    // Static message, ids only: the error text can echo row content.
    reportApprovalOp("landingReadFailed", error, { approvalId: id, userId: user.id, extra: { read: "row" } });
    throw new Error("approval read failed");
  }
  if (!data) notFound();
  const row = data as unknown as StoredApprovalRowWithRequester;

  const read = readStoredApproval(row);

  // Request count (header from request 2): every status for the same conversation and action, read under the same RLS.
  // A failed read is reported and the count line is omitted (the card shows it from 2 up): never a silent "1".
  let requestCount = 1;
  let countKnown = false;
  const counted = await supabase
    .from("approval_request")
    .select("id", { count: "exact", head: true })
    .eq("conversation_id", row.conversation_id)
    .eq("action_sha256", row.action_sha256);
  if (counted.error) {
    reportApprovalOp("landingReadFailed", counted.error, { approvalId: id, userId: user.id, extra: { read: "request-count" } });
  } else if (typeof counted.count === "number" && counted.count > 0) {
    requestCount = counted.count;
    countKnown = true;
  }

  // Who raised the request (#9601). Only after the Owner-only RLS read above succeeded (`approval_request_owner_select` is
  // `is_workspace_owner(workspace_id, auth.uid())`) and only when there is a card to label. The literal "you" for the
  // verified requester. Another member's label only while ONE request exists: with two or more (or an unknown count) a
  // single label would be ambiguous, so the labeler is not asked and the line is omitted. A failed lookup omits it too.
  // (Deviation from "start in parallel with the count": the count decides whether the labeler may be called at all.)
  let requester: string | undefined;
  if (read.kind === "ok") {
    if (isVerifiedRequester(user.id, row.requested_by_user_id)) requester = REQUESTER_SELF;
    else if (countKnown && requestCount < 2) requester = await createRequesterLabeler()(row.workspace_id, user.id, row.requested_by_user_id);
  }

  return (
    <main className="mx-auto max-w-2xl px-4 py-6 md:px-6 md:py-10">
      <header className="mb-4">
        <h1 className="text-xl font-medium text-soleur-text-primary">{APPROVAL_LANDING_COPY.pageTitle}</h1>
        {/* Fixed copy on purpose: the conversation title is model-influenceable text and never reaches this page. */}
        <p className="mt-1 text-sm text-soleur-text-secondary">{APPROVAL_LANDING_COPY.fromAgent}</p>
      </header>
      {read.kind === "unverifiable" ? (
        <p role="alert" data-testid="approval-unverifiable" className="rounded-xl border-2 border-soleur-border-default bg-soleur-bg-surface-1 p-4 text-sm text-soleur-text-primary">
          {APPROVAL_LANDING_COPY.unverifiable}
        </p>
      ) : (
        <ApprovalLanding
          approvalId={row.id}
          view={read.kind === "ok" ? read.view : null}
          requestCount={requestCount}
          requester={requester}
          initial={{
            status: row.status,
            expiresAt: row.expires_at,
            decidedAt: row.decided_at,
            decidedByViewer: row.decided_by === user.id,
            revoked: row.revoked_at !== null,
            // The retention scrub clock (migration 180): COALESCE(consumed_at, expired_at, revoked_at, decided_at). An expired
            // row has no `expired_at` column in this read, so its expiry time stands in (the sweep stamps it within minutes).
            endedAt:
              row.status === "pending"
                ? null
                : (row.consumed_at ?? (row.status === "expired" ? row.expires_at : null) ?? row.revoked_at ?? row.decided_at),
          }}
        />
      )}
    </main>
  );
}
