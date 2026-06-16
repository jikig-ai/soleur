import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// FIX 3 — auto-sync trigger lease/auth resilience (plan Phase 5, AC3).
//
// Drives the extracted `triggerHeadlessSync(userId, repoUrl, seams)` helper.
// The `startAgentSession` SDK call is INJECTED so the bounded retry/backoff is
// unit-testable without pulling in @anthropic-ai/claude-agent-sdk.
//
// Invariants under test:
//   - exactly ONE `conversations` INSERT across all retry attempts (no orphan
//     rows — architecture P0-3); the SAME conversationId is reused each attempt.
//   - `RuntimeAuthError` / `ByokLeaseError("escape")` / the
//     "Authentication unavailable; retry shortly" message are retried with
//     backoff; eventual success resolves cleanly.
//   - exhausted retries → reportSilentFallback(feature=repo-setup,
//     op=auto-sync-trigger), NO rethrow, NO repo_status mutation.
//   - keyless users (userHasEffectiveByokKey=false) → no INSERT, no session.
//
// Mocking strategy mirrors account-delete-sentry-mirror.test.ts: mock
// `@/server/observability` directly and assert on helper input args.

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));

// Override only `reportSilentFallback`; keep the rest (notably `hashUserId`,
// which `userid-pseudonymize` re-imports for the Sentry user-scope hash).
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: mockReportSilentFallback,
}));

// The error classes the retry must catch. Import the REAL classes so the
// `instanceof` discrimination in the helper is exercised, not a stub shape.
import { RuntimeAuthError } from "@/lib/supabase/tenant";
import { ByokLeaseError } from "@/server/byok-lease";
import {
  triggerHeadlessSync,
  type TriggerHeadlessSyncSeams,
} from "@/server/auto-sync-trigger";

const USER_ID = "11111111-1111-4111-8111-111111111111";
const REPO_URL = "https://github.com/acme/widget";
const WORKSPACE_ID = "22222222-2222-4222-8222-222222222222";

/**
 * Build a fake service client that records `conversations` INSERTs. Only the
 * surface `triggerHeadlessSync` touches is implemented.
 */
function makeServiceClient() {
  const inserts: Array<Record<string, unknown>> = [];
  const serviceClient = {
    from(table: string) {
      if (table !== "conversations") {
        throw new Error(`unexpected table ${table}`);
      }
      return {
        insert(row: Record<string, unknown>) {
          inserts.push(row);
          return Promise.resolve({ error: null });
        },
      };
    },
  };
  return { serviceClient, inserts };
}

function baseSeams(startAgentSession: ReturnType<typeof vi.fn>) {
  const { serviceClient, inserts } = makeServiceClient();
  const seams: TriggerHeadlessSyncSeams = {
    startAgentSession: startAgentSession as unknown as TriggerHeadlessSyncSeams["startAgentSession"],
    serviceClient: serviceClient as never,
    resolveWorkspaceId: vi.fn().mockResolvedValue(WORKSPACE_ID),
    userHasEffectiveByokKey: vi.fn().mockResolvedValue(true),
  };
  return { inserts, seams };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("triggerHeadlessSync — lease/auth retry resilience (AC3)", () => {
  test("retries once on RuntimeAuthError then succeeds; exactly ONE conversation INSERT", async () => {
    const startAgentSession = vi
      .fn()
      .mockRejectedValueOnce(new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly"))
      .mockResolvedValueOnce(undefined);
    const { inserts, seams } = baseSeams(startAgentSession);

    const p = triggerHeadlessSync(USER_ID, REPO_URL, seams);
    await vi.runAllTimersAsync();
    await p;

    expect(startAgentSession).toHaveBeenCalledTimes(2);
    expect(inserts).toHaveLength(1);
    // Same conversationId reused on every attempt.
    const conversationIds = startAgentSession.mock.calls.map((c) => c[1]);
    expect(new Set(conversationIds).size).toBe(1);
    expect(conversationIds[0]).toBe(inserts[0].id);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("retries on ByokLeaseError('escape') then succeeds", async () => {
    const startAgentSession = vi
      .fn()
      .mockRejectedValueOnce(new ByokLeaseError("escape", "Authentication unavailable; retry shortly"))
      .mockResolvedValueOnce(undefined);
    const { inserts, seams } = baseSeams(startAgentSession);

    const p = triggerHeadlessSync(USER_ID, REPO_URL, seams);
    await vi.runAllTimersAsync();
    await p;

    expect(startAgentSession).toHaveBeenCalledTimes(2);
    expect(inserts).toHaveLength(1);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("exhausted retries → reportSilentFallback(op=auto-sync-trigger), no rethrow, ONE INSERT", async () => {
    const startAgentSession = vi
      .fn()
      .mockRejectedValue(new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly"));
    const { inserts, seams } = baseSeams(startAgentSession);

    // Must NOT reject into the setup `.then()` — resolves cleanly.
    const p = triggerHeadlessSync(USER_ID, REPO_URL, seams);
    await vi.runAllTimersAsync();
    await expect(p).resolves.toBeUndefined();

    // 1 initial + 3 retries = 4 attempts (bounded).
    expect(startAgentSession).toHaveBeenCalledTimes(4);
    expect(inserts).toHaveLength(1);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.feature).toBe("repo-setup");
    expect(opts.op).toBe("auto-sync-trigger");
  });

  test("non-lease error does NOT retry (single attempt) and still falls loud", async () => {
    const startAgentSession = vi.fn().mockRejectedValue(new Error("boom unrelated"));
    const { inserts, seams } = baseSeams(startAgentSession);

    const p = triggerHeadlessSync(USER_ID, REPO_URL, seams);
    await vi.runAllTimersAsync();
    await expect(p).resolves.toBeUndefined();

    expect(startAgentSession).toHaveBeenCalledTimes(1);
    expect(inserts).toHaveLength(1);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test('"Authentication unavailable; retry shortly" plain Error is retried (defensive substring)', async () => {
    const startAgentSession = vi
      .fn()
      .mockRejectedValueOnce(new Error("Authentication unavailable; retry shortly"))
      .mockResolvedValueOnce(undefined);
    const { seams } = baseSeams(startAgentSession);

    const p = triggerHeadlessSync(USER_ID, REPO_URL, seams);
    await vi.runAllTimersAsync();
    await p;

    expect(startAgentSession).toHaveBeenCalledTimes(2);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });
});

describe("triggerHeadlessSync — gating", () => {
  test("keyless user → no INSERT, no session, no error", async () => {
    const startAgentSession = vi.fn();
    const { inserts, seams } = baseSeams(startAgentSession);
    seams.userHasEffectiveByokKey = vi.fn().mockResolvedValue(false);

    await triggerHeadlessSync(USER_ID, REPO_URL, seams);

    expect(startAgentSession).not.toHaveBeenCalled();
    expect(inserts).toHaveLength(0);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("conversation INSERT failure → reportSilentFallback, no session fired", async () => {
    const startAgentSession = vi.fn();
    const seams: TriggerHeadlessSyncSeams = {
      startAgentSession:
        startAgentSession as unknown as TriggerHeadlessSyncSeams["startAgentSession"],
      serviceClient: {
        from() {
          return {
            insert: () => Promise.resolve({ error: { message: "insert failed", code: "23502" } }),
          };
        },
      } as never,
      resolveWorkspaceId: vi.fn().mockResolvedValue(WORKSPACE_ID),
      userHasEffectiveByokKey: vi.fn().mockResolvedValue(true),
    };

    await triggerHeadlessSync(USER_ID, REPO_URL, seams);

    expect(startAgentSession).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("happy path: first attempt succeeds, one INSERT, no retry, headless prompt passed", async () => {
    const startAgentSession = vi.fn().mockResolvedValue(undefined);
    const { inserts, seams } = baseSeams(startAgentSession);

    await triggerHeadlessSync(USER_ID, REPO_URL, seams);

    expect(startAgentSession).toHaveBeenCalledTimes(1);
    expect(inserts).toHaveLength(1);
    // The conversation is stamped with the repo url + workspace.
    expect(inserts[0].repo_url).toBe(REPO_URL);
    expect(inserts[0].workspace_id).toBe(WORKSPACE_ID);
    // The injected session is invoked with the headless sync prompt.
    const promptArg = startAgentSession.mock.calls[0][4];
    expect(promptArg).toContain("/soleur:sync");
    expect(promptArg).toContain("--headless");
  });
});
