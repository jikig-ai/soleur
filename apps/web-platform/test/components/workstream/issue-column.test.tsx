import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import {
  COLUMN_CAP_NOTICE,
  type ColumnConfig,
  type WorkstreamIssue,
} from "@/lib/workstream";
import { IssueColumn } from "@/components/workstream/issue-column";

// Collapse is driven SOLELY by emptiness (v5): content ⇒ expanded, empty ⇒
// collapsed strip. There is no manual collapse/expand toggle and no persisted
// state — so a content column is ALWAYS open and an empty one ALWAYS collapsed.

const column: ColumnConfig = {
  status: "backlog",
  label: "Backlog",
  accent: "#9AA3B2",
};

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "SOLAA-900",
    title: "Seed issue",
    description: "desc",
    status: "backlog",
    priority: "medium",
    assigneeRole: "cto",
    createdAt: "2026-06-20T09:00:00.000Z",
    updatedAt: "2026-06-20T09:00:00.000Z",
    ...over,
  };
}

afterEach(() => cleanup());

describe("IssueColumn — emptiness drives open/closed; no manual toggle", () => {
  it("a column WITH content is always expanded (w-72) and renders no collapse/expand toggle", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("w-72");
    expect(cls).not.toContain("w-10");
    // No toggle buttons exist at all anymore.
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
    // The card itself is still rendered.
    expect(screen.getByText("Seed issue")).toBeTruthy();
  });

  it("an empty column is always collapsed to the w-10 strip with no toggle", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[]} onOpen={() => {}} />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("w-10");
    expect(cls).not.toContain("w-72");
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
  });

  it("the empty collapsed strip shows the 0 count pill and the column label", () => {
    render(<IssueColumn column={column} issues={[]} onOpen={() => {}} />);
    expect(screen.getByText("0")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Backlog" })).toBeTruthy();
  });

  it("the empty collapsed strip announces 'No issues' for screen readers", () => {
    render(<IssueColumn column={column} issues={[]} onOpen={() => {}} />);
    expect(screen.getByText("No issues")).toBeTruthy();
  });
});

describe("IssueColumn — visible column tint (both states)", () => {
  it("content/expanded: section backgroundColor carries the accent with a non-0d alpha", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const bg =
      container.querySelector("section")?.getAttribute("style") ?? "";
    expect(bg.toLowerCase()).not.toContain("#9aa3b20d");
    expect(bg.toLowerCase()).toContain("#9aa3b2");
  });

  it("empty/collapsed: section backgroundColor carries the same raised alpha (lockstep)", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[]} onOpen={() => {}} />,
    );
    const bg =
      container.querySelector("section")?.getAttribute("style") ?? "";
    expect(bg.toLowerCase()).not.toContain("#9aa3b20d");
    expect(bg.toLowerCase()).toContain("#9aa3b2");
  });
});

describe("IssueColumn — 200 render cap", () => {
  function manyIssues(n: number): WorkstreamIssue[] {
    return Array.from({ length: n }, (_, i) =>
      issue({ id: `i-${i}`, title: `Issue ${i}` }),
    );
  }
  function cardCount(container: HTMLElement): number {
    // Card roots are <button> with NO aria-label (and there are no toggle
    // buttons anymore), so every button is a card.
    return [...container.querySelectorAll("button")].filter(
      (b) => b.getAttribute("aria-label") === null,
    ).length;
  }

  it("201 issues → exactly 200 cards + the exact cap notice", () => {
    const { container } = render(
      <IssueColumn column={column} issues={manyIssues(201)} onOpen={() => {}} />,
    );
    expect(cardCount(container)).toBe(200);
    expect(screen.getByText(COLUMN_CAP_NOTICE)).toBeTruthy();
    // Count pill shows the TRUE total (201), not the capped 200.
    expect(screen.getByText("201")).toBeTruthy();
  });

  it("≤200 issues → no cap notice", () => {
    render(
      <IssueColumn column={column} issues={manyIssues(200)} onOpen={() => {}} />,
    );
    expect(screen.queryByText(COLUMN_CAP_NOTICE)).toBeNull();
  });
});

describe("IssueColumn — collapse animation class contract", () => {
  it("the persistent section carries the width transition + reduced-motion reset", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("transition-[width]");
    expect(cls).toContain("motion-reduce:transition-none");
    expect(cls).not.toContain("transition-all");
  });
});
