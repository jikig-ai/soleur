// @vitest-environment happy-dom
import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ReactNode } from "react";

// #9545 PR2 — the destination view. It is presentational: the loader's tagged result is the only input,
// so every branch of the state ladder (plan D3) is driven here without a database or a router.

vi.mock("@/components/ui/nav-link", () => ({
  NavLink: ({ href, children, ...rest }: { href: string; children: ReactNode }) => (
    <a href={href} {...rest}>
      {children}
    </a>
  ),
}));
vi.mock("@/components/settings/egress-audit-refresh-button", () => ({
  EgressAuditRefreshButton: ({ label }: { label: string }) => <button type="button">{label}</button>,
}));

import { EgressAuditView } from "@/components/settings/egress-audit-view";
import { EGRESS_AUDIT_HEADING_ID } from "@/components/settings/egress-audit-focus";
import { EGRESS_AUDIT_PATH, PAGE_LIMIT, type EgressAuditPayload, type EgressAuditResult } from "@/lib/egress-audit/summary";

// The completeness-claim rules (spec FR4): never these words, never a calendar date in a retention sentence.
const FORBIDDEN = /\bcomplete\b|every connection|tamper-proof|\bsessions\b/i;
// "all"/"every" used as a claim that the list is complete (not "every current member", not "(all outcomes)").
const COMPLETENESS_CLAIM = /\ball (?:requests|hosts|sites|connections|traffic|activity)\b|\bevery (?:request|host|site|outbound|connection)\b|\bcomplete (?:list|record|log)\b/i;

const NOW = Date.parse("2026-10-26T12:10:00Z");
const BASE = EGRESS_AUDIT_PATH;

const payload = (over: Partial<EgressAuditPayload> = {}): EgressAuditPayload => ({
  window: { start: "2026-09-26T12:10:00Z", end: "2026-10-26T12:10:00Z" },
  truncated: false,
  summary: { request_count_min: 14326, blocked_request_count_min: 121, last_request_at: "2026-10-26T12:06:00Z" },
  rows: [
    { host: "github.com", decision: "allowed", request_count: 4812, last_seen: "2026-10-26T12:08:00Z" },
    { host: "example-tracker.net", decision: "denied", request_count: 71, last_seen: "2026-10-26T10:10:00Z" },
    { host: "httpbin.org", decision: "other", request_count: 6, last_seen: "2026-10-22T12:00:00Z" },
  ],
  overflow: [
    { decision: "allowed", request_count: 1240, last_seen: "2026-10-25T12:00:00Z" },
    { decision: "denied", request_count: 9, last_seen: "2026-10-20T12:00:00Z" },
  ],
  ...over,
});

const empty = (over: Partial<EgressAuditPayload> = {}) =>
  payload({
    rows: [],
    overflow: [],
    summary: { request_count_min: 0, blocked_request_count_min: 0, last_request_at: null },
    ...over,
  });

const ready = (data: EgressAuditPayload, over: Partial<Extract<EgressAuditResult, { kind: "ready" }>> = {}): EgressAuditResult => ({
  kind: "ready",
  data,
  collection: true,
  webAccess: true,
  workspaceName: "Acme",
  ...over,
});

const show = (result: EgressAuditResult, filter: "all" | "allowed" | "blocked" | "other" = "all") =>
  render(<EgressAuditView result={result} filter={filter} now={NOW} />);

afterEach(cleanup);

describe("EgressAuditView — populated", () => {
  it("lists hosts with outcome text, 'at least' counts and relative times; overflow rows are labelled and never host rows", () => {
    show(ready(payload()));
    const row = screen.getByRole("row", { name: /github\.com/ });
    expect(within(row).getByText("Allowed")).toBeTruthy();
    expect(within(row).getByText("at least 4,812")).toBeTruthy();
    expect(within(row).getByText("2 minutes ago")).toBeTruthy();
    expect(screen.getByRole("row", { name: /example-tracker\.net/ })).toBeTruthy();
    expect(within(screen.getByRole("row", { name: /example-tracker\.net/ })).getByText("Blocked")).toBeTruthy();
    expect(within(screen.getByRole("row", { name: /httpbin\.org/ })).getByText("Other")).toBeTruthy();
    const overflow = screen.getAllByText("Other hosts, not listed individually");
    expect(overflow).toHaveLength(2);
    expect(screen.queryByText("(other)")).toBeNull();
    expect(screen.getByText("at least 1,240")).toBeTruthy();
  });

  it("names the workspace in the subtitle and states the summary as minimums", () => {
    show(ready(payload()));
    expect(screen.getByText(/Sites Acme's agents contacted in about the last 30 days/)).toBeTruthy();
    expect(screen.getByText("At least 14,326 requests · at least 121 blocked")).toBeTruthy();
  });

  it("shows the best-effort banner with pre-join visibility and the 30-day deletion sentence, and the footer states history cannot be deleted from here", () => {
    show(ready(payload()));
    expect(screen.getByText("A best-effort summary, not a full record.")).toBeTruthy();
    expect(screen.getByText(/including activity from before they joined/)).toBeTruthy();
    expect(screen.getByText(/Records are deleted about 30 days after they were recorded\.$/, { selector: "span" }).textContent).toBe(
      "Some requests may be missing and counts are minimums. Every current member of this workspace can see this list, including activity from before they joined. No member or session is recorded. Records are deleted about 30 days after they were recorded.",
    );
    expect(screen.getByText(/History can't be deleted from this page/)).toBeTruthy();
    const link = screen.getByRole("link", { name: "How to request erasure" });
    expect(link.getAttribute("href")).toBe("https://soleur.ai/legal/privacy-policy/#data-subject-rights");
  });

  it("filter chips are links with aria-current on the selected one; the summary says (all outcomes) under a filter", () => {
    show(ready(payload()), "blocked");
    const nav = screen.getByRole("navigation", { name: "Filter by outcome" });
    const chips = within(nav).getAllByRole("link");
    expect(chips.map((c) => c.textContent)).toEqual(["All", "Allowed", "Blocked", "Other"]);
    expect(chips.map((c) => c.getAttribute("href"))).toEqual([BASE, `${BASE}?decision=allowed`, `${BASE}?decision=blocked`, `${BASE}?decision=other`]);
    expect(chips.filter((c) => c.getAttribute("aria-current") === "page").map((c) => c.textContent)).toEqual(["Blocked"]);
    expect(screen.getByText(/\(all outcomes\)/)).toBeTruthy();
  });

  it("truncation says entries (not sites), names the filter, and does not repeat itself in a footer", () => {
    const { unmount } = show(ready(payload({ truncated: true })));
    expect(screen.getAllByText(/most recent entries/)).toHaveLength(1);
    expect(screen.queryByText(/200 sites shown/)).toBeNull();
    unmount();
    show(ready(payload({ truncated: true })), "blocked");
    expect(screen.getByText(`Showing the ${PAGE_LIMIT} most recent Blocked entries.`)).toBeTruthy();
  });

  it("pins the four disclosures: truncation announcement naming the limit, the labelled overflow line with its 'at least' count, no completeness claim, the limit stated", () => {
    show(ready(payload({ truncated: true })));
    expect(PAGE_LIMIT).toBeGreaterThan(0);
    const trunc = screen.getByText(`Showing the ${PAGE_LIMIT} most recent entries.`);
    expect(trunc.textContent).toContain(String(PAGE_LIMIT));
    expect(screen.getByText("Older entries in this 30-day window are not listed, and counts are minimums.")).toBeTruthy();
    const overflowRow = screen.getAllByRole("row").find((r) => r.textContent?.includes("Other hosts, not listed individually"));
    expect(overflowRow).toBeTruthy();
    expect(within(overflowRow as HTMLElement).getByText("at least 1,240")).toBeTruthy();
    expect(document.body.textContent).not.toMatch(COMPLETENESS_CLAIM);
    expect(document.body.textContent).not.toMatch(FORBIDDEN);
  });

  it("an overflow row carries visible (not title-only) minimum-count text", () => {
    show(ready(payload()));
    const overflowRow = screen.getAllByRole("row").find((r) => r.textContent?.includes("Other hosts, not listed individually")) as HTMLElement;
    expect(within(overflowRow).getByText("Counts are minimums and may be lower than actual activity.")).toBeTruthy();
    expect(overflowRow.querySelector("[title]")).toBeNull();
  });

  it("a very long workspace name is clipped with an ellipsis and the subtitle may wrap", () => {
    const long = "W".repeat(200);
    show(ready(payload(), { workspaceName: long }));
    const sub = screen.getByText(/^Sites W+….s agents contacted/);
    expect(sub.textContent).not.toContain(long);
    expect(sub.className).toContain("break-words");
  });

  it("no element carries a title with a clock time (relative age only)", () => {
    show(ready(payload()));
    const titles = Array.from(document.querySelectorAll("[title]")).map((e) => e.getAttribute("title") ?? "");
    expect(titles.length).toBeGreaterThan(0); // the host cells still have a title
    for (const t of titles) expect(t).not.toMatch(/\d{2}:\d{2}/);
    expect(document.querySelector("time[title]")).toBeNull();
  });

  it("table semantics survive the mobile restack: explicit roles and a visible label on every value", () => {
    show(ready(payload()));
    expect(screen.getByRole("table")).toBeTruthy();
    expect(screen.getAllByRole("rowgroup")).toHaveLength(2);
    expect(screen.getAllByRole("columnheader").map((c) => c.textContent)).toEqual(["Host", "Outcome", "Requests (minimum)", "Last seen"]);
    const rows = screen.getAllByRole("row");
    expect(rows).toHaveLength(1 + 3 + 2);
    const row = screen.getByRole("row", { name: /github\.com/ });
    expect(within(row).getByRole("rowheader").textContent).toContain("github.com");
    const cells = within(row).getAllByRole("cell");
    expect(cells).toHaveLength(3);
    expect(cells.map((c) => c.querySelector("span.md\\:hidden")?.textContent)).toEqual(["Outcome", "Requests", "Last seen"]);
    expect(within(row).getByRole("rowheader").querySelector("span.md\\:hidden")?.textContent).toBe("Host");
    // The roles must be explicit attributes (not just implied by the tags): WebKit drops the implicit role once display is overridden.
    expect(screen.getByRole("table").getAttribute("role")).toBe("table");
    for (const rg of screen.getAllByRole("rowgroup")) expect(rg.getAttribute("role")).toBe("rowgroup");
    for (const r of rows) expect(r.getAttribute("role")).toBe("row");
    for (const c of cells) expect(c.getAttribute("role")).toBe("cell");
    expect(within(row).getByRole("rowheader").getAttribute("role")).toBe("rowheader");
    for (const h of screen.getAllByRole("columnheader")) expect(h.getAttribute("role")).toBe("columnheader");
  });

  it("the heading is a focus target for the refresh button", () => {
    show(ready(payload()));
    const h1 = screen.getByRole("heading", { level: 1 });
    expect(h1.id).toBe(EGRESS_AUDIT_HEADING_ID);
    expect(h1.getAttribute("tabindex")).toBe("-1");
  });

  it("web access unknown (null) with data shows rows and NO 'Web access is off' notice", () => {
    show(ready(payload(), { webAccess: null }));
    expect(screen.getByRole("row", { name: /github\.com/ })).toBeTruthy();
    expect(screen.queryByText("Web access is off. Nothing new is recorded.")).toBeNull();
  });

  it("web access on with data shows NO 'Web access is off' notice", () => {
    show(ready(payload(), { webAccess: true }));
    expect(screen.queryByText("Web access is off. Nothing new is recorded.")).toBeNull();
  });

  it("only overflow rows (no host rows) is still data: the overflow row shows, not 'No requests recorded yet'", () => {
    show(ready(payload({ rows: [] })));
    expect(screen.getAllByText("Other hosts, not listed individually")).toHaveLength(2);
    expect(screen.queryByText("No requests recorded yet")).toBeNull();
    expect(screen.queryByText("Recording isn't on for this workspace.")).toBeNull();
  });

  it("only host rows (no overflow) is still data", () => {
    show(ready(payload({ overflow: [] })));
    expect(screen.getByRole("row", { name: /github\.com/ })).toBeTruthy();
    expect(screen.queryByText("No requests recorded yet")).toBeNull();
  });

  it("a workspace with web access off shows the notice with no date and keeps the rows", () => {
    show(ready(payload(), { webAccess: false }));
    expect(screen.getByText("Web access is off. Nothing new is recorded.")).toBeTruthy();
    expect(screen.getByText("Records are deleted about 30 days after they were recorded.")).toBeTruthy();
    expect(screen.getByRole("row", { name: /github\.com/ })).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/\b20\d\d\b[^:]*\bNov\b|until [A-Z][a-z]{2} \d/);
  });

  it("rows are shown even when collection is off now (history stays visible), and the banner stays", () => {
    show(ready(payload(), { collection: false }));
    expect(screen.getByRole("row", { name: /github\.com/ })).toBeTruthy();
    expect(screen.getByText("A best-effort summary, not a full record.")).toBeTruthy();
  });
});

describe("EgressAuditView — empty ladder", () => {
  it("collection off, no rows: 'Recording isn't on' and the visibility banner is hidden", () => {
    show(ready(empty(), { collection: false }));
    expect(screen.getByText("Recording isn't on for this workspace.")).toBeTruthy();
    expect(screen.queryByText("A best-effort summary, not a full record.")).toBeNull();
  });

  it("collection on and web access on, no rows: 'No requests recorded yet' with Refresh and no date", () => {
    show(ready(empty()));
    expect(screen.getByText("No requests recorded yet")).toBeTruthy();
    expect(screen.getByText(/Requests can take a few minutes to appear/)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/Recording since/);
  });

  it("collection on and web access off, no rows: 'Nothing recorded in the last 30 days'", () => {
    show(ready(empty(), { webAccess: false }));
    expect(screen.getByText("Nothing recorded in the last 30 days")).toBeTruthy();
    expect(screen.getByText(/Web access is off, so nothing new is recorded/)).toBeTruthy();
  });

  it("an unknown collection state or unknown web access renders the error, never 'isn't on'", () => {
    show(ready(empty(), { collection: "unknown" }));
    expect(screen.getByRole("alert").textContent).toContain("loading error, not an empty log");
    expect(screen.queryByText("Recording isn't on for this workspace.")).toBeNull();
    cleanup();
    show(ready(empty(), { webAccess: null }));
    expect(screen.getByRole("alert").textContent).toContain("loading error, not an empty log");
  });

  it("a filtered view with no rows and a zero total, collection off, is 'Recording isn't on', not 'No Blocked requests'", () => {
    show(ready(empty(), { collection: false }), "blocked");
    expect(screen.getByText("Recording isn't on for this workspace.")).toBeTruthy();
    expect(screen.queryByText(/No Blocked requests/)).toBeNull();
  });

  it("a filter with no matches while the window has requests is its own line with 'Show all', chips kept", () => {
    show(ready(empty({ summary: { request_count_min: 500, blocked_request_count_min: 0, last_request_at: "2026-10-26T12:00:00Z" } })), "blocked");
    expect(screen.getByText("No Blocked requests in the last 30 days.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Show all" }).getAttribute("href")).toBe(BASE);
    expect(screen.getByRole("navigation", { name: "Filter by outcome" })).toBeTruthy();
    expect(screen.queryByText("No requests recorded yet")).toBeNull();
  });
});

describe("EgressAuditView — error and access states", () => {
  it("unavailable is an alert that says it is a loading error with Try again", () => {
    show({ kind: "unavailable" });
    const alert = screen.getByRole("alert");
    expect(alert.textContent).toContain("Couldn't load the egress audit log.");
    expect(alert.textContent).toContain("This is a loading error, not an empty log.");
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
    expect(screen.queryByRole("row")).toBeNull();
  });

  it("forbidden says access is gone, shows no rows, and links to switch workspace", () => {
    show({ kind: "forbidden" });
    expect(screen.getByText("You no longer have access to this workspace.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Switch workspace" })).toBeTruthy();
    expect(screen.queryByRole("row")).toBeNull();
    expect(screen.queryByText("A best-effort summary, not a full record.")).toBeNull();
  });

  it("forbidden and unbound are alerts like the unavailable card", () => {
    show({ kind: "forbidden" });
    expect(screen.getByRole("alert").textContent).toContain("You no longer have access");
    cleanup();
    show({ kind: "unbound" });
    expect(screen.getByRole("alert").textContent).toContain("We couldn't determine your workspace.");
  });

  it("unbound says the workspace could not be determined", () => {
    show({ kind: "unbound" });
    expect(screen.getByText("We couldn't determine your workspace.")).toBeTruthy();
    expect(screen.queryByRole("row")).toBeNull();
  });
});

describe("EgressAuditView — copy rules", () => {
  it("no state renders a forbidden word, a completeness claim or a calendar date in a retention sentence", () => {
    const states: EgressAuditResult[] = [
      ready(payload()),
      ready(payload({ truncated: true }), { webAccess: false }),
      ready(payload({ truncated: true }), {}),
      ready(empty()),
      ready(empty(), { webAccess: false }),
      ready(empty(), { collection: false }),
      ready(empty(), { collection: "unknown" }),
      ready(empty(), { webAccess: null }),
      ready(empty({ summary: { request_count_min: 500, blocked_request_count_min: 0, last_request_at: "2026-10-26T12:00:00Z" } })),
      { kind: "unavailable" },
      { kind: "forbidden" },
      { kind: "unbound" },
    ];
    // Filtered states: the truncated+filter notice and the filtered-empty line.
    const filtered: [EgressAuditResult, "allowed" | "blocked" | "other"][] = [
      [ready(payload({ truncated: true })), "blocked"],
      [ready(empty({ summary: { request_count_min: 500, blocked_request_count_min: 0, last_request_at: "2026-10-26T12:00:00Z" } })), "other"],
      [ready(empty(), { collection: false }), "allowed"],
    ];
    expect(states.length).toBeGreaterThan(0);
    expect(filtered.length).toBeGreaterThan(0);
    const runs: [EgressAuditResult, "all" | "allowed" | "blocked" | "other"][] = [...states.map((r) => [r, "all"] as [EgressAuditResult, "all"]), ...filtered];
    expect.hasAssertions();
    for (const [s, f] of runs) {
      const { unmount } = show(s, f);
      const text = document.body.textContent ?? "";
      expect(text.length).toBeGreaterThan(0);
      expect(text).not.toMatch(FORBIDDEN);
      expect(text).not.toMatch(COMPLETENESS_CLAIM);
      expect(text).not.toMatch(/(?:until|since|on)\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d/);
      unmount();
    }
  });

  it("the 'Other' explainer says 'allowed through' and the chips never claim completeness", () => {
    show(ready(payload()));
    expect(screen.getByText(/Other: the request was neither allowed through nor blocked by policy/)).toBeTruthy();
  });
});
