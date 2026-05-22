import { beforeEach, describe, expect, it, vi } from "vitest";

// PR-A (#4124) — Tests for the `agent-on-spawn-requested` Inngest function.
//
// Drives `agentOnSpawnRequestedHandler` directly with a mock `step` so the
// Inngest runtime is not required for unit coverage (mirror of the
// `cfo-on-payment-failed.test.ts` shape). Mocks:
//   - service-role Supabase client (users SELECT + action_sends UPDATE)
//   - createGitHubAppClient → an Octokit-shaped mock
//   - reportSilentFallback observability mirror

// --- Module mocks (hoisted by vitest) ----------------------------------------

interface UpdateCall {
  table: string;
  patch: unknown;
  eqArgs: unknown[];
}
const updateCalls: UpdateCall[] = [];
let usersSelectResult: { data: unknown; error: unknown } = {
  data: { github_installation_id: 99 },
  error: null,
};

function buildSupabaseClient() {
  // Fresh chain per call; mock state lives in module-scoped vars above.
  let currentTable = "";
  let currentPatch: unknown = undefined;
  const eqArgs: unknown[] = [];

  const chain = {
    from(table: string) {
      currentTable = table;
      return chain;
    },
    select(_cols: string) {
      return chain;
    },
    update(patch: unknown) {
      currentPatch = patch;
      return chain;
    },
    eq(col: string, val: unknown) {
      eqArgs.push({ col, val });
      // If we are mid-UPDATE, this is the terminal — return a resolved
      // PostgrestBuilder-shaped result. If we are mid-SELECT, the
      // terminal is .maybeSingle() which is handled separately.
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
    maybeSingle() {
      return Promise.resolve(usersSelectResult);
    },
  };
  return chain;
}

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: vi.fn(() => buildSupabaseClient()),
}));

const createCommentSpy = vi.fn();
const addLabelsSpy = vi.fn();
const createGitHubAppClientSpy = vi.fn(async () => ({
  rest: {
    issues: {
      createComment: createCommentSpy,
      addLabels: addLabelsSpy,
    },
  },
}));
vi.mock("@/server/github/app-client", () => ({
  createGitHubAppClient: createGitHubAppClientSpy,
}));

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: {
    createFunction: () => ({}) as unknown,
  },
}));

// --- Helpers ----------------------------------------------------------------

interface MockStep {
  calls: { name: string }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      // Record entry BEFORE awaiting cb so step ordering is observable
      // even when the callback throws (matches Inngest's per-step trace
      // semantics — every entered step is visible in the run log).
      calls.push({ name });
      return await cb();
    },
  };
}

const logger = { warn: vi.fn(), info: vi.fn(), error: vi.fn() };

function makeEvent(args: {
  sourceRef: string;
  founderId?: string;
  messageId?: string;
  actionClass?: string;
  actionSendId?: string;
}) {
  return {
    name: "agent.spawn.requested" as const,
    data: {
      founderId: args.founderId ?? "founder-123",
      messageId: args.messageId ?? "msg-abc",
      actionClass: (args.actionClass ?? "engineering.pr_review_pending") as never,
      sourceRef: args.sourceRef,
      actionSendId: args.actionSendId ?? "as-001",
    },
  };
}

// --- Tests ------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  updateCalls.length = 0;
  // Default happy path: users row carries installation 99.
  usersSelectResult = {
    data: { github_installation_id: 99 },
    error: null,
  };
  createCommentSpy.mockResolvedValue({
    data: { html_url: "https://github.com/acme/repo/pull/7#issuecomment-1" },
  });
  addLabelsSpy.mockResolvedValue({ data: [] });
});

describe("agent-on-spawn-requested handler", () => {
  it("posts a PR comment for pr-* source refs (happy path)", async () => {
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step,
      logger,
    });
    expect(result).toMatchObject({
      acknowledged: true,
      artifactUrl: "https://github.com/acme/repo/pull/7#issuecomment-1",
    });
    expect(createCommentSpy).toHaveBeenCalledTimes(1);
    expect(addLabelsSpy).not.toHaveBeenCalled();
    expect(createGitHubAppClientSpy).toHaveBeenCalledWith(99, "founder-123");
    expect(step.calls.map((c) => c.name)).toEqual([
      "resolve-installation",
      "post-acknowledgment",
      "mark-acknowledged",
    ]);
  });

  it("adds an issue label for non-pr source refs (happy path)", async () => {
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({
        sourceRef: "issue-acme:repo:42",
        actionClass: "triage.p0p1_issue",
      }),
      step,
      logger,
    });
    expect(result).toMatchObject({ acknowledged: true });
    expect(addLabelsSpy).toHaveBeenCalledTimes(1);
    expect(addLabelsSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        owner: "acme",
        repo: "repo",
        issue_number: 42,
        labels: ["soleur/acknowledged"],
      }),
    );
    expect(createCommentSpy).not.toHaveBeenCalled();
  });

  it("kb_drift link-* source refs deadletter as malformed_source_ref in PR-A (resolved in PR-B)", async () => {
    // PR-A's deterministic stub only targets pr-*, issue-*, secret-scan-*
    // source refs (the deriveSourceRef shapes that carry owner+repo+number).
    // kb_drift `link-<hash>` and `anchor-<hash>` refs have no GitHub
    // issue/PR target; PR-B's leader-prompt loop adds per-class
    // resolution. Until then, the Inngest function classifies the ref as
    // malformed and persists failure_reason.
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({
        sourceRef: "link-deadbeef00000000",
        actionClass: "knowledge.kb_drift",
      }),
      step,
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "malformed_source_ref",
    });
    expect(addLabelsSpy).not.toHaveBeenCalled();
    expect(createCommentSpy).not.toHaveBeenCalled();
  });

  it("persists failure_reason when founder lacks github_installation_id (cross-tenant guard)", async () => {
    usersSelectResult = {
      data: { github_installation_id: null },
      error: null,
    };
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step,
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "github_installation_unauthorized",
    });
    expect(createGitHubAppClientSpy).not.toHaveBeenCalled();
    expect(createCommentSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(step.calls.map((c) => c.name)).toEqual([
      "resolve-installation",
      "persist-failure",
    ]);
    // The persist-failure step UPDATEs action_sends.failure_reason only.
    expect(updateCalls).toHaveLength(1);
    expect(updateCalls[0].table).toBe("action_sends");
    expect(updateCalls[0].patch).toEqual({
      failure_reason: "github_installation_unauthorized",
    });
  });

  it("persists failure_reason on GitHub 401 (Octokit hook.error path)", async () => {
    const err = Object.assign(new Error("Bad credentials"), { status: 401 });
    createCommentSpy.mockRejectedValueOnce(err);
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step,
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "github_installation_unauthorized",
    });
    expect(step.calls.map((c) => c.name)).toEqual([
      "resolve-installation",
      "post-acknowledgment",
      "persist-failure",
    ]);
  });

  it("classifies malformed source_ref as malformed_source_ref", async () => {
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    const step = makeStep();
    const result = await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "not-a-valid-ref" }),
      step,
      logger,
    });
    expect(result).toEqual({
      acknowledged: false,
      failureReason: "malformed_source_ref",
    });
  });

  it("UPDATE on action_sends touches ONLY acknowledged_at and artifact_url (WORM compat)", async () => {
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7" }),
      step: makeStep(),
      logger,
    });
    // Exactly one UPDATE in the happy path — the mark-acknowledged step.
    expect(updateCalls).toHaveLength(1);
    expect(updateCalls[0].table).toBe("action_sends");
    const patch = updateCalls[0].patch as Record<string, unknown>;
    const keys = Object.keys(patch).sort();
    expect(keys).toEqual(["acknowledged_at", "artifact_url"]);
    expect(typeof patch.acknowledged_at).toBe("string");
    expect(patch.artifact_url).toBe(
      "https://github.com/acme/repo/pull/7#issuecomment-1",
    );
  });

  it("duplicate handler invocations on the same actionSendId target the same row id", async () => {
    const { agentOnSpawnRequestedHandler } = await import(
      "@/server/inngest/functions/agent-on-spawn-requested"
    );
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7", actionSendId: "as-dup" }),
      step: makeStep(),
      logger,
    });
    await agentOnSpawnRequestedHandler({
      event: makeEvent({ sourceRef: "pr-acme:repo:7", actionSendId: "as-dup" }),
      step: makeStep(),
      logger,
    });
    // Inngest's `idempotency: "event.data.actionSendId"` prevents the
    // second from ever running in production; the handler must still be
    // safe under local dev replay. Both invocations target the same row.
    const ids = updateCalls.flatMap((u) =>
      u.eqArgs
        .filter((e): e is { col: string; val: unknown } =>
          typeof e === "object" &&
          e !== null &&
          (e as { col: string }).col === "id",
        )
        .map((e) => e.val),
    );
    expect(ids).toEqual(["as-dup", "as-dup"]);
  });
});
