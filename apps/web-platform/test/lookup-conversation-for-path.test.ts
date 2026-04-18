import { describe, test, expect, vi, beforeEach } from "vitest";

// RED phase for #2511 — single-query collapse.
//
// Contract (from plan Phase 3):
//   lookupConversationForPath makes exactly ONE Supabase round-trip using
//   a PostgREST embedded-resource aggregate:
//     .select("id, context_path, last_active, messages(count)")
//   The response shape `messages: [{ count: N }]` maps to
//   `message_count: N` on the returned row. Count of ZERO must come through
//   as `messageCount: 0`, not null/undefined. The embed may also be `null`
//   due to postgrest-js 2.99 strict-type generics (also maps to 0).
//
//   `LookupConversationResult` no longer includes `"count_failed"` — the
//   single call collapses both error sources into `"lookup_failed"`.

const { mockFrom, mockReportSilentFallback } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

async function importHelper() {
  return await import("@/server/lookup-conversation-for-path");
}

/**
 * Build a mock chain that terminates at .maybeSingle(). Captures the
 * .select() argument so tests can assert the query shape.
 */
function mockSingleChain(result: { data: unknown; error: unknown }) {
  const calls = { select: [] as unknown[] };
  const chain = {
    select: vi.fn((arg: unknown) => {
      calls.select.push(arg);
      return chain;
    }),
    eq: vi.fn(() => chain),
    is: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => chain),
    maybeSingle: vi.fn(async () => result),
  };
  mockFrom.mockImplementation(() => chain);
  return { chain, calls };
}

describe("lookupConversationForPath — single-query collapse (#2511)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("hit path: pins message_count to the exact embedded aggregate value", async () => {
    mockSingleChain({
      data: {
        id: "conv-1",
        context_path: "knowledge-base/x.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 7 }],
      },
      error: null,
    });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath("u1", "knowledge-base/x.md");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.row).not.toBeNull();
    // Pin exact value — rule cq-mutation-assertions-pin-exact-post-state.
    expect(result.row?.message_count).toBe(7);
    expect(result.row?.id).toBe("conv-1");
    expect(result.row?.context_path).toBe("knowledge-base/x.md");
  });

  test("hit path: issues exactly ONE Supabase call (single round-trip)", async () => {
    mockSingleChain({
      data: {
        id: "conv-1",
        context_path: "knowledge-base/x.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 3 }],
      },
      error: null,
    });

    const { lookupConversationForPath } = await importHelper();
    await lookupConversationForPath("u1", "knowledge-base/x.md");

    // `from("conversations")` must be called exactly once — the removed
    // second `from("messages")` call MUST NOT exist.
    expect(mockFrom).toHaveBeenCalledTimes(1);
    expect(mockFrom).toHaveBeenCalledWith("conversations");
  });

  test("hit path: .select() string includes PostgREST embedded aggregate `messages(count)`", async () => {
    const { calls } = mockSingleChain({
      data: {
        id: "conv-1",
        context_path: "knowledge-base/x.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 1 }],
      },
      error: null,
    });

    const { lookupConversationForPath } = await importHelper();
    await lookupConversationForPath("u1", "knowledge-base/x.md");

    // The embed syntax is the load-bearing claim of #2511. Regex-assert it.
    expect(calls.select).toHaveLength(1);
    expect(String(calls.select[0])).toMatch(/messages\(count\)/);
  });

  test("zero-messages edge: count 0 returns message_count: 0 (exact)", async () => {
    mockSingleChain({
      data: {
        id: "conv-empty",
        context_path: "knowledge-base/x.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 0 }],
      },
      error: null,
    });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath("u1", "knowledge-base/x.md");
    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    // .toBe(0) — not .toBeFalsy(), not .toContain. Rule pin.
    expect(result.row?.message_count).toBe(0);
  });

  test("null-embed edge: postgrest-js generics quirk maps to 0 via ?? fallback", async () => {
    mockSingleChain({
      data: {
        id: "conv-x",
        context_path: "knowledge-base/x.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: null,
      },
      error: null,
    });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath("u1", "knowledge-base/x.md");
    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.row?.message_count).toBe(0);
  });

  test("miss path: null data yields { ok: true, row: null } with one call", async () => {
    mockSingleChain({ data: null, error: null });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath("u1", "knowledge-base/x.md");
    expect(result).toEqual({ ok: true, row: null });
    expect(mockFrom).toHaveBeenCalledTimes(1);
  });

  test("error path: Supabase error returns { ok: false, error: 'lookup_failed' } + Sentry mirror", async () => {
    const err = { message: "db explode", code: "PGRST" };
    mockSingleChain({ data: null, error: err });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath("u1", "knowledge-base/x.md");
    expect(result).toEqual({ ok: false, error: "lookup_failed" });
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [errArg, optsArg] = mockReportSilentFallback.mock.calls[0];
    expect(errArg).toBe(err);
    expect(optsArg).toMatchObject({
      feature: "kb-chat",
      op: "conversation-lookup",
    });
  });

});
