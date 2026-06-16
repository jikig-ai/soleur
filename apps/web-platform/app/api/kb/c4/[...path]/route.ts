import { NextResponse } from "next/server";
import { authenticateAndResolveKbPath } from "@/server/kb-route-helpers";
import { writeC4Diagram } from "@/server/c4-writer";
import { createClient } from "@/lib/supabase/server";
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { getRuntimeFlag } from "@/lib/feature-flags/server";
import { C4_EDIT_FLAG } from "@/lib/c4-constants";

export const runtime = "nodejs";
// A .c4 save commits the source, then re-renders model.likec4.json out-of-process
// (likec4 CLI) and commits + re-syncs it. The real wall-clock bound is in-code
// (c4-render.ts RENDER_TIMEOUT_MS=25s + the GitHub/sync fetch timeouts); under
// this app's custom Node server `maxDuration` is a forward-compat platform hint,
// not the enforcing killer (kept for parity with the upload route). (#4964)
export const maxDuration = 60;

/**
 * PUT /api/kb/c4/<diagrams-relative path>
 *
 * Saves an edited LikeC4 source (`.c4`) from the in-browser code editor.
 * Scope is enforced by `writeC4Diagram` (diagrams dir only).
 */
export async function PUT(
  request: Request,
  { params }: { params: Promise<{ path: string[] }> },
) {
  // blockMarkdown: false — the diagrams dir holds both .c4 sources and the
  // .md view-embed pages; writeC4Diagram applies the real scope guard.
  const resolved = await authenticateAndResolveKbPath(request, params, {
    endpoint: "api/kb/c4",
    blockMarkdown: false,
  });
  if (!resolved.ok) return resolved.response;
  const { ctx } = resolved;

  // SECURITY BOUNDARY (feat-c4-viewer-remove-code-panel-gate-edit): the
  // user-direct edit surface is gated behind `c4-edit`, default OFF for all
  // roles. `ctx` carries no identity, so resolve the caller's real identity
  // here — `resolveIdentity` is request-cache-deduped and fails CLOSED to a
  // `prd`/anon identity on any read error, so a Flagsmith outage (env mirror
  // FLAG_C4_EDIT=0) or an identity-read error can only ever DENY. The Concierge
  // `edit_c4_diagram` path (gated on the separate `c4-visualizer` flag) is the
  // only live KB writer while this flag is OFF.
  const identity = await resolveIdentity(await createClient());
  if (!(await getRuntimeFlag(C4_EDIT_FLAG, identity))) {
    return NextResponse.json(
      {
        error:
          "Diagram editing is currently disabled. Ask the Concierge to edit this diagram.",
      },
      { status: 403 },
    );
  }

  let content: string;
  try {
    const body = await request.json();
    content = body?.content;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const result = await writeC4Diagram({
    userId: ctx.user.id,
    installationId: ctx.userData.github_installation_id,
    owner: ctx.owner,
    repo: ctx.repo,
    workspacePath: ctx.userData.workspace_path,
    relativePath: ctx.relativePath,
    content,
  });

  if (!result.ok) {
    return NextResponse.json(
      { error: result.error, ...(result.code ? { code: result.code } : {}) },
      { status: result.status },
    );
  }
  return NextResponse.json(
    {
      commitSha: result.commitSha,
      rerendered: result.rerendered,
      ...(result.rerenderDiagnostic
        ? { rerenderDiagnostic: result.rerenderDiagnostic }
        : {}),
    },
    { status: 200 },
  );
}
