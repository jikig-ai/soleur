/**
 * #11303 — the gated platform-tool branch of `createCanUseTool` used to await `abortableReviewGate` unguarded. The gate
 * rejects on timeout (5 min) or abort, which threw out of `canUseTool` and stranded the conversation in
 * `waiting_for_user`. Removing gated names from SDK `allowedTools` (`buildAllowedTools`) makes this branch reachable
 * for the legacy runner, so its lifecycle must fail closed.
 *
 * Contract under test: for every gated platform-tool invocation `canUseTool` returns a verdict (never throws); the
 * verdict is deny unless the selection is exactly `Approve`; the conversation status policy is ONE deterministic rule for
 * both gate classes (ADR-305):
 *   - hold: a compare-and-set to `waiting_for_user` on the FIRST pending gate;
 *   - restore: only when the LAST pending gate resolves AND the session controller was not aborted, and only as a
 *     compare-and-set `waiting_for_user -> active` (never over `completed` / `failed`);
 *   - on abort the abort branch of `startAgentSession` finalizes from `active` OR `waiting_for_user`, so either write
 *     order ends in the same state (a disconnect with a card pending ends `failed`).
 * Also pinned here: the fail-closed card (no card, no status write, no notification when the input cannot be shown in
 * full), the non-interactive fast deny, and the pending-card cap.
 */
import { vi, describe, test, expect, beforeEach, afterEach } from "vitest";

const { log, mockWarn, mockLogDecision } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarn: vi.fn(),
  mockLogDecision: vi.fn(),
}));
vi.mock("../server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("../server/permission-log", () => ({ logPermissionDecision: mockLogDecision }));
vi.mock("../server/observability", () => ({ warnSilentFallback: mockWarn, reportSilentFallback: vi.fn() }));

import { createCanUseTool, type CanUseToolContext, type StatusGuard } from "../server/permission-callback";
import { abortableReviewGate, REVIEW_GATE_TIMEOUT_MS } from "../server/review-gate";

const P = "mcp__soleur_platform__";
const TELL_USER = "Tell the user the action was not performed and ask how they want to proceed.";
const EXPIRED_DENY = `The approval request expired before it was answered, so the action was not performed. Do not retry unless the user asks. ${TELL_USER}`;
const REJECTED_DENY = `User rejected the action. Do not retry unless the user asks. ${TELL_USER}`;
const NON_INTERACTIVE_DENY = "This action needs interactive approval and is not available in background sync. Do not retry.";
const TOO_MANY_DENY = "Too many approvals are waiting. Answer or decline the pending ones first.";
const RECIPIENT_DENY =
  "The recipient could not be shown in full for review, so the email was not sent. Fix the recipient and try again.";

/** A gate that never settles: the card stays open until the test releases it some other way (or never). */
const HANG = () => new Promise<string>(() => {});

type Row = { status: string };

function makeCtx(
  gate: (...args: unknown[]) => Promise<string>,
  opts: { controller?: AbortController; extra?: Record<string, unknown>; ctxExtra?: Record<string, unknown>; row?: Row } = {},
) {
  const controller = opts.controller ?? new AbortController();
  const row: Row = opts.row ?? { status: "active" };
  // A compare-and-set store with the production semantics: a guarded write lands only when the CURRENT status is in the set.
  const updateConversationStatus = vi.fn(async (_id: string, status: string, guard?: StatusGuard) => {
    if (guard && !(guard.onlyIfStatusIn as readonly string[]).includes(row.status)) return;
    row.status = status;
  });
  const deps = {
    abortableReviewGate: vi.fn(gate),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus,
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
    ...opts.ctxExtra,
    deps,
  } as unknown as CanUseToolContext;
  return { ctx, deps, controller, row };
}

/** What the ABORT branch of startAgentSession does (ABORT_FINALIZE_FROM_STATUSES): finalize from active OR waiting_for_user. */
const abortFinalize = (row: Row, next: "failed" | "waiting_for_user") => {
  if (row.status === "active" || row.status === "waiting_for_user") row.status = next;
};

const statuses = (deps: { updateConversationStatus: { mock: { calls: unknown[][] } } }) =>
  deps.updateConversationStatus.mock.calls.map((c) => c[1]);
const guards = (deps: { updateConversationStatus: { mock: { calls: unknown[][] } } }) =>
  deps.updateConversationStatus.mock.calls.map((c) => c[2]);

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
    const { ctx, deps, row } = makeCtx(() => Promise.reject(new Error("review gate timeout")));
    const res = await callTool(ctx);
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1); // precondition: the stub was reached and rejected
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(EXPIRED_DENY);
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
    expect(row.status).toBe("active");
  });

  test("the hold and the restore are compare-and-set writes (never over a terminal row)", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"));
    await callTool(ctx);
    expect(guards(deps)).toEqual([
      { onlyIfStatusIn: ["active", "waiting_for_user"] },
      { onlyIfStatusIn: ["waiting_for_user"] },
    ]);
  });

  test("timeout logs at warn (it must reach Better Stack) with the delivery, conversation and reason fields", async () => {
    const { ctx } = makeCtx(() => Promise.reject(new Error("review gate timeout")));
    await callTool(ctx);
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({
        sec: true,
        decision: "platform-gate-expired",
        reason: "timeout",
        delivered: true,
        conversationId: "c",
        tool: `${P}email_send`,
      }),
      "Platform tool gate expired without an answer; denied",
    );
    expect(mockLogDecision).toHaveBeenCalledWith("canUseTool-platform-gated", `${P}email_send`, "deny", "gate expired");
    // expected user behaviour: no Sentry capture for expiry itself
    expect(mockWarn).not.toHaveBeenCalled();
  });

  test("an offline user's expiry row says delivered:false", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")));
    deps.sendToClient.mockReturnValue(false);
    await callTool(ctx);
    expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ decision: "platform-gate-expired", delivered: false }), expect.any(String));
  });

  test.each([
    ["AbortError-shaped", () => Object.assign(new Error("aborted"), { name: "AbortError" })],
    ["plain Error timeout", () => new Error("timeout")],
  ])("%s rejection after the session controller aborted: deny, logged as aborted, and NO restore", async (_n, mk) => {
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
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ decision: "platform-gate-aborted", reason: "aborted", delivered: true, conversationId: "c" }),
      "Platform tool gate aborted before an answer; denied",
    );
    expect(mockLogDecision).toHaveBeenCalledWith("canUseTool-platform-gated", `${P}email_send`, "deny", "gate aborted");
  });

  test("a rejection after an already-aborted signal behaves the same (no restore)", async () => {
    const controller = new AbortController();
    controller.abort(new Error("disconnect-grace"));
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("aborted")), { controller });
    const res = await callTool(ctx);
    expect(res.behavior).toBe("deny");
    expect(statuses(deps)).not.toContain("active");
  });

  test("a per-call abort with the session still alive denies, logs aborted, and RESTORES active", async () => {
    const perCall = new AbortController();
    const { ctx, deps } = makeCtx(() => {
      perCall.abort();
      return Promise.reject(Object.assign(new Error("aborted"), { name: "AbortError" }));
    });
    const res = await callTool(ctx, "email_send", { signal: perCall.signal });
    expect(res.behavior).toBe("deny");
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
    expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ decision: "platform-gate-aborted" }), expect.any(String));
  });

  test("the gate stub resolving Approve instead would allow (suite-edit row: the timeout case's precondition is the rejection)", async () => {
    const { ctx } = makeCtx(() => Promise.resolve("Approve"));
    expect((await callTool(ctx)).behavior).toBe("allow");
  });
});

describe("gated platform tool: the per-call signal reaches the gate", () => {
  test("the gate is given options.signal itself, and aborting it denies (a detached controller would hang)", async () => {
    const perCall = new AbortController();
    const { ctx, deps } = makeCtx((...args: unknown[]) => {
      const signal = args[2] as AbortSignal;
      return new Promise<string>((_resolve, reject) => signal.addEventListener("abort", () => reject(signal.reason)));
    });
    const pending = callTool(ctx, "email_send", { signal: perCall.signal });
    await tick();
    expect(deps.abortableReviewGate.mock.calls[0][2]).toBe(perCall.signal);
    perCall.abort();
    const res = await pending;
    expect(res.behavior).toBe("deny");
    expect(res.message).toBe(EXPIRED_DENY);
  });

  test("composed with the REAL abortableReviewGate: no answer within REVIEW_GATE_TIMEOUT_MS denies and restores", async () => {
    vi.useFakeTimers();
    try {
      const { ctx, deps, row } = makeCtx((...args: unknown[]) =>
        abortableReviewGate(args[0] as never, args[1] as string, args[2] as AbortSignal, undefined, args[4] as string[]),
      );
      const pending = callTool(ctx);
      await vi.advanceTimersByTimeAsync(REVIEW_GATE_TIMEOUT_MS + 1);
      const res = await pending;
      expect(res.behavior).toBe("deny");
      expect(res.message).toBe(EXPIRED_DENY);
      expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
      expect(row.status).toBe("active");
      expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ decision: "platform-gate-expired", reason: "timeout" }), expect.any(String));
    } finally {
      vi.useRealTimers();
    }
  });

  test("the gate is registered BEFORE the waiting_for_user write lands (a fast Approve is never 'not found')", async () => {
    let releaseWrite!: () => void;
    const order: string[] = [];
    const { ctx, deps } = makeCtx(() => {
      order.push("gate-registered");
      return Promise.resolve("Approve");
    });
    deps.updateConversationStatus.mockImplementationOnce(
      () =>
        new Promise<void>((r) => {
          order.push("write-started");
          releaseWrite = () => {
            order.push("write-done");
            r();
          };
        }),
    );
    const pending = callTool(ctx);
    await tick();
    expect(order).toEqual(["gate-registered", "write-started"]);
    releaseWrite();
    expect((await pending).behavior).toBe("allow");
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

  test("both deny texts tell the agent to tell the user the action was not performed", () => {
    expect(EXPIRED_DENY).toContain(TELL_USER);
    expect(REJECTED_DENY).toContain(TELL_USER);
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
      run(`${P}${tool}`, { to: "x@example.invalid", subject: "s", body: "b", contactId: "c" }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never);
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
      run(`${P}email_send`, { to: "x@example.invalid", subject: "s", body: "b" }, opts),
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

describe("abort / restore ordering ends in one deterministic state (ADR-305)", () => {
  const BASH = { command: "make deploy-something" };
  const opts = () => ({ signal: new AbortController().signal, toolUseID: "t", requestId: "r" }) as never;

  test("abort-first: the abort branch finalizes failed while the card is pending, then the gate rejects -> still failed", async () => {
    const controller = new AbortController();
    const { ctx, row } = makeCtx(
      (...args: unknown[]) => {
        const signal = args[2] as AbortSignal;
        return new Promise<string>((_r, rej) => controller.signal.addEventListener("abort", () => rej(signal.reason ?? new Error("aborted"))));
      },
      { controller },
    );
    const pending = callTool(ctx);
    await tick();
    expect(row.status).toBe("waiting_for_user");
    controller.abort(new Error("disconnected"));
    abortFinalize(row, "failed"); // accepts waiting_for_user: a disconnect with a card pending ends failed
    expect(row.status).toBe("failed");
    expect((await pending).behavior).toBe("deny");
    expect(row.status).toBe("failed"); // the aborted gate did NOT restore active over it
  });

  test("restore-first (no abort): Approve restores active, a later abort finalizes it -> failed", async () => {
    const controller = new AbortController();
    const { ctx, row } = makeCtx(() => Promise.resolve("Approve"), { controller });
    await callTool(ctx);
    expect(row.status).toBe("active");
    controller.abort(new Error("disconnected"));
    abortFinalize(row, "failed");
    expect(row.status).toBe("failed");
  });

  test("a user Stop with a card pending ends waiting_for_user in either order", async () => {
    const controller = new AbortController();
    const { ctx, row } = makeCtx(() => HANG(), { controller });
    void callTool(ctx);
    await tick();
    controller.abort(new Error("user stop"));
    abortFinalize(row, "waiting_for_user");
    expect(row.status).toBe("waiting_for_user");
  });

  test("a concurrent `completed` is NOT overwritten by the restore (compare-and-set)", async () => {
    let release!: (v: string) => void;
    const { ctx, row } = makeCtx(() => new Promise<string>((r) => (release = r)));
    const pending = callTool(ctx);
    await tick();
    expect(row.status).toBe("waiting_for_user");
    row.status = "completed"; // the result branch wrote a terminal state while the card was open
    release("Approve");
    await pending;
    expect(row.status).toBe("completed");
  });

  test("a terminal row is never revived by the hold either", async () => {
    const { ctx, row } = makeCtx(() => Promise.resolve("Approve"), { row: { status: "failed" } });
    await callTool(ctx);
    expect(row.status).toBe("failed");
  });

  test("stacked Bash + platform gates with an abort: neither restores, the abort branch owns the end state", async () => {
    const controller = new AbortController();
    const { ctx, deps, row } = makeCtx(
      () => new Promise<string>((_r, rej) => controller.signal.addEventListener("abort", () => rej(new Error("aborted")))),
      { controller },
    );
    const run = createCanUseTool(ctx);
    const both = Promise.all([run(`${P}email_send`, { to: "x@example.invalid", subject: "s", body: "b" }, opts()), run("Bash", BASH, opts())]);
    await tick();
    expect(statuses(deps)).toEqual(["waiting_for_user"]);
    controller.abort(new Error("disconnected"));
    abortFinalize(row, "failed");
    const done = await both;
    expect(done.map((d) => d?.behavior)).toEqual(["deny", "deny"]);
    expect(statuses(deps)).toEqual(["waiting_for_user"]); // no `active` write from either class
    expect(row.status).toBe("failed");
  });
});

describe("fail-closed card: an email the card cannot show in full is denied before anything exists", () => {
  test.each([
    ["an over-long recipient", { to: `${"a".repeat(260)}@example.invalid`, subject: "s", body: "b" }, RECIPIENT_DENY],
    ["a recipient list", { to: "a@example.invalid, b@example.invalid", subject: "s", body: "b" }, RECIPIENT_DENY],
    ["a body over 4000 characters", { to: "x@example.invalid", subject: "s", body: "b".repeat(4001) }, "Shorten the body to 4,000 characters or fewer and try again."],
  ])("%s: static deny, no card, no status write, no notification, no gate", async (_n, input, message) => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"));
    deps.sendToClient.mockReturnValue(false); // even an offline user gets no push
    const res = await callTool(ctx, "email_send", {}, input);
    expect(res).toEqual({ behavior: "deny", message });
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(deps.notifyOfflineUser).not.toHaveBeenCalled();
    expect(deps.updateConversationStatus).not.toHaveBeenCalled();
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ decision: "platform-gate-unreviewable" }), expect.any(String));
  });

  test("the deny path leaks no tool input into the message or the log row", async () => {
    const { ctx } = makeCtx(() => Promise.resolve("Approve"));
    const res = await callTool(ctx, "email_send", {}, { to: "a@example.invalid, victim@example.invalid", subject: "SECRET-SUBJECT", body: "SECRET-BODY" });
    expect(res.message).not.toMatch(/victim|SECRET/);
    expect(JSON.stringify(log.warn.mock.calls)).not.toMatch(/victim|SECRET/);
  });
});

describe("non-interactive sessions (background auto-sync)", () => {
  test("a gated platform tool is denied at once: no card, no status write, no notification", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"), { ctxExtra: { nonInteractive: true } });
    deps.sendToClient.mockReturnValue(false);
    const res = await callTool(ctx);
    expect(res).toEqual({ behavior: "deny", message: NON_INTERACTIVE_DENY });
    expect(deps.sendToClient).not.toHaveBeenCalled();
    expect(deps.notifyOfflineUser).not.toHaveBeenCalled();
    expect(deps.updateConversationStatus).not.toHaveBeenCalled();
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ decision: "platform-gate-non-interactive" }), expect.any(String));
  });

  test("the flag is explicit: an interactive ctx with the same prompt-less shape still shows the card", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"));
    expect((await callTool(ctx)).behavior).toBe("allow");
    expect(deps.sendToClient).toHaveBeenCalledTimes(1);
  });
});

describe("pending-card cap", () => {
  test("a 6th gated platform call is denied while 5 cards are open (Bash and platform counted together)", async () => {
    const { ctx, deps } = makeCtx(() => HANG());
    const run = createCanUseTool(ctx);
    const opts = () => ({ signal: new AbortController().signal, toolUseID: "t", requestId: "r" }) as never;
    void run("Bash", { command: "make one" }, opts());
    void run("Bash", { command: "make two" }, opts());
    for (let i = 0; i < 3; i++) void run(`${P}crm_note_append`, { contactId: `c${i}`, lens: ["sales"] }, opts());
    await tick();
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(5);
    const sentBefore = deps.sendToClient.mock.calls.length;
    const res = await verdict(run(`${P}crm_note_append`, { contactId: "c9", lens: ["sales"] }, opts()));
    expect(res).toEqual({ behavior: "deny", message: TOO_MANY_DENY });
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(5);
    expect(deps.sendToClient.mock.calls.length).toBe(sentBefore);
    expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ decision: "platform-gate-too-many-pending" }), expect.any(String));
  });

  test("below the cap a 5th card is still shown", async () => {
    const { ctx, deps } = makeCtx(() => HANG());
    const run = createCanUseTool(ctx);
    const opts = () => ({ signal: new AbortController().signal, toolUseID: "t", requestId: "r" }) as never;
    for (let i = 0; i < 5; i++) void run(`${P}crm_note_append`, { contactId: `c${i}`, lens: ["sales"] }, opts());
    await tick();
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(5);
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
    expect(new Set(messages).size).toBe(4); // four distinct, static messages (none is a shared default)
    for (const m of messages) expect(typeof m).toBe("string");
  });
});

describe("Bash class follows the same deterministic status rule", () => {
  test("a Bash gate rejected after the controller aborted does NOT restore active (the abort branch owns the status)", async () => {
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
    expect(statuses(deps)).toEqual(["waiting_for_user"]);
  });

  test("a Bash gate rejected with the session alive still restores active", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")));
    await verdict(createCanUseTool(ctx)("Bash", { command: "make deploy-something" }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never));
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });
});

afterEach(() => {
  vi.useRealTimers();
});
