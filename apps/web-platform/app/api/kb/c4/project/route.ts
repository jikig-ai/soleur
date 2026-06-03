import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient } from "@/lib/supabase/server";
import { resolveUserKbRoot } from "@/server/kb-route-helpers";
import { isPathInWorkspace } from "@/server/sandbox";
import { computeC4Model } from "@/server/c4-compute";
import { C4_DIAGRAMS_DIR, C4_SOURCE_EXT } from "@/lib/c4-constants";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

// likec4 (graphviz-wasm) is a Node-only dependency — never run on edge.
export const runtime = "nodejs";

const MAX_C4_BYTES = 512 * 1024; // generous ceiling for a project's combined .c4 sources

/**
 * GET /api/kb/c4/project?dir=<kb-relative dir>
 *
 * Reads the `.c4` sources of a LikeC4 project from the caller's workspace,
 * computes a layouted model, and returns it for client-side rendering.
 * Read-only; defaults to the canonical architecture diagrams project.
 */
export async function GET(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const resolved = await resolveUserKbRoot(user.id);
  if (!resolved.ok) return resolved.response;
  const { kbRoot } = resolved;

  const requestedDir =
    new URL(request.url).searchParams.get("dir") || C4_DIAGRAMS_DIR;
  if (requestedDir.includes("\0") || requestedDir.includes("..")) {
    return NextResponse.json({ error: "Invalid dir" }, { status: 400 });
  }

  const dirAbs = path.join(kbRoot, requestedDir);
  if (!isPathInWorkspace(dirAbs, kbRoot)) {
    return NextResponse.json({ error: "Invalid dir" }, { status: 400 });
  }

  try {
    let entries: string[];
    try {
      entries = await fs.readdir(dirAbs);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT") {
        return NextResponse.json(
          { error: "No diagram project found" },
          { status: 404 },
        );
      }
      throw e;
    }

    const c4Files = entries.filter((f) => f.endsWith(C4_SOURCE_EXT)).sort();
    if (c4Files.length === 0) {
      return NextResponse.json(
        { error: "No .c4 sources in this directory" },
        { status: 404 },
      );
    }

    const sources: Record<string, string> = {};
    let totalBytes = 0;
    for (const file of c4Files) {
      const abs = path.join(dirAbs, file);
      if (!isPathInWorkspace(abs, kbRoot)) continue;
      const stat = await fs.lstat(abs);
      if (stat.isSymbolicLink()) continue;
      totalBytes += stat.size;
      if (totalBytes > MAX_C4_BYTES) {
        return NextResponse.json(
          { error: "Diagram project too large to render" },
          { status: 413 },
        );
      }
      sources[file] = await fs.readFile(abs, "utf8");
    }

    // Combine in stable order so the layout is deterministic across requests.
    const combined = c4Files.map((f) => sources[f]).join("\n\n");
    const { dump, viewIds, diagnostics } = await computeC4Model(combined);

    return NextResponse.json(
      { dir: requestedDir, sources, dump, viewIds, diagnostics },
      {
        status: 200,
        headers: { "Cache-Control": "private, no-cache" },
      },
    );
  } catch (error) {
    Sentry.captureException(error);
    // Pseudonymise userId at the source per #3698 (computed off the logger line).
    const errLog = renameUserIdToHash({ userId: user.id });
    logger.error(
      { err: error, ...errLog, dir: requestedDir },
      "kb/c4/project: compute failed",
    );
    return NextResponse.json(
      { error: "Failed to compute diagram" },
      { status: 500 },
    );
  }
}
