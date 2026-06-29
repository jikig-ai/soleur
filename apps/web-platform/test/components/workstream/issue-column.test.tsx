import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import {
  COLUMN_CAP_NOTICE,
  type ColumnConfig,
  type WorkstreamIssue,
} from "@/lib/workstream";
import { IssueColumn } from "@/components/workstream/issue-column";

// Default + override rule (v6): a CONTENT column is OPEN by default but CAN be
// collapsed by the user (Collapse → strip with an Expand toggle). An EMPTY column
// is COLLAPSED by default with NO toggle (nothing to expand to).

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

describe("IssueColumn — content open by default, collapsible", () => {
  it("content + no collapse flag → expanded (w-72) with a Collapse toggle", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("w-72");
    expect(cls).not.toContain("w-10");
    const btn = screen.getByRole("button", { name: "Collapse Backlog" });
    expect(btn.getAttribute("aria-expanded")).toBe("true");
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
    expect(screen.getByText("Seed issue")).toBeTruthy();
  });

  it("content + collapsed=true → collapsed strip (w-10) with an Expand toggle", () => {
    const { container } = render(
      <IssueColumn
        column={column}
        issues={[issue()]}
        onOpen={() => {}}
        collapsed
        onToggleCollapse={() => {}}
      />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("w-10");
    expect(cls).not.toContain("w-72");
    const btn = screen.getByRole("button", { name: "Expand Backlog" });
    expect(btn.getAttribute("aria-expanded")).toBe("false");
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
  });

  it("clicking the toggle calls onToggleCollapse with the column status", () => {
    const onToggleCollapse = vi.fn();
    render(
      <IssueColumn
        column={column}
        issues={[issue()]}
        onOpen={() => {}}
        onToggleCollapse={onToggleCollapse}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Collapse Backlog" }));
    expect(onToggleCollapse).toHaveBeenCalledTimes(1);
    expect(onToggleCollapse).toHaveBeenCalledWith("backlog");
  });
});

describe("IssueColumn — empty column collapses with no toggle", () => {
  it("an empty column renders the w-10 strip and no toggle (collapsed flag unset)", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[]} onOpen={() => {}} />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("w-10");
    expect(cls).not.toContain("w-72");
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
  });

  it("an empty column ignores collapsed=true the same way — strip, no toggle", () => {
    const { container } = render(
      <IssueColumn
        column={column}
        issues={[]}
        onOpen={() => {}}
        collapsed
        onToggleCollapse={() => {}}
      />,
    );
    const cls = container.querySelector("section")?.getAttribute("class") ?? "";
    expect(cls).toContain("w-10");
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
  });

  it("the empty collapsed strip shows the 0 count, the label, and an sr-only 'No issues'", () => {
    render(<IssueColumn column={column} issues={[]} onOpen={() => {}} />);
    expect(screen.getByText("0")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Backlog" })).toBeTruthy();
    expect(screen.getByText("No issues")).toBeTruthy();
  });
});

describe("IssueColumn — visible column tint", () => {
  it("expanded: section backgroundColor carries the accent with a non-0d alpha", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const bg =
      container.querySelector("section")?.getAttribute("style") ?? "";
    expect(bg.toLowerCase()).not.toContain("#9aa3b20d");
    expect(bg.toLowerCase()).toContain("#9aa3b2");
  });

  it("collapsed: section backgroundColor carries the same raised alpha (lockstep)", () => {
    const { container } = render(
      <IssueColumn
        column={column}
        issues={[issue()]}
        onOpen={() => {}}
        collapsed
        onToggleCollapse={() => {}}
      />,
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
    // Card roots are <button> with NO aria-label; the toggle button HAS one.
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
