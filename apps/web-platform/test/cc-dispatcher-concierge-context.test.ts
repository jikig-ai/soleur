/**
 * KB Concierge document-context resolver — exercises
 * `resolveConciergeDocumentContext` against the real filesystem under a
 * temp workspace. Mirrors the legacy `agent-runner.ts:595-631` injection
 * so the cc-soleur-go path stays at parity.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, mkdirSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import path from "path";

const { fetchUserWorkspacePathSpy } = vi.hoisted(() => ({
  fetchUserWorkspacePathSpy: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          single: async () => fetchUserWorkspacePathSpy(),
        }),
      }),
    }),
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { resolveConciergeDocumentContext } from "@/server/cc-dispatcher";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = mkdtempSync(path.join(tmpdir(), "concierge-ctx-"));
  fetchUserWorkspacePathSpy.mockResolvedValue({
    data: { workspace_path: tmpRoot },
    error: null,
  });
});

afterEach(() => {
  rmSync(tmpRoot, { recursive: true, force: true });
  vi.clearAllMocks();
});

describe("resolveConciergeDocumentContext", () => {
  it("returns {} for empty contextPath", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "",
    });
    expect(out).toEqual({});
  });

  it("returns {} for null contextPath", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: null,
    });
    expect(out).toEqual({});
  });

  it("returns documentKind=pdf and skips file read for .pdf paths", async () => {
    // No file written; the resolver must not attempt to read it.
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/foo.pdf",
    });
    expect(out).toEqual({
      artifactPath: "knowledge-base/foo.pdf",
      documentKind: "pdf",
    });
  });

  it("inlines text body for small files within the workspace", async () => {
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "vision.md"),
      "# Vision\nWe build for users.",
    );

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/vision.md",
    });
    expect(out.artifactPath).toBe("knowledge-base/vision.md");
    expect(out.documentKind).toBe("text");
    expect(out.documentContent).toContain("We build for users.");
  });

  it("rejects path-traversal attempts (returns {})", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "../../../etc/passwd",
    });
    expect(out).toEqual({});
  });

  it("falls through to instruction-only when the file does not exist", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/missing.md",
    });
    // Defense-in-depth: no documentContent; agent will Read.
    expect(out.artifactPath).toBe("knowledge-base/missing.md");
    expect(out.documentKind).toBe("text");
    expect(out.documentContent).toBeUndefined();
  });

  it("drops oversized text files to instruction-only (no content inlined)", async () => {
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "big.md"),
      "a".repeat(60_000),
    );
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/big.md",
    });
    expect(out.artifactPath).toBe("knowledge-base/big.md");
    expect(out.documentKind).toBe("text");
    expect(out.documentContent).toBeUndefined();
  });

  it("uses provided content (skips read) when caller passes providedContent", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/anywhere.md",
      providedContent: "client-side body",
    });
    expect(out.artifactPath).toBe("knowledge-base/anywhere.md");
    expect(out.documentKind).toBe("text");
    expect(out.documentContent).toBe("client-side body");
  });

  it("provided content for a PDF still resolves as kind=pdf (no inlining)", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/foo.pdf",
      providedContent: "ignored-binary-bytes",
    });
    expect(out.artifactPath).toBe("knowledge-base/foo.pdf");
    expect(out.documentKind).toBe("pdf");
    expect(out.documentContent).toBeUndefined();
  });
});
