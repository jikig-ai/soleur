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

  it("falls through to documentKind=pdf without content when extractor errors (with errorClass)", async () => {
    // Corrupted, encrypted, or oversized PDFs surface a typed
    // `{ error: <class> }` from the extractor; the resolver falls through
    // to the runner with `documentExtractError` set and mirrors a Sentry
    // event tagged with the same class so operators see WHICH failure
    // shape fired without parsing breadcrumbs.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "scanned.pdf"),
      Buffer.from("%PDF-1.4\ncorrupted"),
    );
    extractPdfTextSpy.mockResolvedValueOnce({ error: "corrupted" });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/scanned.pdf",
    });
    expect(out).toEqual({
      artifactPath: "knowledge-base/scanned.pdf",
      documentKind: "pdf",
      documentExtractError: "corrupted",
    });
    // Sentry mirror MUST fire so a degraded extractor path is observable
    // (per cq-silent-fallback-must-mirror-to-sentry).
    const sentryCalls = reportSilentFallbackSpy.mock.calls.filter(
      ([, opts]) => (opts as { op?: string })?.op === "extractPdfText",
    );
    expect(sentryCalls.length).toBe(1);
    // The errorClass MUST be on extra so operators read it directly off the
    // event without breadcrumb parsing.
    const [[, opts]] = sentryCalls as Array<
      [unknown, { extra?: { errorClass?: unknown } }]
    >;
    expect(opts.extra?.errorClass).toBe("corrupted");
  });

  it("mirrors empty_text distinctly via op: extractPdfText.empty_text", async () => {
    // Hypothesis B fold-in: a parsed-but-empty PDF (scanned image-only) is
    // its own failure class. Pre-fix, the resolver swallowed
    // text.length === 0 silently — no Sentry mirror — and the agent ran
    // into the apt-get cascade with no observability hook. Post-fix, the
    // extractor returns { error: "empty_text" } and the resolver mirrors
    // distinctly so Hypothesis B is distinguishable from Hypothesis A.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "image-only.pdf"),
      Buffer.from("%PDF-1.4\nfake"),
    );
    extractPdfTextSpy.mockResolvedValueOnce({
      error: "empty_text",
      pageCount: 12,
    });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/image-only.pdf",
    });
    expect(out).toEqual({
      artifactPath: "knowledge-base/image-only.pdf",
      documentKind: "pdf",
      documentExtractError: "empty_text",
    });
    const sentryCalls = reportSilentFallbackSpy.mock.calls.filter(
      ([, opts]) =>
        (opts as { op?: string })?.op === "extractPdfText.empty_text",
    );
    expect(sentryCalls.length).toBe(1);
    const [[, opts]] = sentryCalls as Array<
      [unknown, { extra?: { errorClass?: unknown; pageCount?: unknown } }]
    >;
    expect(opts.extra?.errorClass).toBe("empty_text");
    expect(opts.extra?.pageCount).toBe(12);
  });

  it("encrypted PDFs surface documentExtractError=encrypted with a Sentry mirror", async () => {
    // Pinned in plan §Hypothesis C. The extractor's outer catch maps
    // pdfjs's PasswordException via `err.name === "PasswordException"`;
    // synthesizing spec-correct AES-128 in pure JS is disproportionate, so
    // the extractor-level test relies on this resolver-level mock to pin
    // the contract (`{ error: "encrypted" }` → documentExtractError +
    // Sentry op: extractPdfText).
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "locked.pdf"),
      Buffer.from("%PDF-1.4\nfake"),
    );
    extractPdfTextSpy.mockResolvedValueOnce({ error: "encrypted" });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/locked.pdf",
    });
    expect(out.documentExtractError).toBe("encrypted");
    expect(out.documentContent).toBeUndefined();
    const sentryCalls = reportSilentFallbackSpy.mock.calls.filter(
      ([, opts]) => (opts as { op?: string })?.op === "extractPdfText",
    );
    expect(sentryCalls.length).toBe(1);
    const [[, opts]] = sentryCalls as Array<
      [unknown, { extra?: { errorClass?: unknown } }]
    >;
    expect(opts.extra?.errorClass).toBe("encrypted");
  });

  it("lazy_import_failed (broken runner image) surfaces documentExtractError + Sentry mirror", async () => {
    // Production runner images can fail to lazy-load `pdfjs-dist` (broken
    // native dep, missing libstdc++). The extractor catches and returns
    // `{ error: "lazy_import_failed" }`. Pinned via mock — the actual
    // import failure is environment-specific and not reproducible in the
    // test runner.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "any.pdf"),
      Buffer.from("%PDF-1.4\nfake"),
    );
    extractPdfTextSpy.mockResolvedValueOnce({ error: "lazy_import_failed" });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/any.pdf",
    });
    expect(out.documentExtractError).toBe("lazy_import_failed");
    const sentryCalls = reportSilentFallbackSpy.mock.calls.filter(
      ([, opts]) => (opts as { op?: string })?.op === "extractPdfText",
    );
    expect(sentryCalls.length).toBe(1);
    const [[, opts]] = sentryCalls as Array<
      [unknown, { extra?: { errorClass?: unknown } }]
    >;
    expect(opts.extra?.errorClass).toBe("lazy_import_failed");
  });

  it("oversized_buffer surfaces documentExtractError so the runner can pick the user-facing message", async () => {
    // Hypothesis A regression: the failure class flows through the resolver
    // so the runner emits a content-grounded "this PDF is too large" reply
    // instead of the apt-get cascade. Pre-fix, oversized was indistinguishable
    // from corrupted from the runner's perspective.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "huge.pdf"),
      Buffer.from("%PDF-1.4\nfake"),
    );
    extractPdfTextSpy.mockResolvedValueOnce({ error: "oversized_buffer" });

    const out = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/huge.pdf",
    });
    expect(out.documentExtractError).toBe("oversized_buffer");
    expect(out.documentContent).toBeUndefined();
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

  it("inlines the extractor's body when truncated=true is reported", async () => {
    // The resolver passes the extractor's body through verbatim — even when
    // truncated=true. Better than the Read-directive path (no body at all).
    // Test pins the contract (resolver inlines what extractor returned),
    // not the cap constant.
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
    expect(out.documentContent?.length).toBe(cappedBody.length);
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
