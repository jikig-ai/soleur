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

  it("renders a creator chip only when `creator` is present", () => {
    const { rerender } = render(
      <IssueCard issue={issue({ creator: undefined })} onOpen={() => {}} />,
    );
    expect(screen.queryByTitle(/^Created by/)).toBeNull();

    rerender(
      <IssueCard
        issue={issue({
          creator: {
            login: "octocat",
            isSoleur: false,
            display: { name: "octocat", initials: "OC" },
          },
        })}
        onOpen={() => {}}
      />,
    );
    expect(screen.getByTitle("Created by octocat")).toBeTruthy();
  });

  it("shows the word 'Soleur' on a bot-created card with no known initiator", () => {
    render(
      <IssueCard
        issue={issue({
          creator: {
            login: "soleur-ai[bot]",
            isSoleur: true,
            display: { name: "Soleur", initials: "SO" },
          },
        })}
        onOpen={() => {}}
      />,
    );
    const chip = screen.getByTitle("Created by Soleur");
    expect(chip.textContent).toContain("Soleur");
  });

  it("labels a Soleur-created card with the initiator when known", () => {
    render(
      <IssueCard
        issue={issue({
          creator: {
            login: "soleur-ai[bot]",
            isSoleur: true,
            initiatorLogin: "harry",
            display: { name: "harry", initials: "HA" },
          },
        })}
        onOpen={() => {}}
      />,
    );
    expect(
      screen.getByTitle("Created by Soleur · initiated by harry"),
    ).toBeTruthy();
  });
});
