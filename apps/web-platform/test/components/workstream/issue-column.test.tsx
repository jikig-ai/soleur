import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import {
  COLUMN_CAP_NOTICE,
  type ColumnConfig,
  type WorkstreamIssue,
} from "@/lib/workstream";
import { IssueColumn } from "@/components/workstream/issue-column";

// Visual-polish coverage (PR follow-up to #5659): the glyph→icon swap and the
// raised column tint. The collapse/persist behaviour itself is covered by
// workstream-board.test.tsx (queries by aria-label, which this change preserves).

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

describe("IssueColumn — collapse icon-button", () => {
  it("expanded: renders a Collapse button with aria-expanded=true and an <svg> icon (not a bare glyph)", () => {
    render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const btn = screen.getByRole("button", { name: "Collapse Backlog" });
    expect(btn.getAttribute("aria-expanded")).toBe("true");
    expect(btn.querySelector("svg")).toBeTruthy();
    expect(btn.textContent).not.toContain("⌄");
  });

  it("collapsed: renders an Expand button with aria-expanded=false and an <svg> icon (not a bare glyph)", () => {
    render(
      <IssueColumn
        column={column}
        issues={[issue()]}
        onOpen={() => {}}
        collapsed
        onToggleCollapse={() => {}}
      />,
    );
    const btn = screen.getByRole("button", { name: "Expand Backlog" });
    expect(btn.getAttribute("aria-expanded")).toBe("false");
    expect(btn.querySelector("svg")).toBeTruthy();
    expect(btn.textContent).not.toContain("›");
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

describe("IssueColumn — visible column tint", () => {
  it("expanded: section backgroundColor carries the accent with a non-0d alpha", () => {
    const { container } = render(
      <IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />,
    );
    const section = container.querySelector("section");
    const bg = section?.getAttribute("style") ?? "";
    // The accent must be present, but NOT at the old ~5% (0d) alpha.
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
    const section = container.querySelector("section");
    const bg = section?.getAttribute("style") ?? "";
    expect(bg.toLowerCase()).not.toContain("#9aa3b20d");
    expect(bg.toLowerCase()).toContain("#9aa3b2");
  });
});

describe("IssueColumn — empty column has no toggle", () => {
  it("an empty column shows neither a Collapse nor an Expand button", () => {
    render(<IssueColumn column={column} issues={[]} onOpen={() => {}} />);
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
  });

  it("an empty column is force-expanded even when collapsed=true (no Expand toggle)", () => {
    render(
      <IssueColumn
        column={column}
        issues={[]}
        onOpen={() => {}}
        collapsed
        onToggleCollapse={() => {}}
      />,
    );
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
  });
});

describe("IssueColumn — one control at a time (cross-fade regression lock)", () => {
  it("expanded: the Expand button is ABSENT", () => {
    render(<IssueColumn column={column} issues={[issue()]} onOpen={() => {}} />);
    expect(screen.getByRole("button", { name: "Collapse Backlog" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Expand Backlog" })).toBeNull();
  });
  it("collapsed: the Collapse button is ABSENT", () => {
    render(
      <IssueColumn
        column={column}
        issues={[issue()]}
        onOpen={() => {}}
        collapsed
        onToggleCollapse={() => {}}
      />,
    );
    expect(screen.getByRole("button", { name: "Expand Backlog" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Collapse Backlog" })).toBeNull();
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
