/**
 * Phase 1 (#3287) — Sentry breadcrumb at the cc-soleur-go cold-Query
 * construction site.
 *
 * Pins the diagnostic instrumentation that ws-handler.ts emits at the
 * `dispatchSoleurGoForConversation` document-resolution gate so two
 * production reproductions of the poppler-utils install cascade can
 * disambiguate hypothesis A (directive missed cold-Query construction) from
 * hypothesis B (directive present, model overrode it).
 *
 * Tested via the exported helper `emitConciergeDocumentResolutionBreadcrumb`
 * — pure side-effecting function. No real Sentry, supabase, or agent-runner
 * traffic.
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";

const addBreadcrumbSpy = vi.fn();
const captureMessageSpy = vi.fn();

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: (...args: unknown[]) => addBreadcrumbSpy(...args),
  captureMessage: (...args: unknown[]) => captureMessageSpy(...args),
  captureException: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: vi.fn(),
    auth: { getUser: vi.fn() },
  }),
  serverUrl: "https://test.supabase.co",
}));

vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

import { emitConciergeDocumentResolutionBreadcrumb } from "../server/ws-handler";

beforeEach(() => {
  addBreadcrumbSpy.mockClear();
  captureMessageSpy.mockClear();
});

describe("emitConciergeDocumentResolutionBreadcrumb (#3287 Phase 1)", () => {
  it("Scenario 1: PDF cold-Query — fires breadcrumb with documentKind=pdf", () => {
    emitConciergeDocumentResolutionBreadcrumb({
      conversationId: "conv-pdf-1",
      contextPath: "knowledge-base/overview/book.pdf",
      hasActiveCcQuery: false,
      documentArgs: {
        artifactPath: "knowledge-base/overview/book.pdf",
        documentKind: "pdf",
      },
      routingKind: "soleur_go_pending",
    });

    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    expect(captureMessageSpy).not.toHaveBeenCalled();

    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    expect(crumb).toMatchObject({
      category: "cc-pdf-resolver",
      level: "info",
      message: "concierge document context resolved",
      data: expect.objectContaining({
        hasContextPath: true,
        pathBasename: "book.pdf",
        pathExtension: "pdf",
        hasActiveCcQuery: false,
        documentKindResolved: "pdf",
        documentContentBytes: 0,
        conversationId: "conv-pdf-1",
        routingKind: "soleur_go_pending",
      }),
    });
  });

  it("Scenario 2: text cold-Query — fires breadcrumb with documentKind=text", () => {
    emitConciergeDocumentResolutionBreadcrumb({
      conversationId: "conv-text-1",
      contextPath: "knowledge-base/notes.md",
      hasActiveCcQuery: false,
      documentArgs: {
        artifactPath: "knowledge-base/notes.md",
        documentKind: "text",
        documentContent: "hello world",
      },
      routingKind: "soleur_go_pending",
    });

    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    expect(captureMessageSpy).not.toHaveBeenCalled();

    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    expect(crumb.data).toMatchObject({
      hasContextPath: true,
      pathBasename: "notes.md",
      pathExtension: "md",
      documentKindResolved: "text",
      documentContentBytes: "hello world".length,
    });
  });

  it("Scenario 3: no context.path — fires breadcrumb with hasContextPath=false", () => {
    emitConciergeDocumentResolutionBreadcrumb({
      conversationId: "conv-no-ctx",
      contextPath: undefined,
      hasActiveCcQuery: false,
      documentArgs: {},
      routingKind: "soleur_go_pending",
    });

    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    expect(captureMessageSpy).not.toHaveBeenCalled();

    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    expect(crumb.data).toMatchObject({
      hasContextPath: false,
      pathBasename: null,
      pathExtension: null,
      hasActiveCcQuery: false,
      documentKindResolved: null,
      documentContentBytes: 0,
    });
  });

  it("Scenario 4: warm cc-Query skip — fires breadcrumb with hasActiveCcQuery=true and no captureMessage", () => {
    // Resolver is deliberately skipped on warm turns; documentArgs is empty
    // by construction. This must NOT trigger the suspicious-skip warning —
    // a warm-turn skip is the documented happy path.
    emitConciergeDocumentResolutionBreadcrumb({
      conversationId: "conv-warm",
      contextPath: "knowledge-base/overview/book.pdf",
      hasActiveCcQuery: true,
      documentArgs: {},
      routingKind: "soleur_go_active",
    });

    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    expect(captureMessageSpy).not.toHaveBeenCalled();

    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    expect(crumb.data).toMatchObject({
      hasContextPath: true,
      hasActiveCcQuery: true,
      documentKindResolved: null,
    });
  });

  it("Scenario 5: suspicious-skip — path present, resolver returned {}, fires warning captureMessage", () => {
    // Cold Query (hasActiveCcQuery=false) AND hasContextPath=true AND
    // documentKindResolved=null is the suspicious branch the plan calls out:
    // the resolver dropped a path it should have classified. Pair the
    // breadcrumb with a level=warning Sentry event so the gap surfaces in
    // dashboards without log diving.
    emitConciergeDocumentResolutionBreadcrumb({
      conversationId: "conv-suspicious",
      contextPath: "knowledge-base/overview/book.pdf",
      hasActiveCcQuery: false,
      documentArgs: {},
      routingKind: "soleur_go_pending",
    });

    expect(addBreadcrumbSpy).toHaveBeenCalledTimes(1);
    expect(captureMessageSpy).toHaveBeenCalledTimes(1);

    const [message, options] = captureMessageSpy.mock.calls[0]!;
    expect(message).toMatch(/cc-pdf-resolver-skip/i);
    expect(options).toMatchObject({
      level: "warning",
      tags: expect.objectContaining({
        feature: "cc-pdf-resolver-skip",
      }),
    });
  });

  it("does not leak directory portions of context.path into breadcrumb data", () => {
    // KB paths can carry user-identifying directory segments
    // (knowledge-base/customers/<name>/...). Per kb-document-resolver.ts
    // precedent, log only the basename and extension — never the full path.
    emitConciergeDocumentResolutionBreadcrumb({
      conversationId: "conv-priv",
      contextPath: "knowledge-base/customers/jane-doe-financials/q1.pdf",
      hasActiveCcQuery: false,
      documentArgs: {
        artifactPath: "knowledge-base/customers/jane-doe-financials/q1.pdf",
        documentKind: "pdf",
      },
      routingKind: "soleur_go_pending",
    });

    const [crumb] = addBreadcrumbSpy.mock.calls[0]!;
    const dataJson = JSON.stringify(crumb.data);
    expect(dataJson).not.toContain("customers");
    expect(dataJson).not.toContain("jane-doe");
    expect(crumb.data.pathBasename).toBe("q1.pdf");
  });
});
