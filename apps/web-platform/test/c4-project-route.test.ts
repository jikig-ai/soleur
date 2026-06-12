import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Owner-scoped C4 project endpoint. Unlike the public shared route, this one
// DOES return raw sources for the editor. This test exercises the real
// `isPathInWorkspace` + `O_NOFOLLOW` guards against a real temp filesystem;
// only auth + the workspace resolver are mocked.
const mocks = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockResolveKbRoot: vi.fn(),
  mockLoggerError: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mocks.mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({})),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspaceKbRoot: mocks.mockResolveKbRoot,
}));

vi.mock("@/server/logger", () => ({
  default: {
    info: vi.fn(),
    error: mocks.mockLoggerError,
    warn: vi.fn(),
    debug: vi.fn(),
  },
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { GET } from "@/app/api/kb/c4/project/route";
import { C4_DIAGRAMS_DIR } from "@/lib/c4-constants";

let kbRoot: string;
const dirAbs = () => path.join(kbRoot, C4_DIAGRAMS_DIR);

function writeFile(name: string, content: string) {
  fs.writeFileSync(path.join(dirAbs(), name), content);
}

async function callGET() {
  return GET(new Request("http://localhost:3000/api/kb/c4/project"));
}

beforeEach(() => {
  vi.clearAllMocks();
  kbRoot = fs.mkdtempSync(path.join(os.tmpdir(), "owner-c4-"));
  fs.mkdirSync(dirAbs(), { recursive: true });
  mocks.mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
  mocks.mockResolveKbRoot.mockResolvedValue({ ok: true, kbRoot });
});

afterEach(() => {
  fs.rmSync(kbRoot, { recursive: true, force: true });
});

describe("GET /api/kb/c4/project — owner sources filter (AC6)", () => {
  beforeEach(() => {
    // A representative diagrams dir: .c4 sources, the model JSON, the
    // README directory index, AND the c4-model.md view-embed page.
    fs.writeFileSync(
      path.join(dirAbs(), "model.likec4.json"),
      JSON.stringify({ views: { index: {} } }),
    );
    writeFile("spec.c4", "specification {}");
    writeFile("model.c4", "model {}");
    writeFile("views.c4", "views {}");
    writeFile("README.md", "# Diagrams\n\nFile taxonomy.");
    writeFile("c4-model.md", "```likec4-view\nindex\n```");
  });

  it("includes README.md in the returned sources alongside the .c4 files", async () => {
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(Object.keys(body.sources).sort()).toEqual([
      "README.md",
      "model.c4",
      "spec.c4",
      "views.c4",
    ]);
    expect(body.sources["README.md"]).toContain("File taxonomy.");
  });

  it("does NOT surface c4-model.md (exact README.md match, not blanket .md)", async () => {
    const res = await callGET();
    const body = await res.json();
    expect("c4-model.md" in body.sources).toBe(false);
  });

  it("still serves when no README is present (README is optional)", async () => {
    fs.rmSync(path.join(dirAbs(), "README.md"));
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect("README.md" in body.sources).toBe(false);
    expect("model.c4" in body.sources).toBe(true);
  });

  it("rejects a symlinked README via O_NOFOLLOW without leaking it or 500ing", async () => {
    // The README read uses the SAME O_NOFOLLOW open as the .c4 reads (the plan
    // mandates identical handling). A symlinked README → ELOOP, swallowed by the
    // best-effort sources catch: the link content never leaks into `sources` and
    // the response degrades to 200 (sources optional), never a 500.
    fs.rmSync(path.join(dirAbs(), "README.md"));
    const realTarget = path.join(dirAbs(), "real-readme.md");
    fs.writeFileSync(realTarget, "# secret");
    fs.symlinkSync(realTarget, path.join(dirAbs(), "README.md"));
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    // The symlinked README is never followed → its content is not exposed.
    expect("README.md" in body.sources).toBe(false);
    expect(JSON.stringify(body.sources)).not.toContain("secret");
  });
});
