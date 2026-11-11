/**
 * #12597 (CTO ruling 2026-11-11, extends #12197 D1): when the approval flow gives no verdict (flag off or unreadable, or no
 * dependency), the legacy runner's in-memory card for EVERY approval-required tool may be answered only by the workspace
 * Owner. A member, a failed or timed-out role read, or a missing dependency is the static deny, with no card, no status
 * write and no offline notification; Stop or the session ending during the role read is the expired-gate deny. An Approve
 * is honoured only if the role, read again after the answer, is still Owner (CTO S1), with the same fail-closed outcomes
 * (failure, deadline, abort). The pending-card cap holds across
 * the role read (CTO F10). Gated tools outside the approval-required set keep the card for any user, with no role read.
 * Settings' PUSH_DISCLOSURE ("nothing is pushed that way unless the workspace owner approves that push") relies on this.
 *
 * The file name keeps "push" (CTO F9: the path is cited in ADR-309 and the mutation battery); it covers all eight tools.
 * Every population comes from the shared lists (`APPROVAL_REQUIRED_TOOLS`, `APPROVAL_EXEMPT_TOOLS`), never a hand-copied one.
 *
 * Synthesized data only.
 */
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { log, reports } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  reports: [] as unknown[][],
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: vi.fn() }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportApprovalOp: (...args: unknown[]) => {
    reports.push(args);
  },
}));

import { createCanUseTool, OWNER_ROLE_READ_DEADLINE_MS, type CanUseToolContext } from "@/server/permission-callback";
import { logPermissionDecision } from "@/server/permission-log";
import { APPROVAL_UNAVAILABLE_DENY } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { clearAllWaiters } from "@/server/approval/waiters";
import { APPROVAL_EXEMPT_TOOLS, APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";
import { TOOL_TIER_MAP } from "@/server/tool-tiers";
import { CONVERSATION_ID, SAMPLES, USER_ID, WORKSPACE_ID } from "./fixtures";

beforeEach(() => {
  clearAllWaiters();
  reports.length = 0;
  log.warn.mockClear();
  vi.mocked(logPermissionDecision).mockClear();
  process.env.SENTRY_USERID_PEPPER = "legacy-push-owner-fallback-test-pepper";
});
afterEach(() => {
  vi.useRealTimers();
});

type Role = "owner" | "member" | "throws" | "no-approval" | "member-flag-throws" | "owner-flag-throws";
type Res = { behavior: string; message?: string };

const EXEMPT_TOOLS = Object.keys(APPROVAL_EXEMPT_TOOLS);

/**
 * One `createCanUseTool` instance per harness: the pending-card counter is per instance, so the cap-race case needs every
 * call on the same one. `controller` is the session controller (its signal is `ctx.controllerSignal`).
 */
function setup(
  role: Role,
  opts: {
    viewerRole?: () => Promise<"owner" | "member">;
    gate?: (...a: unknown[]) => Promise<string>;
  } = {},
) {
  const controller = new AbortController();
  const viewerRole = vi.fn(
    opts.viewerRole ??
      (async () => {
        if (role === "throws") throw new Error("viewer role read failed");
        return role === "owner" || role === "owner-flag-throws" ? ("owner" as const) : ("member" as const);
      }),
  );
  // The flag is off (or its read throws), so the approval flow answers null (no verdict) and the call reaches the fallback.
  const approval = {
    isEnabled: vi.fn(async () => {
      if (role === "member-flag-throws" || role === "owner-flag-throws") throw new Error("flagsmith down");
      return false;
    }),
    workspaceId: WORKSPACE_ID,
    grants: new ExecutionGrants(),
    resolveServerDerived: vi.fn(),
    submit: vi.fn(),
    readStatus: vi.fn(),
    consume: vi.fn(),
    viewerRole,
  } as unknown as ApprovalGateDeps;
  const abortableReviewGate = vi.fn(opts.gate ?? (() => Promise.resolve("Approve")));
  const sendToClient = vi.fn((..._a: unknown[]) => true);
  const notifyOfflineUser = vi.fn().mockResolvedValue(true);
  const updateConversationStatus = vi.fn(async () => {});
  const ctx = {
    userId: USER_ID,
    conversationId: CONVERSATION_ID,
    leaderId: "cto",
    workspacePath: "/tmp/ws",
    platformToolNames: [...APPROVAL_REQUIRED_TOOLS, ...EXEMPT_TOOLS],
    pluginMcpServerNames: [],
    repoOwner: "example-org",
    repoName: "example-repo",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: controller.signal,
    deps: {
      abortableReviewGate,
      sendToClient,
      notifyOfflineUser,
      updateConversationStatus,
      ...(role === "no-approval" ? {} : { approval }),
    },
  } as unknown as CanUseToolContext;
  const canUseTool = createCanUseTool(ctx);
  const call = (tool: string, input: Record<string, unknown>, signal: AbortSignal = new AbortController().signal) =>
    canUseTool(tool, input, { signal, toolUseID: "t", requestId: "r" } as never) as Promise<Res>;
  const cards = () => sendToClient.mock.calls.filter((c) => c[1] && (c[1] as { type?: string }).type === "review_gate");
  /** No write of any kind: no card, no status, no notification, no approval row, no bind. */
  const expectNoWrites = () => {
    expect(sendToClient).not.toHaveBeenCalled();
    expect(abortableReviewGate).not.toHaveBeenCalled();
    expect(notifyOfflineUser).not.toHaveBeenCalled();
    expect(updateConversationStatus).not.toHaveBeenCalled();
    const a = approval as unknown as { submit: ReturnType<typeof vi.fn>; resolveServerDerived: ReturnType<typeof vi.fn> };
    expect(a.submit).not.toHaveBeenCalled();
    expect(a.resolveServerDerived).not.toHaveBeenCalled();
  };
  return { call, controller, viewerRole, abortableReviewGate, sendToClient, notifyOfflineUser, updateConversationStatus, cards, expectNoWrites };
}

const input = (tool: string) => structuredClone(SAMPLES[tool].input);
const warnsWith = (decision: string) =>
  log.warn.mock.calls.filter((c) => (c[0] as { decision?: string } | undefined)?.decision === decision);
const deferred = <T,>() => {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
};
const ROLE_FAILED_CONTEXT = (tool: string) =>
  expect.objectContaining({
    toolName: tool,
    workspaceId: WORKSPACE_ID,
    tags: { stage: "legacy-push-owner-check" },
    extra: { outcome: "denied-no-card" },
  });

describe("legacy fallback: the populations are the shared lists", () => {
  test("every approval-required tool is gated and has a sample; the exempt list is non-empty and disjoint", () => {
    expect(APPROVAL_REQUIRED_TOOLS.length).toBeGreaterThan(0);
    for (const tool of APPROVAL_REQUIRED_TOOLS) {
      expect(SAMPLES[tool]?.input, tool).toBeDefined();
      expect(TOOL_TIER_MAP[tool], tool).toBe("gated");
    }
    expect(EXEMPT_TOOLS.length).toBeGreaterThan(0);
    const required = new Set<string>(APPROVAL_REQUIRED_TOOLS);
    expect(EXEMPT_TOOLS.filter((t) => required.has(t))).toEqual([]);
  });
});

describe("legacy fallback: only the Owner may answer the in-memory card for every approval-required tool (#12597)", () => {
  test.each(APPROVAL_REQUIRED_TOOLS)("%s: Owner gets the card and the answer is honoured", async (tool) => {
    let readsWhenCardShown = -1;
    const h = setup("owner", {
      gate: async () => {
        readsWhenCardShown = h.viewerRole.mock.calls.length;
        return "Approve";
      },
    });
    const res = await h.call(tool, input(tool));
    expect(readsWhenCardShown).toBe(1); // the role was read before the card
    expect(h.viewerRole).toHaveBeenCalledTimes(2); // and again after Approve (CTO S1)
    expect(h.cards()).toHaveLength(1);
    expect(h.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(res.behavior).toBe("allow");
    expect(reports).toEqual([]);
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ sec: true, decision: "platform-gate-legacy-card-issued", tool, role: "owner", conversationId: CONVERSATION_ID }),
      expect.any(String),
    );
  });

  test.each(APPROVAL_REQUIRED_TOOLS)("%s: a member gets the static deny, with no card, status write or notification", async (tool) => {
    const h = setup("member");
    const res = await h.call(tool, input(tool));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    h.expectNoWrites();
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({
        sec: true,
        decision: "platform-gate-push-owner-required",
        tool,
        role: "member",
        conversationId: CONVERSATION_ID,
      }),
      expect.any(String),
    );
    expect(warnsWith("platform-gate-legacy-card-issued")).toEqual([]);
  });

  test.each(APPROVAL_REQUIRED_TOOLS)("%s: the flag read throws and the user is a member: static deny, no card", async (tool) => {
    const h = setup("member-flag-throws");
    const res = await h.call(tool, input(tool));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    h.expectNoWrites();
    // The deny comes from the role check, not from a short-circuit on the flag error.
    expect(h.viewerRole).toHaveBeenCalledTimes(1);
  });

  test.each(APPROVAL_REQUIRED_TOOLS)("%s: the flag read throws and the user is the Owner: the card is still emitted", async (tool) => {
    let readsWhenCardShown = -1;
    const h = setup("owner-flag-throws", {
      gate: async () => {
        readsWhenCardShown = h.viewerRole.mock.calls.length;
        return "Approve";
      },
    });
    const res = await h.call(tool, input(tool));
    expect(readsWhenCardShown).toBe(1);
    expect(h.viewerRole).toHaveBeenCalledTimes(2);
    expect(h.cards()).toHaveLength(1);
    expect(res.behavior).toBe("allow");
  });

  test.each(APPROVAL_REQUIRED_TOOLS)("%s: the role read fails: static deny, no card, viewerRoleFailed reported with its stage", async (tool) => {
    const h = setup("throws");
    await expect(h.call(tool, input(tool))).resolves.toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    h.expectNoWrites();
    expect(reports).toHaveLength(1);
    expect(reports[0][0]).toBe("viewerRoleFailed");
    expect(reports[0][2]).toEqual(ROLE_FAILED_CONTEXT(tool));
    expect((reports[0][1] as { code?: unknown }).code).toBeUndefined();
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ sec: true, decision: "platform-gate-push-owner-required", role: "unavailable" }),
      expect.any(String),
    );
    expect(logPermissionDecision).toHaveBeenCalledWith("canUseTool-platform-gated", tool, "deny", "owner required (unavailable)");
  });

  test.each(APPROVAL_REQUIRED_TOOLS)(
    "%s: a role read that never settles ends at the deadline: static deny, viewerRoleFailed reported",
    async (tool) => {
      vi.useFakeTimers();
      const h = setup("owner", { viewerRole: () => new Promise(() => {}) });
      const pending = h.call(tool, input(tool));
      const settled = vi.fn();
      pending.then(settled, settled);
      await vi.advanceTimersByTimeAsync(OWNER_ROLE_READ_DEADLINE_MS + 1);
      await vi.advanceTimersByTimeAsync(0);
      expect(settled).toHaveBeenCalledWith({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
      h.expectNoWrites();
      expect(reports.map((r) => r[0])).toEqual(["viewerRoleFailed"]);
      expect(reports[0][2]).toEqual(ROLE_FAILED_CONTEXT(tool));
      expect(reports[0][1]).toEqual(expect.objectContaining({ code: "role_read_timeout" }));
    },
    2_000,
  );

  test.each(APPROVAL_REQUIRED_TOOLS)("%s: no approval dependency: static deny, no card, reported as a wiring defect", async (tool) => {
    const h = setup("no-approval");
    const res = await h.call(tool, input(tool));
    expect(reports).toHaveLength(1);
    expect(reports[0][0]).toBe("gateFailed");
    expect(reports[0][2]).toEqual(expect.objectContaining({ toolName: tool, extra: { stage: "wiring-absent" } }));
    expect(log.warn).toHaveBeenCalledWith(expect.objectContaining({ sec: true, role: "unavailable" }), expect.any(String));
    expect(logPermissionDecision).toHaveBeenCalledWith("canUseTool-platform-gated", tool, "deny", "owner required (unavailable)");
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    h.expectNoWrites();
  });

  const expectAbortedDuringRead = (h: ReturnType<typeof setup>, res: Res) => {
    expect(res.behavior).toBe("deny");
    expect(res.message).toMatch(/expired before it was answered/);
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ decision: "platform-gate-aborted", reason: "aborted", delivered: false, stage: "owner-role-read" }),
      expect.any(String),
    );
    h.expectNoWrites();
    expect(reports).toEqual([]);
  };

  test.each(APPROVAL_REQUIRED_TOOLS)(
    "%s: Stop pressed while the role is read: denied as aborted, no card, no notification, no status write, no report",
    async (tool) => {
      const callCtl = new AbortController();
      const h = setup("owner", {
        viewerRole: () =>
          new Promise((resolve) => {
            callCtl.abort();
            setTimeout(() => resolve("owner"), 0);
          }),
      });
      const res = await h.call(tool, input(tool), callCtl.signal);
      expectAbortedDuringRead(h, res);
    },
  );

  test.each(APPROVAL_REQUIRED_TOOLS)(
    "%s: the session ends while the role is read: denied as aborted, no card, no notification, no status write, no report",
    async (tool) => {
      const session = { ctl: undefined as AbortController | undefined };
      const h = setup("owner", {
        viewerRole: () =>
          new Promise((resolve) => {
            session.ctl?.abort();
            setTimeout(() => resolve("owner"), 0);
          }),
      });
      session.ctl = h.controller;
      const res = await h.call(tool, input(tool));
      expectAbortedDuringRead(h, res);
    },
  );

  test.each(APPROVAL_REQUIRED_TOOLS)("%s: the Owner is demoted while the card waits: Approve is refused", async (tool) => {
    const h = setup("owner");
    h.viewerRole.mockResolvedValueOnce("owner").mockResolvedValueOnce("member");
    const res = await h.call(tool, input(tool));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.cards()).toHaveLength(1);
    expect(h.viewerRole).toHaveBeenCalledTimes(2);
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ decision: "platform-gate-push-owner-required", tool, role: "member", stage: "on-answer" }),
      expect.any(String),
    );
    // A Reject performs nothing, so it skips the answer-time re-read.
    const r = setup("owner", { gate: () => Promise.resolve("Reject") });
    const rejected = await r.call(tool, input(tool));
    expect(rejected.behavior).toBe("deny");
    expect(rejected.message).toMatch(/^User rejected the action/);
    expect(r.viewerRole).toHaveBeenCalledTimes(1);
  });

  // The answer-time re-read (CTO S1) has the same fail-closed outcomes as the first read; `outcome` tells them apart.
  const ANSWER_FAILED_CONTEXT = (tool: string) =>
    expect.objectContaining({
      toolName: tool,
      workspaceId: WORKSPACE_ID,
      tags: { stage: "legacy-push-owner-check" },
      extra: { outcome: "denied-on-answer" },
    });

  test.each(APPROVAL_REQUIRED_TOOLS)(
    "%s: the role read fails after Approve: static deny, viewerRoleFailed reported as denied-on-answer",
    async (tool) => {
      const h = setup("owner");
      h.viewerRole.mockResolvedValueOnce("owner").mockRejectedValueOnce(new Error("viewer role read failed"));
      const res = await h.call(tool, input(tool));
      expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
      expect(h.cards()).toHaveLength(1);
      expect(h.viewerRole).toHaveBeenCalledTimes(2);
      expect(reports).toHaveLength(1);
      expect(reports[0][0]).toBe("viewerRoleFailed");
      expect(reports[0][2]).toEqual(ANSWER_FAILED_CONTEXT(tool));
      expect(log.warn).toHaveBeenCalledWith(
        expect.objectContaining({ decision: "platform-gate-push-owner-required", tool, role: "unavailable", stage: "on-answer" }),
        expect.any(String),
      );
      expect(logPermissionDecision).toHaveBeenCalledWith("canUseTool-platform-gated", tool, "deny", "owner required on answer (unavailable)");
    },
  );

  test.each(APPROVAL_REQUIRED_TOOLS)(
    "%s: a role read after Approve that never settles ends at the deadline: static deny, viewerRoleFailed reported",
    async (tool) => {
      vi.useFakeTimers();
      const h = setup("owner");
      h.viewerRole.mockResolvedValueOnce("owner").mockImplementationOnce(() => new Promise(() => {}));
      const pending = h.call(tool, input(tool));
      const settled = vi.fn();
      pending.then(settled, settled);
      await vi.waitFor(() => expect(h.viewerRole).toHaveBeenCalledTimes(2));
      expect(settled).not.toHaveBeenCalled();
      await vi.advanceTimersByTimeAsync(OWNER_ROLE_READ_DEADLINE_MS + 1);
      await vi.advanceTimersByTimeAsync(0);
      expect(settled).toHaveBeenCalledWith({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
      expect(reports.map((r) => r[0])).toEqual(["viewerRoleFailed"]);
      expect(reports[0][2]).toEqual(ANSWER_FAILED_CONTEXT(tool));
      expect(reports[0][1]).toEqual(expect.objectContaining({ code: "role_read_timeout" }));
    },
    2_000,
  );

  test.each(APPROVAL_REQUIRED_TOOLS)(
    "%s: Stop pressed while the role is read after Approve: denied as aborted at stage owner-role-answer, no report",
    async (tool) => {
      const callCtl = new AbortController();
      const h = setup("owner");
      h.viewerRole.mockResolvedValueOnce("owner").mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            callCtl.abort();
            setTimeout(() => resolve("owner"), 0);
          }),
      );
      const res = await h.call(tool, input(tool), callCtl.signal);
      expect(res.behavior).toBe("deny");
      expect(res.message).toMatch(/expired before it was answered/);
      expect(h.cards()).toHaveLength(1);
      expect(log.warn).toHaveBeenCalledWith(
        expect.objectContaining({ decision: "platform-gate-aborted", reason: "aborted", delivered: true, stage: "owner-role-answer" }),
        expect.any(String),
      );
      expect(reports).toEqual([]);
    },
  );
});

describe("legacy fallback: the pending-card cap holds across the role read (#12597, CTO F10)", () => {
  test(
    "two Owner calls racing for the last pending slot: one card, one too-many-pending deny",
    async () => {
      const CAP = 5; // MAX_PENDING_GATES in permission-callback.ts (module-private)
      const tool = APPROVAL_REQUIRED_TOOLS[0];
      // Every held card stays open until its call signal aborts.
      const h = setup("owner", {
        gate: (...a: unknown[]) =>
          new Promise<string>((_resolve, reject) => {
            const signal = a[2] as AbortSignal;
            signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
          }),
      });
      const ctls = Array.from({ length: CAP + 1 }, () => new AbortController());
      // 1. CAP - 1 cards open (their role reads answer at once).
      const holders = ctls.slice(0, CAP - 1).map((c) => h.call(tool, input(tool), c.signal));
      await vi.waitFor(() => expect(h.abortableReviewGate).toHaveBeenCalledTimes(CAP - 1));
      // 2. Two more calls whose role reads are held: both get past the first cap check.
      const dA = deferred<"owner" | "member">();
      const dB = deferred<"owner" | "member">();
      h.viewerRole.mockImplementationOnce(() => dA.promise).mockImplementationOnce(() => dB.promise);
      const pA = h.call(tool, input(tool), ctls[CAP - 1].signal);
      const pB = h.call(tool, input(tool), ctls[CAP].signal);
      await vi.waitFor(() => expect(h.viewerRole).toHaveBeenCalledTimes(CAP + 1));
      // 3. Both reads settle in the same tick.
      dA.resolve("owner");
      dB.resolve("owner");
      await vi.waitFor(() => expect(h.cards().length).toBeGreaterThanOrEqual(CAP));
      // 4. Exactly one new card.
      expect(h.cards()).toHaveLength(CAP);
      expect(h.abortableReviewGate).toHaveBeenCalledTimes(CAP);
      // 5. The other call is the too-many-pending deny.
      const loser = await Promise.race([pA, pB]);
      expect(loser.behavior).toBe("deny");
      expect(loser.message).toMatch(/^Too many approvals are already waiting/);
      expect(warnsWith("platform-gate-too-many-pending")).toHaveLength(1);
      // 6. Cleanup.
      for (const c of ctls) c.abort();
      await Promise.allSettled([...holders, pA, pB]);
    },
    2_000,
  );
});

describe("gated tools outside the approval-required set keep the in-memory card", () => {
  test.each(Object.keys(APPROVAL_EXEMPT_TOOLS))("%s: a member still gets the card and no role is read", async (tool) => {
    const h = setup("member");
    const res = await h.call(tool, { title: "t", body: "b" });
    expect(h.viewerRole).not.toHaveBeenCalled();
    expect(h.cards()).toHaveLength(1);
    expect(res.behavior).toBe("allow");
  });
});
