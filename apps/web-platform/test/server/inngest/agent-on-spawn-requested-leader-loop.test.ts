/**
 * PR-B (#4379) — Tests for the Anthropic-SDK leader-prompt loop body of
 * `agent-on-spawn-requested` per AC1 (loop topology) + AC5/AC6/AC8/AC10/
 * AC17 (cache-token persistence, UUIDv5 conversationId, tool-allowlist,
 * failure-reason taxonomy, prompt-caching).
 *
 * Strategy mirrors the PR-A test (agent-on-spawn-requested.test.ts):
 * drive the handler directly with a mock `step` so Inngest runtime is
 * not required. Mocks include the Anthropic SDK, BYOK lease, cost-writer
 * awaitable, BYOK cap RPC wrapper, service-role Supabase client, and
 * GitHub App client factory.
 *
 * Replay determinism (AC1 sentinel): `step.run` results are memoized by
 * step name in this mock (mirroring Inngest's per-step memoization). A
 * second handler invocation with the SAME memoized results from turn 1
 * re-uses the cached cap-check / cost / cancel / progress / claude
 * outputs and re-runs ONLY the steps that errored on the first pass.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import { LEADER_PROMPTS } from "@/server/inngest/leader-prompts";

// --- Module mocks (hoisted by vitest) ----------------------------------------

interface UpdateCall {
  table: string;
  patch: unknown;
  eqArgs: unknown[];
}
const updateCalls: UpdateCall[] = [];

// #5470: the install is resolved from the user's solo WORKSPACE row via the
// service-role resolver (resolveInstallationIdForWorkspace → from("workspaces")),
// no longer from users.github_installation_id. Keyed id=founderId (solo).
let workspaceInstallResult: { data: unknown; error: unknown } = {
  data: { github_installation_id: 99 },
  error: null,
};
let actionSendsSelectResult: { data: unknown; error: unknown } = {
  data: { cancellation_requested_at: null },
  error: null,
};
// feat-l5-runaway-guard: spawn-entry pause gate reads users.runtime_paused_at.
let usersSelectResult: { data: unknown; error: unknown } = {
  data: { runtime_paused_at: null, runtime_cost_cap_cents: 2000 },
  error: null,
};
let cumulativeCostCents = 0;
let auditSelectError: unknown = null;
// Layer-2 window (#7774). This fake returns rows regardless of predicates, so it
// CANNOT simulate the `.gt("created_at", …)` filter — asserting on the returned
// sum would certify nothing. Capture the predicate instead and assert the query
// carries it: that is the part the fake can actually witness.
interface RangeFilter {
  table: string;
  col: string;
  val: unknown;
}
let gtFilters: RangeFilter[] = [];

function buildSupabaseClient() {
  let currentTable = "";
  let currentPatch: unknown = undefined;
  let pendingSelectCols = "";
  const eqArgs: unknown[] = [];

  const chain = {
    from(table: string) {
      currentTable = table;
      return chain;
    },
    select(cols: string) {
      pendingSelectCols = cols;
      return chain;
    },
    update(patch: unknown) {
      currentPatch = patch;
      return chain;
    },
    eq(col: string, val: unknown) {
      eqArgs.push({ col, val });
      if (currentPatch !== undefined) {
        updateCalls.push({
          table: currentTable,
          patch: currentPatch,
          eqArgs: [...eqArgs],
        });
        currentPatch = undefined;
        return Promise.resolve({ error: null });
      }
      return chain;
    },
    gt(col: string, val: unknown) {
      gtFilters.push({ table: currentTable, col, val });
      return chain;
    },
    maybeSingle() {
      if (currentTable === "workspaces") {
        return Promise.resolve(workspaceInstallResult);
      }
      if (currentTable === "action_sends") {
        return Promise.resolve(actionSendsSelectResult);
      }
      if (currentTable === "users") {
        return Promise.resolve(usersSelectResult);
      }
      return Promise.resolve({ data: null, error: null });
    },
    // The Layer-2 window anchor read (`action_sends.created_at`) terminates in
    // `.single()`, unlike the sibling reads above which use `.maybeSingle()`.
    single() {
      if (currentTable === "action_sends") {
        return Promise.resolve(actionSendsSelectResult);
      }
      return Promise.resolve({ data: null, error: null });
    },
    // Used by the cumulative-cost query (turn-N-precheck-cost-ceiling).
    csv() {
      return Promise.resolve({ data: "", error: null });
    },
    // Cumulative-cost SUM query — handler awaits this terminator.
    then(onFulfilled: (v: unknown) => unknown) {
      // pendingSelectCols contains "unit_cost_cents"; return the sum as a
      // single-row aggregate-shape payload.
      void pendingSelectCols;
      const rows = auditSelectError
        ? { data: null, error: auditSelectError }
        : {
            data: [{ unit_cost_cents: cumulativeCostCents }],
            error: null,
          };
      return Promise.resolve(rows).then(onFulfilled);
    },
  };
  return chain;
}

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: vi.fn(() => buildSupabaseClient()),
}));

// GitHub App client factory — captures every Octokit tool call.
interface ToolInvocation {
  route: string;
  params: unknown;
}
const toolInvocations: ToolInvocation[] = [];
let octokitResponses: Record<string, unknown> = {};
let octokitThrowFor: string | null = null;

const requestSpy = vi.fn(async (route: string, params: unknown) => {
  toolInvocations.push({ route, params });
  if (octokitThrowFor && route === octokitThrowFor) {
    const err = Object.assign(new Error("Bad credentials"), { status: 401 });
    throw err;
  }
  return octokitResponses[route] ?? { data: {} };
});
const createGitHubAppClientSpy = vi.fn(async () => ({ request: requestSpy }));
vi.mock("@/server/github/app-client", () => ({
  createGitHubAppClient: createGitHubAppClientSpy,
}));

// Observability — Sentry mirror.
const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

// Offline notification dispatch (feat-l5-runaway-guard). Records the payload
// AND the number of action_sends failure_reason UPDATEs already applied at
// call time — used to prove notify fires BEFORE the terminal UPDATE (AC3).
interface NotifyCall {
  userId: string;
  payload: Record<string, unknown>;
  actionSendsUpdatesBefore: number;
}
const notifyCalls: NotifyCall[] = [];
const notifyOfflineUserSpy = vi.fn(async (userId: string, payload: unknown) => {
  notifyCalls.push({
    userId,
    payload: payload as Record<string, unknown>,
    actionSendsUpdatesBefore: updateCalls.filter(
      (u) => (u.patch as Record<string, unknown>).failure_reason !== undefined,
    ).length,
  });
});
// Include isCostBreakerReason — the handler now imports it for the fire-guard.
// A wholesale factory that omitted it would make the guard call `undefined()`.
const COST_BREAKER_NOTIFY_REASONS_FIXTURE = [
  "cost_ceiling_exceeded",
  "byok_cap_exceeded",
  "leader_max_turns_exceeded",
  "cap_check_unavailable",
];
vi.mock("@/server/notifications", () => ({
  notifyOfflineUser: notifyOfflineUserSpy,
  isCostBreakerReason: (r: string) =>
    COST_BREAKER_NOTIFY_REASONS_FIXTURE.includes(r),
}));

// Inngest stub.
vi.mock("@/server/inngest/client", () => ({
  inngest: {
    createFunction: () => ({}) as unknown,
  },
}));

// BYOK cap RPC wrapper.
let capRpcResult: { cumulativeCents: number; killTripped: boolean } = {
  cumulativeCents: 0,
  killTripped: false,
};
let capRpcThrows: Error | null = null;
const recordByokUseAndCheckCapSpy = vi.fn(async () => {
  if (capRpcThrows) throw capRpcThrows;
  return capRpcResult;
});
vi.mock("@/server/byok-cap-rpc", () => ({
  recordByokUseAndCheckCap: recordByokUseAndCheckCapSpy,
}));

// BYOK lease — call fn directly (no real ALS scope; the handler uses lease
// only to obtain the API key, and we mock the Anthropic client below).
let leaseOpenThrows: Error | null = null;
// A spy (reset in beforeEach) so Guard 2 can make key retrieval throw and count
// how many times the step re-ran it.
const getRestApiKeySpy = vi.fn(async (): Promise<string> => "test-api-key");
const runWithByokLeaseSpy = vi.fn(async (_args: unknown, fn: unknown) => {
  if (leaseOpenThrows) throw leaseOpenThrows;
  const lease = {
    workspaceContextUserId: "founder-123",
    keyOwnerUserId: "founder-123",
    // Raw-REST consumer (`new Anthropic({apiKey})`) → getRestApiKey.
    getRestApiKey: getRestApiKeySpy,
  };
  return (fn as (l: unknown) => Promise<unknown>)(lease);
});
vi.mock("@/server/byok-lease", () => ({
  runWithByokLease: runWithByokLeaseSpy,
  ByokLeaseError: class ByokLeaseError extends Error {
    cause: string;
    constructor(cause: string, message: string) {
      super(message);
      this.cause = cause;
    }
  },
}));

// Cost-writer awaitable. Typed with a 5-arg shape so `mock.calls[i][j]`
// indices resolve under strict TS.
const persistTurnCostAwaitableSpy = vi.fn(
  async (
    _userId: string,
    _conversationId: string,
    _leaderId: string,
    _workspaceId: string,
    _input: unknown,
  ): Promise<void> => undefined,
);
vi.mock("@/server/cost-writer", () => ({
  persistTurnCost: vi.fn(),
  persistTurnCostAwaitable: persistTurnCostAwaitableSpy,
}));

// Anthropic SDK — mock the constructor + messages.create.
const anthropicCreateSpy = vi.fn();
class AnthropicMock {
  messages = { create: anthropicCreateSpy };
  constructor(public opts: { apiKey: string }) {}
}
vi.mock("@anthropic-ai/sdk", () => ({
  default: AnthropicMock,
  __esModule: true,
}));

// --- Helpers ----------------------------------------------------------------

interface MockStep {
  calls: { name: string }[];
  memoized: Map<string, unknown>;
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(opts?: { seedMemo?: Map<string, unknown> }): MockStep {
  const calls: { name: string }[] = [];
  const memoized = opts?.seedMemo ?? new Map<string, unknown>();
  return {
    calls,
    memoized,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      if (memoized.has(name)) {
        calls.push({ name });
        return memoized.get(name) as T;
      }
      calls.push({ name });
      const result = await cb();
      memoized.set(name, result);
      return result;
    },
  };
}

// Like makeStep, but re-invokes a throwing callback up to `retries` more times,
// the way Inngest's `retries: 3` does (makeStep memoizes only on success, so a
// re-invocation re-runs the callback). The error that finally escapes is
// rebuilt the way it survives Inngest's StepError round-trip: `message`,
// `stack` and a string `cause` are kept; `status` and a custom `name` are not.
function makeRetryingStep(opts: { retries: number }): MockStep {
  const calls: { name: string }[] = [];
  const memoized = new Map<string, unknown>();
  return {
    calls,
    memoized,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push({ name });
      if (memoized.has(name)) return memoized.get(name) as T;
      let lastErr: unknown;
      for (let attempt = 0; attempt <= opts.retries; attempt++) {
        try {
          const result = await cb();
          memoized.set(name, result);
          return result;
        } catch (err) {
          lastErr = err;
        }
      }
      const e = lastErr as Error & { cause?: unknown };
      throw Object.assign(new Error(e.message), {
        cause: e.cause,
        stack: e.stack,
      });
    },
  };
}

// The SDK is vi.mock'ed, so its error classes are unavailable: synthesize the
// fields production reads (`status`, message prefix).
function apiError(
  status: number,
  message = "synthetic",
): Error & { status: number } {
  return Object.assign(
    new Error(
      `${status} {"type":"error","error":{"type":"x","message":"${message}"}}`,
    ),
    { status },
  );
}

const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

interface EventArgs {
  sourceRef: string;
  founderId?: string;
  messageId?: string;
  actionClass?: string;
  actionSendId?: string;
}

function makeEvent(args: EventArgs) {
  return {
    name: "agent.spawn.requested" as const,
    data: {
      founderId: args.founderId ?? "founder-123",
      messageId: args.messageId ?? "msg-abc",
      actionClass: (args.actionClass ?? "engineering.pr_review_pending") as never,
      sourceRef: args.sourceRef,
      actionSendId: args.actionSendId ?? "11111111-1111-1111-1111-111111111111",
    },
  };
}

function endTurnResponse(opts?: {
  tools?: { name: string; input: unknown }[];
  cacheRead?: number;
  cacheCreate?: number;
}) {
  const tools = opts?.tools ?? [];
  return {
    id: "msg_test",
    stop_reason: tools.length > 0 ? "tool_use" : "end_turn",
    content: [
      { type: "text", text: "ok" },
      ...tools.map((t, i) => ({
        type: "tool_use",
        id: `tu_${i}`,
        name: t.name,
        input: t.input,
      })),
    ],
    usage: {
      input_tokens: 100,
      output_tokens: 50,
      cache_read_input_tokens: opts?.cacheRead ?? 0,
      cache_creation_input_tokens: opts?.cacheCreate ?? 0,
    },
  };
}

// --- Test setup -------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  updateCalls.length = 0;
  toolInvocations.length = 0;
  workspaceInstallResult = {
    data: { github_installation_id: 99 },
    error: null,
  };
  actionSendsSelectResult = {
    // created_at is the Layer-2 window anchor (#7774); cancellation_requested_at
    // is read by the same table's cancel-check step.
    data: {
      cancellation_requested_at: null,
      created_at: "2026-09-03T10:00:00.000Z",
    },
    error: null,
  };
  usersSelectResult = {
    data: { runtime_paused_at: null, runtime_cost_cap_cents: 2000 },
    error: null,
  };
  notifyCalls.length = 0;
  cumulativeCostCents = 0;
  auditSelectError = null;
  gtFilters = [];
  octokitResponses = {
    "POST /repos/{owner}/{repo}/issues/{issue_number}/comments": {
      data: { id: 42, html_url: "https://github.com/acme/repo/pull/7#c-42" },
    },
    "POST /repos/{owner}/{repo}/pulls/{pull_number}/comments": {
      data: { id: 7, html_url: "https://github.com/acme/repo/pull/7#dr-7" },
    },
    "POST /repos/{owner}/{repo}/issues/{issue_number}/labels": {
      data: [{ name: "soleur/triage" }],
    },
    "POST /repos/{owner}/{repo}/git/refs": {
      data: { ref: "refs/heads/soleur/fix-cve" },
    },
    "POST /repos/{owner}/{repo}/git/blobs": {
      data: { sha: "blob-sha" },
    },
    "POST /repos/{owner}/{repo}/git/commits": {
      data: { sha: "commit-sha" },
    },
    "POST /repos/{owner}/{repo}/pulls": {
      data: {
        number: 99,
        html_url: "https://github.com/acme/repo/pull/99",
        head: { ref: "soleur/fix-cve" },
      },
    },
  };
  octokitThrowFor = null;
  capRpcResult = { cumulativeCents: 0, killTripped: false };
  capRpcThrows = null;
  leaseOpenThrows = null;
  anthropicCreateSpy.mockReset();
  // vitest 4: mockReset restores the original implementation, so a per-case
  // mockRejectedValue cannot leak into the next test.
  getRestApiKeySpy.mockReset();
  persistTurnCostAwaitableSpy.mockReset();
});

// --- Tests ------------------------------------------------------------------

describe("agent-on-spawn-requested — Anthropic leader loop (PR-B)", () => {
  it("happy path: single end_turn returns artifact_url, writes acknowledged_at and reversal_handles", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(
      endTurnResponse({
        tools: [
          {
            name: "createComment",
            input: { owner: "acme", repo: "repo", issue_number: 7, body: "LGTM" },
          },
        ],
      }),
    );
    // After tool_use, next turn returns end_turn with no tool calls.
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());

    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step,
      logger,
    });
    expect(result).toMatchObject({ acknowledged: true });

    // Step ordering: resolve-installation → turn-1 cap/cost/cancel/progress/
    // claude/tool → turn-2 cap/cost/cancel/progress/claude → mark-acknowledged.
    const names = step.calls.map((c) => c.name);
    expect(names[0]).toBe("resolve-installation");
    expect(names).toContain("turn-1-cap-check");
    expect(names).toContain("turn-1-precheck-cost-ceiling");
    expect(names).toContain("turn-1-cancel-check");
    expect(names).toContain("turn-1-progress-write");
    expect(names).toContain("turn-1-claude");
    expect(names).toContain("turn-1-tool-0");
    expect(names).toContain("turn-2-claude");
    expect(names[names.length - 1]).toBe("mark-acknowledged");

    // The final UPDATE writes acknowledged_at + artifact_url + reversal_handles.
    const ackUpdates = updateCalls.filter(
      (u) =>
        u.table === "action_sends" &&
        (u.patch as Record<string, unknown>).acknowledged_at !== undefined,
    );
    expect(ackUpdates).toHaveLength(1);
    const patch = ackUpdates[0].patch as Record<string, unknown>;
    expect(Array.isArray(patch.reversal_handles)).toBe(true);
    expect((patch.reversal_handles as unknown[]).length).toBeGreaterThan(0);
    expect(typeof patch.artifact_url).toBe("string");
  });

  it("#8611: the leader-loop cost marker carries the turn index and the Inngest attempt (the double-bill signal)", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse({ cacheRead: 0, cacheCreate: 0 }));
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
      attempt: 2,
    });
    expect(persistTurnCostAwaitableSpy).toHaveBeenCalled();
    // The spy's typed signature stops at `input`; the 6th positional arg is the cost marker.
    const marker = (persistTurnCostAwaitableSpy.mock.calls[0] as unknown[])[5] as {
      source: string;
      turn?: number;
      attempt?: number;
    };
    expect(marker.source).toBe("leader-loop");
    expect(Number.isInteger(marker.turn)).toBe(true);
    expect(marker.attempt).toBe(2);
  });

  it("AC17: cache_read + cache_creation tokens flow through persistTurnCostAwaitable", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(
      endTurnResponse({ cacheRead: 1000, cacheCreate: 500 }),
    );
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(persistTurnCostAwaitableSpy).toHaveBeenCalled();
    const firstCall = persistTurnCostAwaitableSpy.mock.calls[0];
    // signature: (userId, conversationId, leaderId, workspaceId, { totalCostUsd, usage })
    const input = firstCall[4] as {
      usage: {
        cache_read_input_tokens: number;
        cache_creation_input_tokens: number;
      };
    };
    expect(input.usage.cache_read_input_tokens).toBe(1000);
    expect(input.usage.cache_creation_input_tokens).toBe(500);
  });

  it("AC6: conversationId is UUIDv5 of actionSendId under the frozen namespace", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({
        sourceRef: "pr-acme:repo:7",
        actionSendId: "00000000-0000-0000-0000-000000000000",
      }),
      step: makeStep(),
      logger,
    });
    expect(persistTurnCostAwaitableSpy).toHaveBeenCalled();
    const conversationId = persistTurnCostAwaitableSpy.mock.calls[0][1];
    // Derived deterministically; specific value is pinned in
    // conversation-namespace-stability.test.ts (Phase 3 sentinel).
    expect(conversationId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
  });

  it("AC10 byok_cap_exceeded: cap-check killTripped → persist failure, no Anthropic call", async () => {
    capRpcResult = { cumulativeCents: 9999, killTripped: true };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "byok_cap_exceeded",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    const failureUpdates = updateCalls.filter(
      (u) =>
        (u.patch as Record<string, unknown>).failure_reason ===
        "byok_cap_exceeded",
    );
    expect(failureUpdates.length).toBeGreaterThanOrEqual(1);
  });

  it("#7774 Layer 2 is scoped to THIS spawn — the sum excludes rows predating the action send", async () => {
    // `leaderId` is `agent.spawn.requested:${actionClass}` — an action CLASS,
    // constant across every spawn — so the two `.eq` filters alone summed the
    // founder's LIFETIME spend for that class. Once it crossed 260¢ every later
    // spawn of the class failed at turn 1, permanently, and audit_byok_use is
    // WORM so the balance could not be trimmed.
    //
    // This fake returns rows regardless of predicates, so it cannot simulate
    // the filter; asserting on the returned sum would certify nothing. Assert
    // the query CARRIES the predicate, with the anchor read from the DB.
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });

    const window = gtFilters.filter((f) => f.table === "audit_byok_use");
    expect(
      window.length,
      "the ceiling query must be window-bounded on every turn",
    ).toBeGreaterThan(0);
    for (const f of window) {
      expect(f.col).toBe("created_at");
      // The DB value, not a wall-clock `new Date()` — an Inngest replay
      // re-executes the body, and a wall-clock anchor would re-derive a
      // different window on every retry.
      expect(f.val).toBe("2026-09-03T10:00:00.000Z");
    }
  });

  it("#7774 the window anchor read fails CLOSED — a missing action_sends row halts the spawn", async () => {
    // Without this, a failed anchor read would widen the window back to all of
    // history, silently restoring the defect the window exists to close.
    actionSendsSelectResult = { data: null, error: { message: "no row" } };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await expect(
      agentOnSpawnRequestedHandler({
        event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
        step: makeStep(),
        logger,
      }),
    ).rejects.toThrow(/could not read action_sends\.created_at/);
    // Fail-closed means no model spend on an unverifiable window.
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("AC10 cost_ceiling_exceeded: cumulative ≥ $2.60 → persist failure, no Anthropic call", async () => {
    cumulativeCostCents = 300; // > PER_SPAWN_COST_CEILING_CENTS (260)
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "cost_ceiling_exceeded",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    // Notifies against the per-spawn window with honest amount-vs-ceiling.
    expect(notifyCalls).toHaveLength(1);
    expect(notifyCalls[0].payload.reason).toBe("cost_ceiling_exceeded");
    expect(notifyCalls[0].payload.which_window).toBe("spawn");
  });

  it("AC10 cancelled_by_operator: cancellation_requested_at NOT NULL → short-circuit", async () => {
    actionSendsSelectResult = {
      // created_at is present on every real action_sends row and is the
      // Layer-2 window anchor (#7774); a fixture omitting it models a row
      // the producer cannot emit.
      data: {
        cancellation_requested_at: "2026-05-25T12:00:00Z",
        created_at: "2026-09-03T10:00:00.000Z",
      },
      error: null,
    };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "cancelled_by_operator",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  // --- feat-l5-runaway-guard PR-A --------------------------------------------

  it("AC1 run_paused: paused founder halts at the entry gate before any cap-check or Anthropic call", async () => {
    usersSelectResult = {
      data: {
        runtime_paused_at: "2026-07-01T09:00:00Z",
        runtime_cost_cap_cents: 2000,
      },
      error: null,
    };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "run_paused",
    });
    // Never entered the turn loop: no cap-check RPC (⇒ zero new
    // audit_byok_use rows) and no Anthropic spend.
    expect(recordByokUseAndCheckCapSpy).not.toHaveBeenCalled();
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
  });

  it("AC1 fail-closed: a users-read error at the entry gate HALTS (run_paused), never enters the loop", async () => {
    // CTO ruling (#5767-vs-#5919): the pause gate is the SOLE working-pause
    // guard (the cap RPC no longer backstops the paused case), so it must fail
    // CLOSED — an unverifiable pause state must not admit a possibly-paused
    // founder into the loop.
    usersSelectResult = { data: null, error: { message: "connection reset" } };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({ acknowledged: false, failureReason: "run_paused" });
    expect(recordByokUseAndCheckCapSpy).not.toHaveBeenCalled();
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    // Mirrored to Sentry (via persistFailure's reportSilentFallback).
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
  });

  it("cap_check_unavailable: a transient cap-check RPC error is NOT reported as byok_cap_exceeded", async () => {
    capRpcThrows = new Error("connection reset by peer");
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "cap_check_unavailable",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    // Still notifies (honest "couldn't verify" copy), tagged to the 1h window.
    expect(notifyCalls).toHaveLength(1);
    expect(notifyCalls[0].payload.reason).toBe("cap_check_unavailable");
    expect(notifyCalls[0].payload.which_window).toBe("cap-1h");
  });

  it("AC3 notify: byok_cap_exceeded fires cost_breaker_tripped BEFORE the action_sends UPDATE", async () => {
    capRpcResult = { cumulativeCents: 9999, killTripped: true };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(notifyCalls).toHaveLength(1);
    expect(notifyCalls[0].userId).toBe("founder-123");
    expect(notifyCalls[0].payload.type).toBe("cost_breaker_tripped");
    expect(notifyCalls[0].payload.reason).toBe("byok_cap_exceeded");
    expect(notifyCalls[0].payload.which_window).toBe("cap-1h");
    // Ordering (AC3): notify fires before the terminal failure_reason UPDATE.
    expect(notifyCalls[0].actionSendsUpdatesBefore).toBe(0);
  });

  it("AC3 notify: run_paused does NOT notify (avoids a paged-every-blocked-spawn storm)", async () => {
    // The founder was already paged by the byok_cap_exceeded breach that set
    // the pause; the Today card surfaces this blocked spawn + Resume. Re-paging
    // every subsequent paused spawn would be a storm from the guard itself.
    usersSelectResult = {
      data: {
        runtime_paused_at: "2026-07-01T09:00:00Z",
        runtime_cost_cap_cents: 2000,
      },
      error: null,
    };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({ acknowledged: false, failureReason: "run_paused" });
    expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
  });

  it("AC3 notify: cancelled_by_operator NEVER notifies (operator-initiated stops are not surprises)", async () => {
    actionSendsSelectResult = {
      // created_at is present on every real action_sends row and is the
      // Layer-2 window anchor (#7774); a fixture omitting it models a row
      // the producer cannot emit.
      data: {
        cancellation_requested_at: "2026-05-25T12:00:00Z",
        created_at: "2026-09-03T10:00:00.000Z",
      },
      error: null,
    };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(notifyOfflineUserSpy).not.toHaveBeenCalled();
  });

  it("AC10 leader_response_truncated: stop_reason=max_tokens → persist failure", async () => {
    anthropicCreateSpy.mockResolvedValueOnce({
      id: "msg_truncated",
      stop_reason: "max_tokens",
      content: [{ type: "text", text: "..." }],
      usage: {
        input_tokens: 4000,
        output_tokens: 4096,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
      },
    });
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "leader_response_truncated",
    });
  });

  it("AC10 leader_tool_invalid: out-of-allowlist tool call → persist failure", async () => {
    // pr_review_pending allowlist = [createPullRequestReviewComment, createComment].
    // Model tries `addLabels`, which is NOT in its allowlist.
    anthropicCreateSpy.mockResolvedValueOnce(
      endTurnResponse({
        tools: [
          {
            name: "addLabels",
            input: { owner: "acme", repo: "repo", issue_number: 7, labels: ["x"] },
          },
        ],
      }),
    );
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "leader_tool_invalid",
    });
    // The out-of-allowlist tool must NEVER be invoked on GitHub.
    expect(
      toolInvocations.filter(
        (t) =>
          t.route ===
          "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
      ).length,
    ).toBe(0);
  });

  it("AC10 leader_max_turns_exceeded: 8 tool-use turns with no end_turn → persist failure", async () => {
    // Every turn requests a tool call → loop runs to LEADER_MAX_TURNS (8)
    // without an end_turn signal.
    for (let i = 0; i < 8; i++) {
      anthropicCreateSpy.mockResolvedValueOnce(
        endTurnResponse({
          tools: [
            {
              name: "createComment",
              input: {
                owner: "acme",
                repo: "repo",
                issue_number: 7,
                body: `turn ${i + 1}`,
              },
            },
          ],
        }),
      );
    }
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "leader_max_turns_exceeded",
    });
    // 8 anthropic calls, 8 tool invocations.
    expect(anthropicCreateSpy).toHaveBeenCalledTimes(8);
  });

  it("AC10 byok_lease_unavailable: lease opener throws → persist failure", async () => {
    leaseOpenThrows = Object.assign(new Error("no key"), {
      cause: "fetch_failed",
      name: "ByokLeaseError",
    });
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "byok_lease_unavailable",
    });
  });

  it("AC10 anthropic_rate_limited: an in-process SDK 429 error classifies as rate-limited", async () => {
    anthropicCreateSpy.mockRejectedValueOnce(
      Object.assign(new Error("Rate limited"), { status: 429 }),
    );
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "anthropic_rate_limited",
    });
  });

  it("AC10 anthropic_timeout: SDK times out → persist failure", async () => {
    const err: Error & { status?: number } = new Error("Request timed out");
    err.name = "APIConnectionTimeoutError";
    anthropicCreateSpy.mockRejectedValueOnce(err);
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "anthropic_timeout",
    });
  });

  it("AC1 replay determinism: memoized turn-1 + forced fail on turn-2 → only turn-2 re-runs on replay", async () => {
    // First pass: turn-1 tool_use succeeds; turn-2 anthropic call rejects.
    anthropicCreateSpy.mockResolvedValueOnce(
      endTurnResponse({
        tools: [
          {
            name: "createComment",
            input: { owner: "acme", repo: "repo", issue_number: 7, body: "ok" },
          },
        ],
      }),
    );
    anthropicCreateSpy.mockRejectedValueOnce(
      Object.assign(new Error("Rate limited"), { status: 429 }),
    );

    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step1 = makeStep();
    const result1 = await agentOnSpawnRequestedHandler({
      event: makeEvent({
        sourceRef: "pr-acme:repo:7",
        actionSendId: "22222222-2222-2222-2222-222222222222",
      }),
      step: step1,
      logger,
    });
    expect(result1).toMatchObject({
      acknowledged: false,
      failureReason: "anthropic_rate_limited",
    });

    // Second pass: re-use the memoized step results. anthropic.messages.create
    // returns end_turn this time.
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());
    const step2 = makeStep({ seedMemo: step1.memoized });
    // Drop the memoized turn-2 entries so they re-run (persist-failure
    // and turn-2-claude). In real Inngest replay, the failed step is the
    // one that re-runs.
    step2.memoized.delete("turn-2-claude");
    step2.memoized.delete("persist-failure");

    const callCountBefore = anthropicCreateSpy.mock.calls.length;
    const result2 = await agentOnSpawnRequestedHandler({
      event: makeEvent({
        sourceRef: "pr-acme:repo:7",
        actionSendId: "22222222-2222-2222-2222-222222222222",
      }),
      step: step2,
      logger,
    });
    expect(result2).toMatchObject({ acknowledged: true });
    // Only turn-2 anthropic call re-ran; turn-1 came from memoization.
    expect(anthropicCreateSpy.mock.calls.length - callCountBefore).toBe(1);
  });

  it("AC2 per-class happy path: triage.p0p1_issue with addLabels + createComment writes both reversal handles", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(
      endTurnResponse({
        tools: [
          {
            name: "addLabels",
            input: {
              owner: "acme",
              repo: "repo",
              issue_number: 42,
              labels: ["soleur/triage"],
            },
          },
          {
            name: "createComment",
            input: {
              owner: "acme",
              repo: "repo",
              issue_number: 42,
              body: "Triaged",
            },
          },
        ],
      }),
    );
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());

    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({
        sourceRef: "issue-acme:repo:42",
        actionClass: "triage.p0p1_issue",
      }),
      step: makeStep(),
      logger,
    });
    expect(result).toMatchObject({ acknowledged: true });
    const ackUpdate = updateCalls.find(
      (u) =>
        (u.patch as Record<string, unknown>).acknowledged_at !== undefined,
    );
    expect(ackUpdate).toBeDefined();
    const handles = (ackUpdate!.patch as Record<string, unknown>)
      .reversal_handles as unknown[];
    expect(handles).toHaveLength(2);
    const kinds = handles.map((h) => (h as { kind: string }).kind);
    expect(kinds).toContain("issue_label");
    expect(kinds).toContain("issue_comment");
  });

  it("AC8: all Octokit calls route through createGitHubAppClient(installationId, founderId)", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(
      endTurnResponse({
        tools: [
          {
            name: "createComment",
            input: { owner: "acme", repo: "repo", issue_number: 7, body: "ok" },
          },
        ],
      }),
    );
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(createGitHubAppClientSpy).toHaveBeenCalledWith(99, "founder-123");
  });

  it("PR-A I1 inherited: founder whose solo workspace has no install deadletters with github_installation_unauthorized", async () => {
    workspaceInstallResult = {
      data: { github_installation_id: null },
      error: null,
    };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "github_installation_unauthorized",
    });
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(createGitHubAppClientSpy).not.toHaveBeenCalled();
  });

  it("LEADER_CLASSES_DISABLED kill switch: configured class deadletters with leader_class_disabled, no Anthropic call", async () => {
    const original = process.env.LEADER_CLASSES_DISABLED;
    process.env.LEADER_CLASSES_DISABLED = "engineering.pr_review_pending";
    try {
      const { agentOnSpawnRequestedHandler } = await import(
        "@/server/inngest/functions/agent-on-spawn-requested"
      );
      const result = await agentOnSpawnRequestedHandler({
        event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
        step: makeStep(),
        logger,
      });
      expect(result).toEqual({
        acknowledged: false,
        failureReason: "leader_class_disabled",
      });
      expect(anthropicCreateSpy).not.toHaveBeenCalled();
    } finally {
      if (original === undefined) {
        delete process.env.LEADER_CLASSES_DISABLED;
      } else {
        process.env.LEADER_CLASSES_DISABLED = original;
      }
    }
  });

  it("LEADER_CLASSES_DISABLED kill switch: classes NOT in the list still run", async () => {
    const original = process.env.LEADER_CLASSES_DISABLED;
    process.env.LEADER_CLASSES_DISABLED = "engineering.ci_failed,triage.p0p1_issue";
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());
    try {
      const { agentOnSpawnRequestedHandler } = await import(
        "@/server/inngest/functions/agent-on-spawn-requested"
      );
      const result = await agentOnSpawnRequestedHandler({
        event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
        step: makeStep(),
        logger,
      });
      expect(result).toMatchObject({ acknowledged: true });
      expect(anthropicCreateSpy).toHaveBeenCalled();
    } finally {
      if (original === undefined) {
        delete process.env.LEADER_CLASSES_DISABLED;
      } else {
        process.env.LEADER_CLASSES_DISABLED = original;
      }
    }
  });

  it("AC5: persistTurnCostAwaitable called with leaderId scoped to actionClass", async () => {
    anthropicCreateSpy.mockResolvedValueOnce(endTurnResponse());
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    const leaderId = persistTurnCostAwaitableSpy.mock.calls[0][2];
    expect(leaderId).toBe(
      "agent.spawn.requested:engineering.pr_review_pending",
    );
  });
});

// --- Guard 1: cache breakpoints stay under the API cap (ADR-042 §I5) ---------

// Counts every `cache_control` object key anywhere in the request: top-level,
// system, tools and messages. A quoted "cache_control" inside prompt text
// serializes as \"cache_control\", which this regex does not match, so only an
// object key counts. Such a key in a tool schema or tool_use input would fail
// loud (a false RED), never silently.
function countBreakpoints(params: unknown): number {
  return JSON.stringify(params).match(/"cache_control"/g)?.length ?? 0;
}

type CreateParams = Record<string, unknown> & {
  system: { cache_control?: unknown }[];
  messages: { role: string; content: unknown }[];
};

function expectCompliantRequest(params: CreateParams, cls: string): void {
  // The Messages API rejects a request with more than 4 breakpoints (the
  // top-level automatic one included). `=== 2` is the tighter pin: one explicit
  // system marker plus the automatic one, on every turn.
  expect(countBreakpoints(params)).toBeLessThanOrEqual(4);
  expect(countBreakpoints(params)).toBe(2);
  // Exact shape, so no `ttl` can creep in: MODEL_PRICING's cache-write rate
  // assumes the 5-minute default.
  expect(params.cache_control).toEqual({ type: "ephemeral" });
  expect(params.system.at(-1)?.cache_control).toEqual({ type: "ephemeral" });
  // Tools go out exactly as the class module defines them, with no marker.
  expect(params.tools).toEqual(
    LEADER_PROMPTS[cls as keyof typeof LEADER_PROMPTS].tools,
  );
}

describe("Guard 1 — leader-loop cache breakpoints (ADR-042 §I5)", () => {
  it.each(Object.keys(LEADER_PROMPTS))(
    "%s: one system marker plus top-level automatic caching, tools unmarked",
    async (cls) => {
      const captured: CreateParams[] = [];
      anthropicCreateSpy.mockImplementation(async (p: CreateParams) => {
        captured.push(structuredClone(p));
        return endTurnResponse();
      });
      const { agentOnSpawnRequestedHandler } = await import(
        "@/server/inngest/functions/agent-on-spawn-requested"
      );
      await agentOnSpawnRequestedHandler({
        event: makeEvent({ sourceRef: "pr-acme:repo:7", actionClass: cls }),
        step: makeStep(),
        logger,
      });
      // Floor: a class that exits before `create` must not pass over zero calls.
      expect(captured.length).toBeGreaterThan(0);
      for (const params of captured) expectCompliantRequest(params, cls);
    },
  );

  it("multi-turn: every request stays compliant as the conversation grows", async () => {
    const cls = "engineering.pr_review_pending";
    const toolTurn = () =>
      endTurnResponse({
        tools: [
          {
            name: "createComment",
            input: { owner: "acme", repo: "repo", issue_number: 7, body: "ok" },
          },
        ],
      });
    const responses = [toolTurn(), toolTurn(), endTurnResponse()];
    // The handler passes one shared `messages` array and appends to it after
    // each call, so `mock.calls[i][0]` would all show the final state. Clone
    // each request as it is made.
    const captured: CreateParams[] = [];
    anthropicCreateSpy.mockImplementation(async (p: CreateParams) => {
      captured.push(structuredClone(p));
      return responses.shift();
    });
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7", actionClass: cls }),
      step: makeStep(),
      logger,
    });
    expect(result).toMatchObject({ acknowledged: true });
    expect(captured).toHaveLength(3);
    expect(captured[0].messages).toHaveLength(1);
    for (const params of captured) expectCompliantRequest(params, cls);
    const blockTypes = captured[2].messages.flatMap((m) =>
      Array.isArray(m.content)
        ? (m.content as { type: string }[]).map((b) => b.type)
        : [],
    );
    expect(blockTypes).toContain("tool_use");
    expect(blockTypes).toContain("tool_result");
  });
});

// --- Guard 1b: the cached prefix is byte-stable across turns ------------------

describe("Guard 1 — the cached prefix is byte-stable across turns (ADR-042 §I5)", () => {
  it("system, tools and every earlier message are unchanged on each later turn", async () => {
    const toolTurn = () =>
      endTurnResponse({
        tools: [
          {
            name: "createComment",
            input: { owner: "acme", repo: "repo", issue_number: 7, body: "ok" },
          },
        ],
      });
    const responses = [toolTurn(), toolTurn(), endTurnResponse()];
    const captured: CreateParams[] = [];
    anthropicCreateSpy.mockImplementation(async (p: CreateParams) => {
      captured.push(structuredClone(p));
      return responses.shift();
    });
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(captured).toHaveLength(3);
    for (let i = 1; i < captured.length; i++) {
      const prev = captured[i - 1];
      const cur = captured[i];
      // Anything that varies per turn in this prefix breaks the cache on
      // every call, which is the change's whole point.
      expect(JSON.stringify(cur.system)).toBe(JSON.stringify(prev.system));
      expect(JSON.stringify(cur.tools)).toBe(JSON.stringify(prev.tools));
      expect(cur.messages.length).toBeGreaterThan(prev.messages.length);
      expect(cur.messages.slice(0, prev.messages.length)).toEqual(
        prev.messages,
      );
    }
  });
});

// --- Guard 2: deterministic API rejections are returned, not retried --------

describe("Guard 2 — deterministic rejections are returned from the step (ADR-042 §I1)", () => {
  async function runWith(step: MockStep) {
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    return agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step,
      logger,
    });
  }

  function deadletterCall() {
    return reportSilentFallbackSpy.mock.calls.find((c) =>
      String((c[1] as { message?: string } | undefined)?.message).includes(
        "deadlettered",
      ),
    );
  }

  it("400 → anthropic_request_rejected after one create call; Sentry gets the SDK message and stack", async () => {
    const original = apiError(400);
    anthropicCreateSpy.mockRejectedValue(original);
    const result = await runWith(makeRetryingStep({ retries: 3 }));
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "anthropic_request_rejected",
    });
    expect(anthropicCreateSpy).toHaveBeenCalledTimes(1);
    expect(persistTurnCostAwaitableSpy).not.toHaveBeenCalled();
    const call = deadletterCall();
    expect(call).toBeDefined();
    expect((call![0] as Error).message.startsWith("400 ")).toBe(true);
    expect((call![0] as Error).stack).toBe(original.stack);
    expect((call![1] as { extra: Record<string, unknown> }).extra).toMatchObject({
      status: 400,
      turn: 1,
      model: LEADER_PROMPTS["engineering.pr_review_pending"].model,
    });
  });

  it.each([404, 413, 422])(
    "%i → anthropic_request_rejected after one create call",
    async (status) => {
      anthropicCreateSpy.mockRejectedValue(apiError(status));
      const result = await runWith(makeRetryingStep({ retries: 3 }));
      expect(result).toEqual({
        acknowledged: false,
        failureReason: "anthropic_request_rejected",
      });
      expect(anthropicCreateSpy).toHaveBeenCalledTimes(1);
    },
  );

  it.each([
    [401, "invalid x-api-key"],
    [402, "billing"],
    [403, "permission"],
    // The founder's account, reported as 400 invalid_request_error.
    [400, "Your credit balance is too low to access the Anthropic API."],
    [400, "You have reached your specified API usage limits."],
  ])(
    "%i (%s) → byok_lease_unavailable after one create call",
    async (status, message) => {
      anthropicCreateSpy.mockRejectedValue(apiError(status, message));
      const result = await runWith(makeRetryingStep({ retries: 3 }));
      expect(result).toEqual({
        acknowledged: false,
        failureReason: "byok_lease_unavailable",
      });
      expect(anthropicCreateSpy).toHaveBeenCalledTimes(1);
      expect(persistTurnCostAwaitableSpy).not.toHaveBeenCalled();
    },
  );

  it("MissingByokKeyError → byok_lease_unavailable after one key read, no create call", async () => {
    getRestApiKeySpy.mockRejectedValue(
      Object.assign(new Error("no key configured"), {
        name: "MissingByokKeyError",
      }),
    );
    const step = makeRetryingStep({ retries: 3 });
    const result = await runWith(step);
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "byok_lease_unavailable",
    });
    expect(getRestApiKeySpy).toHaveBeenCalledTimes(1);
    expect(anthropicCreateSpy).not.toHaveBeenCalled();
    expect(
      (step.memoized.get("turn-1-claude") as { status: unknown }).status,
    ).toBeNull();
  });

  // Transient errors are thrown and retried. The step rebuilds the final error
  // the way Inngest does, so `status` is gone by the time the handler
  // classifies it: a 429 that survives every retry reads anthropic_timeout
  // (the documented residual).
  it.each([429, 500, 408, 409])(
    "%i is transient: thrown, retried 3 times, then anthropic_timeout",
    async (status) => {
      anthropicCreateSpy.mockRejectedValue(apiError(status));
      const step = makeRetryingStep({ retries: 3 });
      const result = await runWith(step);
      expect(result).toEqual({
        acknowledged: false,
        failureReason: "anthropic_timeout",
      });
      expect(anthropicCreateSpy).toHaveBeenCalledTimes(4);
      expect(step.memoized.has("turn-1-claude")).toBe(false);
    },
  );

  it("a lease ByokLeaseError(fetch_failed) is thrown, retried, and classified by its surviving cause", async () => {
    getRestApiKeySpy.mockRejectedValue(
      Object.assign(new Error("fetch failed"), {
        name: "ByokLeaseError",
        cause: "fetch_failed",
      }),
    );
    const result = await runWith(makeRetryingStep({ retries: 3 }));
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "byok_lease_unavailable",
    });
    expect(getRestApiKeySpy).toHaveBeenCalledTimes(4);
  });

  it("a rejection on turn 2 records turn 2, after turn 1's cost", async () => {
    anthropicCreateSpy
      .mockResolvedValueOnce(
        endTurnResponse({
          tools: [
            {
              name: "createComment",
              input: { owner: "acme", repo: "repo", issue_number: 7, body: "ok" },
            },
          ],
        }),
      )
      .mockRejectedValueOnce(apiError(400));
    const result = await runWith(makeRetryingStep({ retries: 3 }));
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "anthropic_request_rejected",
    });
    expect(anthropicCreateSpy).toHaveBeenCalledTimes(2);
    expect(persistTurnCostAwaitableSpy).toHaveBeenCalledTimes(1);
    expect(
      (deadletterCall()![1] as { extra: Record<string, unknown> }).extra,
    ).toMatchObject({ status: 400, turn: 2 });
  });

  it("an error after billing is never read as a rejection, even with a 4xx status", async () => {
    anthropicCreateSpy.mockResolvedValue(endTurnResponse());
    persistTurnCostAwaitableSpy.mockRejectedValue(
      Object.assign(new Error("rpc failed"), { status: 400 }),
    );
    const step = makeRetryingStep({ retries: 3 });
    const result = await runWith(step);
    expect(step.memoized.has("turn-1-claude")).toBe(false);
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "anthropic_timeout",
    });
  });

  it("the returned rejection is plain JSON (Inngest memoizes it as-is)", async () => {
    anthropicCreateSpy.mockRejectedValue(apiError(400));
    const step = makeRetryingStep({ retries: 3 });
    await runWith(step);
    const memo = step.memoized.get("turn-1-claude") as Record<string, unknown>;
    expect(JSON.parse(JSON.stringify(memo))).toEqual(memo);
    expect(memo).toMatchObject({
      kind: "turn_rejection",
      rejected: "anthropic_request_rejected",
      status: 400,
    });
    expect(String(memo.message).startsWith("400 ")).toBe(true);
    expect(typeof memo.stack).toBe("string");
  });
});

// --- Terminal stop reasons ------------------------------------------------------

describe("stop_reason other than end_turn/tool_use is terminal", () => {
  it.each([
    ["refusal", "leader_refused"],
    ["model_context_window_exceeded", "leader_response_truncated"],
    ["max_tokens", "leader_response_truncated"],
  ])("%s → %s, with no further create call", async (stopReason, reason) => {
    anthropicCreateSpy.mockResolvedValueOnce({
      ...endTurnResponse(),
      stop_reason: stopReason,
    });
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    expect(result).toEqual({ acknowledged: false, failureReason: reason });
    expect(anthropicCreateSpy).toHaveBeenCalledTimes(1);
  });
});
