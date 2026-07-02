import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { WorkstreamIssue } from "@/lib/workstream";
import { IssueCard } from "@/components/workstream/issue-card";

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "SOLAA-198",
    title: "Wire the board",
    description: "",
    status: "in_progress",
    priority: "high",
    assigneeRole: "cto",
    createdAt: "2026-06-20T09:00:00.000Z",
    updatedAt: "2026-06-20T09:00:00.000Z",
    ...over,
  };
}

afterEach(() => cleanup());

describe("IssueCard", () => {
  it("shows id, title, labeled priority pill, and the role chip", () => {
    render(<IssueCard issue={issue()} onOpen={() => {}} />);
    expect(screen.getByText("SOLAA-198")).toBeTruthy();
    expect(screen.getByText("Wire the board")).toBeTruthy();
    expect(screen.getByText("High")).toBeTruthy();
    expect(screen.getByText("CTO")).toBeTruthy();
  });

  it("renders the secondary user avatar only when `user` is present", () => {
    const { rerender } = render(
      <IssueCard issue={issue({ user: undefined })} onOpen={() => {}} />,
    );
    expect(screen.queryByText("HC")).toBeNull();

    rerender(
      <IssueCard
        issue={issue({ user: { name: "Harry Cole", initials: "HC" } })}
        onOpen={() => {}}
      />,
    );
    expect(screen.getByText("HC")).toBeTruthy();
  });

  it("shows the quiet Live marker only for an In Progress + live card", () => {
    const { rerender } = render(
      <IssueCard issue={issue({ live: true })} onOpen={() => {}} />,
    );
    expect(screen.getByText("Live")).toBeTruthy();

    rerender(
      <IssueCard
        issue={issue({ status: "ready", live: true })}
        onOpen={() => {}}
      />,
    );
    expect(screen.queryByText("Live")).toBeNull();
  });

  it("calls onOpen with the issue id when clicked", () => {
    const onOpen = vi.fn();
    render(<IssueCard issue={issue()} onOpen={onOpen} />);
    fireEvent.click(screen.getByText("Wire the board"));
    expect(onOpen).toHaveBeenCalledWith("SOLAA-198");
  });
});
