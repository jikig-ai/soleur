import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient } from "@/lib/supabase/server";
import { resolveUserKbRoot } from "@/server/kb-route-helpers";
import { isPathInWorkspace } from "@/server/sandbox";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import { C4_DIAGRAMS_DIR, C4_SOURCE_EXT, C4_MODEL_JSON } from "@/lib/c4-constants";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

export const runtime = "nodejs";

const MAX_C4_BYTES = 4 * 1024 * 1024; // layouted model JSON can be large

/**
 * GET /api/kb/c4/project?dir=<kb-relative dir>
 *
 * Returns a LikeC4 project for client-side rendering: the precomputed,
 * layouted model (`model.likec4.json`, produced by `likec4 export json` and
 * committed alongside the sources) plus the raw `.c4` sources for the editor.
 *
 * Deliberately does NOT compute layout at runtime — the `likec4` toolchain
 * pulls vite/esbuild into prod deps and breaks npm10/npm11 lockfile parity.
 * The model is rebuilt out-of-band via `/soleur:architecture render`.
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
    // Layouted model (required).
    const jsonAbs = path.join(dirAbs, C4_MODEL_JSON);
    if (!isPathInWorkspace(jsonAbs, kbRoot)) {
      return NextResponse.json({ error: "Invalid dir" }, { status: 400 });
    }
    let dump: unknown;
    try {
      const stat = await fs.lstat(jsonAbs);
      if (stat.isSymbolicLink() || stat.size > MAX_C4_BYTES) {
        return NextResponse.json({ error: "Diagram model too large" }, { status: 413 });
      }
      dump = JSON.parse(await fs.readFile(jsonAbs, "utf8"));
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT") {
        return NextResponse.json(
          {
            error:
              "Diagram model not built. Run `/soleur:architecture render` to generate it.",
            code: "MODEL_NOT_BUILT",
          },
          { status: 404 },
        );
      }
      throw e;
    }

    const viewIds = Object.keys(
      (dump as { views?: Record<string, unknown> }).views ?? {},
    );

    // Raw .c4 sources for the editor (best-effort).
    const sources: Record<string, string> = {};
    try {
      for (const file of (await fs.readdir(dirAbs)).filter((f) =>
        f.endsWith(C4_SOURCE_EXT),
      ).sort()) {
        const abs = path.join(dirAbs, file);
        if (!isPathInWorkspace(abs, kbRoot)) continue;
        if ((await fs.lstat(abs)).isSymbolicLink()) continue;
        sources[file] = await fs.readFile(abs, "utf8");
      }
    } catch {
      // sources are optional for rendering
    }

    return NextResponse.json(
      { dir: requestedDir, sources, dump, viewIds, diagnostics: [] },
      { status: 200, headers: { "Cache-Control": "private, no-cache" } },
    );
  } catch (error) {
    Sentry.captureException(error);
    const errLog = renameUserIdToHash({ userId: user.id });
    logger.error(
      { err: error, ...errLog, dir: requestedDir },
      "kb/c4/project: read failed",
    );
    return NextResponse.json({ error: "Failed to load diagram" }, { status: 500 });
  }
}
