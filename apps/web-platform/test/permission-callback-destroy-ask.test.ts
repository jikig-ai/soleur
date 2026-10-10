/**
 * #9776 / ADR-284 — the hosted must-ask lane in `canUseTool` (Guard 1 and Guard 2 of the plan).
 *
 * A command the destroy classifier matches is sent to the review gate with exactly two options (Approve, Reject)
 * BEFORE the autonomous bypass, the first-run disclosure hold and the batched-approval cache. Approval is this
 * command only: no acknowledgement, no cache entry. The blocklist still wins and the support persona still denies
 * (no gate). Telemetry carries the rule id and never the command (CLO C5).
 *
 * Sibling of `permission-callback-autonomous.test.ts` (same mock surface). The review-gate module is REAL here so the
 * lifecycle rows (AC-19) exercise the production resolver map, timeout and abort handling.
 */
import { vi, describe, test, expect, beforeEach, afterEach } from "vitest";

const { mockLog, mockWarnSilentFallback, mockReportSilentFallback, mockLogPermissionDecision } = vi.hoisted(() => ({
  mockLog: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarnSilentFallback: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLogPermissionDecision: vi.fn(),
}));

vi.mock("../server/logger", () => ({ createChildLogger: () => mockLog, default: mockLog }));
vi.mock("../server/permission-log", () => ({ logPermissionDecision: mockLogPermissionDecision }));
vi.mock("../server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: mockReportSilentFallback,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";
import { abortableReviewGate } from "../server/review-gate";
import { getBashApprovalCache, _resetBashApprovalCacheForTests } from "../server/permission-callback-bash-batch";

const FORCE_MAIN = "git push --force origin main";
const CANARY = "ghs_canary0123456789abcdef";

type Overrides = Record<string, unknown>;
function buildContext(depsOverrides: Overrides = {}, ctxOverrides: Overrides = {}) {
  const session = { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null };
  const deps = {
    abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    verifyAutonomousAck: vi.fn().mockResolvedValue("2026-10-10T00:00:00Z"),
    bashAutonomous: true,
    autonomousAckAt: 1_700_000_000_000,
    isOwner: true,
    resolveProtectedBranches: vi.fn().mockResolvedValue({ names: new Set(["main", "master"]), authoritative: true }),
    connectedRepoSlug: "alice/app",
    ...depsOverrides,
  };
  const ctx = {
    userId: "user-1",
    conversationId: "conv-1",
    leaderId: "cc_router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session,
    controllerSignal: new AbortController().signal,
    deps,
    ...ctxOverrides,
  } as unknown as CanUseToolContext;
  return { ctx, deps, session };
}
const sdkOptions = (signal = new AbortController().signal) => ({ signal, toolUseID: "tu-1", requestId: "req-1" });
async function run(ctx: CanUseToolContext, command: string, signal?: AbortSignal) {
  const result = await createCanUseTool(ctx)("Bash", { command }, sdkOptions(signal));
  if (result === null) throw new Error("canUseTool returned null");
  return result;
}
function gateFrames(deps: { sendToClient: ReturnType<typeof vi.fn> }) {
  return deps.sendToClient.mock.calls.map((c) => c[1]).filter((m) => m.type === "review_gate");
}
function allTelemetry(): string {
  return JSON.stringify([
    mockLog.info.mock.calls, mockLog.warn.mock.calls, mockLog.error.mock.calls, mockLog.debug.mock.calls,
    mockWarnSilentFallback.mock.calls, mockReportSilentFallback.mock.calls, mockLogPermissionDecision.mock.calls,
  ]);
}

beforeEach(() => {
  vi.clearAllMocks();
  _resetBashApprovalCacheForTests();
});

describe("lane: a matched command is gated in every posture (AC-1, AC-4)", () => {
  test.each([
    ["acked autonomous owner", {}],
    ["autonomous non-owner member", { isOwner: false }],
    ["non-autonomous", { bashAutonomous: false }],
  ])("%s: force-push over main gets the review gate, never an auto-approval", async (_label, over) => {
    const { ctx, deps } = buildContext(over);
    const res = await run(ctx, FORCE_MAIN);
    expect(res.behavior).toBe("allow"); // the mock gate answered Approve
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(deps.abortableReviewGate.mock.calls[0][4]).toEqual(["Approve", "Reject"]);
    const frames = gateFrames(deps);
    expect(frames).toHaveLength(1);
    expect(frames[0].options).toEqual(["Approve", "Reject"]);
  });

  test.each([
    "terraform destroy",
    "tofu apply -destroy",
    "git push origin :main",
    "gh api -X DELETE repos/o/r/git/refs/heads/main",
    "gh repo delete o/r --yes",
    "git push --mirror",
    "bash -lc 'git push -f origin master'",
  ])("%s asks", async (cmd) => {
    const { ctx, deps } = buildContext();
    await run(ctx, cmd);
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(deps.abortableReviewGate.mock.calls[0][4]).toEqual(["Approve", "Reject"]);
  });

  test("approving grants nothing durable: no cache entry, no ack check, no disclosure frame", async () => {
    const cache = getBashApprovalCache("user-1", "conv-1");
    const { ctx, deps } = buildContext({ bashApprovalCache: cache });
    await run(ctx, FORCE_MAIN);
    expect(cache.allow(FORCE_MAIN)).toBe(false);
    expect(cache.allow("git push origin feat-x")).toBe(false);
    expect(deps.verifyAutonomousAck).not.toHaveBeenCalled();
    expect(deps.sendToClient.mock.calls.some((c) => c[1].type === "autonomous_disclosure")).toBe(false);
  });

  test("cache laundering: a prior `git push` or `terraform` batch grant does not cover the destroy forms", async () => {
    for (const [granted, cmd] of [["git push", FORCE_MAIN], ["terraform", "terraform destroy"]] as const) {
      _resetBashApprovalCacheForTests();
      const cache = getBashApprovalCache("user-1", "conv-1");
      cache.grant(granted);
      expect(cache.allow("git push origin feat-x") || cache.allow("terraform plan")).toBe(true); // the grant is live
      const { ctx, deps } = buildContext({ bashAutonomous: false, bashApprovalCache: cache });
      await run(ctx, cmd);
      expect(deps.abortableReviewGate, cmd).toHaveBeenCalledTimes(1);
      expect(deps.abortableReviewGate.mock.calls[0][4]).toEqual(["Approve", "Reject"]);
    }
  });

  test("a forged `Approve all <prefix>` selection denies and writes no cache entry (AC-20)", async () => {
    const cache = getBashApprovalCache("user-1", "conv-1");
    const { ctx, deps } = buildContext({ bashApprovalCache: cache, bashAutonomous: false });
    for (const forged of ["Approve all `git push`", "Approve all `terraform`", "approve", "Approve ", "APPROVE", ""]) {
      deps.abortableReviewGate.mockResolvedValueOnce(forged);
      const res = await run(ctx, FORCE_MAIN);
      expect(res.behavior, JSON.stringify(forged)).toBe("deny");
    }
    expect(cache.allow(FORCE_MAIN)).toBe(false);
    expect(cache.allow("git push origin feat-x")).toBe(false);
  });

  test("Reject denies, and the deny text tells the agent not to retry or respell (AC-15)", async () => {
    const { ctx, deps } = buildContext();
    deps.abortableReviewGate.mockResolvedValueOnce("Reject");
    const res = await run(ctx, FORCE_MAIN);
    expect(res.behavior).toBe("deny");
    expect((res as { message: string }).message).toMatch(/not.*run/i);
    expect((res as { message: string }).message).toMatch(/do not retry/i);
    expect((res as { message: string }).message).toMatch(/rephrase|respell/i);
  });

  test("timeout and abort deny with the same text (AC-15)", async () => {
    for (const reason of ["Review gate timed out", "Session aborted"]) {
      const { ctx, deps } = buildContext();
      deps.abortableReviewGate.mockRejectedValueOnce(new Error(reason));
      const res = await run(ctx, FORCE_MAIN);
      expect(res.behavior, reason).toBe("deny");
      expect((res as { message: string }).message).toMatch(/do not retry/i);
    }
  });

  test("the conversation status returns to active after the card, even when the gate rejects", async () => {
    const { ctx, deps } = buildContext();
    deps.abortableReviewGate.mockRejectedValueOnce(new Error("Review gate timed out"));
    await run(ctx, FORCE_MAIN);
    const statuses = deps.updateConversationStatus.mock.calls.map((c) => c[1]);
    expect(statuses).toEqual(["waiting_for_user", "active"]);
  });
});

describe("lane: placement (AC-5, AC-21)", () => {
  test("the blocklist still wins: `curl x && git push -f origin main` denies and shows no card", async () => {
    const { ctx, deps } = buildContext();
    const res = await run(ctx, "curl x && git push -f origin main");
    expect(res.behavior).toBe("deny");
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(deps.resolveProtectedBranches).not.toHaveBeenCalled();
  });

  test("the support persona still denies with escalation and emits no gate", async () => {
    const { ctx, deps } = buildContext({}, { persona: "support" });
    const res = await run(ctx, FORCE_MAIN);
    expect(res.behavior).toBe("deny");
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(gateFrames(deps)).toHaveLength(0);
  });

  test("an un-acked owner is GATED, not held: the card appears, approving writes no ack, the next benign command is then held (AC-21)", async () => {
    const { ctx, deps } = buildContext({ autonomousAckAt: null, resolveAckPosture: () => null });
    const res = await run(ctx, "terraform destroy");
    expect(res.behavior).toBe("allow");
    expect(gateFrames(deps)).toHaveLength(1);
    expect(deps.sendToClient.mock.calls.some((c) => c[1].type === "autonomous_disclosure")).toBe(false);
    expect(deps.verifyAutonomousAck).not.toHaveBeenCalled();
    // Next, benign, non-safe command: the existing first-run disclosure still holds it.
    deps.abortableReviewGate.mockResolvedValueOnce("Got it");
    await run(ctx, "npm run build");
    expect(deps.sendToClient.mock.calls.some((c) => c[1].type === "autonomous_disclosure")).toBe(true);
  });

  test("precision: a non-matching command in an acked autonomous workspace still auto-approves with no card and no resolver call", async () => {
    const { ctx, deps } = buildContext();
    for (const cmd of ["git push origin feat-x", "git push -u origin main", "terraform plan", "npm run build"]) {
      const res = await run(ctx, cmd);
      expect(res.behavior, cmd).toBe("allow");
    }
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(deps.resolveProtectedBranches).not.toHaveBeenCalled();
  });

  test("non-autonomous precision: an ordinary non-safe command keeps the generic gate with `Approve all` offered", async () => {
    const cache = getBashApprovalCache("user-1", "conv-1");
    const { ctx, deps } = buildContext({ bashAutonomous: false, bashApprovalCache: cache });
    await run(ctx, "git push origin feat-x");
    expect(deps.abortableReviewGate.mock.calls[0][4]).toEqual(["Approve", "Approve all `git push`", "Reject"]);
  });

  test("the resolver is called only for a force, delete or mirror push with a named destination", async () => {
    const { ctx, deps } = buildContext();
    await run(ctx, "terraform destroy");
    await run(ctx, "git push --mirror");
    expect(deps.resolveProtectedBranches).not.toHaveBeenCalled();
    await run(ctx, "git push --force origin main");
    expect(deps.resolveProtectedBranches).toHaveBeenCalledTimes(1);
  });

  test("an unresolved default branch asks on every force push, with authoritative=false in the telemetry (AC-3)", async () => {
    const { ctx, deps } = buildContext({
      resolveProtectedBranches: vi.fn().mockResolvedValue({ names: new Set(["main", "master"]), authoritative: false }),
    });
    await run(ctx, "git push --force-with-lease origin feat-x");
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
    const warn = mockLog.warn.mock.calls.map((c) => c[0]).find((o) => o?.decision === "destroy-ask");
    expect(warn).toMatchObject({ ruleId: "hosted-destroy-ask:git-push-unknown-default", authoritative: false });
  });

  test("a deployment without the resolver dep (legacy runner) fails toward ask", async () => {
    const { ctx, deps } = buildContext({ resolveProtectedBranches: undefined, bashAutonomous: undefined, autonomousAckAt: undefined });
    await run(ctx, "git push --force-with-lease origin feat-x");
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
  });
});

describe("card text (CPO4-R2, CLO C3/C4, AC-20)", () => {
  test("leads with the cause and the matched segment, names Approve as this command only", async () => {
    const { ctx, deps } = buildContext();
    await run(ctx, FORCE_MAIN);
    const q: string = gateFrames(deps)[0].question;
    expect(q.startsWith("Destructive command - paused for your approval")).toBe(true);
    expect(q).toMatch(/default branch/);
    expect(q).toContain(FORCE_MAIN);
    expect(q).toMatch(/this command only|once/i);
    expect(q).toMatch(/runs the whole command/i);
  });

  test("a destroy segment at character 250 of a `&&` chain stays visible outside the truncated preview", async () => {
    const filler = `echo ${"x".repeat(240)}`;
    const cmd = `${filler} && terraform destroy -auto-approve && echo done`;
    expect(cmd.indexOf("terraform destroy")).toBeGreaterThan(245);
    const { ctx, deps } = buildContext();
    await run(ctx, cmd);
    const q: string = gateFrames(deps)[0].question;
    expect(q).toContain("terraform destroy -auto-approve");
    expect(q).toMatch(/destroy infrastructure/i);
    expect(q).toMatch(/runs the whole command/i);
  });

  test("the card is neutral about who owns the repository", async () => {
    const { ctx, deps } = buildContext({ isOwner: false });
    await run(ctx, FORCE_MAIN);
    expect(gateFrames(deps)[0].question).not.toMatch(/\byour (repository|repo)\b/i);
  });

  test("vocabulary guard: no blocks, prevents, protects, safe to approve, guaranteed, always", async () => {
    const texts: string[] = [];
    for (const cmd of [FORCE_MAIN, "terraform destroy", "gh repo delete o/r --yes", "git push -f origin \"x", "git push --mirror"]) {
      const { ctx, deps } = buildContext();
      deps.abortableReviewGate.mockResolvedValueOnce("Reject");
      const res = await run(ctx, cmd);
      texts.push(gateFrames(deps)[0].question, (res as { message: string }).message);
    }
    expect(texts.length).toBeGreaterThanOrEqual(10);
    for (const t of texts) expect(t).not.toMatch(/\b(blocks|prevents?|protects?|safe to approve|guaranteed?|always)\b/i);
  });

  test("the card redacts credentials in the preview (same emit-boundary gate as every Bash card)", async () => {
    const { ctx, deps } = buildContext();
    await run(ctx, `GH_TOKEN=${CANARY} git push --force origin main`);
    expect(gateFrames(deps)[0].question).not.toContain(CANARY);
  });

  test("offline: an undelivered card notifies the user with the same question", async () => {
    const { ctx, deps } = buildContext({ sendToClient: vi.fn().mockReturnValue(false) });
    await run(ctx, FORCE_MAIN);
    expect(deps.notifyOfflineUser).toHaveBeenCalledTimes(1);
    expect(deps.notifyOfflineUser.mock.calls[0][1]).toMatchObject({ type: "review_gate", conversationId: "conv-1" });
  });
});

describe("telemetry (AC-8, CLO C5)", () => {
  test("per ask: pino decision destroy-ask and Sentry hosted-destroy-ask carry the rule id, and never the command", async () => {
    const { ctx } = buildContext();
    await run(ctx, `GH_TOKEN=${CANARY} git push --force origin main`);
    const pino = mockLog.warn.mock.calls.map((c) => c[0]).find((o) => o?.decision === "destroy-ask");
    expect(pino).toMatchObject({
      sec: true,
      decision: "destroy-ask",
      ruleId: "hosted-destroy-ask:git-force-default",
      family: "git-default-branch",
      autonomous: true,
      isOwner: true,
      acked: true,
      authoritative: true,
      repo: "alice/app",
    });
    const sentry = mockWarnSilentFallback.mock.calls.find((c) => c[1]?.op === "hosted-destroy-ask");
    expect(sentry).toBeDefined();
    expect(sentry![1]).toMatchObject({
      feature: "cc-permissions",
      op: "hosted-destroy-ask",
      extra: { ruleId: "hosted-destroy-ask:git-force-default", family: "git-default-branch", autonomous: true, isOwner: true, authoritative: true },
    });
    expect(JSON.stringify(sentry![1])).not.toContain("alice/app"); // repo is pino-only
  });

  test("no emitted payload, in any outcome, carries the command, a branch name or a refspec", async () => {
    for (const sel of ["Approve", "Reject"]) {
      const { ctx, deps } = buildContext();
      deps.abortableReviewGate.mockResolvedValueOnce(sel);
      await run(ctx, `GH_TOKEN=${CANARY} git push --force origin main`);
    }
    const { ctx, deps } = buildContext();
    deps.abortableReviewGate.mockRejectedValueOnce(new Error("Review gate timed out"));
    await run(ctx, `GH_TOKEN=${CANARY} git push --force origin main`);
    const t = allTelemetry();
    expect(t).not.toContain(CANARY);
    expect(t).not.toContain("push --force");
    expect(t).not.toContain("origin main");
    expect(t.length).toBeGreaterThan(200); // the scan covered real payloads
  });

  test("outcome lines: approved, rejected, expired, each with the approver role", async () => {
    const outcomes: Array<[string, () => void]> = [
      ["destroy-ask-approved", () => {}],
      ["destroy-ask-rejected", () => {}],
      ["destroy-ask-expired", () => {}],
    ];
    for (const [decision] of outcomes) {
      mockLog.info.mockClear();
      mockLog.warn.mockClear();
      const { ctx, deps } = buildContext({ isOwner: false });
      if (decision === "destroy-ask-rejected") deps.abortableReviewGate.mockResolvedValueOnce("Reject");
      if (decision === "destroy-ask-expired") deps.abortableReviewGate.mockRejectedValueOnce(new Error("Review gate timed out"));
      await run(ctx, FORCE_MAIN);
      const lines = [...mockLog.info.mock.calls, ...mockLog.warn.mock.calls].map((c) => c[0]);
      expect(lines.find((o) => o?.decision === decision), decision).toMatchObject({ sec: true, ruleId: expect.stringContaining("hosted-destroy-ask:"), approverRole: "member" });
    }
  });

  test("near-miss: a destructive keyword with no match emits destroy-classifier-near-miss, deduped per context, with a leading token only", async () => {
    const { ctx } = buildContext();
    for (let i = 0; i < 3; i++) await run(ctx, "make destroy-docs");
    const calls = mockWarnSilentFallback.mock.calls.filter((c) => c[1]?.op === "destroy-classifier-near-miss");
    expect(calls).toHaveLength(1);
    expect(calls[0][1].extra.leadingToken.length).toBeLessThanOrEqual(32);
    expect(JSON.stringify(calls[0][1])).not.toContain("make destroy-docs");
  });

  test("a gh delete and a graphql mutation are near-miss only: no card", async () => {
    const { ctx, deps } = buildContext();
    await run(ctx, "gh issue delete 5");
    await run(ctx, "gh api graphql -f query='mutation{deleteRef(input:{refId:\"x\"}){clientMutationId}}'");
    expect(deps.abortableReviewGate).not.toHaveBeenCalled();
    expect(mockWarnSilentFallback.mock.calls.filter((c) => c[1]?.op === "destroy-classifier-near-miss").length).toBeGreaterThanOrEqual(1);
  });

  test("telemetry sources are enumerated: the scan above covers every emitter in the lane", async () => {
    const { readdirSync, readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const serverDir = join(__dirname, "..", "server");
    const files = readdirSync(serverDir)
      .filter((f) => f.endsWith(".ts"))
      .filter((f) => /destroy-ask|destroy-classifier/.test(readFileSync(join(serverDir, f), "utf8")))
      .sort();
    expect(files.length).toBeGreaterThanOrEqual(2);
    for (const f of files) expect(["destroy-ask-classifier.ts", "destroy-ask-lane.ts", "permission-callback.ts", "resolve-protected-branches.ts"]).toContain(f);
  });
});

describe("gate lifecycle with the real review-gate (AC-19)", () => {
  afterEach(() => vi.useRealTimers());
  const realGate = (session: unknown) =>
    vi.fn((s: never, gateId: string, signal: AbortSignal, timeoutMs: number | undefined, options: string[]) =>
      abortableReviewGate(session as never, gateId, signal, timeoutMs, options),
    );

  test("a late Approve after expiry is ignored and the command is not run", async () => {
    vi.useFakeTimers();
    const { ctx, deps, session } = buildContext();
    deps.abortableReviewGate = realGate(session) as never;
    const p = run(ctx, FORCE_MAIN);
    await vi.advanceTimersByTimeAsync(0);
    const gateId = gateFrames(deps)[0].gateId as string;
    await vi.advanceTimersByTimeAsync(5 * 60_000 + 1);
    const res = await p;
    expect(res.behavior).toBe("deny");
    expect(session.reviewGateResolvers.has(gateId)).toBe(false); // a late response finds nothing to resolve
  });

  test("an abort mid-card denies and clears the resolver (fail-closed)", async () => {
    const ac = new AbortController();
    const { ctx, deps, session } = buildContext();
    deps.abortableReviewGate = realGate(session) as never;
    const p = run(ctx, FORCE_MAIN, ac.signal);
    await Promise.resolve();
    await new Promise((r) => setImmediate(r));
    ac.abort(new Error("disconnect"));
    const res = await p;
    expect(res.behavior).toBe("deny");
    expect(session.reviewGateResolvers.size).toBe(0);
  });

  test("two cards back to back, and a destroy card beside another pending gate, resolve independently by gateId", async () => {
    const { ctx, deps, session } = buildContext();
    deps.abortableReviewGate = realGate(session) as never;
    const other = abortableReviewGate(session as never, "other-gate", new AbortController().signal, undefined, ["Approve", "Reject"]);
    const a = run(ctx, FORCE_MAIN);
    await new Promise((r) => setImmediate(r));
    const b = run(ctx, "terraform destroy");
    await new Promise((r) => setImmediate(r));
    const frames = gateFrames(deps);
    expect(frames).toHaveLength(2);
    const [idA, idB] = frames.map((f) => f.gateId as string);
    expect(idA).not.toBe(idB);
    session.reviewGateResolvers.get(idB)!.resolve("Approve");
    expect((await b).behavior).toBe("allow");
    expect(session.reviewGateResolvers.has(idA)).toBe(true); // A still pending
    expect(session.reviewGateResolvers.has("other-gate")).toBe(true);
    session.reviewGateResolvers.get(idA)!.resolve("Reject");
    expect((await a).behavior).toBe("deny");
    session.reviewGateResolvers.get("other-gate")!.resolve("Approve");
    expect(await other).toBe("Approve");
  });

  test("a response whose selection is not exactly Approve never releases the command", async () => {
    const { ctx, deps, session } = buildContext();
    deps.abortableReviewGate = realGate(session) as never;
    const p = run(ctx, FORCE_MAIN);
    await new Promise((r) => setImmediate(r));
    const id = gateFrames(deps)[0].gateId as string;
    session.reviewGateResolvers.get(id)!.resolve("Approve all `git push`");
    expect((await p).behavior).toBe("deny");
  });
});
