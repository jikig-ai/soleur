// Set env vars BEFORE dynamic imports — ws-handler.ts creates its
// service-role Supabase client at module load.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach } from "vitest";
import { WS_CLOSE_CODES } from "@/lib/types";
import { TC_VERSION } from "@/lib/legal/tc-version";

// Plan AC6/AC11: gated inbound message types must re-check
// users.tc_accepted_version mid-session. After a TC_VERSION bump,
// the socket closes with 4004 (TC_NOT_ACCEPTED) on the next gated
// message. abort_turn + close_conversation are EXEMPT (RC8): a user
// must always be able to stop a stream / close a conversation even
// with stale consent — refusing those would worsen UX without
// changing GDPR demonstrability.
//
// A 30-second in-process cache keyed on userId means up to 30 s of
// stale-consent agent traffic can pass between bump and enforcement;
// that's the explicit trade-off documented in AC6.

const {
  mockServiceFrom,
} = vi.hoisted(() => ({
  mockServiceFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockServiceFrom,
    auth: { getUser: vi.fn() },
  }),
  serverUrl: "https://test.supabase.co",
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
}));

// Stub the agent-runner so module-load doesn't require the SDK.
vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { recheckTcMidSession, TC_RECHECK_CACHE_MS, type ClientSession } from "@/server/ws-handler";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

interface MockWs {
  readyState: number;
  send: ReturnType<typeof vi.fn>;
  close: ReturnType<typeof vi.fn>;
  ping: ReturnType<typeof vi.fn>;
}

function makeSession(overrides: Partial<ClientSession> = {}): ClientSession {
  const ws: MockWs = {
    readyState: 1,
    send: vi.fn(),
    close: vi.fn(),
    ping: vi.fn(),
  };
  return {
    ws: ws as unknown as ClientSession["ws"],
    lastActivity: Date.now(),
    ...overrides,
  } as ClientSession;
}

function stubUsersSelect(version: string | null) {
  const single = vi.fn().mockResolvedValue({
    data: { tc_accepted_version: version },
    error: null,
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  mockServiceFrom.mockReturnValue({ select });
  return { single, select, eq };
}

const GATED_TYPES = [
  "start_session",
  "resume_session",
  "chat",
  "interactive_prompt_response",
  "review_gate_response",
] as const;

const EXEMPT_TYPES = ["abort_turn", "close_conversation"] as const;

beforeEach(() => {
  vi.clearAllMocks();
});

describe("recheckTcMidSession — gated message types (AC6/AC11)", () => {
  test.each(GATED_TYPES)(
    "stale tc_accepted_version on %s → ws.close(TC_NOT_ACCEPTED)",
    async (msgType) => {
      stubUsersSelect("0.9.0-stale"); // != TC_VERSION
      const session = makeSession();

      const closed = await recheckTcMidSession("user-1", session, msgType);

      expect(closed).toBe(true);
      const mockWs = session.ws as unknown as MockWs;
      expect(mockWs.close).toHaveBeenCalledWith(
        WS_CLOSE_CODES.TC_NOT_ACCEPTED,
        expect.any(String),
      );
    },
  );

  test.each(GATED_TYPES)(
    "current tc_accepted_version on %s → does NOT close socket",
    async (msgType) => {
      stubUsersSelect(TC_VERSION);
      const session = makeSession();

      const closed = await recheckTcMidSession("user-1", session, msgType);

      expect(closed).toBe(false);
      const mockWs = session.ws as unknown as MockWs;
      expect(mockWs.close).not.toHaveBeenCalled();
    },
  );
});

describe("recheckTcMidSession — exempt message types (AC6 / RC8)", () => {
  test.each(EXEMPT_TYPES)(
    "stale tc_accepted_version on %s → does NOT close socket",
    async (msgType) => {
      stubUsersSelect("0.9.0-stale");
      const session = makeSession();

      const closed = await recheckTcMidSession("user-1", session, msgType);

      expect(closed).toBe(false);
      const mockWs = session.ws as unknown as MockWs;
      expect(mockWs.close).not.toHaveBeenCalled();
      // Exempt types short-circuit before the DB query — no SELECT.
      expect(mockServiceFrom).not.toHaveBeenCalled();
    },
  );
});

describe("recheckTcMidSession — 30s cache (AC11)", () => {
  test("two gated messages within 30 s → users SELECT runs exactly once", async () => {
    const { single } = stubUsersSelect(TC_VERSION);
    const session = makeSession();

    await recheckTcMidSession("user-1", session, "chat");
    await recheckTcMidSession("user-1", session, "chat");

    expect(single).toHaveBeenCalledTimes(1);
    expect(session.tcRecheckCacheUntil).toBeGreaterThan(Date.now());
  });

  test("gated message after cache expiry → SELECT runs again", async () => {
    const { single } = stubUsersSelect(TC_VERSION);
    const session = makeSession();

    await recheckTcMidSession("user-1", session, "chat");
    // Force cache expiry by rewinding tcRecheckCacheUntil into the past.
    session.tcRecheckCacheUntil = Date.now() - 1;
    await recheckTcMidSession("user-1", session, "chat");

    expect(single).toHaveBeenCalledTimes(2);
  });

  test("cache TTL is 30 seconds", () => {
    expect(TC_RECHECK_CACHE_MS).toBe(30_000);
  });
});

describe("recheckTcMidSession — DB error on gated type", () => {
  test("supabase SELECT error → closes socket (fail-closed)", async () => {
    const single = vi.fn().mockResolvedValue({
      data: null,
      error: { message: "ECONNRESET" },
    });
    const eq = vi.fn().mockReturnValue({ single });
    const select = vi.fn().mockReturnValue({ eq });
    mockServiceFrom.mockReturnValue({ select });

    const session = makeSession();
    const closed = await recheckTcMidSession("user-1", session, "chat");

    expect(closed).toBe(true);
    const mockWs = session.ws as unknown as MockWs;
    expect(mockWs.close).toHaveBeenCalledWith(
      WS_CLOSE_CODES.TC_NOT_ACCEPTED,
      expect.any(String),
    );
  });
});
