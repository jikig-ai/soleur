/**
 * Ref #11635 (epic Ref #9601): the cc dispatcher sets `approvalFailClosed`, so an approval-required tool that reaches the
 * gated branch of `createCanUseTool` is DENIED (static text, no in-memory review card) whenever the approval flow gave no
 * verdict: the wiring is absent, the flag is off, or the flag read failed. With the switch unset the branch is unchanged.
 *
 * Drives the real `createCanUseTool` with a hand-built `ApprovalGateDeps` (DB-free), mirroring
 * permission-callback-gated-branch.test.ts. The gate's own behaviour is proven in gate-flow.test.ts.
 *
 * Synthesized data only.
 */
import { beforeEach, describe, expect, test, vi } from "vitest";

const { log, logDecision, reportSilentFallback, warnSilentFallback } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  logDecision: vi.fn(),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: logDecision }));
vi.mock("@/server/observability", () => ({ warnSilentFallback, reportSilentFallback }));

import { createCanUseTool, SOLEUR_GO_SAFE_UX_TOOLS, type CanUseToolContext } from "@/server/permission-callback";
import { isSafeTool } from "@/server/tool-path-checker";
import { APPROVAL_UNAVAILABLE_DENY } from "@/server/approval/gate-flow";
import { APPROVAL_OPS } from "@/server/approval/ops";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { clearAllWaiters } from "@/server/approval/waiters";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";
import { TOOL_TIER_MAP } from "@/server/tool-tiers";
import { CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const P = "mcp__soleur_platform__";
const CRM_WRITES = [`${P}crm_contact_upsert`, `${P}crm_note_append`, `${P}crm_contact_set_stage`] as const;
const CRM_INPUT: Record<string, Record<string, unknown>> = {
  [`${P}crm_contact_upsert`]: { name: "Dana Example" },
  [`${P}crm_note_append`]: { contactId: "c-1", lens: ["sales"], body: "note" },
  [`${P}crm_contact_set_stage`]: { contactId: "c-1", toStage: "won" },
};
/** Any input for a required tool: the late deny never reads it. A tool outside the sample set gets an empty object. */
const inputFor = (tool: string): Record<string, unknown> => SAMPLES[tool]?.input ?? {};

beforeEach(() => {
  clearAllWaiters();
  vi.clearAllMocks();
  process.env.SENTRY_USERID_PEPPER = "cc-approval-fail-closed-test-pepper";
});

type FlagMode = "on" | "off" | "throws";
interface SetupOptions {
  /** The cc dispatcher sets this; every other runner leaves it unset. */
  failClosed?: boolean;
  /** `absent` models a CanUseToolDeps with no `approval` (the wiring was dropped). */
  approval?: "absent" | FlagMode;
  /** Pre-set the sticky flag, as if the approval flow had already run earlier in this session. */
  enforcing?: boolean;
  persona?: "support";
  nonInteractive?: boolean;
  reviewAnswer?: "Approve" | "Reject";
  /** A review gate that never answers (to fill the pending-gate cap). */
  hangReview?: boolean;
}

function setup(opts: SetupOptions = {}) {
  const mode = opts.approval ?? "off";
  const isEnabled = vi.fn(async () => {
    if (mode === "throws") throw new Error("flag backend down");
    return mode === "on";
  });
  // With the flag on the bind step fails, so the gate answers the static unavailable deny without touching a database.
  const resolveServerDerived = vi.fn(async () => {
    throw new Error("bind failed");
  });
  const grants = new ExecutionGrants();
  if (opts.enforcing) grants.enforcing = true;
  const approval =
    mode === "absent"
      ? undefined
      : ({
          isEnabled,
          workspaceId: WORKSPACE_ID,
          grants,
          resolveServerDerived,
          submit: vi.fn(),
          readStatus: vi.fn(),
          consume: vi.fn(),
          viewerRole: vi.fn(async () => "owner" as const),
        } as unknown as ApprovalGateDeps);
  const abortableReviewGate = vi.fn(() =>
    opts.hangReview ? new Promise<string>(() => {}) : Promise.resolve(opts.reviewAnswer ?? "Approve"),
  );
  const sendToClient = vi.fn(() => true);
  const ctx = {
    userId: USER_ID,
    conversationId: CONVERSATION_ID,
    leaderId: "cto",
    workspacePath: "/tmp/ws",
    platformToolNames: [...APPROVAL_REQUIRED_TOOLS, ...CRM_WRITES],
    pluginMcpServerNames: [],
    repoOwner: "example-org",
    repoName: "example-repo",
    persona: opts.persona,
    nonInteractive: opts.nonInteractive,
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    deps: {
      abortableReviewGate,
      sendToClient,
      notifyOfflineUser: vi.fn().mockResolvedValue(true),
      updateConversationStatus: vi.fn(async () => {}),
      ...(approval ? { approval } : {}),
      ...(opts.failClosed ? { approvalFailClosed: true } : {}),
    },
  } as unknown as CanUseToolContext;
  // One callback for the whole case: the pending-gate counter is per `createCanUseTool` call.
  const canUseTool = createCanUseTool(ctx);
  const call = (tool: string, input: Record<string, unknown>, signal: AbortSignal = new AbortController().signal) =>
    canUseTool(tool, input, { signal, toolUseID: "t", requestId: "r" } as never) as Promise<{ behavior: string; message?: string }>;
  return { call, isEnabled, resolveServerDerived, abortableReviewGate, sendToClient, grants };
}

const reviewCards = (h: { sendToClient: ReturnType<typeof vi.fn> }) =>
  h.sendToClient.mock.calls.filter((c) => (c[1] as { type?: string } | undefined)?.type === "review_gate");

/** The wiring-absent Sentry events (the one op this switch adds a reason to). */
const wiringAbsentEvents = () =>
  reportSilentFallback.mock.calls.filter(
    (c) => (c[1] as { extra?: { stage?: string } } | undefined)?.extra?.stage === "wiring-absent",
  );

describe("non-vacuity: the sweep is over the live approval-required set", () => {
  test("there are at least eight approval-required tools and every one is in the gated tier (the fail-closed branch lives inside it)", () => {
    expect(APPROVAL_REQUIRED_TOOLS.length).toBeGreaterThanOrEqual(8);
    for (const tool of APPROVAL_REQUIRED_TOOLS) expect(TOOL_TIER_MAP[tool]).toBe("gated");
  });
});

describe("pre-gate allow sets", () => {
  test("no approval-required tool is in the UX allow set that is checked before the platform branch", () => {
    expect(SOLEUR_GO_SAFE_UX_TOOLS.size).toBeGreaterThan(0);
    for (const tool of APPROVAL_REQUIRED_TOOLS) expect(SOLEUR_GO_SAFE_UX_TOOLS.has(tool), tool).toBe(false);
  });

  test("no approval-required tool is accepted by isSafeTool (SAFE_TOOLS is also checked before the platform branch)", () => {
    expect(isSafeTool("TodoRead")).toBe(true); // positive control: the predicate can say yes
    for (const tool of APPROVAL_REQUIRED_TOOLS) expect(isSafeTool(tool), tool).toBe(false);
  });
});

describe("approvalFailClosed set, approval wiring ABSENT", () => {
  test.each([...APPROVAL_REQUIRED_TOOLS])("%s is denied with the static text, no card, one wiring-absent Sentry error", async (tool) => {
    const h = setup({ failClosed: true, approval: "absent" });
    const res = await h.call(tool, inputFor(tool));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(reviewCards(h)).toHaveLength(0);
    expect(logDecision).toHaveBeenCalledWith("canUseTool-platform-gated", tool, "deny", "approval flow gave no verdict");
    const events = wiringAbsentEvents();
    expect(events).toHaveLength(1);
    const [first, options] = events[0] as [unknown, { feature: string; op: string; extra: Record<string, unknown> }];
    expect(first).toBeNull();
    expect(options.feature).toBe("approval-queue");
    expect(options.op).toBe(APPROVAL_OPS.gateFailed.op);
    expect(options.extra.tool).toBe(tool);
  });

  test("the Sentry payload carries no tool input", async () => {
    const h = setup({ failClosed: true, approval: "absent" });
    await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend));
    const payload = JSON.stringify(reportSilentFallback.mock.calls);
    expect(payload).not.toContain("maria@example.test");
    expect(payload).not.toContain("Updated pricing");
  });
});

describe("approvalFailClosed set, approval wired, the flow gives no verdict", () => {
  test.each([...APPROVAL_REQUIRED_TOOLS])("%s: flag cleanly OFF is denied with no card, the flag read once, and no Sentry error", async (tool) => {
    const h = setup({ failClosed: true, approval: "off" });
    const res = await h.call(tool, inputFor(tool));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.isEnabled).toHaveBeenCalledTimes(1);
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(reviewCards(h)).toHaveLength(0);
    // A clean OFF is a dormant state, not a fault.
    expect(reportSilentFallback).not.toHaveBeenCalled();
    expect(wiringAbsentEvents()).toHaveLength(0);
    expect(logDecision).toHaveBeenCalledWith("canUseTool-platform-gated", tool, "deny", "approval flow gave no verdict");
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ sec: true, tool, decision: "platform-gate-approval-fail-closed", enforcing: false }),
      expect.any(String),
    );
  });

  test("a flag seam that THROWS (the gate's own handling; the production seam swallows to false) is denied with no card", async () => {
    const h = setup({ failClosed: true, approval: "throws" });
    const res = await h.call(TOOLS.pushBranch, inputFor(TOOLS.pushBranch));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(reviewCards(h)).toHaveLength(0);
  });

  test("flag ON: the gate's own verdict is returned (bind failure -> unavailable deny), enforcing turns on, and the new site is not what answered", async () => {
    const h = setup({ failClosed: true, approval: "on" });
    const res = await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.resolveServerDerived).toHaveBeenCalled();
    expect(h.grants.enforcing).toBe(true);
    expect(reviewCards(h)).toHaveLength(0);
    expect(log.warn).not.toHaveBeenCalledWith(
      expect.objectContaining({ decision: "platform-gate-approval-fail-closed" }),
      expect.any(String),
    );
  });

  test("flag switched OFF after the flow ran (sticky enforcing): the gate's own sticky deny answers, not the fail-closed site", async () => {
    const h = setup({ failClosed: true, approval: "off", enforcing: true });
    const res = await h.call(TOOLS.createPr, inputFor(TOOLS.createPr));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(logDecision).toHaveBeenCalledWith(
      "canUseTool-platform-gated",
      TOOLS.createPr,
      "deny",
      "approval flow unavailable after it ran in this session",
    );
    expect(log.warn).not.toHaveBeenCalledWith(
      expect.objectContaining({ decision: "platform-gate-approval-fail-closed" }),
      expect.any(String),
    );
    expect(reviewCards(h)).toHaveLength(0);
  });

  test("the gate dependency throwing with the flag on is a static deny, never an escape and never the card", async () => {
    const h = setup({ failClosed: true, approval: "on" });
    h.resolveServerDerived.mockRejectedValue(new Error("boom"));
    const res = await h.call(TOOLS.kbShareCreate, inputFor(TOOLS.kbShareCreate));
    expect(res.behavior).toBe("deny");
    expect(reviewCards(h)).toHaveLength(0);
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
  });
});

// The legacy runner is NOT byte-identical to before any more (#12597): with no verdict, its in-memory card for every
// approval-required tool needs the workspace Owner, so a missing dependency (no role to read) is the unavailable deny.
describe("approvalFailClosed UNSET (the legacy runner): the in-memory card needs the workspace Owner", () => {
  test("approval absent: a required tool gets the unavailable deny, no card, and one wiring-absent event", async () => {
    const h = setup({ approval: "absent" });
    const res = await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend));
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(reviewCards(h)).toHaveLength(0);
    expect(wiringAbsentEvents()).toHaveLength(1);
  });

  test("flag off, the user is the Owner: a required tool still reaches the in-memory review card", async () => {
    // setup's viewer role is the Owner.
    const h = setup({ approval: "off" });
    const res = await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend));
    expect(h.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(res.behavior).toBe("allow");
  });
});

describe("earlier exits keep their own static text, and every one is still a deny with no card", () => {
  test("non-interactive session", async () => {
    const h = setup({ failClosed: true, approval: "absent", nonInteractive: true });
    const res = await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend));
    expect(res.behavior).toBe("deny");
    expect(res.message).not.toBe(APPROVAL_UNAVAILABLE_DENY);
    expect(logDecision).toHaveBeenCalledWith("canUseTool-platform-gated", TOOLS.emailSend, "deny", "non-interactive session");
    expect(wiringAbsentEvents()).toHaveLength(0);
    expect(reviewCards(h)).toHaveLength(0);
  });

  test("an input that cannot be shown in full (unreviewable)", async () => {
    const h = setup({ failClosed: true, approval: "off" });
    const res = await h.call(TOOLS.emailSuppress, { recipient: 42, reason: "x" });
    expect(res.behavior).toBe("deny");
    expect(res.message).not.toBe(APPROVAL_UNAVAILABLE_DENY);
    expect(logDecision).toHaveBeenCalledWith("canUseTool-platform-gated", TOOLS.emailSuppress, "deny", "input not reviewable");
    expect(reviewCards(h)).toHaveLength(0);
    expect(h.isEnabled).not.toHaveBeenCalled();
  });

  test("the pending-gate cap is reached", async () => {
    // The cap is MAX_PENDING_GATES (5, module-private in permission-callback.ts); five held cards fill it.
    const CAP = 5;
    const h = setup({ failClosed: true, approval: "off", hangReview: true });
    for (let i = 0; i < CAP; i++) {
      const crm = CRM_WRITES[i % CRM_WRITES.length];
      void h.call(crm, CRM_INPUT[crm]);
    }
    await vi.waitFor(() => expect(h.abortableReviewGate).toHaveBeenCalledTimes(CAP));
    const res = await h.call(TOOLS.pushBranch, inputFor(TOOLS.pushBranch));
    expect(res.behavior).toBe("deny");
    expect(res.message).not.toBe(APPROVAL_UNAVAILABLE_DENY);
    expect(logDecision).toHaveBeenCalledWith("canUseTool-platform-gated", TOOLS.pushBranch, "deny", "too many pending approvals");
    expect(h.abortableReviewGate).toHaveBeenCalledTimes(CAP);
    expect(h.isEnabled).not.toHaveBeenCalled();
  });

  test("a call signal that is already aborted still returns the deny promptly with no hang and no card", async () => {
    const h = setup({ failClosed: true, approval: "off" });
    const aborted = new AbortController();
    aborted.abort();
    const res = await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend), aborted.signal);
    expect(res.behavior).toBe("deny");
    expect(reviewCards(h)).toHaveLength(0);
  });

  test("the support persona never reaches the gate for a required tool name", async () => {
    const h = setup({ failClosed: true, approval: "absent", persona: "support" });
    const res = await h.call(TOOLS.emailSend, inputFor(TOOLS.emailSend));
    expect(res.behavior).toBe("deny");
    expect(res.message).not.toBe(APPROVAL_UNAVAILABLE_DENY);
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });
});

describe("gated tools that are NOT approval-required stay on the human review card", () => {
  test.each([...CRM_WRITES])("%s: switch set, approval wired, flag seam true: the flag is never read, the card is shown, and Reject denies", async (tool) => {
    const h = setup({ failClosed: true, approval: "on", reviewAnswer: "Reject" });
    const res = await h.call(tool, CRM_INPUT[tool]);
    expect(h.isEnabled).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(reviewCards(h)).toHaveLength(1);
    expect(res.behavior).toBe("deny");
  });

  test.each([...CRM_WRITES])("%s: switch set and approval absent behaves the same (the switch cannot over-deny)", async (tool) => {
    const h = setup({ failClosed: true, approval: "absent", reviewAnswer: "Approve" });
    const res = await h.call(tool, CRM_INPUT[tool]);
    expect(reviewCards(h)).toHaveLength(1);
    expect(res.behavior).toBe("allow");
    expect(wiringAbsentEvents()).toHaveLength(0);
  });
});
