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
import {
  EGRESS_AUDIT_PATH,
  PAGE_LIMIT,
  TIME_WINDOWS,
  WINDOW_LABEL,
  type EgressAuditPayload,
  type EgressAuditResult,
  type TimeWindow,
} from "@/lib/egress-audit/summary";

// Substring match on the accessible name: a host is data here, not a pattern.
const rowFor = (host: string) =>
  screen.getByRole("row", { name: (accessibleName) => accessibleName.includes(host) });

// The completeness-claim rules (spec FR4): never these words, never a calendar date in a retention sentence.
const FORBIDDEN = /\bcomplete\b|every connection|tamper-proof|\bsessions\b/i;
// "all"/"every" used as a claim that the list is complete (not "every current member", not "(all outcomes)").
const ISO_STAMP = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;
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

type Filter = "all" | "allowed" | "blocked" | "other";
// window-assembly: timeWindow — not a regex-extracted source region: it is the selected time window (24h / 7d / 30d)
// the view is rendered with. The closure assertions below are complete against TIME_WINDOWS and the LADDER states.
const show = (result: EgressAuditResult, filter: Filter = "all", timeWindow: TimeWindow = "30d") =>
  render(<EgressAuditView result={result} filter={filter} timeWindow={timeWindow} now={NOW} />);

afterEach(cleanup);

describe("EgressAuditView — populated", () => {
  it("lists hosts with outcome text, 'at least' counts and relative times; overflow rows are labelled and never host rows", () => {
    show(ready(payload()));
    const row = rowFor("github.com");
    expect(within(row).getByText("Allowed")).toBeTruthy();
    expect(within(row).getByText("at least 4,812")).toBeTruthy();
    expect(within(row).getByText("2 minutes ago")).toBeTruthy();
    expect(rowFor("example-tracker.net")).toBeTruthy();
    expect(within(rowFor("example-tracker.net")).getByText("Blocked")).toBeTruthy();
    expect(within(rowFor("httpbin.org")).getByText("Other")).toBeTruthy();
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
    expect(screen.getByText("Older entries in this window are not listed, and counts are minimums.")).toBeTruthy();
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

  it("no <time> element and no ISO timestamp anywhere in the markup (DPIA C7: no full timestamp on any time cell)", () => {
    show(ready(payload()));
    expect(document.querySelector("time")).toBeNull();
    expect(document.body.innerHTML).not.toMatch(ISO_STAMP);
    expect(screen.getByText("2 minutes ago")).toBeTruthy();
  });

  it("table semantics survive the mobile restack: explicit roles and a visible label on every value", () => {
    show(ready(payload()));
    expect(screen.getByRole("table")).toBeTruthy();
    expect(screen.getAllByRole("rowgroup")).toHaveLength(2);
    expect(screen.getAllByRole("columnheader").map((c) => c.textContent)).toEqual(["Host", "Outcome", "Requests (minimum)", "Last seen"]);
    const rows = screen.getAllByRole("row");
    expect(rows).toHaveLength(1 + 3 + 2);
    const row = rowFor("github.com");
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

  it("the 'Scope Grants' back link points at the scope grants settings page", () => {
    show(ready(payload()));
    expect(screen.getByRole("link", { name: "Scope Grants" }).getAttribute("href")).toBe("/dashboard/settings/scope-grants");
  });

  it("an empty or missing workspace name falls back to 'your workspace's' in the subtitle", () => {
    show(ready(payload(), { workspaceName: "" }));
    expect(screen.getByText(/^Sites your workspace's agents contacted in about the last 30 days/)).toBeTruthy();
    cleanup();
    show(ready(payload(), { workspaceName: null }));
    expect(screen.getByText(/^Sites your workspace's agents contacted in about the last 30 days/)).toBeTruthy();
  });

  it("the heading is a focus target for the refresh button", () => {
    show(ready(payload()));
    const h1 = screen.getByRole("heading", { level: 1 });
    expect(h1.id).toBe(EGRESS_AUDIT_HEADING_ID);
    expect(h1.getAttribute("tabindex")).toBe("-1");
  });

  it("web access unknown (null) with data shows rows and NO 'Web access is off' notice", () => {
    show(ready(payload(), { webAccess: null }));
    expect(rowFor("github.com")).toBeTruthy();
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
    expect(rowFor("github.com")).toBeTruthy();
    expect(screen.queryByText("No requests recorded yet")).toBeNull();
  });

  it("a workspace with web access off shows the notice with no date and keeps the rows", () => {
    show(ready(payload(), { webAccess: false }));
    expect(screen.getByText("Web access is off. Nothing new is recorded.")).toBeTruthy();
    expect(screen.getByText("Records are deleted about 30 days after they were recorded.")).toBeTruthy();
    expect(rowFor("github.com")).toBeTruthy();
    expect(document.body.textContent).not.toMatch(/\b20\d\d\b[^:]*\bNov\b|until [A-Z][a-z]{2} \d/);
  });

  it("rows are shown even when collection is off now (history stays visible), and the banner stays", () => {
    show(ready(payload(), { collection: false }));
    expect(rowFor("github.com")).toBeTruthy();
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

  it("collection on and web access off, no rows: 'Nothing recorded in about the last 30 days'", () => {
    show(ready(empty(), { webAccess: false }));
    expect(screen.getByText("Nothing recorded in about the last 30 days")).toBeTruthy();
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
    expect(screen.getByText("No Blocked requests recorded in about the last 30 days.")).toBeTruthy();
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
    expect(alert.textContent).toContain("If it keeps happening, try again in a minute.");
    expect(alert.textContent).not.toMatch(/Nothing has been deleted/i);
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
    expect(screen.queryByRole("row")).toBeNull();
  });

  it("forbidden says access is gone, shows no rows, and links to switch workspace", () => {
    show({ kind: "forbidden" });
    expect(screen.getByText("You no longer have access to this workspace.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Switch workspace" }).getAttribute("href")).toBe("/dashboard");
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

  it("unbound says the workspace could not be determined and links to switch workspace", () => {
    show({ kind: "unbound" });
    expect(screen.getByText("We couldn't determine your workspace.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Switch workspace" }).getAttribute("href")).toBe("/dashboard");
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
      expect(document.querySelector("time")).toBeNull();
      expect(document.body.innerHTML).not.toMatch(ISO_STAMP);
      expect(text).not.toMatch(/(?:until|since|on)\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d/);
      unmount();
    }
  });

  it("the 'Other' explainer says 'allowed through' and the chips never claim completeness", () => {
    show(ready(payload()));
    expect(screen.getByText(/Other: the request was neither allowed through nor blocked by policy/)).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------------------------------------
// #11238 — the time-window selector. The window is chosen by the URL; the view derives every window-scoped
// sentence from it. Retention and visibility sentences are never windowed.
// ---------------------------------------------------------------------------------------------------------

const WINDOW_NAV = { name: "Time window" } as const;
const SOME = { request_count_min: 500, blocked_request_count_min: 0, last_request_at: "2026-10-26T12:00:00Z" };
const SHORTER = ["24h", "7d"] as const;

const BANNER_LEAD = "A best-effort summary, not a full record.";
const BANNER_BODY =
  "Some requests may be missing and counts are minimums. Every current member of this workspace can see this list, including activity from before they joined. No member or session is recorded. Records are deleted about 30 days after they were recorded.";
const RETENTION = "Records are deleted about 30 days after they were recorded.";
const WEB_OFF_EMPTY_BODY = "Web access is off, so nothing new is recorded. Records are deleted about 30 days after they were recorded.";
const RECORDING_OFF_BODY = "Nothing is listed because recording hasn't started, not because agents made no requests. When it starts, the sites agents contact appear here.";

// Wording bans (spec FR4 + CTO ruling 3): the copy describes only what is measured.
const BANNED = /\bexactly\b|\bcomplete\b|\bguarantee|\bwe block\b|\bprevent|\bprotect|every connection|tamper-proof|\bsessions\b/i;

type Cell = { name: string; result: EgressAuditResult; filter: Filter };
// The state ladder (Guard 2): every branch of the view that renders window-scoped or retention copy.
const LADDER: Cell[] = [
  { name: "forbidden", result: { kind: "forbidden" }, filter: "all" },
  { name: "unbound", result: { kind: "unbound" }, filter: "all" },
  { name: "unavailable", result: { kind: "unavailable" }, filter: "all" },
  { name: "ready with rows", result: ready(payload()), filter: "all" },
  { name: "ready with rows, filtered", result: ready(payload()), filter: "blocked" },
  { name: "ready with truncation", result: ready(payload({ truncated: true })), filter: "all" },
  { name: "ready with truncation, filtered", result: ready(payload({ truncated: true })), filter: "blocked" },
  { name: "ready filter-empty", result: ready(empty({ summary: SOME })), filter: "blocked" },
  { name: "ready web-off with rows", result: ready(payload(), { webAccess: false }), filter: "all" },
  { name: "ready web-off empty", result: ready(empty(), { webAccess: false }), filter: "all" },
  { name: "ready collection-off", result: ready(empty(), { collection: false }), filter: "all" },
  { name: "ready collection-unknown", result: ready(empty(), { collection: "unknown" }), filter: "all" },
  { name: "ready web-access-unknown", result: ready(empty(), { webAccess: null }), filter: "all" },
  { name: "ready recording-on empty (shorter-window empty at 24h/7d, 30-day empty at 30d)", result: ready(empty()), filter: "all" },
  { name: "ready recording-on empty, filtered", result: ready(empty()), filter: "blocked" },
];

// The single chokepoint of the sweep: renders every cell of ladder x windows and hands back the rendered text.
function renderSweep(workspaceName: string | null = "Acme"): { name: string; timeWindow: TimeWindow; text: string; root: HTMLElement }[] {
  const out: { name: string; timeWindow: TimeWindow; text: string; root: HTMLElement }[] = [];
  for (const timeWindow of TIME_WINDOWS) {
    for (const cell of LADDER) {
      const result = cell.result.kind === "ready" ? { ...cell.result, workspaceName } : cell.result;
      const { container, unmount } = show(result, cell.filter, timeWindow);
      out.push({ name: cell.name, timeWindow, text: container.textContent ?? "", root: container.cloneNode(true) as HTMLElement });
      unmount();
    }
  }
  return out;
}

// What a stray "30" scan sees: the rendered text without the selector's own chip, the "Show 30 days" link and
// the allowlisted retention sentence (closed list of exact sentences). The workspace name is not content.
function strayScanText(root: HTMLElement, workspaceName: string | null, allowlist: readonly string[] = [RETENTION]): string {
  for (const el of Array.from(root.querySelectorAll('nav[aria-label="Time window"]'))) el.remove();
  for (const a of Array.from(root.querySelectorAll("a"))) if (a.textContent === "Show 30 days") a.remove();
  // attribute text is user-visible too (screen readers, tooltips): aria-label, title and alt are scanned with the text
  const attrs = Array.from(root.querySelectorAll("[aria-label],[title],[alt]")).flatMap((el) =>
    ["aria-label", "title", "alt"].map((a) => el.getAttribute(a) ?? ""),
  );
  let text = [root.textContent ?? "", ...attrs].join(" ");
  for (const sentence of allowlist) text = text.split(sentence).join("");
  if (workspaceName) text = text.split(workspaceName).join("");
  return text;
}

describe("EgressAuditView — window selector", () => {
  it("renders a labelled nav of three link chips in order, aria-current on the selected one, before the outcome chips", () => {
    show(ready(payload()), "all", "7d");
    const nav = screen.getByRole("navigation", WINDOW_NAV);
    const chips = within(nav).getAllByRole("link");
    expect(chips.map((c) => c.textContent)).toEqual(["24 hours", "7 days", "30 days"]);
    expect(chips.filter((c) => c.getAttribute("aria-current") === "page").map((c) => c.textContent)).toEqual(["7 days"]);
    expect(screen.getByText("Time window", { selector: "span, p, div, label" })).toBeTruthy();
    const outcomeNav = screen.getByRole("navigation", { name: "Filter by outcome" });
    // Window group first in document order (same row on desktop, stacked above on mobile).
    expect(nav.compareDocumentPosition(outcomeNav) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("the 30-day view marks the 30 days chip current (the prop is required: the page always passes the parsed window)", () => {
    show(ready(payload()));
    const chips = within(screen.getByRole("navigation", WINDOW_NAV)).getAllByRole("link");
    expect(chips.filter((c) => c.getAttribute("aria-current") === "page").map((c) => c.textContent)).toEqual(["30 days"]);
  });

  it.each(SHORTER)("%s: a decision filter on a window with no rows stays clearable (outcome chips render, 'All' links back)", (w) => {
    show(ready(empty()), "blocked", w);
    const outcome = screen.getByRole("navigation", { name: "Filter by outcome" });
    const all = within(outcome).getByRole("link", { name: "All" });
    expect(all.getAttribute("href")).toBe(`${BASE}?window=${w}`);
  });

  it("window chips carry the current decision; canonical URLs omit the defaults and order decision before window", () => {
    show(ready(payload()), "all", "30d");
    let chips = within(screen.getByRole("navigation", WINDOW_NAV)).getAllByRole("link");
    expect(chips.map((c) => c.getAttribute("href"))).toEqual([`${BASE}?window=24h`, `${BASE}?window=7d`, BASE]);
    cleanup();
    show(ready(payload()), "blocked", "30d");
    chips = within(screen.getByRole("navigation", WINDOW_NAV)).getAllByRole("link");
    expect(chips.map((c) => c.getAttribute("href"))).toEqual([`${BASE}?decision=blocked&window=24h`, `${BASE}?decision=blocked&window=7d`, `${BASE}?decision=blocked`]);
  });

  it("outcome chips carry the current window", () => {
    show(ready(payload()), "blocked", "7d");
    const chips = within(screen.getByRole("navigation", { name: "Filter by outcome" })).getAllByRole("link");
    expect(chips.map((c) => c.getAttribute("href"))).toEqual([
      `${BASE}?window=7d`,
      `${BASE}?decision=allowed&window=7d`,
      `${BASE}?decision=blocked&window=7d`,
      `${BASE}?decision=other&window=7d`,
    ]);
    cleanup();
    show(ready(payload()), "allowed", "30d");
    const chips30 = within(screen.getByRole("navigation", { name: "Filter by outcome" })).getAllByRole("link");
    expect(chips30.map((c) => c.getAttribute("href"))).toEqual([BASE, `${BASE}?decision=allowed`, `${BASE}?decision=blocked`, `${BASE}?decision=other`]);
  });

  it("a window chip is a real link element handled by NavLink (no native button, no bare onClick navigation)", () => {
    show(ready(payload()), "all", "24h");
    const nav = screen.getByRole("navigation", WINDOW_NAV);
    expect(nav.querySelectorAll("button")).toHaveLength(0);
    for (const a of Array.from(nav.querySelectorAll("a"))) expect(a.getAttribute("href")).toMatch(/^\/dashboard\/settings\/scope-grants\/egress-audit/);
  });

  it.each([
    ["populated", ready(payload()), "all"],
    ["truncated", ready(payload({ truncated: true })), "all"],
    ["filter-empty", ready(empty({ summary: SOME })), "blocked"],
    ["web off with rows", ready(payload(), { webAccess: false }), "all"],
    ["web off, empty", ready(empty(), { webAccess: false }), "all"],
    ["recording on, empty", ready(empty()), "all"],
  ] as [string, EgressAuditResult, Filter][])("the window group is present in the %s state under every window", (_n, result, filter) => {
    for (const w of TIME_WINDOWS) {
      const { unmount } = show(result, filter, w);
      expect([w, screen.queryByRole("navigation", WINDOW_NAV) !== null]).toEqual([w, true]);
      unmount();
    }
  });

  it.each([
    ["forbidden", { kind: "forbidden" } as EgressAuditResult],
    ["unbound", { kind: "unbound" } as EgressAuditResult],
    ["unavailable", { kind: "unavailable" } as EgressAuditResult],
    ["collection off", ready(empty(), { collection: false })],
    ["collection unknown", ready(empty(), { collection: "unknown" })],
    ["web access unknown", ready(empty(), { webAccess: null })],
  ])("the window group is absent where there is no data to scope: %s", (_n, result) => {
    for (const w of TIME_WINDOWS) {
      const { unmount } = show(result, "all", w);
      expect([w, screen.queryByRole("navigation", WINDOW_NAV)]).toEqual([w, null]);
      unmount();
    }
  });
});

describe("EgressAuditView — window-aware strings", () => {
  it.each(TIME_WINDOWS)("%s: subtitle, table caption and truncation body say 'about the last N' / 'this window'", (w) => {
    const n = WINDOW_LABEL[w];
    show(ready(payload({ truncated: true })), "all", w);
    expect(screen.getByText(`Sites Acme's agents contacted in about the last ${n}, with the outcome of each (best-effort).`)).toBeTruthy();
    expect(screen.getByRole("table", { name: `Hosts your workspace's agents contacted in about the last ${n}, with outcome and a minimum request count` })).toBeTruthy();
    expect(screen.getByText("Older entries in this window are not listed, and counts are minimums.")).toBeTruthy();
  });

  it.each(TIME_WINDOWS)("%s: the unnamed-workspace subtitle is window-aware too", (w) => {
    show(ready(payload(), { workspaceName: null }), "all", w);
    expect(screen.getByText(`Sites your workspace's agents contacted in about the last ${WINDOW_LABEL[w]}, with the outcome of each (best-effort).`)).toBeTruthy();
  });

  it.each(TIME_WINDOWS)("%s: the filter-empty line says 'recorded' and names the window, and 'Show all' keeps the window", (w) => {
    show(ready(empty({ summary: SOME })), "blocked", w);
    expect(screen.getByText(`No Blocked requests recorded in about the last ${WINDOW_LABEL[w]}.`)).toBeTruthy();
    const showAll = screen.getByRole("link", { name: "Show all" });
    expect(showAll.getAttribute("href")).toBe(w === "30d" ? BASE : `${BASE}?window=${w}`);
  });

  it.each(TIME_WINDOWS)("%s: web access off with no rows says 'Nothing recorded in about the last N' with the unchanged body", (w) => {
    show(ready(empty(), { webAccess: false }), "all", w);
    expect(screen.getByText(`Nothing recorded in about the last ${WINDOW_LABEL[w]}`)).toBeTruthy();
    expect(screen.getByText(WEB_OFF_EMPTY_BODY)).toBeTruthy();
  });

  it.each(SHORTER)("%s: recording on, web access on, no rows is the shorter-window empty state with Refresh and 'Show 30 days'", (w) => {
    show(ready(empty()), "all", w);
    expect(screen.getByText(`No requests recorded in about the last ${WINDOW_LABEL[w]}`)).toBeTruthy();
    expect(
      screen.getByText(
        "Nothing was recorded in this window. This list is best-effort, so this does not show that no requests were made. Requests can take some time to appear. A longer window may show more.",
      ),
    ).toBeTruthy();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "Show 30 days" }).getAttribute("href")).toBe(BASE);
    expect(screen.queryByText("No requests recorded yet")).toBeNull();
    // The banner stays above the empty state; the outcome chips are hidden; the window group stays.
    expect(screen.getByText(BANNER_LEAD)).toBeTruthy();
    expect(screen.queryByRole("navigation", { name: "Filter by outcome" })).toBeNull();
    expect(screen.getByRole("navigation", WINDOW_NAV)).toBeTruthy();
  });

  it("'Show 30 days' drops only the window (keeps an active decision filter)", () => {
    show(ready(empty()), "blocked", "24h");
    expect(screen.getByRole("link", { name: "Show 30 days" }).getAttribute("href")).toBe(`${BASE}?decision=blocked`);
  });

  it("the 30-day empty state is unchanged and has no 'Show 30 days' dead end", () => {
    show(ready(empty()), "all", "30d");
    expect(screen.getByText("No requests recorded yet")).toBeTruthy();
    expect(screen.getByText("Nothing has been recorded yet. Requests can take a few minutes to appear.")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeTruthy();
    expect(screen.queryByRole("link", { name: "Show 30 days" })).toBeNull();
  });
});

describe("EgressAuditView — sentences that must not move with the window", () => {
  it.each(TIME_WINDOWS)("%s: the banner, retention notices, recording-off card, summary line and footer are byte-identical", (w) => {
    const populated = show(ready(payload(), { webAccess: false }), "all", w);
    expect(screen.getByText(BANNER_LEAD)).toBeTruthy();
    expect(screen.getByText(BANNER_BODY, { selector: "span" }).textContent).toBe(BANNER_BODY);
    expect(screen.getByText("Web access is off. Nothing new is recorded.")).toBeTruthy();
    expect(screen.getByText(RETENTION, { selector: "span" })).toBeTruthy();
    expect(screen.getByText("At least 14,326 requests · at least 121 blocked")).toBeTruthy();
    expect(screen.getByText(/History can't be deleted from this page/).textContent).toBe("History can't be deleted from this page. How to request erasure");
    populated.unmount();

    const off = show(ready(empty(), { collection: false }), "all", w);
    expect(screen.getByText("Recording isn't on for this workspace.")).toBeTruthy();
    expect(screen.getByText(RECORDING_OFF_BODY)).toBeTruthy();
    off.unmount();

    const webOff = show(ready(empty(), { webAccess: false }), "all", w);
    expect(screen.getByText(WEB_OFF_EMPTY_BODY)).toBeTruthy();
    expect(screen.getByText(BANNER_BODY, { selector: "span" }).textContent).toBe(BANNER_BODY);
    webOff.unmount();

    show(ready(payload()), "blocked", w);
    expect(screen.getByText("At least 14,326 requests · at least 121 blocked (all outcomes)")).toBeTruthy();
  });

  it.each(TIME_WINDOWS)("%s: the unavailable, forbidden and unbound cards are unchanged and carry no window group", (w) => {
    for (const result of [{ kind: "unavailable" }, { kind: "forbidden" }, { kind: "unbound" }] as EgressAuditResult[]) {
      const { unmount } = show(result, "all", w);
      expect([w, result.kind, screen.queryByRole("navigation", WINDOW_NAV)]).toEqual([w, result.kind, null]);
      unmount();
    }
    show({ kind: "unavailable" }, "all", w);
    expect(screen.getByText("Couldn't load the egress audit log.")).toBeTruthy();
    expect(screen.getByText(BANNER_BODY, { selector: "span" }).textContent).toBe(BANNER_BODY);
  });

  it("the banner renders above every window state, including the shorter-window empty state", () => {
    for (const w of TIME_WINDOWS) {
      for (const result of [ready(payload()), ready(empty()), ready(empty(), { webAccess: false }), ready(empty({ summary: SOME }))]) {
        const { unmount } = show(result, result.kind === "ready" && result.data.rows.length === 0 && result.data.summary.request_count_min ? "blocked" : "all", w);
        expect([w, screen.queryByText(BANNER_LEAD) !== null]).toEqual([w, true]);
        unmount();
      }
    }
  });

  it("no finer last-seen precision: no <time>, no ISO stamp, under any window", () => {
    for (const w of TIME_WINDOWS) {
      const { unmount } = show(ready(payload()), "all", w);
      expect(document.querySelector("time")).toBeNull();
      expect(document.body.innerHTML).not.toMatch(ISO_STAMP);
      unmount();
    }
  });
});

describe("Guard 2 — no stale 30-day copy; wording bans (state ladder x windows)", () => {
  it("the sweep covers the whole cross product (a dropped window or state fails here, not silently)", () => {
    const cells = renderSweep();
    // exact, not a floor: dropping a state must be a deliberate edit of this number (a floor tolerates silent drops)
    expect(LADDER.length).toBe(15);
    expect(cells).toHaveLength(TIME_WINDOWS.length * LADDER.length);
    expect(new Set(cells.map((c) => c.timeWindow))).toEqual(new Set(["24h", "7d", "30d"]));
  });

  it("24h and 7d render no '30' outside the allowlisted retention sentence, the 30-day chip and the 'Show 30 days' link", () => {
    const cells = renderSweep().filter((c) => c.timeWindow !== "30d");
    expect(cells).toHaveLength(SHORTER.length * LADDER.length);
    for (const c of cells) {
      const scanned = strayScanText(c.root, "Acme");
      expect([c.timeWindow, c.name, scanned.match(/30/g)?.length ?? 0]).toEqual([c.timeWindow, c.name, 0]);
    }
  });

  it("the sweep is load-bearing: with the retention allowlist emptied it goes RED on the legitimate retention sentences", () => {
    const withRetention = renderSweep().filter((c) => c.timeWindow === "24h" && /^ready (?:with rows|web-off empty)/.test(c.name));
    expect(withRetention.length).toBeGreaterThan(0);
    for (const c of withRetention) expect(strayScanText(c.root, "Acme", []).includes("30")).toBe(true);
  });

  it("a workspace name containing the digits 30 does not trip the scan", () => {
    const cells = renderSweep("Acme30").filter((c) => c.timeWindow !== "30d");
    for (const c of cells) expect([c.timeWindow, c.name, strayScanText(c.root, "Acme30").includes("30")]).toEqual([c.timeWindow, c.name, false]);
  });

  it("the window phrase appears in the windowed strings of the 24h and 7d cells (a hard-coded window cannot hide)", () => {
    for (const c of renderSweep().filter((x) => x.timeWindow !== "30d" && x.name === "ready with truncation")) {
      expect(c.text).toContain(`about the last ${WINDOW_LABEL[c.timeWindow]}`);
      expect(c.text).not.toContain("about the last 30 days");
    }
  });

  it("no state x window renders a banned word, a completeness claim or a calendar date in a retention sentence", () => {
    for (const c of renderSweep()) {
      const where = `${c.timeWindow} / ${c.name}`;
      expect([where, BANNED.test(c.text)]).toEqual([where, false]);
      // a wrong-window sentence need not contain the digits 30
      expect([where, /\b(last|past) month\b|\b4 weeks\b/i.test(c.text)]).toEqual([where, false]);
      expect([where, COMPLETENESS_CLAIM.test(c.text)]).toEqual([where, false]);
      expect([where, FORBIDDEN.test(c.text)]).toEqual([where, false]);
      expect([where, c.root.querySelector("time")]).toEqual([where, null]);
      expect([where, ISO_STAMP.test(c.root.innerHTML)]).toEqual([where, false]);
    }
  });
});
