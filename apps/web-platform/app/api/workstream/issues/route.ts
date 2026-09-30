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
// GET has two response shapes negotiated by `Accept`:
//   - `text/event-stream` (the board's streaming fetcher): an SSE feed of delta
//     frames — meta → issues* (one per upstream REST page) → statuses? →
//     done|error — so the board fills progressively instead of waiting out the
//     whole upstream page chain (ADR-113 transport precedent, cf. /api/support).
//   - anything else (nav badge's jsonFetcher, curl, out-of-tree readers): the
//     unchanged bulk `{issues, board}` JSON.
// Resolution degrades run BEFORE the stream is constructed either way, so a
// 502/401 is always a real status code — never an SSE skeleton.
//
// POST creates a real GitHub issue through the shared audited write accessor
// (ADR-109). owner/repo/installation + initiatorLogin resolve SERVER-SIDE from
// the active workspace — the request body carries only { title, body?, status? };
// any owner/repo/login in the body is ignored (anti-spoof, no cross-tenant).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import {
  getWorkstreamIssues,
  resolveBoardReadContext,
  streamWorkstreamIssues,
  type BoardReadContext,
} from "@/server/workstream/get-workstream-issues";
import {
  formatWorkstreamSseFrame,
  type WorkstreamFeedEvent,
} from "@/lib/workstream-feed";
import {
  createWorkstreamIssue,
  resolveWorkstreamBoardMeta,
} from "@/server/workstream/mutate-workstream-issue";
import {
  checkWorkstreamWriteRate,
  classifyWriteError,
} from "@/server/workstream/workstream-write-throttle";
import { verifiedUserId } from "@/server/request-auth";
import {
  STATUS_ORDER,
  WorkstreamDegradedError,
  type WorkstreamStatus,
} from "@/lib/workstream";

export const dynamic = "force-dynamic";

// Hard cap on the SSE feed — mirrors SUPPORT_TURN_MAX_MS's backstop role: a
// wedged upstream or a buffering middlebox must not pin the connection (and
// its server resources) open indefinitely.
const WORKSTREAM_FEED_MAX_MS = 90_000;

export async function GET(request: Request) {
  const userId = await verifiedUserId(request);
  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // The SSE arm runs the shared resolution preamble BEFORE constructing the
  // Response so a degrade still answers a real 502 JSON — pre-stream failures
  // never masquerade as an open stream (empty-vs-throw contract).
  if ((request.headers.get("accept") ?? "").includes("text/event-stream")) {
    return streamIssuesFeed(userId);
  }

  try {
    const [issues, board] = await Promise.all([
      getWorkstreamIssues(userId),
      resolveWorkstreamBoardMeta(userId),
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

/** The negotiated progressive feed (delta frames; see lib/workstream-feed). */
async function streamIssuesFeed(userId: string): Promise<Response> {
  let ctx: BoardReadContext;
  try {
    ctx = await resolveBoardReadContext(userId);
  } catch (e) {
    if (!(e instanceof WorkstreamDegradedError)) {
      Sentry.captureException(e, { tags: { surface: "workstream-issues" } });
    }
    return NextResponse.json(
      { error: "workstream_query_error" },
      { status: 502 },
    );
  }

  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let closed = false;
      const enqueue = (event: WorkstreamFeedEvent): void => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(formatWorkstreamSseFrame(event)));
        } catch {
          closed = true;
        }
      };

      // Cap backstop: emit an honest terminal frame, then close — the client's
      // done-absent EOF rule turns this into the loud error path, never a
      // silently-complete board.
      const capTimer = setTimeout(() => {
        enqueue({ type: "error", code: "workstream_feed_timeout" });
        closed = true;
        try {
          controller.close();
        } catch {
          // already closed
        }
      }, WORKSTREAM_FEED_MAX_MS);

      try {
        // The accessor emits the terminal `error` frame itself before
        // rethrowing; the catch here is the route-level Sentry capture (skipped
        // for WorkstreamDegradedError — already mirrored at its source).
        await streamWorkstreamIssues(ctx, enqueue);
      } catch (err) {
        if (!(err instanceof WorkstreamDegradedError)) {
          Sentry.captureException(err, {
            tags: { surface: "workstream-issues" },
          });
        }
      } finally {
        clearTimeout(capTimer);
        closed = true;
        try {
          controller.close();
        } catch {
          // already closed
        }
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}

export async function POST(req: Request) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/workstream/issues", origin);

  const userId = await verifiedUserId(req);
  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  if (!checkWorkstreamWriteRate(userId)) {
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
    const issue = await createWorkstreamIssue(userId, input);
    return NextResponse.json({ issue });
  } catch (e) {
    const { status, code } = classifyWriteError(e);
    if (status >= 500) {
      Sentry.captureException(e, {
        tags: { surface: "workstream-issue-create" },
        extra: { userId },
      });
    }
    return NextResponse.json({ error: code }, { status });
  }
}
