import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import type { WorkstreamIssue } from "@/lib/workstream";

// Drive the badge by controlling useSWR (shared honesty logic is unit-tested in
// nav-count-badge.test.tsx); here we pin the "needs founder attention" predicate
// and that the badge reuses the board's shared key.
const useSWRMock = vi.fn();
vi.mock("swr", async (importOriginal) => {
  const actual = await importOriginal<typeof import("swr")>();
  return { ...actual, default: (...args: unknown[]) => useSWRMock(...args) };
});

function issue(overrides: Partial<WorkstreamIssue>): WorkstreamIssue {
  return {
    id: "1",
    title: "t",
    description: "",
    status: "todo",
    priority: "none",
    assigneeRole: null,
    createdAt: "2026-07-03T00:00:00Z",
    updatedAt: "2026-07-03T00:00:00Z",
    ...overrides,
  };
}

beforeEach(() => useSWRMock.mockReset());
afterEach(() => cleanup());

async function render_(collapsed = false) {
  const { WorkstreamNavBadge } = await import(
    "@/components/dashboard/workstream-nav-badge"
  );
  return render(<WorkstreamNavBadge collapsed={collapsed} />);
}

describe("isWorkstreamAttentionItem", () => {
  it("counts blocked and CEO-assigned OPEN items; excludes closed and others", async () => {
    const { isWorkstreamAttentionItem } = await import(
      "@/components/dashboard/workstream-nav-badge"
    );
    // Attention:
    expect(isWorkstreamAttentionItem(issue({ status: "blocked" }))).toBe(true);
    expect(
      isWorkstreamAttentionItem(issue({ status: "todo", assigneeRole: "ceo" })),
    ).toBe(true);
    // NOT attention:
    expect(isWorkstreamAttentionItem(issue({ status: "in_progress" }))).toBe(
      false,
    );
    expect(
      isWorkstreamAttentionItem(issue({ status: "todo", assigneeRole: "cto" })),
    ).toBe(false);
    // Closed wins even if blocked/ceo (done/cancelled are resolved):
    expect(isWorkstreamAttentionItem(issue({ status: "done" }))).toBe(false);
    expect(
      isWorkstreamAttentionItem(
        issue({ status: "cancelled", assigneeRole: "ceo" }),
      ),
    ).toBe(false);
  });
});

describe("WorkstreamNavBadge", () => {
  it("reuses the board's shared SWR key (dedup)", async () => {
    useSWRMock.mockReturnValue({ data: { issues: [] }, error: undefined });
    await render_();
    const { swrKeys } = await import("@/lib/swr-config");
    expect(useSWRMock.mock.calls[0]![0]).toEqual(swrKeys.workstreamIssues());
  });

  it("renders the count of attention items only", async () => {
    useSWRMock.mockReturnValue({
      data: {
        issues: [
          issue({ id: "1", status: "blocked" }),
          issue({ id: "2", status: "todo", assigneeRole: "ceo" }),
          issue({ id: "3", status: "in_progress" }), // not attention
          issue({ id: "4", status: "done", assigneeRole: "ceo" }), // closed
        ],
      },
      error: undefined,
    });
    await render_();
    const badge = screen.getByTestId("workstream-nav-badge");
    expect(badge).toHaveTextContent("2");
    expect(badge).toHaveAccessibleName("2 workstream items needing attention");
  });

  it("omits the badge when no items need attention", async () => {
    useSWRMock.mockReturnValue({
      data: { issues: [issue({ status: "in_progress" })] },
      error: undefined,
    });
    await render_();
    expect(
      screen.queryByTestId("workstream-nav-badge"),
    ).not.toBeInTheDocument();
  });

  it("omits (never a false 0) on a cold fetch error", async () => {
    useSWRMock.mockReturnValue({ data: undefined, error: new Error("500") });
    await render_();
    expect(
      screen.queryByTestId("workstream-nav-badge"),
    ).not.toBeInTheDocument();
  });
});
