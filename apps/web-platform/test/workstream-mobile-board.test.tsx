import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react";
import { MobileBoard } from "@/components/workstream/mobile-board";
import type { WorkstreamIssue, WorkstreamStatus } from "@/lib/workstream";

function issue(id: string, status: WorkstreamStatus, title = `Issue ${id}`): WorkstreamIssue {
  return {
    id,
    title,
    description: "",
    status,
    priority: "none",
    assigneeRole: null,
    createdAt: "2026-07-23T00:00:00Z",
    updatedAt: "2026-07-23T00:00:00Z",
  };
}

const ISSUES: WorkstreamIssue[] = [
  issue("6809", "in_progress", "Retry LUKS canary"),
  issue("6533", "in_progress", "image_pull_failed"),
  issue("5743", "in_progress", "guided-tour onboarding"),
  issue("100", "backlog"),
  issue("101", "backlog"),
  issue("200", "ready"),
];

beforeEach(() => {
  sessionStorage.clear();
});
afterEach(() => {
  cleanup();
});

describe("MobileBoard", () => {
  test("renders 7 status tabs, each with its count, and a tabpanel", () => {
    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    const tabs = screen.getAllByRole("tab");
    expect(tabs).toHaveLength(7);
    // Counts match per-status.
    expect(within(screen.getByRole("tab", { name: /In Progress/ })).getByText("3")).toBeTruthy();
    expect(within(screen.getByRole("tab", { name: /Backlog/ })).getByText("2")).toBeTruthy();
    expect(within(screen.getByRole("tab", { name: /Ready/ })).getByText("1")).toBeTruthy();
    expect(within(screen.getByRole("tab", { name: /Done/ })).getByText("0")).toBeTruthy();
    expect(screen.getByRole("tabpanel")).toBeTruthy();
  });

  test("default selection is the first non-empty column in board order (backlog)", () => {
    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    const backlogTab = screen.getByRole("tab", { name: /Backlog/ });
    expect(backlogTab.getAttribute("aria-selected")).toBe("true");
    // Backlog cards are shown (IssueCard renders the title).
    expect(screen.getByText("Issue 100")).toBeTruthy();
    // In-progress cards are NOT shown yet.
    expect(screen.queryByText("Retry LUKS canary")).toBeNull();
  });

  test("tapping a status tab swaps the visible column + marks it selected with the gold ring", () => {
    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    const ipTab = screen.getByRole("tab", { name: /In Progress/ });
    fireEvent.click(ipTab);

    expect(ipTab.getAttribute("aria-selected")).toBe("true");
    expect(ipTab.className).toContain("ring-soleur-accent-gold-fg");
    expect(screen.getByText("Retry LUKS canary")).toBeTruthy();
    expect(screen.getByText("image_pull_failed")).toBeTruthy();
    // tabpanel is labelled by the active tab.
    expect(screen.getByRole("tabpanel").getAttribute("aria-labelledby")).toBe(
      "workstream-tab-in_progress",
    );
  });

  test("tapping a card calls onOpen with the issue id", () => {
    const onOpen = vi.fn();
    render(<MobileBoard issues={ISSUES} onOpen={onOpen} />);
    fireEvent.click(screen.getByRole("tab", { name: /In Progress/ }));
    fireEvent.click(screen.getByText("Retry LUKS canary"));
    expect(onOpen).toHaveBeenCalledWith("6809");
  });

  test("selected status persists to sessionStorage and is restored on remount", () => {
    const { unmount } = render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: /Ready/ }));
    expect(sessionStorage.getItem("workstream:mobile-status-v1")).toBe("ready");
    unmount();

    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    expect(screen.getByRole("tab", { name: /Ready/ }).getAttribute("aria-selected")).toBe("true");
  });

  test("a status with 0 post-filter cards shows a per-column empty message", () => {
    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    fireEvent.click(screen.getByRole("tab", { name: /Done/ }));
    expect(screen.getByText(/No issues in Done/i)).toBeTruthy();
  });

  test("Arrow Right moves the selection to the next status", () => {
    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    // Default = backlog (first non-empty). ArrowRight → ready.
    const tablist = screen.getByRole("tablist");
    fireEvent.keyDown(tablist, { key: "ArrowRight" });
    expect(screen.getByRole("tab", { name: /Ready/ }).getAttribute("aria-selected")).toBe("true");
  });

  test("tabs are >=44px touch targets (min-h-11)", () => {
    render(<MobileBoard issues={ISSUES} onOpen={vi.fn()} />);
    for (const tab of screen.getAllByRole("tab")) {
      expect(tab.className).toContain("min-h-11");
    }
  });
});
