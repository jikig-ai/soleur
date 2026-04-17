// Regression / characterization test for the 23505 index-name
// disambiguation guard in createConversation. The guard already shipped in
// #2382 (see `server/ws-handler.ts` `isContextPathUniqueViolation`). This
// test locks the behaviour so a future refactor cannot regress back to
// the bug the reviewers flagged in issue #2390 item 10D: a 23505 on an
// UNRELATED unique constraint (e.g., `conversations_pkey` id collision)
// was falling through into the context_path lookup and returning a
// neighbour's conversation id.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi } from "vitest";

// ws-handler.ts creates its Supabase client at module load. Stub it so
// importing the pure guard below does not attempt a real connection.
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: vi.fn(),
    auth: { getUser: vi.fn() },
  }),
  serverUrl: "https://test.supabase.co",
}));

// Stub agent-runner so importing ws-handler does not pull in
// @anthropic-ai/claude-agent-sdk for a pure-function test.
vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

import { isContextPathUniqueViolation } from "../server/ws-handler";

describe("isContextPathUniqueViolation (#2382 / #2390 10D)", () => {
  it("returns true for a 23505 on the context_path partial UNIQUE index", () => {
    const err = {
      code: "23505",
      message:
        "duplicate key value violates unique constraint \"conversations_context_path_user_uniq\"",
      details: null,
    };
    expect(isContextPathUniqueViolation(err)).toBe(true);
  });

  it("returns FALSE for a 23505 on conversations_pkey (id collision)", () => {
    const err = {
      code: "23505",
      message:
        "duplicate key value violates unique constraint \"conversations_pkey\"",
      details: null,
    };
    // The guard MUST reject this so createConversation re-throws instead of
    // silently returning a different user's/context_path's conversation id.
    expect(isContextPathUniqueViolation(err)).toBe(false);
  });

  it("returns FALSE for a 23505 on any other unique constraint", () => {
    const err = {
      code: "23505",
      message:
        "duplicate key value violates unique constraint \"some_other_index\"",
    };
    expect(isContextPathUniqueViolation(err)).toBe(false);
  });

  it("returns FALSE for non-23505 errors", () => {
    expect(
      isContextPathUniqueViolation({ code: "23502", message: "not null violation" }),
    ).toBe(false);
    expect(
      isContextPathUniqueViolation({ code: "42P01", message: "relation does not exist" }),
    ).toBe(false);
  });

  it("returns FALSE for null / undefined / non-object inputs", () => {
    expect(isContextPathUniqueViolation(null)).toBe(false);
    expect(isContextPathUniqueViolation(undefined)).toBe(false);
    expect(isContextPathUniqueViolation("23505")).toBe(false);
  });

  it("returns FALSE for a 23505 with a missing message", () => {
    expect(isContextPathUniqueViolation({ code: "23505" })).toBe(false);
    expect(
      isContextPathUniqueViolation({ code: "23505", message: null as unknown as string }),
    ).toBe(false);
  });
});
