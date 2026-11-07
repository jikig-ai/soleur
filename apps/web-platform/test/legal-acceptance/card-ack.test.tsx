/**
 * #12344 / #12197: the card for the REAL committed key `founder-acceptance-record` (a text of kind acknowledgement).
 *   - nothing a founder can see presumes terms: the DOM (document.body, so the portalled dialog is included) has zero matches for
 *     /terms|accepted|accept the|updated/ in every card state and both dialog steps, with no negation stripping and no allowlist.
 *     The committed text itself is excluded from the scan: it is the thing being acknowledged, not the card's wording;
 *   - the retention notice, the finality clause and the exact-text region are all shown before the Yes button (CPO C2);
 *   - a key with no declared kind renders nothing.
 * The terms variant is exercised by card.test.tsx with a mocked declaration; this file uses the real map.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LegalAcceptanceCard, type LegalAcceptanceCardProps, type LegalRowFacts } from "@/components/approvals/legal-acceptance-card";
import { LEGAL_COPY, LEGAL_KIND_COPY, legalDisplayLabel } from "@/lib/legal-acceptance-copy";
import { getLegalText } from "@/server/legal-acceptance/canonical";
import type { LegalChoiceWire } from "@/lib/legal-acceptance-wire";

const KEY = "founder-acceptance-record";
const entry = getLegalText(KEY);
const KC = LEGAL_KIND_COPY.acknowledgement;
const TERMS_PRESUMING = /\bterms?\b|\baccept(ed|s|ance)?\b|accept the|\bupdated\b/i;

const props = (over: Partial<LegalAcceptanceCardProps> = {}): LegalAcceptanceCardProps => ({
  keyName: KEY,
  label: legalDisplayLabel("acknowledgement", KEY, entry.body),
  version: entry.version,
  body: entry.body,
  textHash: entry.textHash,
  validUntil: null,
  state: "pending",
  row: null,
  flagEnabled: true,
  email: "dana@example.com",
  currentVersion: entry.version,
  ...over,
});

const row = (choice: LegalChoiceWire, extra: Partial<LegalRowFacts> = {}): LegalRowFacts => ({
  choice,
  version: entry.version,
  decidedAt: "2026-11-04T10:42:00Z",
  reauthAt: null,
  requestedEdit: null,
  ...extra,
});

let layout = { scrollHeight: 0, clientHeight: 0 };
beforeEach(() => {
  layout = { scrollHeight: 0, clientHeight: 0 };
  Object.defineProperty(HTMLElement.prototype, "scrollHeight", { configurable: true, get: () => layout.scrollHeight });
  Object.defineProperty(HTMLElement.prototype, "clientHeight", { configurable: true, get: () => layout.clientHeight });
});
afterEach(() => {
  delete (HTMLElement.prototype as unknown as Record<string, unknown>).scrollHeight;
  delete (HTMLElement.prototype as unknown as Record<string, unknown>).clientHeight;
  cleanup();
  vi.unstubAllGlobals();
});

/** The visible words of the whole document without the committed text itself (the dialog is portalled, so document.body, not the render container). */
const cardWords = (): string => document.body.textContent.split(entry.body).join(" ");

describe("the real acknowledgement text: the DOM presumes no terms", () => {
  it("the scan is not vacuous: the committed text does contain a banned word (it says it does not accept any other text), so it must be excluded and the rest still scanned", () => {
    expect(TERMS_PRESUMING.test(entry.body)).toBe(true);
    render(<LegalAcceptanceCard {...props()} />);
    expect(document.body.textContent).toMatch(TERMS_PRESUMING);
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
    expect(cardWords().length).toBeGreaterThan(500);
  });

  it("pending, flag on: title, rows, notices, choices and the locked or open lines", async () => {
    render(<LegalAcceptanceCard {...props()} />);
    expect(screen.getByRole("heading", { name: KC.pendingTitle("How your decisions are recorded and kept") })).toBeInTheDocument();
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
    // the Request changes box and the decline confirm are part of the pending card too
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: /^Request changes/ }));
    expect(screen.getByText(LEGAL_COPY.requestChangesNotice)).toBeInTheDocument();
    expect(screen.getByText(KC.changesFooter)).toBeInTheDocument();
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
    await user.click(screen.getByRole("button", { name: /^No/ }));
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
  });

  it("pending, flag off: the not-available line", () => {
    render(<LegalAcceptanceCard {...props({ flagEnabled: false })} />);
    expect(screen.getByText(KC.pendingNotAvailable)).toBeInTheDocument();
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
  });

  it.each([
    ["accepted", "accept", { reauthAt: "2026-11-04T10:42:00Z" }],
    ["declined", "decline", {}],
    ["changes_requested", "request_changes", { requestedEdit: "Shorter, please." }],
    ["expired", "accept", {}],
    ["replaced", "accept", { version: "2026-01-01" }],
  ] as const)("resolved state %s", (state, choice, extra) => {
    render(<LegalAcceptanceCard {...props({ state, row: state === "expired" ? null : row(choice, extra), body: state === "replaced" ? "" : entry.body, currentVersion: state === "replaced" ? entry.version : entry.version })} />);
    expect(screen.getByTestId("legal-card")).toHaveAttribute("data-state", state);
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
  });

  it("the accepted state says acknowledged, quotes the title and says it is not consent", () => {
    render(<LegalAcceptanceCard {...props({ state: "accepted", row: row("accept", { reauthAt: "2026-11-04T10:42:00Z" }) })} />);
    expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: 'You acknowledged "How your decisions are recorded and kept"' })).toBeInTheDocument();
    expect(screen.getByText(KC.acceptedBody)).toBeInTheDocument();
  });

  it("both dialog steps (the dialog is portalled): start, then the code step", async () => {
    layout = { scrollHeight: 100, clientHeight: 200 }; // the whole text fits, so Yes unlocks at once
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ ok: true, status: 200, json: async () => ({ ok: true, state: "sent" }) })),
    );
    const user = userEvent.setup();
    render(<LegalAcceptanceCard {...props()} />);
    await user.click(screen.getByRole("button", { name: /^Yes/ }));
    expect(await screen.findByRole("dialog")).toBeInTheDocument();
    expect(document.body.textContent).toContain(KC.answerDetail("How your decisions are recorded and kept", entry.version));
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByLabelText(LEGAL_COPY.dialog.codeLabel);
    expect(document.body.textContent).toContain(LEGAL_COPY.dialog.codeBody);
    expect(cardWords()).not.toMatch(TERMS_PRESUMING);
  });
});

describe("the real acknowledgement text: what the founder reads before the Yes button", () => {
  it("the exact-text region, the retention notice and the finality clause all come before the Yes button", () => {
    render(<LegalAcceptanceCard {...props()} />);
    const yes = screen.getByRole("button", { name: /^Yes/ });
    const before = (el: Element): boolean => Boolean(el.compareDocumentPosition(yes) & Node.DOCUMENT_POSITION_FOLLOWING);
    expect(before(screen.getByRole("region", { name: LEGAL_COPY.exactTextHeading }))).toBe(true);
    expect(before(screen.getByText(LEGAL_COPY.cardNotice))).toBe(true);
    expect(before(screen.getByText(KC.noBody))).toBe(true);
    expect(KC.noBody).toContain("Final once recorded.");
    expect(KC.changesBody).toContain("Final once recorded.");
    expect(LEGAL_COPY.cardNotice).toContain("5 years from the date of the decision");
    expect(screen.getByText(LEGAL_COPY.finalNote)).toBeInTheDocument();
  });

  it("the Yes row says it is an acknowledgement, not consent", () => {
    render(<LegalAcceptanceCard {...props()} />);
    expect(screen.getByText(KC.yesBody)).toBeInTheDocument();
  });
});

describe("a key with no declared card kind renders nothing (no default)", () => {
  it("an unknown key, and the object-prototype names, render an empty card", () => {
    for (const keyName of ["customer-terms", "unknown-text", "constructor", "toString"]) {
      const { container, unmount } = render(<LegalAcceptanceCard {...props({ keyName })} />);
      expect(container.textContent, keyName).toBe("");
      expect(screen.queryByTestId("legal-card"), keyName).toBeNull();
      unmount();
    }
  });
});
