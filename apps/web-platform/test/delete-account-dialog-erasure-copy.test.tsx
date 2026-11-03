import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// #8211 / #9066 follow-up (copy derived from the merged Privacy Policy, best effort).
// Pre-delete: the dialog cannot know the erasure outcome, so it must not promise an
// unqualified deletion and must carry the best-effort retry qualifier.
// Post-delete: the outcome rides the URL (hard nav stays unconditional, GAP F).

import { DeleteAccountDialog } from "@/components/settings/delete-account-dialog";
import {
  ERASURE_RETRY_QUALIFIER,
  NEW_TAB_CUE,
  PRIVACY_POLICY_CITATION,
  PRIVACY_POLICY_URL,
} from "@/lib/legal/account-deletion-copy";

const EMAIL = "test@example.com";
const assignMock = vi.fn();
const fetchMock = vi.fn();
let originalAssign: typeof window.location.assign;

beforeEach(() => {
  vi.stubGlobal("fetch", fetchMock);
  assignMock.mockClear();
  fetchMock.mockReset();
  originalAssign = window.location.assign;
  Object.defineProperty(window.location, "assign", { configurable: true, writable: true, value: assignMock });
});
afterEach(() => {
  Object.defineProperty(window.location, "assign", { configurable: true, writable: true, value: originalAssign });
  vi.unstubAllGlobals();
  cleanup();
});

async function openAndConfirm() {
  render(<DeleteAccountDialog userEmail={EMAIL} />);
  await userEvent.click(screen.getByRole("button", { name: /delete account/i }));
  await userEvent.type(screen.getByPlaceholderText(EMAIL), EMAIL);
  return screen.getByRole("button", { name: /confirm deletion/i });
}

describe("DeleteAccountDialog pre-delete copy", () => {
  it("carries the full best-effort qualifier in its own paragraph, tied to the confirm control", async () => {
    const confirm = await openAndConfirm();
    const paragraph = screen.getByText(ERASURE_RETRY_QUALIFIER);
    expect(paragraph.textContent).toContain(ERASURE_RETRY_QUALIFIER);
    expect(paragraph.id).not.toBe("");
    expect(confirm.getAttribute("aria-describedby")).toContain(paragraph.id);
    expect(screen.getByPlaceholderText(EMAIL).getAttribute("aria-describedby")).toContain(paragraph.id);
  });

  it("heading and body agree: no 'Permanently'/'All your data', no guarantee, no timeline", async () => {
    const { container } = render(<DeleteAccountDialog userEmail={EMAIL} />);
    await userEvent.click(screen.getByRole("button", { name: /delete account/i }));
    expect(screen.getByRole("heading", { level: 3 }).textContent).toBe("Delete your account");
    const text = container.textContent ?? "";
    expect(text).toContain("This action cannot be undone.");
    expect(text).toContain("Your account and conversations are deleted from our application.");
    expect(text).toContain("Payment records are kept as French tax law requires.");
    expect(text).not.toMatch(/permanent|all your data|workspace files|straight away|will be completed|we keep your/i);
  });

  it("links the Privacy Policy by heading name with a new-tab cue and never mentions residue or purging", async () => {
    const { container } = render(<DeleteAccountDialog userEmail={EMAIL} />);
    await userEvent.click(screen.getByRole("button", { name: /delete account/i }));
    const link = screen.getByRole("link", { name: PRIVACY_POLICY_CITATION + NEW_TAB_CUE });
    expect(link.getAttribute("href")).toBe(PRIVACY_POLICY_URL);
    expect(link.childNodes[0].textContent).toBe(PRIVACY_POLICY_CITATION);
    expect(link.textContent).toBe(PRIVACY_POLICY_CITATION + NEW_TAB_CUE);
    expect(link).toHaveAttribute("rel", "noopener noreferrer");
    expect(container.textContent ?? "").not.toMatch(/\.gc-cursor|lock file|purge|erased|removed/i);
  });
});

describe("DeleteAccountDialog post-delete outcome", () => {
  it("hard-navs to the plain deleted state when the response has no pending flag", async () => {
    fetchMock.mockResolvedValue({ ok: true, json: async () => ({ success: true }) });
    await userEvent.click(await openAndConfirm());
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/login?deleted=true"));
  });

  it("hard-navs to the erasure-pending state when gitDataErasurePending is true", async () => {
    fetchMock.mockResolvedValue({ ok: true, json: async () => ({ success: true, gitDataErasurePending: true }) });
    await userEvent.click(await openAndConfirm());
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/login?deleted=true&erasure=pending"));
  });
});
