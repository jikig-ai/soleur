// `workflow_ended` status copy — the raw wire `status` (a closed
// z.enum(WORKFLOW_END_STATUSES) carrying internal enum names like
// `internal_error`) must never reach the founder-facing transcript card
// or lifecycle badge. Two layers:
//   1. WORKFLOW_ENDED_BADGE_COPY — exhaustive per-status terse label for
//      the badge pill, keyed on WorkflowEndStatus.
//   2. workflowEndedCopy — transcript-card sentence, delegated to the
//      parity-pinned SESSION_ENDED_COPY for mapped statuses and falling
//      back to WORKFLOW_ENDED_GENERIC_COPY otherwise.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { WORKFLOW_END_STATUSES } from "@/lib/types";
import {
  WORKFLOW_ENDED_BADGE_COPY,
  WORKFLOW_ENDED_BADGE_GENERIC,
  WORKFLOW_ENDED_GENERIC_COPY,
  hasWorkflowEndedBadge,
  workflowEndedBadge,
  workflowEndedCopy,
} from "@/lib/workflow-ended-copy";
import { SESSION_ENDED_COPY } from "@/lib/session-ended-copy";
import { WorkflowLifecycleBar } from "@/components/chat/workflow-lifecycle-bar";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

describe("WORKFLOW_ENDED_BADGE_COPY", () => {
  it("has an entry for every WorkflowEndStatus", () => {
    // Compile-time rail (Record<WorkflowEndStatus, string>) plus this
    // key-parity test — a new status without a badge row fails both.
    expect(Object.keys(WORKFLOW_ENDED_BADGE_COPY).sort()).toEqual(
      [...WORKFLOW_END_STATUSES].sort(),
    );
  });

  it("never leaks a raw wire token — no snake_case in any copy string", () => {
    for (const [status, copy] of Object.entries(WORKFLOW_ENDED_BADGE_COPY)) {
      expect(copy.length, `badge copy for ${status} is empty`).toBeGreaterThan(0);
      expect(copy, `badge copy for ${status} leaks a raw token`).not.toMatch(
        /[a-zA-Z]+_[a-zA-Z]+/,
      );
    }
    expect(WORKFLOW_ENDED_BADGE_GENERIC.length).toBeGreaterThan(0);
    expect(WORKFLOW_ENDED_BADGE_GENERIC).not.toMatch(/[a-zA-Z]+_[a-zA-Z]+/);
    expect(WORKFLOW_ENDED_GENERIC_COPY.length).toBeGreaterThan(0);
    expect(WORKFLOW_ENDED_GENERIC_COPY).not.toMatch(/[a-zA-Z]+_[a-zA-Z]+/);
  });
});

describe("workflow-ended resolvers", () => {
  it("hasWorkflowEndedBadge rejects Object.prototype keys and unknown statuses", () => {
    // The resolver indexes by a wire string — a "constructor"/"__proto__"
    // status must not resolve an inherited member and bypass the generic
    // fallback (the review-seat P1 from the session_ended precedent).
    for (const protoKey of [
      "constructor",
      "toString",
      "hasOwnProperty",
      "__proto__",
      "valueOf",
      "isPrototypeOf",
    ]) {
      expect(hasWorkflowEndedBadge(protoKey), protoKey).toBe(false);
    }
    expect(hasWorkflowEndedBadge("brand_new_status")).toBe(false);
    expect(hasWorkflowEndedBadge("internal_error")).toBe(true);
  });

  it("workflowEndedBadge returns generic copy with mapped:false for non-members", () => {
    // Direct-construction channels (tests, future non-WS sources) can carry
    // a status outside the Zod enum — the generic fallback bounds the render.
    const resolved = workflowEndedBadge("brand_new_status");
    expect(resolved.mapped).toBe(false);
    expect(resolved.copy).toBe(WORKFLOW_ENDED_BADGE_GENERIC);
    expect(typeof resolved.copy).toBe("string");
  });

  it("workflowEndedBadge returns the label with mapped:true for members", () => {
    const resolved = workflowEndedBadge("user_aborted");
    expect(resolved.mapped).toBe(true);
    expect(resolved.copy).toBe(WORKFLOW_ENDED_BADGE_COPY.user_aborted);
  });

  it("workflowEndedCopy delegates mapped statuses to SESSION_ENDED_COPY verbatim", () => {
    for (const status of WORKFLOW_END_STATUSES) {
      const resolved = workflowEndedCopy(status);
      expect(resolved.mapped, `status ${status} unmapped`).toBe(true);
      expect(resolved.copy, `copy drift for ${status}`).toBe(
        SESSION_ENDED_COPY[status],
      );
    }
  });

  it("workflowEndedCopy falls back to the workflow-generic copy for non-members", () => {
    const resolved = workflowEndedCopy("brand_new_status");
    expect(resolved.mapped).toBe(false);
    expect(resolved.copy).toBe(WORKFLOW_ENDED_GENERIC_COPY);
  });
});

// --- WorkflowLifecycleBar render path ---------------------------------------

describe("WorkflowLifecycleBar — ended badge copy", () => {
  it("renders the mapped label for internal_error, never the raw token", () => {
    const { container } = render(
      <WorkflowLifecycleBar
        lifecycle={{
          state: "ended",
          workflow: "brainstorm",
          status: "internal_error",
          summary: "Done",
        }}
      />,
    );
    const badge = container.querySelector(
      '[data-lifecycle-state="ended"][data-lifecycle-status="internal_error"]',
    );
    expect(badge).not.toBeNull();
    expect(container.textContent).toContain(
      WORKFLOW_ENDED_BADGE_COPY.internal_error,
    );
    // Rendered-text scope only — data-lifecycle-status legitimately keeps
    // the raw token as a test hook.
    expect(container.textContent).not.toContain("internal_error");
  });

  it("keeps completed emerald and every other status red", () => {
    const { container } = render(
      <WorkflowLifecycleBar
        lifecycle={{ state: "ended", workflow: "plan", status: "completed" }}
      />,
    );
    const pill = container.querySelector(
      '[data-lifecycle-status="completed"] .bg-emerald-900\\/40',
    );
    expect(pill).not.toBeNull();
    expect(pill?.textContent).toBe(WORKFLOW_ENDED_BADGE_COPY.completed);
  });
});

// --- ChatSurface render path ------------------------------------------------
// Mock boilerplate mirrors chat-surface-context-reset.test.tsx.

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () =>
    createUseTeamNamesMock({
      getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

describe("ChatSurface — workflow_ended card copy", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({ realConversationId: "test-id" });
  });

  async function renderFull() {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant="full" conversationId="test-id" />);
  }

  it("renders SESSION_ENDED_COPY for internal_error, never the raw token", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        {
          id: "wf-end-1",
          role: "assistant",
          content: "",
          type: "workflow_ended",
          workflow: "brainstorm",
          status: "internal_error",
        },
      ],
    });
    const { container } = await renderFull();

    const card = container.querySelector('[data-message-type="workflow_ended"]');
    expect(card).not.toBeNull();
    expect(card?.textContent).toContain(SESSION_ENDED_COPY.internal_error);
    expect(card?.textContent).not.toContain("internal_error");
  });
});
