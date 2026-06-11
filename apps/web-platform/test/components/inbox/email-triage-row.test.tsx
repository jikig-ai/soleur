import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

import {
  EmailTriageRow,
  type EmailTriageItem,
} from "@/components/inbox/email-triage-row";
import { formatDueDate, STATUTORY_RULES } from "@/server/email-triage/statutory-rules";

// feat-operator-inbox-delegation Phase 5b (AC5) — email-triage row variants.
//
// Mock policy: method-aware `vi.fn` fetch mock (no MSW) per
// 2026-05-20-happy-dom-ws-fetch-blockade.md. Assertions key off the public
// DOM contract first (visible text/labels), with the fired-request spy as
// the secondary check, per
// 2026-05-06-test-public-dom-contract-not-setstate-side-effects.md.

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const ORIGINAL_FETCH = globalThis.fetch;

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn(async () =>
    new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  globalThis.fetch = fetchMock as unknown as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = ORIGINAL_FETCH;
  vi.restoreAllMocks();
});

const ITEM_ID = "11111111-2222-3333-4444-555555555555";

function makeItem(overrides: Partial<EmailTriageItem> = {}): EmailTriageItem {
  return {
    id: ITEM_ID,
    message_id: "<msg-1@example.com>",
    sender: "AWS Billing <no-reply@billing.aws.example>",
    subject: "Your AWS invoice is available",
    summary: "May invoice of $42.18 is ready. Autopay scheduled for Jun 24.",
    mail_class: "billing",
    statutory_class: null,
    rule_id: null,
    status: "new",
    status_changed_at: null,
    acknowledged_at: null,
    received_at: "2026-06-10T14:02:11.000Z",
    created_at: "2026-06-10T14:02:30.000Z",
    ...overrides,
  };
}

function makeStatutoryItem(
  overrides: Partial<EmailTriageItem> = {},
): EmailTriageItem {
  return makeItem({
    sender: "K. Osei <k.osei@example.com>",
    subject: "Access request — my personal data",
    summary: "Data subject access request under GDPR Art. 15.",
    mail_class: null,
    statutory_class: "dsar",
    rule_id: "dsar-art15",
    ...overrides,
  });
}

describe("EmailTriageRow — standard variant", () => {
  it("renders class pill, summary, sender, relative received-at, and Archive", () => {
    render(<EmailTriageRow item={makeItem()} />);

    expect(screen.getByText("Billing")).toBeInTheDocument();
    expect(
      screen.getByText(/May invoice of \$42\.18 is ready/),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/AWS Billing <no-reply@billing\.aws\.example>/),
    ).toBeInTheDocument();
    // relativeTime output: "<n>m ago" / "<n>h ago" / ... / "just now"
    expect(screen.getByText(/ago|just now/)).toBeInTheDocument();
    expect(screen.getByLabelText("Archive email")).toBeInTheDocument();
    expect(screen.queryByLabelText("Acknowledge email")).toBeNull();
  });

  it.each([
    ["vendor", "Vendor"],
    ["billing", "Billing"],
    ["security", "Security"],
    ["newsletter", "Newsletter"],
    ["legal-review", "Legal review"],
    ["other", "Other"],
  ])("renders the %s class pill as %s", (mailClass, label) => {
    render(<EmailTriageRow item={makeItem({ mail_class: mailClass })} />);
    expect(screen.getByText(label)).toBeInTheDocument();
  });

  it("Archive fires POST /api/inbox/emails/{id}/archive and calls onChanged", async () => {
    const onChanged = vi.fn();
    render(<EmailTriageRow item={makeItem()} onChanged={onChanged} />);

    fireEvent.click(screen.getByLabelText("Archive email"));

    // DOM/public contract primary: the row reports the change upward so the
    // dashboard refetches (the server then drops archived rows from the list).
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));

    // Fired-request spy secondary.
    expect(fetchMock).toHaveBeenCalledWith(
      `/api/inbox/emails/${ITEM_ID}/archive`,
      expect.objectContaining({ method: "POST" }),
    );
  });
});

describe("EmailTriageRow — statutory variant", () => {
  it("shows due-date text from the registry and an Acknowledge action while new", () => {
    const item = makeStatutoryItem();
    render(<EmailTriageRow item={item} />);

    const rule = STATUTORY_RULES.find((r) => r.ruleId === "dsar-art15")!;
    const expectedDue = formatDueDate(item.received_at, rule.dueRule);
    expect(screen.getByText(new RegExp(escapeRegExp(expectedDue)))).toBeInTheDocument();

    expect(screen.getByText("Statutory")).toBeInTheDocument();
    expect(screen.getByLabelText("Acknowledge email")).toBeInTheDocument();
    expect(screen.queryByLabelText("Archive email")).toBeNull();
  });

  it("Acknowledge fires POST /api/inbox/emails/{id}/acknowledge and calls onChanged", async () => {
    const onChanged = vi.fn();
    render(<EmailTriageRow item={makeStatutoryItem()} onChanged={onChanged} />);

    fireEvent.click(screen.getByLabelText("Acknowledge email"));

    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));
    expect(fetchMock).toHaveBeenCalledWith(
      `/api/inbox/emails/${ITEM_ID}/acknowledge`,
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("acknowledged item stays visible with its clock and the not-legal-resolution copy", () => {
    const item = makeStatutoryItem({
      status: "acknowledged",
      acknowledged_at: "2026-06-10T15:00:00.000Z",
      status_changed_at: "2026-06-10T15:00:00.000Z",
    });
    render(<EmailTriageRow item={item} />);

    const rule = STATUTORY_RULES.find((r) => r.ruleId === "dsar-art15")!;
    const expectedDue = formatDueDate(item.received_at, rule.dueRule);
    // The clock survives acknowledgment.
    expect(screen.getByText(new RegExp(escapeRegExp(expectedDue)))).toBeInTheDocument();
    expect(
      screen.getByText(/Acknowledged — workflow state, not legal resolution/),
    ).toBeInTheDocument();
    // Action is gone once acknowledged.
    expect(screen.queryByLabelText("Acknowledge email")).toBeNull();
  });

  it("reflects the transition after action + onChanged-driven re-render", async () => {
    const onChanged = vi.fn();
    const { rerender } = render(
      <EmailTriageRow item={makeStatutoryItem()} onChanged={onChanged} />,
    );

    fireEvent.click(screen.getByLabelText("Acknowledge email"));
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));

    // The dashboard refetches on onChanged; simulate the refreshed row.
    rerender(
      <EmailTriageRow
        item={makeStatutoryItem({
          status: "acknowledged",
          acknowledged_at: "2026-06-10T15:00:00.000Z",
        })}
        onChanged={onChanged}
      />,
    );

    expect(
      screen.getByText(/Acknowledged — workflow state, not legal resolution/),
    ).toBeInTheDocument();
    expect(screen.queryByLabelText("Acknowledge email")).toBeNull();
  });
});

describe("EmailTriageRow — legal-review variant", () => {
  it("renders the distinct rules-did-not-match warning copy", () => {
    render(<EmailTriageRow item={makeItem({ mail_class: "legal-review" })} />);

    expect(
      screen.getByText(
        /Rules did not match — verify against the original in the Proton ops@ mailbox/,
      ),
    ).toBeInTheDocument();
  });
});

describe("EmailTriageRow — text-nodes-only invariant", () => {
  it("never renders anchors or HTML from item content, and strips bidi controls", () => {
    const item = makeItem({
      subject: 'Urgent ‮gnp.exe <a href="https://evil.example">click me</a>',
      summary: "Visit [our portal](https://evil.example) **now** <b>bold</b>",
      sender: '<a href="https://evil.example">spoofed@evil.example</a>',
    });
    const { container } = render(<EmailTriageRow item={item} />);

    // No anchor element may originate from item content — the row renders
    // zero <a> elements at all (navigation is a router push on the row).
    expect(container.querySelectorAll("a")).toHaveLength(0);

    // The HTML/markdown arrives as inert literal text, not parsed markup.
    expect(
      screen.getByText(/<a href="https:\/\/evil\.example">click me<\/a>/),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/\[our portal\]\(https:\/\/evil\.example\) \*\*now\*\* <b>bold<\/b>/),
    ).toBeInTheDocument();

    // RLO (U+202E) bidi spoof is stripped at render.
    expect(container.textContent).not.toContain("‮");
    // No dangerouslySetInnerHTML output paths: the literal subject text node
    // exists, so nothing got parsed into elements.
    expect(container.querySelectorAll("b")).toHaveLength(0);
  });
});

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
