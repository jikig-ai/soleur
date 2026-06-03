import { NextResponse } from "next/server";
import { authenticateAndResolveKbPath } from "@/server/kb-route-helpers";
import { writeC4Diagram } from "@/server/c4-writer";

export const runtime = "nodejs";

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
  return NextResponse.json({ commitSha: result.commitSha }, { status: 200 });
}
