// PATCH /api/workstream/issues/[number] — session-gated issue update through the
// shared audited write accessor (ADR-109). Body: { title?, status?, state_reason?,
// reopen? }. owner/repo/installation resolve SERVER-SIDE from the active
// workspace (ADR-044) — the body NEVER carries owner/repo/login.
//
// Dispatch:
//   - title            → updateWorkstreamIssueTitle
//   - status           → setWorkstreamIssueStatus (the ONE primitive; status=done
//                        closes with state_reason, non-terminal relabels+reopens)
//   - reopen: true     → reopenWorkstreamIssue (state=open, leaves Done, lands
//                        where surviving labels derive)
// Returns the CANONICAL resulting issue so the client reconciles from stored
// truth, not a bare 2xx. 502 + Sentry on failure (fail-loud, never masquerade).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import {
  reopenWorkstreamIssue,
  setWorkstreamIssueStatus,
  updateWorkstreamIssueTitle,
  type CloseReason,
} from "@/server/workstream/mutate-workstream-issue";
import {
  checkWorkstreamWriteRate,
  classifyWriteError,
} from "@/server/workstream/workstream-write-throttle";
import {
  STATUS_ORDER,
  type WorkstreamIssue,
  type WorkstreamStatus,
} from "@/lib/workstream";

export const dynamic = "force-dynamic";

const CLOSE_REASONS = new Set<CloseReason>(["completed", "not_planned"]);

export async function PATCH(
  req: Request,
  { params }: { params: Promise<{ number: string }> },
) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/workstream/issues/[number]", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const { number: rawNumber } = await params;
  const issueNumber = Number(rawNumber);
  if (!Number.isInteger(issueNumber) || issueNumber <= 0) {
    return NextResponse.json({ error: "invalid_number" }, { status: 400 });
  }

  if (!checkWorkstreamWriteRate(user.id)) {
    return NextResponse.json(
      { error: "rate_limited" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const b = (body ?? {}) as Record<string, unknown>;

  const hasTitle = typeof b.title === "string";
  const hasStatus = typeof b.status === "string";
  const reopen = b.reopen === true;

  // Title validation before any write (empty/whitespace → 422).
  if (hasTitle && !(b.title as string).trim()) {
    return NextResponse.json({ error: "empty_title" }, { status: 422 });
  }
  if (!hasTitle && !hasStatus && !reopen) {
    return NextResponse.json({ error: "no_change" }, { status: 400 });
  }
  // Validate status against the known column set (parity with the agent tool's
  // STATUS_ENUM) so a typo'd status 422s instead of silently landing in Backlog.
  if (hasStatus && !STATUS_ORDER.includes(b.status as WorkstreamStatus)) {
    return NextResponse.json({ error: "invalid_status" }, { status: 422 });
  }
  // Title and status/reopen are separate atomic writes — reject a combined body
  // rather than silently dropping the title (the dispatch below applies only one).
  if (hasTitle && (hasStatus || reopen)) {
    return NextResponse.json(
      { error: "title_and_status_separate" },
      { status: 422 },
    );
  }

  try {
    let issue: WorkstreamIssue;
    if (hasStatus) {
      const stateReason =
        typeof b.state_reason === "string" &&
        CLOSE_REASONS.has(b.state_reason as CloseReason)
          ? (b.state_reason as CloseReason)
          : undefined;
      issue = await setWorkstreamIssueStatus(
        user.id,
        issueNumber,
        b.status as WorkstreamStatus,
        stateReason,
      );
    } else if (reopen) {
      issue = await reopenWorkstreamIssue(user.id, issueNumber);
    } else {
      issue = await updateWorkstreamIssueTitle(
        user.id,
        issueNumber,
        b.title as string,
      );
    }
    return NextResponse.json({ issue });
  } catch (e) {
    const { status, code } = classifyWriteError(e);
    if (status >= 500) {
      Sentry.captureException(e, {
        tags: { surface: "workstream-issue-patch" },
        extra: { userId: user.id, issueNumber },
      });
    }
    return NextResponse.json({ error: code }, { status });
  }
}
