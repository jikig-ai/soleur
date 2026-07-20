// GET + POST /api/workstream/issues — session-gated Workstream board feed +
// issue create. NOT in PUBLIC_PATHS (cookie-session auth, same treatment as the
// routines route).
//
// GET serves the active workspace's REAL connected-repo issues via the shared
// getWorkstreamIssues() accessor (the SAME fn the workstream_issues_list agent
// tool calls) PLUS board-precedence meta (drives the UI drag/affordance gating).
// The accessor returns [] for no connected repo / no installation (honest empty
// board) and THROWS on a GitHub API failure → 502 (never empty-as-success).
//
// POST creates a real GitHub issue through the shared audited write accessor
// (ADR-109). owner/repo/installation + initiatorLogin resolve SERVER-SIDE from
// the active workspace — the request body carries only { title, body?, status? };
// any owner/repo/login in the body is ignored (anti-spoof, no cross-tenant).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { getWorkstreamIssues } from "@/server/workstream/get-workstream-issues";
import {
  createWorkstreamIssue,
  resolveWorkstreamBoardMeta,
} from "@/server/workstream/mutate-workstream-issue";
import {
  checkWorkstreamWriteRate,
  classifyWriteError,
} from "@/server/workstream/workstream-write-throttle";
import {
  STATUS_ORDER,
  WorkstreamDegradedError,
  type WorkstreamStatus,
} from "@/lib/workstream";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  try {
    const [issues, board] = await Promise.all([
      getWorkstreamIssues(user.id),
      resolveWorkstreamBoardMeta(user.id),
    ]);
    return NextResponse.json({ issues, board });
  } catch (e) {
    // A WorkstreamDegradedError already mirrored to Sentry at the degrade source
    // (mirror-precedes-throw) — skip re-capture to avoid a double event. Genuine
    // GitHub-LIST failures (not degraded) keep their route-level capture.
    if (!(e instanceof WorkstreamDegradedError)) {
      Sentry.captureException(e, { tags: { surface: "workstream-issues" } });
    }
    return NextResponse.json(
      { error: "workstream_query_error" },
      { status: 502 },
    );
  }
}

export async function POST(req: Request) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/workstream/issues", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
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

  const title = typeof b.title === "string" ? b.title : "";
  if (!title.trim()) {
    return NextResponse.json({ error: "empty_title" }, { status: 422 });
  }

  // Only title/body/status are accepted — owner/repo/installation/initiatorLogin
  // are resolved server-side, never from the body (anti-spoof / no cross-tenant).
  const input: { title: string; body?: string; status?: WorkstreamStatus } = {
    title,
  };
  if (typeof b.body === "string") input.body = b.body;
  if (typeof b.status === "string") {
    // Validate against the known column set (parity with the agent tool's
    // STATUS_ENUM) — an out-of-enum status would otherwise silently no-op into
    // Backlog (security review nit).
    if (!STATUS_ORDER.includes(b.status as WorkstreamStatus)) {
      return NextResponse.json({ error: "invalid_status" }, { status: 422 });
    }
    // A new issue cannot be created already-closed (create never closes; "done"
    // would yield an open Backlog card — a request/result mismatch).
    if (b.status === "done") {
      return NextResponse.json(
        { error: "cannot_create_closed" },
        { status: 422 },
      );
    }
    input.status = b.status as WorkstreamStatus;
  }

  try {
    const issue = await createWorkstreamIssue(user.id, input);
    return NextResponse.json({ issue });
  } catch (e) {
    const { status, code } = classifyWriteError(e);
    if (status >= 500) {
      Sentry.captureException(e, {
        tags: { surface: "workstream-issue-create" },
        extra: { userId: user.id },
      });
    }
    return NextResponse.json({ error: code }, { status });
  }
}
