import { describe, expect, it } from "vitest";
import {
  CLOSED_STATUSES,
  COLUMN_CAP_NOTICE,
  COLUMN_RENDER_CAP,
  creatorFilterKey,
  deriveColumn,
  deriveFilterOptions,
  emptyFilters,
  githubIssueToWorkstreamIssue,
  hasActiveFilters,
  isClosed,
  matchesFilters,
  matchesSearch,
  STATUS_ORDER,
  type BoardIssueInput,
  type WorkstreamCreator,
  type WorkstreamFilters,
  type WorkstreamIssue,
} from "@/lib/workstream";

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "1",
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

function ghInput(over: Partial<BoardIssueInput> = {}): BoardIssueInput {
  return {
    number: 1,
    title: "t",
    body: null,
    assignees: [],
    labels: [],
    state: "open",
    state_reason: null,
    created_at: "2026-06-20T09:00:00.000Z",
    updated_at: "2026-06-20T09:00:00.000Z",
    ...over,
  };
}

describe("isClosed / CLOSED_STATUSES", () => {
  it("done is closed; the other six are open", () => {
    expect(isClosed(issue({ status: "done" }))).toBe(true);
    for (const s of ["backlog", "ready", "in_progress", "in_review", "blocked", "pending"] as const) {
      expect(isClosed(issue({ status: s }))).toBe(false);
    }
  });

  it("round-trip: every status deriveColumn yields for a closed GitHub issue is in CLOSED_STATUSES", () => {
    // every closed issue folds to done (board has no Cancelled column, ADR-097)
    const completed = deriveColumn(ghInput({ state: "closed", state_reason: "completed" }));
    const notPlanned = deriveColumn(ghInput({ state: "closed", state_reason: "not_planned" }));
    expect(CLOSED_STATUSES.has(completed)).toBe(true);
    expect(CLOSED_STATUSES.has(notPlanned)).toBe(true);
    // open never lands in a closed status
    for (const s of STATUS_ORDER) {
      const open = deriveColumn(ghInput({ state: "open", labels: [] }));
      expect(CLOSED_STATUSES.has(open)).toBe(false);
      void s;
    }
  });
});

describe("domains mapping", () => {
  it("populates domains with every domain/* label; absent when none", () => {
    const multi = githubIssueToWorkstreamIssue(
      ghInput({ labels: ["domain/engineering", "domain/product", "blocked"] }),
    );
    expect(multi.domains).toEqual(["domain/engineering", "domain/product"]);
    const none = githubIssueToWorkstreamIssue(ghInput({ labels: ["blocked"] }));
    expect(none.domains).toBeUndefined();
  });
});

describe("matchesFilters", () => {
  it("empty filters pass everything", () => {
    expect(matchesFilters(issue(), emptyFilters())).toBe(true);
  });

  it("priority: OR within dimension", () => {
    const f: WorkstreamFilters = { ...emptyFilters(), priorities: new Set(["urgent", "high"]) };
    expect(matchesFilters(issue({ priority: "urgent" }), f)).toBe(true);
    expect(matchesFilters(issue({ priority: "high" }), f)).toBe(true);
    expect(matchesFilters(issue({ priority: "low" }), f)).toBe(false);
  });

  it("status tri-state: all/open/closed", () => {
    const open = issue({ status: "ready" });
    const closed = issue({ status: "done" });
    expect(matchesFilters(open, { ...emptyFilters(), status: "all" })).toBe(true);
    expect(matchesFilters(closed, { ...emptyFilters(), status: "all" })).toBe(true);
    expect(matchesFilters(open, { ...emptyFilters(), status: "open" })).toBe(true);
    expect(matchesFilters(closed, { ...emptyFilters(), status: "open" })).toBe(false);
    expect(matchesFilters(closed, { ...emptyFilters(), status: "closed" })).toBe(true);
    expect(matchesFilters(open, { ...emptyFilters(), status: "closed" })).toBe(false);
  });

  it("assignee: role OR person OR unassigned (combined-OR)", () => {
    const byRole = { ...emptyFilters(), roles: new Set(["cto"] as const) };
    expect(matchesFilters(issue({ assigneeRole: "cto" }), byRole)).toBe(true);
    expect(matchesFilters(issue({ assigneeRole: "cmo" }), byRole)).toBe(false);

    const byUser = { ...emptyFilters(), users: new Set(["alice"]) };
    expect(matchesFilters(issue({ user: { name: "alice", initials: "AL" } }), byUser)).toBe(true);
    expect(matchesFilters(issue({ user: { name: "bob", initials: "BO" } }), byUser)).toBe(false);

    const unassigned = { ...emptyFilters(), unassigned: true };
    expect(matchesFilters(issue({ assigneeRole: null }), unassigned)).toBe(true);
    expect(matchesFilters(issue({ assigneeRole: "cto" }), unassigned)).toBe(false);

    // OR within the assignee dimension: role OR unassigned both selected
    const either = { ...emptyFilters(), roles: new Set(["cto"] as const), unassigned: true };
    expect(matchesFilters(issue({ assigneeRole: "cto" }), either)).toBe(true);
    expect(matchesFilters(issue({ assigneeRole: null }), either)).toBe(true);
    expect(matchesFilters(issue({ assigneeRole: "cmo" }), either)).toBe(false);
  });

  it("domain: OR within, on real domain/* labels", () => {
    const f = { ...emptyFilters(), domains: new Set(["domain/product"]) };
    expect(matchesFilters(issue({ domains: ["domain/engineering", "domain/product"] }), f)).toBe(true);
    expect(matchesFilters(issue({ domains: ["domain/engineering"] }), f)).toBe(false);
    expect(matchesFilters(issue({ domains: undefined }), f)).toBe(false);
  });

  it("AND across dimensions", () => {
    const f = {
      ...emptyFilters(),
      priorities: new Set(["urgent"] as const),
      status: "open" as const,
    };
    expect(matchesFilters(issue({ priority: "urgent", status: "ready" }), f)).toBe(true);
    expect(matchesFilters(issue({ priority: "urgent", status: "done" }), f)).toBe(false); // fails status
    expect(matchesFilters(issue({ priority: "low", status: "ready" }), f)).toBe(false); // fails priority
  });
});

describe("creator filter dimension", () => {
  const human: WorkstreamCreator = {
    login: "octocat",
    isSoleur: false,
    display: { name: "octocat", initials: "OC" },
  };
  const soleur: WorkstreamCreator = {
    login: "soleur-ai[bot]",
    isSoleur: true,
    display: { name: "Soleur", initials: "SO" },
  };
  const soleurInitiated: WorkstreamCreator = {
    login: "soleur-ai[bot]",
    isSoleur: true,
    initiatorLogin: "harry",
    display: { name: "harry", initials: "HA" },
  };

  it("creatorFilterKey maps to the effective creator identity", () => {
    expect(creatorFilterKey(human)).toBe("octocat");
    expect(creatorFilterKey(soleur)).toBe("Soleur");
    // the human initiator wins over the bot for a Soleur-initiated issue
    expect(creatorFilterKey(soleurInitiated)).toBe("harry");
  });

  it("matchesFilters gates on the creator key (OR within, absent = excluded)", () => {
    const f: WorkstreamFilters = {
      ...emptyFilters(),
      creators: new Set(["octocat"]),
    };
    expect(matchesFilters(issue({ creator: human }), f)).toBe(true);
    expect(matchesFilters(issue({ creator: soleur }), f)).toBe(false);
    // an issue with no creator is excluded when the creator filter is active
    expect(matchesFilters(issue({ creator: undefined }), f)).toBe(false);
  });

  it("filtering a person surfaces both direct + Soleur-initiated issues", () => {
    const f: WorkstreamFilters = {
      ...emptyFilters(),
      creators: new Set(["harry"]),
    };
    // Soleur-created but initiated by harry
    expect(matchesFilters(issue({ creator: soleurInitiated }), f)).toBe(true);
    // a human "harry" author would also match (key = login)
    expect(
      matchesFilters(
        issue({
          creator: {
            login: "harry",
            isSoleur: false,
            display: { name: "harry", initials: "HA" },
          },
        }),
        f,
      ),
    ).toBe(true);
  });

  it("deriveFilterOptions collects distinct creator keys (alphabetical)", () => {
    const opts = deriveFilterOptions([
      issue({ creator: human }),
      issue({ creator: soleur }),
      issue({ creator: soleurInitiated }),
      issue({ creator: undefined }),
    ]);
    expect(opts.creators).toEqual(["Soleur", "harry", "octocat"]);
  });

  it("hasActiveFilters is true when a creator is selected", () => {
    expect(
      hasActiveFilters({ ...emptyFilters(), creators: new Set(["Soleur"]) }, ""),
    ).toBe(true);
  });
});

describe("matchesSearch composition", () => {
  it("matches id or title, case-insensitive; empty query passes", () => {
    const i = issue({ id: "5660", title: "Filter bar" });
    expect(matchesSearch(i, "")).toBe(true);
    expect(matchesSearch(i, "566")).toBe(true);
    expect(matchesSearch(i, "FILTER")).toBe(true);
    expect(matchesSearch(i, "nope")).toBe(false);
  });
});

describe("deriveFilterOptions", () => {
  it("derives de-duplicated options from the full set, hides empties, surfaces all domains", () => {
    const issues = [
      issue({ priority: "urgent", assigneeRole: "cto", domains: ["domain/engineering"] }),
      issue({ priority: "urgent", assigneeRole: null, user: undefined, domains: ["domain/product"] }),
      issue({ priority: "low", assigneeRole: "cmo", user: { name: "alice", initials: "AL" } }),
    ];
    const opts = deriveFilterOptions(issues);
    expect(opts.priorities).toEqual(expect.arrayContaining(["urgent", "low"]));
    expect(opts.priorities).not.toContain("high"); // empty → hidden
    expect(opts.roles).toEqual(expect.arrayContaining(["cto", "cmo"]));
    expect(opts.users).toContain("alice");
    expect(opts.hasUnassigned).toBe(true);
    expect(opts.domains).toEqual(expect.arrayContaining(["domain/engineering", "domain/product"]));
  });
});

describe("hasActiveFilters", () => {
  it("true when any dimension or search is active", () => {
    expect(hasActiveFilters(emptyFilters(), "")).toBe(false);
    expect(hasActiveFilters(emptyFilters(), "x")).toBe(true);
    expect(hasActiveFilters({ ...emptyFilters(), status: "open" }, "")).toBe(true);
    expect(hasActiveFilters({ ...emptyFilters(), priorities: new Set(["low"]) }, "")).toBe(true);
    expect(hasActiveFilters({ ...emptyFilters(), unassigned: true }, "")).toBe(true);
  });
});

describe("render-cap constants", () => {
  it("cap is 200 and the notice is the exact mandated copy", () => {
    expect(COLUMN_RENDER_CAP).toBe(200);
    expect(COLUMN_CAP_NOTICE).toBe(
      "Some board columns are showing up to 200 issues. Refine filters or search to reveal the rest.",
    );
  });
});
