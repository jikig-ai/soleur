import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Public, token-scoped C4 data endpoint. It must serve the layouted model for
// the shared document's OWN diagram dir with NO Supabase session — so this test
// file intentionally does NOT mock `createClient` / `auth.getUser`. Reaching for
// auth in the route would throw "createClient is not a function" here, which is
// the negative-space proof that the endpoint is anonymous-by-design.
const mocks = vi.hoisted(() => ({
  mockServiceFrom: vi.fn(),
  mockIsAllowed: vi.fn(),
  mockLoggerInfo: vi.fn(),
  mockLoggerWarn: vi.fn(),
  mockLoggerError: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({
    from: mocks.mockServiceFrom,
  })),
}));

vi.mock("@/server/rate-limiter", () => ({
  shareEndpointThrottle: { isAllowed: mocks.mockIsAllowed },
  extractClientIpFromHeaders: vi.fn(() => "127.0.0.1"),
  logRateLimitRejection: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: {
    info: mocks.mockLoggerInfo,
    error: mocks.mockLoggerError,
    warn: mocks.mockLoggerWarn,
    debug: vi.fn(),
  },
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mocks.mockReportSilentFallback,
}));

import { GET } from "@/app/api/shared/[token]/c4/route";
import { shareSupabaseFromMock } from "./helpers/share-mocks";
import { makeUuidWorkspaceTmpdir } from "./helpers/workspace-tmpdir";

let tmpWorkspace: string;
let kbRoot: string;
let shareRow: Record<string, unknown> | null;

const DIAGRAMS_DIR = "engineering/architecture/diagrams";
const DOC_PATH = `${DIAGRAMS_DIR}/c4-model.md`;

function mockShareLookup() {
  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: {
        shareRow: () => shareRow,
        shareError: () => (shareRow ? null : new Error("not found")),
      },
    }),
  );
}

function writeModel(dir: string, model: unknown) {
  const abs = path.join(kbRoot, dir);
  fs.mkdirSync(abs, { recursive: true });
  fs.writeFileSync(path.join(abs, "model.likec4.json"), JSON.stringify(model));
}

async function callGET(url = "http://localhost:3000/api/shared/token-123/c4") {
  return GET(new Request(url), {
    params: Promise.resolve({ token: "token-123" }),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  tmpWorkspace = makeUuidWorkspaceTmpdir("shared-c4-").workspacePath;
  process.env.WORKSPACES_ROOT = path.dirname(tmpWorkspace);
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
  mocks.mockIsAllowed.mockReturnValue(true);
  shareRow = null;
  mockShareLookup();
});

afterEach(() => {
  delete process.env.WORKSPACES_ROOT;
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("GET /api/shared/[token]/c4 — public token-scoped diagram data", () => {
  it("serves { dir, dump, viewIds } for a valid token with NO Supabase session and OMITS .c4 sources", async () => {
    writeModel(DIAGRAMS_DIR, { views: { context: {}, containers: {} } });
    shareRow = { document_path: DOC_PATH, revoked: false };

    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.dir).toBe(DIAGRAMS_DIR);
    expect(body.dump).toEqual({ views: { context: {}, containers: {} } });
    expect(body.viewIds).toEqual(["context", "containers"]);
    // Data-minimization: the public endpoint never returns raw .c4 sources.
    expect("sources" in body).toBe(false);
    expect(mocks.mockLoggerInfo).toHaveBeenCalledWith(
      expect.objectContaining({ event: "shared_c4_served" }),
      expect.any(String),
    );
  });

  it("binds the C4 dir to dirname(document_path) and IGNORES a client-supplied ?dir", async () => {
    // Doc A's diagrams dir holds the real model.
    writeModel(DIAGRAMS_DIR, { views: { context: { id: "A" } } });
    // An unrelated dir B also holds a model — a token for doc A must NEVER read it.
    writeModel("other/secret", { views: { context: { id: "B" } } });
    shareRow = { document_path: DOC_PATH, revoked: false };

    const res = await callGET(
      "http://localhost:3000/api/shared/token-123/c4?dir=other/secret",
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    // Resolved dir is the SHARED doc's own dir, not the query param.
    expect(body.dir).toBe(DIAGRAMS_DIR);
    expect(body.dump.views.context.id).toBe("A");
  });

  it("returns 404 for an unknown token", async () => {
    shareRow = null;
    const res = await callGET();
    expect(res.status).toBe(404);
    expect(res.headers.get("Cache-Control")).toBe("no-store");
  });

  it("returns 410 code:'revoked' for a revoked token", async () => {
    shareRow = { document_path: DOC_PATH, revoked: true };
    const res = await callGET();
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.code).toBe("revoked");
    expect(res.headers.get("Cache-Control")).toBe("no-store");
  });

  it("returns 404 code:'MODEL_NOT_BUILT' when the model file is absent", async () => {
    // No writeModel — the dir exists implicitly only via kbRoot; model missing.
    fs.mkdirSync(path.join(kbRoot, DIAGRAMS_DIR), { recursive: true });
    shareRow = { document_path: DOC_PATH, revoked: false };
    const res = await callGET();
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.code).toBe("MODEL_NOT_BUILT");
  });

  it("returns 413 when the model is a symlink (O_NOFOLLOW → ELOOP)", async () => {
    const dirAbs = path.join(kbRoot, DIAGRAMS_DIR);
    fs.mkdirSync(dirAbs, { recursive: true });
    // Target is INSIDE the workspace so isPathInWorkspace (which resolves the
    // symlink via realpath) passes — proving O_NOFOLLOW is the load-bearing
    // guard that atomically rejects the symlinked final component (ELOOP).
    const realTarget = path.join(dirAbs, "real-model.json");
    fs.writeFileSync(realTarget, JSON.stringify({ views: {} }));
    fs.symlinkSync(realTarget, path.join(dirAbs, "model.likec4.json"));
    shareRow = { document_path: DOC_PATH, revoked: false };
    const res = await callGET();
    expect(res.status).toBe(413);
  });

  it("positive control: a REGULAR model at the same path serves 200 (proves the 413 is caused by the symlink, not an incidental read failure)", async () => {
    // Identical setup to the symlink test minus the symlink — a plain file at
    // model.likec4.json must serve 200. This pins that the symlink case's 413
    // comes from O_NOFOLLOW rejecting the link, not from the path/dir being
    // unreadable for some unrelated reason.
    writeModel(DIAGRAMS_DIR, { views: { context: {} } });
    shareRow = { document_path: DOC_PATH, revoked: false };
    const res = await callGET();
    expect(res.status).toBe(200);
  });

  it("resolves dir='.' for a root-level shared doc (dirname of a top-level file)", async () => {
    // document_path with no directory → dirname is ".", which joins to kbRoot.
    writeModel(".", { views: { root: {} } });
    shareRow = { document_path: "root-diagram.md", revoked: false };
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.dir).toBe(".");
    expect(body.viewIds).toEqual(["root"]);
  });

  it("returns 413 when the model exceeds the size cap", async () => {
    const dirAbs = path.join(kbRoot, DIAGRAMS_DIR);
    fs.mkdirSync(dirAbs, { recursive: true });
    // 5 MiB > MAX_C4_BYTES (4 MiB).
    fs.writeFileSync(
      path.join(dirAbs, "model.likec4.json"),
      Buffer.alloc(5 * 1024 * 1024, "x"),
    );
    shareRow = { document_path: DOC_PATH, revoked: false };
    const res = await callGET();
    expect(res.status).toBe(413);
  });

  it("rate-limits before any filesystem work", async () => {
    mocks.mockIsAllowed.mockReturnValue(false);
    const openSpy = vi.spyOn(fs.promises, "open");
    const res = await callGET();
    expect(res.status).toBe(429);
    expect(openSpy).not.toHaveBeenCalled();
    expect(res.headers.get("Cache-Control")).toBe("no-store");
    openSpy.mockRestore();
  });
});
