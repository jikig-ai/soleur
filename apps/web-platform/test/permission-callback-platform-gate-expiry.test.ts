/**
 * #11303 — the gated platform-tool branch of `createCanUseTool` used to await `abortableReviewGate` unguarded. The gate
 * rejects on timeout (5 min) or abort, which threw out of `canUseTool` and stranded the conversation in
 * `waiting_for_user`. Removing gated names from SDK `allowedTools` (the filter in the next commit) makes this branch
 * reachable in production for the first time, so its lifecycle must fail closed first.
 *
 * Contract under test (Guard 2 of the plan): for every gated platform-tool invocation `canUseTool` returns a verdict
 * (never throws); the verdict is deny unless the selection is exactly `Approve`; the conversation status is `active`
 * again once the LAST pending gate resolves, except when the session controller is aborted (the abort branch of
 * `startAgentSession` owns the terminal status then).
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

const { log, mockWarn, mockLogDecision } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarn: vi.fn(),
  mockLogDecision: vi.fn(),
}));
vi.mock("../server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("../server/permission-log", () => ({ logPermissionDecision: mockLogDecision }));
vi.mock("../server/observability", () => ({ warnSilentFallback: mockWarn, reportSilentFallback: vi.fn() }));

import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";

const P = "mcp__soleur_platform__";
const EXPIRED_DENY =
  "The approval request expired before it was answered, so the action was not performed. Do not retry unless the user asks.";
const REJECTED_DENY = "User rejected the action. Do not retry unless the user asks.";

function makeCtx(
  gate: () => Promise<string>,
  opts: { controller?: AbortController; extra?: Record<string, unknown> } = {},
) {
  const controller = opts.controller ?? new AbortController();
  const deps = {
    abortableReviewGate: vi.fn(gate),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    ...opts.extra,
  };
  const ctx = {
    userId: "u",
    conversationId: "c",
    leaderId: "cto",
    workspacePath: "/tmp/ws",
    platformToolNames: [`${P}email_send`, `${P}crm_note_append`, `${P}workstream_issue_close`, `${P}github_push_branch`],
    pluginMcpServerNames: [],
    repoOwner: "o",
    repoName: "r",
    session: { abort: controller, reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: controller.signal,
    deps,
  } as unknown as CanUseToolContext;
  return { ctx, deps, controller };
}

const statuses = (deps: { updateConversationStatus: { mock: { calls: unknown[][] } } }) =>
  deps.updateConversationStatus.mock.calls.map((c) => c[1]);

// canUseTool may resolve null in the SDK type; every path under test returns a verdict, so a null here is a test failure.
const verdict = async (r: Promise<unknown>) => (await r) as { behavior: string; message: string };

const callTool = (
  ctx: CanUseToolContext,
  tool = "email_send",
  extra: Record<string, unknown> = {},
  input: Record<string, unknown> = { to: "x@example.invalid", subject: "s", body: "b" },
) =>
  verdict(
    createCanUseTool(ctx)(`${P}${tool}`, input, {
      signal: new AbortController().signal,
      toolUseID: "t",
      requestId: "r",
      ...extra,
    } as never),
  );

const tick = () => new Promise((r) => setTimeout(r, 10));

beforeEach(() => {
  vi.clearAllMocks();
});

describe("gated platform tool: gate expiry fails closed (#11303)", () => {
  test("a timed-out gate denies with the static expiry text, restores active, never throws", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("review gate timeout")));
    const res = await callTool(ctx);
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1); // precondition: the stub was reached and rejected
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(EXPIRED_DENY);
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("expiry logs at warn (the shipped level) with sec:true and decision platform-gate-expired, and records the decision", async () => {
    const { ctx } = makeCtx(() => Promise.reject(new Error("review gate timeout")));
    await callTool(ctx);
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ sec: true, decision: "platform-gate-expired", tool: `${P}email_send` }),
      expect.any(String),
    );
    expect(mockLogDecision).toHaveBeenCalledWith("canUseTool-platform-gated", `${P}email_send`, "deny", "gate expired");
    // expected user behaviour: no Sentry capture for expiry itself
    expect(mockWarn).not.toHaveBeenCalled();
  });

  test.each([
    ["AbortError-shaped", () => Object.assign(new Error("aborted"), { name: "AbortError" })],
    ["plain Error timeout", () => new Error("timeout")],
  ])("%s rejection after the session controller aborted: deny, and NO active write (abort branch owns the status)", async (_n, mk) => {
    const controller = new AbortController();
    const { ctx, deps } = makeCtx(
      () => {
        controller.abort(); // user Stop or disconnect grace fires while the card is open
        return Promise.reject(mk());
      },
      { controller },
    );
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(EXPIRED_DENY);
    expect(statuses(deps)).toEqual(["waiting_for_user"]);
  });

  test("a rejection after an already-aborted signal behaves the same (both abort reasons end without an active write)", async () => {
    const controller = new AbortController();
    controller.abort(new Error("disconnect-grace"));
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("aborted")), { controller });
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
    expect(statuses(deps)).not.toContain("active");
  });

  test("a per-call abort with the session still alive denies and RESTORES active", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(Object.assign(new Error("aborted"), { name: "AbortError" })));
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("the gate stub resolving Approve instead would allow (suite-edit row: the timeout case's precondition is the rejection)", async () => {
    const { ctx } = makeCtx(() => Promise.resolve("Approve"));
    expect((await callTool(ctx)).behavior).toBe("allow");
  });
});

describe("gated platform tool: verdicts", () => {
  test("Approve allows and restores active; the card was emitted first", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"));
    const res = await callTool(ctx);
    expect(res.behavior).toBe("allow");
    expect(deps.sendToClient).toHaveBeenCalledWith("u", expect.objectContaining({ type: "review_gate", options: ["Approve", "Reject"] }));
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test.each(["Reject", "approve", "Approve ", "Maybe", ""])("selection %j denies with the static no-retry text", async (sel) => {
    const { ctx, deps } = makeCtx(() => Promise.resolve(sel));
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(REJECTED_DENY);
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test.each(["crm_note_append", "workstream_issue_close", "github_push_branch"])(
    "a gated tool outside the probed eight (%s) takes the identical expiry path",
    async (tool) => {
      const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")));
      const res = await callTool(ctx, tool, {}, { contactId: "c1", number: 1, branch: "b" });
      expect(res.behavior).toBe("deny");
      expect(res.message).toBe(EXPIRED_DENY);
      expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
    },
  );

  test("a subagent call (options.agentID set) takes the identical verdict path", async () => {
    const a = makeCtx(() => Promise.reject(new Error("timeout")));
    const b = makeCtx(() => Promise.reject(new Error("timeout")));
    const main = await callTool(a.ctx);
    const sub = await callTool(b.ctx, "email_send", { agentID: "agent-1" });
    expect(sub).toEqual(main);
    expect(statuses(b.deps)).toEqual(statuses(a.deps));
  });

  test("the deny texts are static: no tool input in them", async () => {
    const { ctx } = makeCtx(() => Promise.reject(new Error("timeout")));
    const res = await callTool(ctx, "email_send", {}, { to: "victim@example.invalid", subject: "SECRET-SUBJECT", body: "b" });
    expect(res.message).not.toMatch(/victim|SECRET-SUBJECT/);
  });
});

describe("gated platform tool: status lifecycle", () => {
  test("in-window: while the gate is pending the status is waiting_for_user and has NOT been restored", async () => {
    let release!: (v: string) => void;
    const { ctx, deps } = makeCtx(() => new Promise<string>((r) => (release = r)));
    const pending = callTool(ctx);
    await tick();
    expect(statuses(deps)).toEqual(["waiting_for_user"]); // a return-time-only assertion cannot see an early `active`
    release("Approve");
    await pending;
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("two concurrent gated calls: one waiting_for_user, one active, only after the LAST resolves", async () => {
    const resolvers: Array<(v: string) => void> = [];
    const { ctx, deps } = makeCtx(() => new Promise<string>((r) => resolvers.push(r)));
    const run = createCanUseTool(ctx);
    const call = (tool: string) =>
      run(`${P}${tool}`, { to: "x", subject: "s", body: "b", contactId: "c" }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never);
    const both = Promise.all([call("email_send"), call("crm_note_append")]);
    await tick();
    expect(resolvers).toHaveLength(2);
    resolvers[0]("Approve");
    await tick();
    expect(statuses(deps)).toEqual(["waiting_for_user"]); // the other card is still open
    resolvers[1]("Reject");
    const done = await both;
    expect(done.map((d) => d?.behavior).sort()).toEqual(["allow", "deny"]);
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("a gated call stacked with a Bash gate shares the pending counter", async () => {
    const resolvers: Array<(v: string) => void> = [];
    const { ctx, deps } = makeCtx(() => new Promise<string>((r) => resolvers.push(r)));
    const run = createCanUseTool(ctx);
    const opts = { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never;
    const both = Promise.all([
      run(`${P}email_send`, { to: "x", subject: "s", body: "b" }, opts),
      run("Bash", { command: "make deploy-something" }, opts),
    ]);
    await tick();
    expect(resolvers).toHaveLength(2);
    resolvers[0]("Approve");
    await tick();
    expect(statuses(deps)).toEqual(["waiting_for_user"]);
    resolvers[1]("Reject");
    await both;
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("a status write failing on HOLD keeps the verdict and emits platform-gate-status-hold with its own static message", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Reject"));
    deps.updateConversationStatus.mockRejectedValueOnce(new Error("db down"));
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(REJECTED_DENY);
    expect(mockWarn).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "cc-permissions", op: "platform-gate-status-hold", message: expect.any(String) }),
    );
  });

  test("a status write failing on RESTORE keeps the verdict and emits platform-gate-status-restore", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"));
    deps.updateConversationStatus.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("db down"));
    const res = await callTool(ctx);
    expect(res.behavior).toBe("allow");
    expect(mockWarn).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "platform-gate-status-restore", message: expect.any(String) }),
    );
  });

  test("a throwing status write never replaces a timeout verdict", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")));
    deps.updateConversationStatus.mockRejectedValue(new Error("db down"));
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
  });
});

describe("status-op labels", () => {
  test("every platform-* and bash-* status op carries its own static, distinct message", async () => {
    const seen = new Map<string, string>();
    const record = () => {
      for (const [, o] of mockWarn.mock.calls as [unknown, { op: string; message: string }][]) seen.set(o.op, o.message);
    };
    // platform hold + restore
    const p1 = makeCtx(() => Promise.resolve("Approve"));
    p1.deps.updateConversationStatus.mockRejectedValue(new Error("db down"));
    await callTool(p1.ctx);
    record();
    // bash hold + restore
    const b1 = makeCtx(() => Promise.resolve("Approve"));
    b1.deps.updateConversationStatus.mockRejectedValue(new Error("db down"));
    await createCanUseTool(b1.ctx)("Bash", { command: "make deploy-something" }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never);
    record();
    expect([...seen.keys()].sort()).toEqual([
      "bash-gate-status-hold",
      "bash-gate-status-restore",
      "platform-gate-status-hold",
      "platform-gate-status-restore",
    ]);
    const messages = [...seen.values()];
    expect(new Set(messages).size).toBe(4);
    for (const m of messages) {
      expect(typeof m).toBe("string");
      expect(m).not.toBe("cc-permissions silent fallback"); // not the shared default
    }
  });
});

describe("Bash class regression (unchanged by the platform restore policy)", () => {
  test("a Bash gate rejected after the controller aborted STILL restores active", async () => {
    const controller = new AbortController();
    const { ctx, deps } = makeCtx(
      () => {
        controller.abort();
        return Promise.reject(new Error("aborted"));
      },
      { controller },
    );
    const res = await verdict(createCanUseTool(ctx)("Bash", { command: "make deploy-something" }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never));
    expect(res.behavior).toBe("deny");
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });
});
