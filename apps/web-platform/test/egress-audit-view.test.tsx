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
import type { EgressAuditResult } from "@/server/egress-audit-read";
import type { EgressAuditPayload } from "@/lib/egress-audit/summary";

const NOW = Date.parse("2026-10-26T12:10:00Z");
const BASE = "/dashboard/settings/scope-grants/egress-audit";

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

  it("shows the best-effort banner with pre-join visibility, and the footer states history cannot be deleted from here", () => {
    show(ready(payload()));
    expect(screen.getByText("A best-effort summary, not a full record.")).toBeTruthy();
    expect(screen.getByText(/including activity from before they joined/)).toBeTruthy();
    expect(screen.getByText(/History can't be deleted from this page/)).toBeTruthy();
    const link = screen.getByRole("link", { name: "How to request erasure" });
    expect(link.getAttribute("href")).toContain("privacy-policy.html#data-subject-rights");
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
    expect(screen.getByText("Showing the 200 most recent Blocked entries.")).toBeTruthy();
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

  it("unbound says the workspace could not be determined", () => {
    show({ kind: "unbound" });
    expect(screen.getByText("We couldn't determine your workspace.")).toBeTruthy();
    expect(screen.queryByRole("row")).toBeNull();
  });
});

describe("EgressAuditView — copy rules", () => {
  it("no state renders a forbidden word or a calendar date in a retention sentence", () => {
    const states: EgressAuditResult[] = [
      ready(payload()),
      ready(payload({ truncated: true }), { webAccess: false }),
      ready(empty()),
      ready(empty(), { webAccess: false }),
      ready(empty(), { collection: false }),
      { kind: "unavailable" },
      { kind: "forbidden" },
      { kind: "unbound" },
    ];
    for (const s of states) {
      const { unmount } = show(s);
      const text = document.body.textContent ?? "";
      expect(text).not.toMatch(/\bcomplete\b|every connection|tamper-proof|\bsessions\b/i);
      expect(text).not.toMatch(/(?:until|since|on)\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d/);
      unmount();
    }
  });
});
