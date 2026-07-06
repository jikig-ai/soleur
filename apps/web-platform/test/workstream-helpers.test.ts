import { describe, expect, it } from "vitest";
import {
  COLUMNS,
  STATUS_ORDER,
  assigneeInitials,
  boardStatusToWorkstreamStatus,
  columnAccent,
  deriveColumn,
  deriveLive,
  derivePriority,
  deriveRole,
  deriveUser,
  githubIssueToWorkstreamIssue,
  isLive,
  priorityBarClass,
  priorityLabel,
  priorityPillClass,
  roleColorClass,
  roleTitle,
  statusLabel,
  statusPillClass,
  type BoardIssueInput,
  type WorkstreamIssue,
  type WorkstreamPriority,
  type WorkstreamStatus,
} from "@/lib/workstream";

function input(over: Partial<BoardIssueInput> = {}): BoardIssueInput {
  return {
    number: 42,
    title: "An issue",
    body: "body text",
    assignees: [],
    labels: [],
    state: "open",
    state_reason: null,
    created_at: "2026-06-20T09:00:00.000Z",
    updated_at: "2026-06-21T09:00:00.000Z",
    ...over,
  };
}

const ALL_STATUSES: WorkstreamStatus[] = [
  "backlog",
  "ready",
  "in_progress",
  "in_review",
  "blocked",
  "pending",
  "done",
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
    expect(columnAccent("ready")).toBe("#5E84C4");
    expect(columnAccent("in_progress")).toBe("#E0A93B");
    expect(columnAccent("in_review")).toBe("#A87BE0");
    expect(columnAccent("blocked")).toBe("#E5534B");
    expect(columnAccent("pending")).toBe("#3FA6B0");
    expect(columnAccent("done")).toBe("#3FB950");
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
    }
    expect(priorityLabel("urgent")).toBe("Urgent");
    expect(priorityPillClass("urgent")).toContain("red");
    expect(priorityBarClass("urgent")).toContain("red");
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

describe("deriveColumn (state + state_reason + labels)", () => {
  it("closed + completed → done", () => {
    expect(
      deriveColumn(input({ state: "closed", state_reason: "completed" })),
    ).toBe("done");
  });

  it("closed with no state_reason → done", () => {
    expect(deriveColumn(input({ state: "closed", state_reason: null }))).toBe(
      "done",
    );
  });

  it("closed + not_planned → done (board has no Cancelled column)", () => {
    expect(
      deriveColumn(input({ state: "closed", state_reason: "not_planned" })),
    ).toBe("done");
  });

  it("closed + duplicate state_reason → done", () => {
    expect(
      deriveColumn(input({ state: "closed", state_reason: "duplicate" })),
    ).toBe("done");
  });

  it("closed + duplicate LABEL → done (every closed issue folds to done)", () => {
    expect(
      deriveColumn(
        input({
          state: "closed",
          state_reason: "completed",
          labels: ["duplicate"],
        }),
      ),
    ).toBe("done");
  });

  it("open + blocked label → blocked", () => {
    expect(deriveColumn(input({ labels: ["blocked"] }))).toBe("blocked");
  });

  it("open + in-progress label → in_progress", () => {
    expect(deriveColumn(input({ labels: ["in-progress"] }))).toBe(
      "in_progress",
    );
  });

  it("open + review / needs-review label → in_review", () => {
    expect(deriveColumn(input({ labels: ["review"] }))).toBe("in_review");
    expect(deriveColumn(input({ labels: ["needs-review"] }))).toBe("in_review");
  });

  it("open + ready / todo label → ready", () => {
    expect(deriveColumn(input({ labels: ["ready"] }))).toBe("ready");
    expect(deriveColumn(input({ labels: ["todo"] }))).toBe("ready");
  });

  it("open + pending label → pending", () => {
    expect(deriveColumn(input({ labels: ["pending"] }))).toBe("pending");
  });

  it("pending takes precedence over in-progress", () => {
    expect(deriveColumn(input({ labels: ["in-progress", "pending"] }))).toBe(
      "pending",
    );
  });

  it("open + no recognized label → backlog", () => {
    expect(deriveColumn(input({ labels: ["whatever", "wontfix"] }))).toBe(
      "backlog",
    );
  });

  it("blocked takes precedence over in-progress", () => {
    expect(
      deriveColumn(input({ labels: ["in-progress", "blocked"] })),
    ).toBe("blocked");
  });
});

describe("board Status preference (Phase 2, ADR-091)", () => {
  it("maps board Status names to app columns (case-insensitive)", () => {
    expect(boardStatusToWorkstreamStatus("Backlog")).toBe("backlog");
    expect(boardStatusToWorkstreamStatus("Ready")).toBe("ready");
    expect(boardStatusToWorkstreamStatus("In progress")).toBe("in_progress");
    expect(boardStatusToWorkstreamStatus("in review")).toBe("in_review");
    expect(boardStatusToWorkstreamStatus("Blocked")).toBe("blocked");
    expect(boardStatusToWorkstreamStatus("Pending")).toBe("pending");
    expect(boardStatusToWorkstreamStatus("Done")).toBe("done");
  });

  it("returns null for an unknown board Status name", () => {
    expect(boardStatusToWorkstreamStatus("Icebox")).toBeNull();
  });

  it("board Status overrides label/state derivation when present + mappable", () => {
    // labels would derive blocked; board says Pending -> Pending wins.
    expect(
      deriveColumn(input({ labels: ["blocked"], boardStatus: "Pending" })),
    ).toBe("pending");
    // board Status wins even over a closed issue's Done fold.
    expect(
      deriveColumn(input({ state: "closed", boardStatus: "In progress" })),
    ).toBe("in_progress");
  });

  it("falls back to label derivation for an unknown/absent board Status", () => {
    expect(
      deriveColumn(input({ labels: ["blocked"], boardStatus: "Nonsense" })),
    ).toBe("blocked");
    expect(deriveColumn(input({ labels: ["blocked"] }))).toBe("blocked");
  });
});

describe("deriveLive", () => {
  it("is true only when open AND carrying in-progress", () => {
    expect(deriveLive(input({ labels: ["in-progress"] }))).toBe(true);
    expect(deriveLive(input({ labels: [] }))).toBe(false);
    expect(
      deriveLive(input({ state: "closed", labels: ["in-progress"] })),
    ).toBe(false);
  });

  it("mirrors deriveColumn — blocked wins over in-progress, so live is false", () => {
    const both = input({ labels: ["blocked", "in-progress"] });
    expect(deriveColumn(both)).toBe("blocked");
    expect(deriveLive(both)).toBe(false);
    // And the full mapper never sets the `live` flag on the blocked card.
    expect(githubIssueToWorkstreamIssue(both).live).toBeUndefined();
  });
});

describe("derivePriority (priority/* label)", () => {
  it("maps p0–p3 to urgent/high/medium/low", () => {
    expect(derivePriority(["priority/p0-critical"])).toBe("urgent");
    expect(derivePriority(["priority/p1-high"])).toBe("high");
    expect(derivePriority(["priority/p2-medium"])).toBe("medium");
    expect(derivePriority(["priority/p3-low"])).toBe("low");
  });

  it("returns none when no priority label is present", () => {
    expect(derivePriority(["domain/engineering"])).toBe("none");
    expect(derivePriority([])).toBe("none");
  });

  it("takes the first matching priority label in issue order", () => {
    expect(derivePriority(["priority/p2-medium", "priority/p0-critical"])).toBe(
      "medium",
    );
  });
});

describe("deriveRole (domain/* label)", () => {
  it("maps each domain label to its role chip", () => {
    expect(deriveRole(["domain/engineering"])).toBe("cto");
    expect(deriveRole(["domain/product"])).toBe("cpo");
    expect(deriveRole(["domain/marketing"])).toBe("cmo");
    expect(deriveRole(["domain/operations"])).toBe("coo");
    expect(deriveRole(["domain/finance"])).toBe("cfo");
    expect(deriveRole(["domain/legal"])).toBe("clo");
    expect(deriveRole(["domain/sales"])).toBe("cro");
    expect(deriveRole(["domain/support"])).toBe("cco");
  });

  it("returns null for an unmapped / absent domain label", () => {
    expect(deriveRole(["domain/unknown"])).toBeNull();
    expect(deriveRole([])).toBeNull();
  });

  it("first domain/* label (in issue order) wins — deterministic", () => {
    expect(deriveRole(["domain/product", "domain/engineering"])).toBe("cpo");
  });
});

describe("deriveUser (first assignee)", () => {
  it("maps the first assignee login to { name, initials }", () => {
    expect(deriveUser(["octocat", "second"])).toEqual({
      name: "octocat",
      initials: "OC",
    });
  });

  it("is undefined when there are no assignees", () => {
    expect(deriveUser([])).toBeUndefined();
  });
});

describe("githubIssueToWorkstreamIssue (full mapper)", () => {
  it("maps number→id (String), title, body→description, timestamps", () => {
    const out = githubIssueToWorkstreamIssue(
      input({ number: 5652, title: "Tighten gap", body: "the body" }),
    );
    expect(out.id).toBe("5652");
    expect(out.title).toBe("Tighten gap");
    expect(out.description).toBe("the body");
    expect(out.createdAt).toBe("2026-06-20T09:00:00.000Z");
    expect(out.updatedAt).toBe("2026-06-21T09:00:00.000Z");
    expect(ALL_STATUSES).toContain(out.status);
    expect(ALL_PRIORITIES).toContain(out.priority);
  });

  it("null body → empty-string description", () => {
    expect(githubIssueToWorkstreamIssue(input({ body: null })).description).toBe(
      "",
    );
  });

  it("composes role + priority + user + live + column from labels/assignees", () => {
    const out = githubIssueToWorkstreamIssue(
      input({
        number: 7,
        labels: [
          "domain/engineering",
          "priority/p1-high",
          "in-progress",
        ],
        assignees: ["harry"],
      }),
    );
    expect(out.status).toBe("in_progress");
    expect(out.priority).toBe("high");
    expect(out.assigneeRole).toBe("cto");
    expect(out.user).toEqual({ name: "harry", initials: "HA" });
    expect(out.live).toBe(true);
    expect(isLive(out)).toBe(true);
  });

  it("degrades to null/none/backlog with no user when unmapped and never throws", () => {
    const out = githubIssueToWorkstreamIssue(
      input({ labels: ["bug", "wontfix"], assignees: [] }),
    );
    expect(out.assigneeRole).toBeNull();
    expect(out.priority).toBe("none");
    expect(out.status).toBe("backlog");
    expect(out.user).toBeUndefined();
    expect(out.live).toBeUndefined();
  });

  it("closed + not_planned → done column", () => {
    expect(
      githubIssueToWorkstreamIssue(
        input({ state: "closed", state_reason: "not_planned" }),
      ).status,
    ).toBe("done");
  });
});
