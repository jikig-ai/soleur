// End-to-end regression coverage for #3376 — sidebar Concierge fails to
// summarize a workspace PDF with "I can't read this specific PDF — the
// file is outside my workspace boundary".
//
// Locks the resolver-to-system-prompt path: take the same shape the
// resolver returns and feed it to `buildSoleurGoSystemPrompt`. Asserts
// that:
//
// - Successful extraction → inline `<document>` body, NEVER the gated
//   Read directive (Phase 4.1).
// - readFile failure → unreadable directive with `read_failed` copy,
//   NEVER the gated Read directive AND NEVER the substring "outside" /
//   "workspace boundary" (Phase 4.2).
// - Every Read instruction in the system prompt injects an absolute
//   path (Bug A1 fix — Phase 4.3).
//
// The resolver is exercised against a real tmp filesystem. The runner is
// not started (no SDK Query); we synthesize the system prompt directly.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  mkdtempSync,
  realpathSync,
  rmSync,
  mkdirSync,
  writeFileSync,
} from "fs";
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
import {
  buildSoleurGoSystemPrompt,
  PDF_GATED_DIRECTIVE_LEAD,
  PDF_UNREADABLE_DIRECTIVE_LEAD,
} from "@/server/soleur-go-runner";
import { _resetWorkspacePathCacheForTests } from "@/server/kb-document-resolver";

let tmpRoot: string;

beforeEach(() => {
  // Wrap in realpathSync so macOS `/var/folders/...` → `/private/var/folders/...`
  // aliasing matches the absolute path the runner injects. Without this,
  // `startsWith(tmpRoot)` assertions in Phase 4.3/4.3b fail on macOS.
  tmpRoot = realpathSync(mkdtempSync(path.join(tmpdir(), "concierge-pdf-e2e-")));
  fetchUserWorkspacePathSpy.mockResolvedValue({
    data: { workspace_path: tmpRoot },
    error: null,
  });
  extractPdfTextSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  _resetWorkspacePathCacheForTests();
});

afterEach(() => {
  rmSync(tmpRoot, { recursive: true, force: true });
  vi.clearAllMocks();
});

describe("cc-concierge PDF summarize end-to-end (#3376)", () => {
  it("Phase 4.1 — successful extraction inlines the body and DOES NOT emit the gated Read directive", async () => {
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

    const documentArgs = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/book.pdf",
    });
    expect(documentArgs.documentContent).toContain("Chapter 1");

    const systemPrompt = buildSoleurGoSystemPrompt({
      artifactPath: documentArgs.artifactPath,
      documentKind: documentArgs.documentKind,
      documentContent: documentArgs.documentContent,
      workspacePath: tmpRoot,
    });

    expect(systemPrompt).toContain("<document>");
    expect(systemPrompt).toContain("Chapter 1");
    expect(systemPrompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    expect(systemPrompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
  });

  it("Phase 4.2 — readFile failure surfaces unreadable directive with read_failed copy and NO 'workspace boundary' string", async () => {
    // Filename drift: persisted contextPath uses spaces, on-disk file is
    // URL-encoded. The resolver's `readFile` raises ENOENT — exactly the
    // shape that produced the user-facing "outside workspace boundary"
    // reply pre-fix.
    mkdirSync(path.join(tmpRoot, "knowledge-base"), { recursive: true });
    writeFileSync(
      path.join(tmpRoot, "knowledge-base", "Au%20Chat%20Potan.pdf"),
      Buffer.from("%PDF-1.4\nfake"),
    );

    const documentArgs = await resolveConciergeDocumentContext({
      userId: "u1",
      contextPath: "knowledge-base/Au Chat Potan.pdf",
    });

    expect(documentArgs.documentExtractError).toBe("read_failed");

    const systemPrompt = buildSoleurGoSystemPrompt({
      artifactPath: documentArgs.artifactPath,
      documentKind: documentArgs.documentKind,
      documentContent: documentArgs.documentContent,
      documentExtractError: documentArgs.documentExtractError,
      workspacePath: tmpRoot,
    });

    // Unreadable directive fired.
    expect(systemPrompt).toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    // The new read_failed copy is present (verbatim from
    // `unreadableCopyForClass`).
    expect(systemPrompt).toContain(
      "I couldn't open this PDF on my end — the file path may have changed",
    );
    // Gated Read directive MUST be absent — its presence would mean the
    // runner picked the apt-get-cascade-prone Read path.
    expect(systemPrompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    // Hard load-bearing assertion: the system prompt must NEVER contain
    // sandbox-internal substrings that the model could paraphrase to the
    // user. This is the user-facing leak from #3376.
    expect(systemPrompt.toLowerCase()).not.toContain("workspace boundary");
    expect(systemPrompt.toLowerCase()).not.toContain("outside the workspace");
  });

  it("Phase 4.3 — Bug A1: gated Read directive injects an absolute path (no relative-path Read instructions)", async () => {
    // No documentContent threaded in (e.g., extractor returned an over-
    // cap body with truncated=true that the resolver chose to pass
    // through, OR a future code path lands a bare PDF context). The
    // gated directive fires; its `Use the Read tool to read "..."`
    // substring MUST embed an absolute path so the SDK Read contract
    // is honored and the sandbox-hook does not deny.
    const systemPrompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/book.pdf",
      documentKind: "pdf",
      // No documentContent — runner falls through to gated directive.
      workspacePath: tmpRoot,
    });

    expect(systemPrompt).toContain(PDF_GATED_DIRECTIVE_LEAD);

    // Every Read instruction must inject an absolute path. Match all
    // `Use the Read tool to read "..."` substrings; assert each path
    // starts with `/`.
    const readInstructions = Array.from(
      systemPrompt.matchAll(/Use the Read tool to read "([^"]+)"/g),
    );
    expect(readInstructions.length).toBeGreaterThanOrEqual(1);
    for (const match of readInstructions) {
      expect(match[1]).toMatch(/^\/[^"]+/);
      // Specifically must be inside the test workspace.
      expect(match[1]?.startsWith(tmpRoot)).toBe(true);
    }
  });

  it("Phase 4.3b — text-too-large fallback also injects an absolute Read path", async () => {
    // Text branch fall-through: a 60KB text body exceeds the inline cap;
    // the runner emits the text-too-large Read directive. Must inject
    // an absolute path (Bug A1 lock-step parity with PDF directive).
    const oversizedBody = "x".repeat(60_000);
    const systemPrompt = buildSoleurGoSystemPrompt({
      artifactPath: "knowledge-base/big.md",
      documentKind: "text",
      documentContent: oversizedBody,
      workspacePath: tmpRoot,
    });

    const readInstructions = Array.from(
      systemPrompt.matchAll(/Use the Read tool to read "([^"]+)"/g),
    );
    expect(readInstructions.length).toBeGreaterThanOrEqual(1);
    for (const match of readInstructions) {
      expect(match[1]).toMatch(/^\/[^"]+/);
      expect(match[1]?.startsWith(tmpRoot)).toBe(true);
    }
  });
});
