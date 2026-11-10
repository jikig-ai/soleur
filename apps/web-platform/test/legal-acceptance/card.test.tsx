/**
 * #12011 PR-C task B1 (AC9, AC11, AC14): the founder legal-acceptance card and its in-place email check.
 * The card is a client component fed plain props by the page; every network call is a mocked fetch.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { LegalAcceptanceCard, type LegalAcceptanceCardProps, type LegalRowFacts } from "@/components/approvals/legal-acceptance-card";
import { LEGAL_COPY, LEGAL_KIND_COPY } from "@/lib/legal-acceptance-copy";
import { FORBIDDEN_CLAIMS } from "./forbidden-claims";
import { OTP_RESEND_COOLDOWN_MS } from "@/lib/auth/constants";
import type { LegalChoiceWire, LegalDecideResult, LegalReauthSendResult, LegalReauthVerifyResult } from "@/lib/legal-acceptance-wire";

// `customer-terms` and `other-terms` are not in the real LEGAL_TEXT_KIND (only the committed text is), so the kind lookup the card
// uses reads a per-test map. Each describe sets what it needs; no fixture key is registered on the real (Readonly) map.
const k = vi.hoisted(() => ({ declared: {} as Record<string, "terms" | "acknowledgement"> }));
vi.mock("@/lib/legal-acceptance-copy", async (orig) => {
  const real = await orig<typeof import("@/lib/legal-acceptance-copy")>();
  return { ...real, legalKindCopy: (key: string) => real.legalKindCopy(key, k.declared), legalTextKind: (key: string) => real.legalTextKind(key, k.declared) };
});
/** The terms wording: today's strings, moved into the kind map. */
const KC = LEGAL_KIND_COPY.terms;

const HASH = "c".repeat(64);
const BODY = "CUSTOMER TERMS\n\n1. Who these terms are between.\n\n2. What we provide.\n\nEnd of version 3.\n";

const baseProps: LegalAcceptanceCardProps = {
  keyName: "customer-terms",
  label: "Customer terms",
  version: "3",
  body: BODY,
  textHash: HASH,
  validUntil: "2026-11-14",
  state: "pending",
  row: null,
  flagEnabled: true,
  email: "dana@example.com",
  currentVersion: "3",
};

function renderCard(over: Partial<LegalAcceptanceCardProps> = {}) {
  return render(<LegalAcceptanceCard {...baseProps} {...over} />);
}

// ---- layout stubs: happy-dom has no layout, so the text viewport is faked ---------------------------------------------
let layout = { scrollHeight: 0, clientHeight: 0 };
beforeEach(() => {
  k.declared = { "customer-terms": "terms", "other-terms": "terms" };
  layout = { scrollHeight: 0, clientHeight: 0 };
  Object.defineProperty(HTMLElement.prototype, "scrollHeight", { configurable: true, get: () => layout.scrollHeight });
  Object.defineProperty(HTMLElement.prototype, "clientHeight", { configurable: true, get: () => layout.clientHeight });
});
afterEach(() => {
  delete (HTMLElement.prototype as unknown as Record<string, unknown>).scrollHeight;
  delete (HTMLElement.prototype as unknown as Record<string, unknown>).clientHeight;
  cleanup();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});
const longText = () => (layout = { scrollHeight: 1000, clientHeight: 200 });

function scrollToEnd() {
  const region = screen.getByRole("region", { name: new RegExp(LEGAL_COPY.exactTextHeading, "i") });
  region.scrollTop = 800;
  fireEvent.scroll(region);
}

// ---- fetch mock --------------------------------------------------------------------------------------------------------
type Reply = { status?: number; body: unknown } | "throw";
interface Routes {
  send?: Reply | (() => Reply);
  verify?: Reply | (() => Reply);
  decide?: Reply | (() => Reply);
}
function mockFetch(routes: Routes) {
  const calls: { url: string; init: RequestInit; body: Record<string, unknown> }[] = [];
  const fn = vi.fn(async (url: string, init: RequestInit) => {
    const body = JSON.parse(String(init.body ?? "{}")) as Record<string, unknown>;
    calls.push({ url, init, body });
    let reply: Routes[keyof Routes];
    if (url.endsWith("/reauth")) reply = body.step === "send" ? routes.send : routes.verify;
    else if (url.endsWith("/decide")) reply = routes.decide;
    const r = typeof reply === "function" ? reply() : reply;
    if (!r) throw new Error(`unexpected fetch ${url}`);
    if (r === "throw") throw new TypeError("network");
    const status = r.status ?? 200;
    return { ok: status >= 200 && status < 300, status, json: async () => r.body };
  });
  vi.stubGlobal("fetch", fn);
  return { calls, fn, decides: () => calls.filter((c) => c.url.endsWith("/decide")), reauths: () => calls.filter((c) => c.url.endsWith("/reauth")) };
}
const SENT: LegalReauthSendResult = { ok: true, state: "sent" };
const VERIFIED: LegalReauthVerifyResult = { ok: true };
const RECORDED_YES: LegalDecideResult = { outcome: "recorded", choice: "accept", decidedAt: "2026-11-04T10:42:00Z", reauthAt: "2026-11-04T10:42:00Z" };

const yesButton = () => screen.getByRole("button", { name: /^Yes/ });
const noButton = () => screen.getByRole("button", { name: /^No/ });
const changesButton = () => screen.getByRole("button", { name: /^Request changes/ });

async function openDialogAndSendCode(user: ReturnType<typeof userEvent.setup>) {
  await user.click(yesButton());
  await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
  await screen.findByLabelText(LEGAL_COPY.dialog.codeLabel);
}
async function enterCode(user: ReturnType<typeof userEvent.setup>, code = "481902") {
  await user.type(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel), code);
}

// =====================================================================================================================
describe("the six card states (AC14, wireframe 16)", () => {
  const row = (choice: LegalChoiceWire, extra: Partial<LegalRowFacts> = {}): LegalRowFacts => ({
    choice,
    version: "3",
    decidedAt: "2026-11-04T10:42:00Z",
    reauthAt: null,
    requestedEdit: null,
    ...extra,
  });

  it("pending: needs your answer, open until the valid-until date, nothing accepted", () => {
    renderCard();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: KC.pendingTitle("Customer terms") })).toBeInTheDocument();
    expect(screen.getByText(KC.pendingNothing)).toBeInTheDocument();
    expect(screen.getByText(LEGAL_COPY.pending.openUntil("2026-11-14"))).toBeInTheDocument();
  });

  it("exposes the declared kind and the key on the article for agent-browser parity (the terms kind here; card-ack.test.tsx pins the acknowledgement kind)", () => {
    renderCard();
    const card = screen.getByTestId("legal-card");
    expect(card).toHaveAttribute("data-kind", "terms");
    expect(card).toHaveAttribute("data-key", "customer-terms");
  });

  it("accepted: says how the answer was given, with the UTC time of the email code", () => {
    renderCard({ state: "accepted", row: row("accept", { reauthAt: "2026-11-04T10:42:00Z" }) });
    expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument();
    expect(screen.getByText("Confirmed with an email code, Wed 4 Nov 2026, 10:42 UTC")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^Yes/ })).toBeNull();
  });

  it("declined: signed in with your account, final, a new version is the way to change it, no undo", () => {
    renderCard({ state: "declined", row: row("decline") });
    expect(screen.getByText(LEGAL_COPY.declined.badge)).toBeInTheDocument();
    expect(screen.getByText(LEGAL_COPY.signedInLine)).toBeInTheDocument();
    expect(screen.getByText(KC.declinedBody)).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("changes requested: shows the note and that nothing is accepted, no undo", () => {
    renderCard({ state: "changes_requested", row: row("request_changes", { requestedEdit: "Please shorten section 5." }) });
    expect(screen.getByText(LEGAL_COPY.changesRequested.badge)).toBeInTheDocument();
    expect(screen.getByText("Please shorten section 5.")).toBeInTheDocument();
    expect(screen.getByText(LEGAL_COPY.signedInLine)).toBeInTheDocument();
    expect(screen.getByText(KC.changesRequestedBody)).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("replaced: the earlier answer stays as given and the new version needs its own answer", () => {
    renderCard({ state: "replaced", version: "3", currentVersion: "4", row: row("request_changes") });
    expect(screen.getByText(LEGAL_COPY.replaced.badge)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: LEGAL_COPY.replaced.title("3", "4") })).toBeInTheDocument();
    expect(screen.getByText(LEGAL_COPY.replaced.earlierAnswer("request_changes"))).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("expired: nobody answered in time, nothing accepted", () => {
    renderCard({ state: "expired", validUntil: "2026-11-01" });
    expect(screen.getByText(LEGAL_COPY.expired.badge)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: LEGAL_COPY.expired.title })).toBeInTheDocument();
    expect(screen.getByText(KC.expiredBody)).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("no state says verified, reviewed, legally binding, audit-ready or compliant", () => {
    for (const [state, r] of [
      ["pending", null],
      ["accepted", row("accept", { reauthAt: "2026-11-04T10:42:00Z" })],
      ["declined", row("decline")],
      ["changes_requested", row("request_changes", { requestedEdit: "x" })],
      ["replaced", row("accept")],
      ["expired", null],
    ] as const) {
      const { container, unmount } = renderCard({ state, row: r });
      expect(container.textContent ?? "").not.toMatch(FORBIDDEN_CLAIMS);
      unmount();
    }
  });
});

// =====================================================================================================================
describe("pending card: the notices and the read-only mode", () => {
  it("shows the (c-2) card-level notice above the choices, word for word", () => {
    renderCard();
    const notice = screen.getByText(LEGAL_COPY.cardNotice);
    expect(notice).toBeInTheDocument();
    expect(notice.compareDocumentPosition(yesButton()) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("with the surface off the text still renders but there are no actions and a plain 'not available yet'", () => {
    renderCard({ flagEnabled: false });
    expect(screen.getByText(KC.pendingNotAvailable)).toBeInTheDocument();
    expect(screen.getByText(/End of version 3/)).toBeInTheDocument();
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
  });
});

// =====================================================================================================================
describe("none pre-selected, Enter alone answers nothing (AC9)", () => {
  it("no choice is pressed, expanded or checked, no dialog or text box is open, and nothing was sent", () => {
    const f = mockFetch({});
    renderCard();
    for (const b of [yesButton(), noButton(), changesButton()]) {
      expect(b).not.toHaveAttribute("aria-pressed", "true");
      expect(b).not.toHaveAttribute("aria-expanded", "true");
    }
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.queryByRole("radio", { checked: true })).toBeNull();
    expect(f.fn).not.toHaveBeenCalled();
  });

  it("pressing Enter with nothing focused, and Enter on No, answers nothing (No only asks to confirm)", async () => {
    const f = mockFetch({ decide: { body: { outcome: "recorded", choice: "decline", decidedAt: "2026-11-04T10:42:00Z" } } });
    const user = userEvent.setup();
    renderCard();
    await user.keyboard("{Enter}");
    expect(f.fn).not.toHaveBeenCalled();
    noButton().focus();
    await user.keyboard("{Enter}");
    expect(f.fn).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: LEGAL_COPY.decline.confirm })).toBeInTheDocument();
    expect(screen.queryByText(LEGAL_COPY.declined.badge)).toBeNull();
  });

  it("No records only after the explicit confirm, and says the answer is final", async () => {
    const f = mockFetch({ decide: { body: { outcome: "recorded", choice: "decline", decidedAt: "2026-11-04T10:42:00Z" } } });
    const user = userEvent.setup();
    renderCard();
    await user.click(noButton());
    expect(screen.getByText(LEGAL_COPY.decline.body)).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.decline.confirm }));
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.declined.badge)).toBeInTheDocument());
    expect(f.decides()).toHaveLength(1);
    expect(f.decides()[0].body).toEqual({ choice: "decline", textHash: HASH });
  });
});

// =====================================================================================================================
describe("Yes is locked until the text is confirmed (AC9)", () => {
  it("a text that fits its viewport unlocks Yes immediately, with no checkbox", () => {
    layout = { scrollHeight: 200, clientHeight: 200 };
    renderCard();
    expect(yesButton()).toHaveAttribute("aria-disabled", "false");
    expect(screen.getByText(LEGAL_COPY.scroll.fits)).toBeInTheDocument();
    expect(screen.queryByRole("checkbox")).toBeNull();
    expect(screen.getByRole("status")).toHaveTextContent(LEGAL_COPY.lock.open);
  });

  it("a long text keeps Yes locked, announces why, and a click opens nothing", async () => {
    longText();
    const user = userEvent.setup();
    renderCard();
    expect(yesButton()).toHaveAttribute("aria-disabled", "true");
    const live = screen.getByRole("status");
    expect(live).toHaveAttribute("aria-live", "polite");
    expect(live).toHaveTextContent(LEGAL_COPY.lock.atEnd);
    expect(yesButton().getAttribute("aria-describedby")).toBe(live.id);
    await user.click(yesButton());
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("scrolling to the end is not enough: the box must also be ticked", async () => {
    longText();
    const user = userEvent.setup();
    renderCard();
    const box = screen.getByRole("checkbox", { name: new RegExp(LEGAL_COPY.scroll.checkbox) });
    expect(box).toHaveAttribute("aria-disabled", "true");
    await user.click(box);
    expect(box).not.toBeChecked();
    scrollToEnd();
    await waitFor(() => expect(box).toHaveAttribute("aria-disabled", "false"));
    expect(screen.getByText(LEGAL_COPY.scroll.reached)).toBeInTheDocument();
    expect(yesButton()).toHaveAttribute("aria-disabled", "true");
    expect(screen.getByRole("status")).toHaveTextContent(LEGAL_COPY.lock.needsTick);
    await user.click(box);
    await waitFor(() => expect(yesButton()).toHaveAttribute("aria-disabled", "false"));
    expect(screen.getByRole("status")).toHaveTextContent(LEGAL_COPY.lock.open);
  });

  it("ticking without having scrolled to the end does nothing (keyboard or pointer)", async () => {
    longText();
    const user = userEvent.setup();
    renderCard();
    const box = screen.getByRole("checkbox");
    box.focus();
    await user.keyboard(" ");
    expect(box).not.toBeChecked();
    expect(yesButton()).toHaveAttribute("aria-disabled", "true");
  });

  it("the text region is focusable so the keyboard can scroll it", () => {
    longText();
    renderCard();
    expect(screen.getByRole("region", { name: new RegExp(LEGAL_COPY.exactTextHeading, "i") })).toHaveAttribute("tabindex", "0");
  });
});

// =====================================================================================================================
describe("Request changes (AC9)", () => {
  it("opens a text box with the (c) notice visible at once, a counter, and no send until there is text", async () => {
    const user = userEvent.setup();
    renderCard();
    await user.click(changesButton());
    expect(changesButton()).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByText(LEGAL_COPY.requestChangesNotice)).toBeVisible();
    const box = screen.getByRole("textbox", { name: /what should change/i });
    expect(screen.getByText(LEGAL_COPY.changes.counter(0, 1000))).toBeInTheDocument();
    const send = screen.getByRole("button", { name: LEGAL_COPY.changes.send });
    expect(send).toBeDisabled();
    await user.type(box, "   ");
    expect(send).toBeDisabled();
    expect(screen.getByText(LEGAL_COPY.changes.required)).toBeInTheDocument();
  });

  it("stops at 1000 characters", async () => {
    const user = userEvent.setup();
    renderCard();
    await user.click(changesButton());
    const box = screen.getByRole("textbox") as HTMLTextAreaElement;
    await user.click(box);
    await user.paste("x".repeat(1200));
    expect(box.value).toHaveLength(1000);
    expect(screen.getByText(LEGAL_COPY.changes.counter(1000, 1000))).toBeInTheDocument();
  });

  it("counts and truncates the note by character (code point), so an emoji is one character and is never cut in half", async () => {
    const user = userEvent.setup();
    renderCard();
    await user.click(changesButton());
    const box = screen.getByRole("textbox") as HTMLTextAreaElement;
    await user.click(box);
    await user.paste("\u{1F600}".repeat(1200));
    expect(Array.from(box.value)).toHaveLength(1000);
    expect(box.value.endsWith("\u{1F600}")).toBe(true);
    expect(screen.getByText(LEGAL_COPY.changes.counter(1000, 1000))).toBeInTheDocument();
    expect(box.getAttribute("maxlength")).toBeNull();
  });

  it("sends the trimmed note with the shown hash, as JSON, and then reads the server's answer", async () => {
    const f = mockFetch({ decide: { body: { outcome: "recorded", choice: "request_changes", decidedAt: "2026-11-04T10:42:00Z" } } });
    const user = userEvent.setup();
    renderCard();
    await user.click(changesButton());
    await user.type(screen.getByRole("textbox"), "  Please shorten section 5.  ");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.changes.send }));
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.changesRequested.badge)).toBeInTheDocument());
    expect(f.decides()).toHaveLength(1);
    expect(f.decides()[0].url).toBe("/api/legal-acceptance/customer-terms/decide");
    expect(f.decides()[0].init.method).toBe("POST");
    expect(new Headers(f.decides()[0].init.headers).get("content-type")).toBe("application/json");
    expect(f.decides()[0].body).toEqual({ choice: "request_changes", textHash: HASH, note: "Please shorten section 5." });
    expect(screen.getByText("Please shorten section 5.")).toBeInTheDocument();
  });

  it("Cancel closes the box and records nothing", async () => {
    const f = mockFetch({});
    const user = userEvent.setup();
    renderCard();
    await user.click(changesButton());
    await user.type(screen.getByRole("textbox"), "hello");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.changes.cancel }));
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(f.fn).not.toHaveBeenCalled();
  });
});

// =====================================================================================================================
describe("a failed or malformed decide never shows success (AC11)", () => {
  async function sendChanges(user: ReturnType<typeof userEvent.setup>) {
    await user.click(changesButton());
    await user.type(screen.getByRole("textbox"), "note");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.changes.send }));
  }

  // Contract: only a refusal status our own routes emit (400, 401, 403, 404, 413, 415) proves nothing was written. A committed row can sit behind a 5xx or a lost reply, so
  // 5xx, 429 and a network error all say "reload to check", never "Nothing was recorded".
  it.each([
    ["HTTP 400", { status: 400, body: { error: "x" } }, LEGAL_COPY.errors.nothingRecorded],
    ["HTTP 403", { status: 403, body: { error: "x" } }, LEGAL_COPY.errors.nothingRecorded],
    ["HTTP 404", { status: 404, body: { error: "x" } }, LEGAL_COPY.errors.nothingRecorded],
    ["HTTP 408", { status: 408, body: { error: "x" } }, LEGAL_COPY.errors.unknownResult],
    ["HTTP 409", { status: 409, body: { error: "x" } }, LEGAL_COPY.errors.unknownResult],
    ["HTTP 499", { status: 499, body: { error: "x" } }, LEGAL_COPY.errors.unknownResult],
    ["HTTP 500", { status: 500, body: { error: "x" } }, LEGAL_COPY.errors.unknownResult],
    ["HTTP 503", { status: 503, body: {} }, LEGAL_COPY.errors.unknownResult],
    ["HTTP 429", { status: 429, body: { error: "slow down" } }, LEGAL_COPY.errors.unknownResult],
    ["a network failure", "throw" as const, LEGAL_COPY.errors.unknownResult],
    ["a 200 with a malformed body", { body: { nope: true } }, LEGAL_COPY.errors.unknownResult],
    ["a 200 with an unknown outcome", { body: { outcome: "banana", choice: "request_changes" } }, LEGAL_COPY.errors.unknownResult],
  ])("%s shows an error and the card stays pending", async (_n, reply, message) => {
    mockFetch({ decide: reply as Reply });
    const user = userEvent.setup();
    renderCard();
    await sendChanges(user);
    expect(await screen.findByRole("alert")).toHaveTextContent(message);
    expect(screen.queryByText(LEGAL_COPY.changesRequested.badge)).toBeNull();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
  });

  it.each([
    ["replaced", LEGAL_COPY.errors.replaced],
    ["expired", LEGAL_COPY.errors.expired],
    ["code_expired", LEGAL_COPY.errors.unknownResult],
  ])("the typed outcome %s records nothing and says so", async (outcome, message) => {
    mockFetch({ decide: { body: { outcome } } });
    const user = userEvent.setup();
    renderCard();
    await sendChanges(user);
    expect(await screen.findByRole("alert")).toHaveTextContent(message);
    expect(screen.queryByText(LEGAL_COPY.changesRequested.badge)).toBeNull();
  });

  it("two tabs: the second tab's already_recorded shows the state the server reports", async () => {
    mockFetch({ decide: { body: { outcome: "already_recorded", choice: "decline", decidedAt: "2026-11-04T10:42:00Z" } } });
    const user = userEvent.setup();
    renderCard();
    await sendChanges(user);
    await waitFor(() => expect(screen.getByText(LEGAL_COPY.declined.badge)).toBeInTheDocument());
    expect(screen.getByText(LEGAL_COPY.alreadyAnswered)).toBeInTheDocument();
    expect(screen.queryByText(LEGAL_COPY.changesRequested.badge)).toBeNull();
  });

  it("already_recorded without a choice cannot be read as success", async () => {
    mockFetch({ decide: { body: { outcome: "already_recorded" } } });
    const user = userEvent.setup();
    renderCard();
    await sendChanges(user);
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
  });
});

// =====================================================================================================================
describe("the in-place email check (AC10, AC11)", () => {
  it("Yes opens a dialog on top of the same card; the card stays on the page", async () => {
    const user = userEvent.setup();
    renderCard();
    await user.click(yesButton());
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByText(LEGAL_COPY.dialog.startTitle)).toBeInTheDocument();
    expect(within(dialog).getByText(/dana@example.com/)).toBeInTheDocument();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
  });

  it("Go back records nothing and sends nothing (not even a send-code request)", async () => {
    const f = mockFetch({});
    const user = userEvent.setup();
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.goBack }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(f.fn).not.toHaveBeenCalled();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
  });

  it("Go back after the code step still records nothing (no decide fetch)", async () => {
    const f = mockFetch({ send: { body: SENT } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.goBack }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(f.decides()).toHaveLength(0);
    expect(f.reauths()).toHaveLength(1);
    expect(f.reauths()[0].body).toEqual({ step: "send" });
  });

  it("happy path: send, enter the code, confirm: verify then decide, then the accepted state with the code time", async () => {
    const f = mockFetch({ send: { body: SENT }, verify: { body: VERIFIED }, decide: { body: RECORDED_YES } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    await waitFor(() => expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument());
    expect(f.calls.map((c) => `${c.url.split("/").pop()}:${String(c.body.step ?? c.body.choice)}`)).toEqual(["reauth:send", "reauth:verify", "decide:accept"]);
    expect(f.calls[1].body).toEqual({ step: "verify", code: "481902" });
    expect(f.calls[2].body).toEqual({ choice: "accept", textHash: HASH });
    for (const c of f.calls) expect(new Headers(c.init.headers).get("content-type")).toBe("application/json");
    expect(screen.getByText("Confirmed with an email code, Wed 4 Nov 2026, 10:42 UTC")).toBeInTheDocument();
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("Confirm is not available until the code is 6 to 8 digits, and non-digits are dropped", async () => {
    mockFetch({ send: { body: SENT } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    const confirm = screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord });
    expect(confirm).toBeDisabled();
    await enterCode(user, "12 34-5");
    expect(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel)).toHaveValue("12345");
    expect(confirm).toBeDisabled();
    await user.type(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel), "6");
    expect(confirm).toBeEnabled();
    await user.type(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel), "789");
    expect(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel)).toHaveValue("12345678");
  });

  it.each([
    ["rate_limited"],
    ["already_recorded"],
    ["replaced"],
    ["unavailable"],
  ] as const)("a send result of %s renders its own wording and records nothing", async (reason) => {
    const f = mockFetch({ send: { body: { ok: false, reason } satisfies LegalReauthSendResult } });
    const user = userEvent.setup();
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.dialog.sendError[reason]);
    expect(f.decides()).toHaveLength(0);
  });

  it("an unreachable send says nothing was recorded and gives a way to get help", async () => {
    mockFetch({ send: "throw" });
    const user = userEvent.setup();
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Nothing was recorded");
    expect(alert).toHaveTextContent("try again shortly");
    expect(screen.getByText(LEGAL_COPY.dialog.help)).toBeInTheDocument();
  });

  it("a non-200 send is the same unavailable wording", async () => {
    mockFetch({ send: { status: 500, body: {} } });
    const user = userEvent.setup();
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.dialog.sendError.unavailable);
  });

  it.each([
    ["wrong_code"],
    ["locked"],
    ["expired"],
    ["replaced"],
    ["code_stale"],
    ["unavailable"],
  ] as const)("a verify result of %s renders its own wording, records nothing, and never decides", async (reason) => {
    const f = mockFetch({ send: { body: SENT }, verify: { body: { ok: false, reason } satisfies LegalReauthVerifyResult } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.dialog.verifyError[reason]);
    expect(f.decides()).toHaveLength(0);
    expect(screen.queryByText(KC.acceptedBadge)).toBeNull();
  });

  it("Send me a new code sends with resend:true (once the cooldown has passed)", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const f = mockFetch({ send: { body: SENT } });
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    renderCard();
    await openDialogAndSendCode(user);
    act(() => {
      vi.advanceTimersByTime(OTP_RESEND_COOLDOWN_MS + 1_000);
    });
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendNewCode }));
    await waitFor(() => expect(f.reauths()).toHaveLength(2));
    expect(f.reauths()[1].body).toEqual({ step: "send", resend: true });
  });

  it("I cannot get the code shows plain help and offers no other method", async () => {
    mockFetch({ send: { body: SENT } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.cannotGetCode }));
    expect(screen.getByText(LEGAL_COPY.dialog.help)).toBeInTheDocument();
    expect(screen.queryByText(/password|google|apple|github|microsoft/i)).toBeNull();
  });

  it.each([
    ["code_expired", LEGAL_COPY.dialog.decideError.code_expired],
    ["replaced", LEGAL_COPY.dialog.decideError.replaced],
    ["expired", LEGAL_COPY.dialog.decideError.expired],
  ])("a decide outcome of %s after a good code records nothing and never shows accepted", async (outcome, message) => {
    mockFetch({ send: { body: SENT }, verify: { body: VERIFIED }, decide: { body: { outcome } } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    expect(await screen.findByRole("alert")).toHaveTextContent(message);
    expect(screen.queryByText(KC.acceptedBadge)).toBeNull();
  });

  it("a failed decide after a good code shows an error, never success, and a retry sends decide only (not verify again)", async () => {
    let n = 0;
    const f = mockFetch({
      send: { body: SENT },
      verify: { body: VERIFIED },
      decide: () => (++n === 1 ? { status: 500, body: {} } : { body: RECORDED_YES }),
    });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    // A 500 may hide a committed row: the wording asks for a reload instead of claiming nothing was written.
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(alert).not.toHaveTextContent("Nothing was recorded");
    expect(screen.queryByText(KC.acceptedBadge)).toBeNull();
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    await waitFor(() => expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument());
    expect(f.calls.filter((c) => c.body.step === "verify")).toHaveLength(1);
    expect(f.decides()).toHaveLength(2);
  });

  it("a malformed decide response after a good code is an error, not success", async () => {
    mockFetch({ send: { body: SENT }, verify: { body: VERIFIED }, decide: { body: { outcome: "recorded-ish" } } });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(screen.queryByText(KC.acceptedBadge)).toBeNull();
  });

  it("two tabs: already_recorded on the Yes path shows the accepted state from the server's answer", async () => {
    mockFetch({
      send: { body: SENT },
      verify: { body: VERIFIED },
      decide: { body: { outcome: "already_recorded", choice: "accept", decidedAt: "2026-11-04T10:42:00Z", reauthAt: "2026-11-04T10:41:00Z" } },
    });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    await waitFor(() => expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument());
    expect(screen.getByText("Confirmed with an email code, Wed 4 Nov 2026, 10:41 UTC")).toBeInTheDocument();
  });

  it("a fresh mount starts the check from the beginning: nothing from an earlier check is restored", async () => {
    const f = mockFetch({ send: { body: SENT } });
    const user = userEvent.setup();
    const first = renderCard();
    await openDialogAndSendCode(user);
    first.unmount();
    renderCard();
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByLabelText(LEGAL_COPY.dialog.codeLabel)).toBeNull();
    expect(f.decides()).toHaveLength(0);
  });
});

// =====================================================================================================================
describe("start-step send respects the cooldown after a rate_limited answer", () => {
  it("disables the first-step button and shows the wait hint until OTP_RESEND_COOLDOWN_MS has passed, then re-enables it", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    mockFetch({ send: { body: { ok: false, reason: "rate_limited" } } });
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByRole("alert");
    expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode })).toBeDisabled();
    expect(screen.getByText(LEGAL_COPY.dialog.resendWait)).toBeInTheDocument();
    act(() => {
      vi.advanceTimersByTime(OTP_RESEND_COOLDOWN_MS + 1_000);
    });
    await waitFor(() => expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode })).toBeEnabled());
    expect(screen.queryByText(LEGAL_COPY.dialog.resendWait)).toBeNull();
  });
});

describe("the email code no longer counts: 403 reverify (contract 1)", () => {
  it("returns to the send step, asks for a new code, and the next confirm verifies again", async () => {
    let n = 0;
    const f = mockFetch({
      send: { body: SENT },
      verify: { body: VERIFIED },
      decide: () => (++n === 1 ? { status: 403, body: { error: "reverify" } } : { body: RECORDED_YES }),
    });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(LEGAL_COPY.dialog.reverify);
    expect(alert).not.toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(screen.queryByText(KC.acceptedBadge)).toBeNull();
    // Back on the send step: the code box is gone and a fresh code is the only way forward.
    expect(screen.queryByLabelText(LEGAL_COPY.dialog.codeLabel)).toBeNull();
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByLabelText(LEGAL_COPY.dialog.codeLabel);
    expect(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel)).toHaveValue("");
    await enterCode(user, "123456");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    await waitFor(() => expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument());
    expect(f.calls.filter((c) => c.body.step === "verify")).toHaveLength(2);
  });

  it("code_expired from the decide answer also needs a new check before the next try", async () => {
    let n = 0;
    const f = mockFetch({
      send: { body: SENT },
      verify: { body: VERIFIED },
      decide: () => (++n === 1 ? { body: { outcome: "code_expired" } } : { body: RECORDED_YES }),
    });
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.dialog.decideError.code_expired);
    // The used code is cleared: a new code has to be entered and checked.
    expect(screen.getByLabelText(LEGAL_COPY.dialog.codeLabel)).toHaveValue("");
    expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord })).toBeDisabled();
    await enterCode(user, "654321");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    await waitFor(() => expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument());
    expect(f.calls.filter((c) => c.body.step === "verify")).toHaveLength(2);
  });
});

// =====================================================================================================================
describe("a decide in flight cannot be discarded (Go back, Escape)", () => {
  it("Go back is disabled and Escape does nothing while the decide is pending; the outcome then shows", async () => {
    let release: (v: unknown) => void = () => {};
    const gate = new Promise((r) => (release = r));
    const calls: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init: RequestInit) => {
        const body = JSON.parse(String(init.body ?? "{}")) as Record<string, unknown>;
        calls.push(`${url.split("/").pop()}:${String(body.step ?? body.choice)}`);
        if (url.endsWith("/decide")) {
          await gate;
          return { ok: true, status: 200, json: async () => RECORDED_YES };
        }
        return { ok: true, status: 200, json: async () => (body.step === "send" ? SENT : VERIFIED) };
      }),
    );
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    await waitFor(() => expect(calls).toContain("decide:accept"));
    expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.goBack })).toBeDisabled();
    await user.keyboard("{Escape}");
    expect(screen.getByRole("dialog")).toBeInTheDocument();
    await act(async () => {
      release(null);
      await gate;
    });
    await waitFor(() => expect(screen.getByText(KC.acceptedBadge)).toBeInTheDocument());
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("Escape closes the dialog when nothing is in flight", async () => {
    mockFetch({});
    const user = userEvent.setup();
    renderCard();
    await user.click(yesButton());
    await screen.findByRole("dialog");
    await user.keyboard("{Escape}");
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

// =====================================================================================================================
describe("Send me a new code: client cooldown and the rate_limited reason (contract 4)", () => {
  afterEach(() => vi.useRealTimers());

  it("is disabled for OTP_RESEND_COOLDOWN_MS after a send, then sends with resend:true", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const f = mockFetch({ send: { body: SENT } });
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    renderCard();
    await openDialogAndSendCode(user);
    const again = screen.getByRole("button", { name: LEGAL_COPY.dialog.sendNewCode });
    expect(again).toBeDisabled();
    expect(screen.getByText(LEGAL_COPY.dialog.resendWait)).toBeInTheDocument();
    act(() => {
      vi.advanceTimersByTime(OTP_RESEND_COOLDOWN_MS - 1_000);
    });
    expect(again).toBeDisabled();
    act(() => {
      vi.advanceTimersByTime(2_000);
    });
    await waitFor(() => expect(again).toBeEnabled());
    expect(screen.queryByText(LEGAL_COPY.dialog.resendWait)).toBeNull();
    await user.click(again);
    await waitFor(() => expect(f.reauths()).toHaveLength(2));
    expect(f.reauths()[1].body).toEqual({ step: "send", resend: true });
    // A fresh send starts a fresh cooldown.
    await waitFor(() => expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendNewCode })).toBeDisabled());
  });

  it("a rate_limited answer to a resend shows its wording and keeps the cooldown running", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    let n = 0;
    mockFetch({ send: () => (++n === 1 ? { body: SENT } : { body: { ok: false, reason: "rate_limited" } satisfies LegalReauthSendResult }) });
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    renderCard();
    await openDialogAndSendCode(user);
    act(() => {
      vi.advanceTimersByTime(OTP_RESEND_COOLDOWN_MS + 1_000);
    });
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendNewCode }));
    expect(await screen.findByRole("alert")).toHaveTextContent(LEGAL_COPY.dialog.sendError.rate_limited);
    expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendNewCode })).toBeDisabled();
  });
});

// =====================================================================================================================
describe("a send that follows a failed send asks for a fresh mail (resend:true)", () => {
  afterEach(() => vi.useRealTimers());

  it.each([
    ["an unavailable answer", { status: 500, body: {} } as Reply],
    ["a rate_limited answer", { body: { ok: false, reason: "rate_limited" } satisfies LegalReauthSendResult } as Reply],
    ["a network failure", "throw" as const],
  ])("after %s the retry from the first step sends resend:true; the send after a success is plain again", async (_n, failure) => {
    let n = 0;
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const f = mockFetch({ send: () => (++n === 1 ? failure : { body: SENT }) });
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime });
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByRole("alert");
    expect(f.reauths()[0].body).toEqual({ step: "send" });
    // A rate_limited answer starts the cooldown, so the start button waits it out; an `unavailable` one does not.
    act(() => {
      vi.advanceTimersByTime(OTP_RESEND_COOLDOWN_MS + 1_000);
    });
    await waitFor(() => expect(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode })).toBeEnabled());
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByLabelText(LEGAL_COPY.dialog.codeLabel);
    expect(f.reauths()[1].body).toEqual({ step: "send", resend: true });
  });

  it("the retry flag lives in one dialog: after fail then success, a fresh dialog's first send is plain again", async () => {
    let n = 0;
    const f = mockFetch({ send: () => (++n === 1 ? { status: 500, body: {} } : { body: SENT }) });
    const user = userEvent.setup();
    const first = renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByRole("alert");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByLabelText(LEGAL_COPY.dialog.codeLabel);
    first.unmount();
    renderCard();
    await user.click(yesButton());
    await user.click(await screen.findByRole("button", { name: LEGAL_COPY.dialog.sendCode }));
    await screen.findByLabelText(LEGAL_COPY.dialog.codeLabel);
    expect(f.reauths()[2].body).toEqual({ step: "send" });
  });
});

// =====================================================================================================================
describe("Yes lock is not a one-way latch against a later reflow", () => {
  const fireResize = () =>
    act(() => {
      window.dispatchEvent(new Event("resize"));
    });

  it("a text that fitted and later overflows (resize) relocks Yes and asks for the scroll and the tick again", async () => {
    layout = { scrollHeight: 200, clientHeight: 200 };
    renderCard();
    expect(yesButton()).toHaveAttribute("aria-disabled", "false");
    longText();
    fireResize();
    await waitFor(() => expect(yesButton()).toHaveAttribute("aria-disabled", "true"));
    expect(screen.getByRole("status")).toHaveTextContent(LEGAL_COPY.lock.atEnd);
    const box = screen.getByRole("checkbox");
    expect(box).toHaveAttribute("aria-disabled", "true");
    expect(box).not.toBeChecked();
  });

  it("a resize that never scrolled to the bottom cannot count as reaching the end", async () => {
    longText();
    renderCard();
    fireResize();
    await waitFor(() => expect(screen.getByRole("checkbox")).toHaveAttribute("aria-disabled", "true"));
    expect(screen.getByRole("status")).toHaveTextContent(LEGAL_COPY.lock.atEnd);
  });

  it("scrolled to the end and ticked, then the text reflows to fit and grows again: the reading and the tick are gone", async () => {
    longText();
    const user = userEvent.setup();
    renderCard();
    scrollToEnd();
    const box = screen.getByRole("checkbox");
    await waitFor(() => expect(box).toHaveAttribute("aria-disabled", "false"));
    await user.click(box);
    await waitFor(() => expect(yesButton()).toHaveAttribute("aria-disabled", "false"));
    layout = { scrollHeight: 200, clientHeight: 200 };
    fireResize();
    await waitFor(() => expect(screen.queryByRole("checkbox")).toBeNull());
    longText();
    fireResize();
    await waitFor(() => expect(yesButton()).toHaveAttribute("aria-disabled", "true"));
    expect(screen.getByRole("checkbox")).not.toBeChecked();
    expect(screen.getByRole("checkbox")).toHaveAttribute("aria-disabled", "true");
    expect(screen.getByRole("status")).toHaveTextContent(LEGAL_COPY.lock.atEnd);
  });

  it("scrolling back up after reaching the end keeps the reading (a real scroll latches)", async () => {
    longText();
    renderCard();
    scrollToEnd();
    const region = screen.getByRole("region", { name: new RegExp(LEGAL_COPY.exactTextHeading, "i") });
    region.scrollTop = 0;
    fireEvent.scroll(region);
    expect(screen.getByRole("checkbox")).toHaveAttribute("aria-disabled", "false");
  });
});

// =====================================================================================================================
describe("No / Request changes have no code step: how the card words a 403 reverify and a non-JSON 200", () => {
  const REVERIFY = { status: 403, body: { error: "reverify" } };

  async function submitChanges(user: ReturnType<typeof userEvent.setup>) {
    await user.click(changesButton());
    await user.type(screen.getByRole("textbox"), "note");
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.changes.send }));
  }
  async function submitDecline(user: ReturnType<typeof userEvent.setup>) {
    await user.click(noButton());
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.decline.confirm }));
  }

  // Today's behaviour (the decide route's 42501 refusal wrote nothing): there is no code to redo here, so the answer reads as
  // "nothing was recorded", with no email dialog, no reload button and no success.
  it.each([
    ["Request changes", submitChanges],
    ["No", submitDecline],
  ])("%s: a 403 reverify says nothing was recorded, opens no email dialog, offers no reload and stays pending", async (_n, submit) => {
    const f = mockFetch({ decide: REVERIFY });
    const user = userEvent.setup();
    renderCard();
    await submit(user);
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(LEGAL_COPY.errors.nothingRecorded);
    expect(alert).not.toHaveTextContent(LEGAL_COPY.dialog.reverify);
    expect(alert).not.toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(within(alert).queryByRole("button", { name: LEGAL_COPY.errors.reload })).toBeNull();
    expect(screen.queryByTestId("legal-reauth-dialog")).toBeNull();
    expect(screen.queryByLabelText(LEGAL_COPY.dialog.codeLabel)).toBeNull();
    expect(screen.queryByText(LEGAL_COPY.declined.badge)).toBeNull();
    expect(screen.queryByText(LEGAL_COPY.changesRequested.badge)).toBeNull();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
    expect(f.decides()).toHaveLength(1);
    expect(f.reauths()).toHaveLength(0);
  });

  it.each([
    ["Request changes", submitChanges],
    ["No", submitDecline],
  ])("%s: a 200 whose body is not JSON says to reload to check, never 'nothing was recorded', and shows no success", async (_n, submit) => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("<html>gateway page</html>", { status: 200, headers: { "content-type": "text/html" } })));
    const user = userEvent.setup();
    renderCard();
    await submit(user);
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(alert).not.toHaveTextContent("Nothing was recorded");
    expect(within(alert).getByRole("button", { name: LEGAL_COPY.errors.reload })).toBeInTheDocument();
    expect(screen.queryByText(LEGAL_COPY.declined.badge)).toBeNull();
    expect(screen.queryByText(LEGAL_COPY.changesRequested.badge)).toBeNull();
    expect(screen.getByText(LEGAL_COPY.pending.badge)).toBeInTheDocument();
  });

  it("the Yes path: a 200 whose decide body is not JSON also says reload to check and shows no accepted state", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init: RequestInit) => {
        if (url.endsWith("/decide")) return new Response("not json", { status: 200 });
        const step = (JSON.parse(String(init.body ?? "{}")) as { step?: string }).step;
        return { ok: true, status: 200, json: async () => (step === "send" ? SENT : VERIFIED) };
      }),
    );
    const user = userEvent.setup();
    renderCard();
    await openDialogAndSendCode(user);
    await enterCode(user);
    await user.click(screen.getByRole("button", { name: LEGAL_COPY.dialog.confirmAndRecord }));
    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(LEGAL_COPY.errors.unknownResult);
    expect(alert).not.toHaveTextContent("Nothing was recorded");
    expect(screen.queryByText(KC.acceptedBadge)).toBeNull();
  });
});
