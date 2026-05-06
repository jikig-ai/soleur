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

const { fetchUserWorkspacePathSpy, extractPdfTextSpy, reportSilentFallbackSpy } =
  vi.hoisted(() => ({
    fetchUserWorkspacePathSpy: vi.fn(),
    extractPdfTextSpy: vi.fn(),
    reportSilentFallbackSpy: vi.fn(),
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
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/pdf-text-extract", () => ({
  extractPdfText: extractPdfTextSpy,
}));

import { resolveConciergeDocumentContext } from "@/server/cc-dispatcher";
import { _resetWorkspacePathCacheForTests } from "@/server/kb-document-resolver";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = mkdtempSync(path.join(tmpdir(), "concierge-ctx-"));
  fetchUserWorkspacePathSpy.mockResolvedValue({
    data: { workspace_path: tmpRoot },
    error: null,
  });
  extractPdfTextSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  // Drain the per-process workspace-path memo so each test sees its own
  // tmpRoot (the resolver caches `users.workspace_path` for the
  // conversation lifetime — without a reset, test N's tmpRoot leaks into
  // test N+1).
  _resetWorkspacePathCacheForTests();
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

  it("returns documentKind=pdf with documentContent when extractor succeeds", async () => {
    // #3338 — server-side PDF text extraction at cold-Query construction.
    // When a PDF is present in the workspace AND the extractor returns a
    // non-empty body within the inline cap, the resolver inlines it via
    // documentContent. The agent never has to call Read.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "book.pdf"),
      Buffer.from("%PDF-1.4\nfake-bytes"),
    );
    extractPdfTextSpy.mockResolvedValueOnce({
      text: "Chapter 1\nIntroduction to Platform Engineering",
      truncated: false,
      pageCount: 12,
    });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/book.pdf",
    });
    expect(out.artifactPath).toBe("knowledge-base/book.pdf");
    expect(out.documentKind).toBe("pdf");
    expect(out.documentContent).toContain("Chapter 1");
    expect(extractPdfTextSpy).toHaveBeenCalledOnce();
  });

  it("falls through to documentKind=pdf without content when extractor returns null", async () => {
    // Corrupted, encrypted, or oversized PDFs return null from the
    // extractor; the resolver falls through to the existing Read-directive
    // path AND mirrors a Sentry breadcrumb so operators see the failure
    // class.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "scanned.pdf"),
      Buffer.from("%PDF-1.4\ncorrupted"),
    );
    extractPdfTextSpy.mockResolvedValueOnce(null);

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/scanned.pdf",
    });
    expect(out).toEqual({
      artifactPath: "knowledge-base/scanned.pdf",
      documentKind: "pdf",
    });
    // Sentry mirror MUST fire so a degraded extractor path is observable
    // (per cq-silent-fallback-must-mirror-to-sentry).
    const sentryCalls = reportSilentFallbackSpy.mock.calls.filter(
      ([, opts]) => (opts as { op?: string })?.op === "extractPdfText",
    );
    expect(sentryCalls.length).toBe(1);
  });

  it("missing PDF file falls through to documentKind=pdf without content", async () => {
    // No file on disk — the resolver should NOT throw. It falls through to
    // the Read directive (matching pre-#3338 behavior).
    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/missing.pdf",
    });
    expect(out).toEqual({
      artifactPath: "knowledge-base/missing.pdf",
      documentKind: "pdf",
    });
    // Extractor never called when readFile fails.
    expect(extractPdfTextSpy).not.toHaveBeenCalled();
  });

  it("uses the extractor's truncated text when output exceeds the inline cap", async () => {
    // The extractor enforces the cap and returns truncated:true; the
    // resolver still inlines what it has — better than the Read-directive
    // path (no body at all).
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "big.pdf"),
      Buffer.from("%PDF-1.4\nfake"),
    );
    const cappedBody = "x".repeat(50_000);
    extractPdfTextSpy.mockResolvedValueOnce({
      text: cappedBody,
      truncated: true,
      pageCount: 400,
    });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/big.pdf",
    });
    expect(out.artifactPath).toBe("knowledge-base/big.pdf");
    expect(out.documentKind).toBe("pdf");
    expect(out.documentContent?.length).toBe(50_000);
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

  it("rejects paths outside the knowledge-base/ subtree (returns {})", async () => {
    // Defense-in-depth: the resolver scopes every read to knowledge-base/.
    // A UI bug (or malicious client) requesting attachments/, .git/, etc.
    // gets dropped entirely — no path leakage into the LLM prompt.
    for (const path of [
      "attachments/other-conv/secret.txt",
      ".git/config",
      ".claude/settings.json",
      "knowledge_base/typo.md", // underscore, not dash
      "etc/passwd",
    ]) {
      const out = await resolveConciergeDocumentContext({
        userId: "u1",
        contextPath: path,
      });
      expect(out).toEqual({});
    }
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
