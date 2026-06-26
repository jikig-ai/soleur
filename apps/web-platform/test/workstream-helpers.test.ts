import { describe, expect, it } from "vitest";
import {
  COLUMNS,
  STATUS_ORDER,
  assigneeInitials,
  columnAccent,
  isLive,
  priorityBarClass,
  priorityLabel,
  priorityPillClass,
  roleColorClass,
  roleTitle,
  statusLabel,
  statusPillClass,
  type WorkstreamIssue,
  type WorkstreamPriority,
  type WorkstreamStatus,
} from "@/lib/workstream";
import { getWorkstreamIssues } from "@/server/workstream/seed-issues";

const ALL_STATUSES: WorkstreamStatus[] = [
  "backlog",
  "todo",
  "in_progress",
  "in_review",
  "blocked",
  "done",
  "cancelled",
];
const ALL_PRIORITIES: WorkstreamPriority[] = [
  "urgent",
  "high",
  "medium",
  "low",
  "none",
];

describe("COLUMNS config", () => {
  it("has the 7 columns in the documented order", () => {
    expect(COLUMNS.map((c) => c.status)).toEqual(ALL_STATUSES);
    expect(STATUS_ORDER).toEqual(ALL_STATUSES);
  });

  it("carries the binding per-column accent hexes (Addendum item 1)", () => {
    expect(columnAccent("backlog")).toBe("#9AA3B2");
    expect(columnAccent("todo")).toBe("#5E84C4");
    expect(columnAccent("in_progress")).toBe("#E0A93B");
    expect(columnAccent("in_review")).toBe("#A87BE0");
    expect(columnAccent("blocked")).toBe("#E5534B");
    expect(columnAccent("done")).toBe("#3FB950");
    expect(columnAccent("cancelled")).toBe("#595959");
  });

  it("labels In Progress and exposes an amber status pill (matches the tint)", () => {
    expect(statusLabel("in_progress")).toBe("In Progress");
    expect(statusPillClass("in_progress")).toContain("amber");
  });
});

describe("priority helpers (Addendum item 3 — labeled pill, 5 levels)", () => {
  it("returns a label, text class, and bar class for every level", () => {
    for (const p of ALL_PRIORITIES) {
      expect(priorityLabel(p).length).toBeGreaterThan(0);
      expect(priorityPillClass(p)).toContain("text-");
      expect(priorityBarClass(p)).toContain("bg-");
    }
    expect(priorityLabel("urgent")).toBe("Urgent");
    expect(priorityPillClass("urgent")).toContain("red");
  });
});

describe("assignee role helpers (self-contained map)", () => {
  it("renders initials, falling back to em dash when unassigned", () => {
    expect(assigneeInitials("cto")).toBe("CTO");
    expect(assigneeInitials(null)).toBe("—");
  });

  it("maps a role to a color and a human title", () => {
    expect(roleColorClass("cto")).toBe("bg-blue-500");
    expect(roleColorClass(null)).toContain("neutral");
    expect(roleTitle("cto")).toContain("Technology");
    expect(roleTitle(null)).toBe("Unassigned");
  });
});

describe("isLive", () => {
  const base: WorkstreamIssue = {
    id: "SOLAA-1",
    title: "t",
    description: "",
    status: "in_progress",
    priority: "high",
    assigneeRole: "cto",
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
  };

  it("is true only for In Progress + live flag", () => {
    expect(isLive({ ...base, live: true })).toBe(true);
    expect(isLive({ ...base, live: false })).toBe(false);
    expect(isLive({ ...base })).toBe(false);
    expect(isLive({ ...base, status: "done", live: true })).toBe(false);
  });
});

describe("getWorkstreamIssues accessor seam", () => {
  const issues = getWorkstreamIssues();

  it("returns a non-empty seed of valid issues", () => {
    expect(issues.length).toBeGreaterThanOrEqual(10);
    for (const i of issues) {
      expect(i.id.startsWith("SOLAA-")).toBe(true);
      expect(ALL_STATUSES).toContain(i.status);
      expect(ALL_PRIORITIES).toContain(i.priority);
      expect(typeof i.title).toBe("string");
      expect(typeof i.createdAt).toBe("string");
      expect(typeof i.updatedAt).toBe("string");
    }
  });

  it("seeds at least one Live card and at least one with a distinct user (Addendum item 5)", () => {
    expect(issues.some((i) => isLive(i))).toBe(true);
    expect(issues.some((i) => i.user && i.user.initials.length > 0)).toBe(true);
  });

  it("returns a fresh copy each call (callers cannot mutate the seed)", () => {
    const a = getWorkstreamIssues();
    a[0].title = "MUTATED";
    expect(getWorkstreamIssues()[0].title).not.toBe("MUTATED");
  });

  it("deep-copies the nested user object (agent tool serializes this payload)", () => {
    const a = getWorkstreamIssues();
    const withUser = a.find((i) => i.user);
    expect(withUser).toBeTruthy();
    withUser!.user!.name = "MUTATED_USER";
    const b = getWorkstreamIssues();
    expect(b.find((i) => i.id === withUser!.id)!.user!.name).not.toBe(
      "MUTATED_USER",
    );
  });
});
