import { vi, type Mock } from "vitest";

/**
 * #3641 F5 — Shared mock scaffolding for cc-dispatcher test files.
 *
 * Both `cc-dispatcher.test.ts` (full 6/6 mock overlap) and
 * `cc-dispatcher-cost.test.ts` (5/6 overlap — omits the `mirrorP0Deduped`
 * spy because it doesn't exercise the W4-orphan path) re-hoisted nearly
 * identical `vi.mock(...)` factory bodies covering the five modules
 * `dispatchSoleurGo` touches: observability, conversation-writer,
 * supabase service, cost-writer, kb-document-resolver. This module
 * centralises those factory bodies.
 *
 * **Hoisting contract** — `vi.mock` is hoisted ABOVE module imports, and
 * so is `vi.hoisted`. The harness file is itself a module the test
 * imports; the test's `vi.mock("...", async () => { const { factory } =
 * await import("@/test/helpers/cc-dispatcher-harness"); return
 * factory({...spies}); })` pattern works because vitest awaits the
 * `vi.mock` factory before resolving the SUT's import graph. The harness
 * itself does NOT call `vi.hoisted` or `vi.mock` — only the test does.
 *
 * Spies are still declared in each consumer test file via `vi.hoisted(() =>
 * ({ mockReportSilentFallback: vi.fn(), ... }))` so the test body can
 * assert against them directly. Each factory takes the relevant spies as
 * parameters and wires them onto the production module's export shape.
 *
 * Five sibling `cc-dispatcher-*.test.ts` files (bash-gate,
 * concierge-context, prefill-guard, real-factory, session-id-writer)
 * stay on bespoke hoists per the plan's harness consumer scoping (1/6
 * mock overlap each — migration would be churn).
 */

export async function observabilityFactory(opts: {
  mockReportSilentFallback: Mock;
  mockMirrorP0Deduped: Mock;
  /** When true, layer a real `TtlDedupMap` over `mirrorWithDebounce`
   *  so the spy `mockReportSilentFallback` honours the 5-minute TTL
   *  (used by cc-dispatcher.test.ts's 3-call-→-1-mirror invariant).
   *  When false, `mirrorWithDebounce` collapses to the spy directly
   *  (cc-dispatcher-cost.test.ts pattern). */
  withTtlDedupWrapper?: boolean;
}): Promise<Record<string, unknown>> {
  const { mockReportSilentFallback, mockMirrorP0Deduped, withTtlDedupWrapper } =
    opts;
  const actual = await vi.importActual<
    typeof import("@/server/observability")
  >("@/server/observability");
  const mirrorWithDebounce = withTtlDedupWrapper
    ? (() => {
        // Reuse the real `TtlDedupMap` (#3639 F3) so the wrapper's dedup
        // bookkeeping stays in lockstep with production — if the
        // TTL/sweep semantics ever change, the 3-call-→-1-mirror
        // assertion in cc-dispatcher.test.ts will not silently drift.
        const dedup = new actual.TtlDedupMap<string>(
          actual.MIRROR_DEBOUNCE_MS,
          Infinity,
        );
        return (
          err: unknown,
          ctx: unknown,
          userId: string,
          errorClass: string,
        ) => {
          if (!dedup.tryClaim(`${userId}:${errorClass}`, Date.now())) return;
          mockReportSilentFallback(err, ctx);
        };
      })()
    : mockReportSilentFallback;
  return {
    ...actual,
    reportSilentFallback: mockReportSilentFallback,
    warnSilentFallback: vi.fn(),
    mirrorWithDebounce,
    mirrorP0Deduped: mockMirrorP0Deduped,
  };
}

export async function conversationWriterFactory(opts: {
  mockUpdateConversationFor: Mock;
}): Promise<Record<string, unknown>> {
  const actual = await vi.importActual<
    typeof import("@/server/conversation-writer")
  >("@/server/conversation-writer");
  return {
    ...actual,
    updateConversationFor: opts.mockUpdateConversationFor,
  };
}

export function costWriterFactory(opts: {
  mockPersistTurnCost?: Mock;
} = {}): Record<string, unknown> {
  return {
    persistTurnCost: opts.mockPersistTurnCost ?? vi.fn(),
  };
}

export async function kbDocumentResolverFactory(opts: {
  mockFetchUserWorkspacePath: Mock;
}): Promise<Record<string, unknown>> {
  const actual = await vi.importActual<
    typeof import("@/server/kb-document-resolver")
  >("@/server/kb-document-resolver");
  return {
    ...actual,
    fetchUserWorkspacePath: opts.mockFetchUserWorkspacePath,
  };
}

export function supabaseServiceFactory(opts: {
  mockMessagesInsert: Mock;
}): Record<string, unknown> {
  return {
    serverUrl: () => "https://test.supabase.co",
    createServiceClient: () => ({
      from: (table: string) => {
        if (table === "messages") {
          return { insert: opts.mockMessagesInsert };
        }
        throw new Error(`unexpected table in cc-dispatcher harness: ${table}`);
      },
      storage: {
        from: () => ({ download: vi.fn() }),
      },
    }),
  };
}
