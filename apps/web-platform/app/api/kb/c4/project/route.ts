import { NextResponse } from "next/server";
import path from "path";
import { promises as fs, constants as fsConstants } from "node:fs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { resolveActiveWorkspaceKbRoot } from "@/server/workspace-resolver";
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

  // ADR-044 (#4543): the KB (and its C4 diagrams) live on the ACTIVE
  // workspace, not the caller's own `users` row — an invited member viewing a
  // shared workspace has an empty solo row. Mirror the tree/content READ paths
  // so the visualizer reads the same clone the sidebar renders from; reading
  // the caller's own root here surfaced as a spurious "Diagram model not built".
  const serviceClient = createServiceClient();
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    return access.status === 404
      ? NextResponse.json({ error: "Workspace not found" }, { status: 404 })
      : NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }
  const { kbRoot } = access;

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
    // Open once and read from the same descriptor — checking via lstat then
    // re-reading by path is a TOCTOU race (the file could be swapped between
    // check and use). O_NOFOLLOW rejects a symlinked final component
    // atomically; fstat on the open fd reads the size of the same inode we
    // then read from. (CodeQL js/file-system-race.)
    let handle: fs.FileHandle | undefined;
    try {
      handle = await fs.open(
        jsonAbs,
        fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
      );
      const stat = await handle.stat();
      if (stat.size > MAX_C4_BYTES) {
        return NextResponse.json({ error: "Diagram model too large" }, { status: 413 });
      }
      dump = JSON.parse(await handle.readFile("utf8"));
    } catch (e) {
      const code = (e as NodeJS.ErrnoException).code;
      if (code === "ENOENT") {
        return NextResponse.json(
          {
            error:
              "Diagram model not built. Run `/soleur:architecture render` to generate it.",
            code: "MODEL_NOT_BUILT",
          },
          { status: 404 },
        );
      }
      // O_NOFOLLOW on a symlink → ELOOP; treat as a rejected oversized/unsafe model.
      if (code === "ELOOP") {
        return NextResponse.json({ error: "Diagram model too large" }, { status: 413 });
      }
      throw e;
    } finally {
      await handle?.close();
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
        // O_NOFOLLOW + read from the same fd: rejects symlinks atomically and
        // avoids the lstat-then-readFile TOCTOU race (CodeQL js/file-system-race).
        let h: fs.FileHandle | undefined;
        try {
          h = await fs.open(abs, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
          sources[file] = await h.readFile("utf8");
        } finally {
          await h?.close();
        }
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
