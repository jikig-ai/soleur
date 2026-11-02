import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// #8211 / #9066 follow-up (CLO recommendation 2026-11-02, copy PENDING CLO sign-off).
// Pre-delete: the dialog cannot know the erasure outcome, so it must not promise an
// unqualified "permanently deleted" and must carry the retry-and-ledger qualifier.
// Post-delete: the outcome rides the URL (hard nav stays unconditional, GAP F).

import { DeleteAccountDialog } from "@/components/settings/delete-account-dialog";
import { ERASURE_RETRY_QUALIFIER } from "@/lib/legal/account-deletion-copy";

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
  it("carries the retry-and-ledger qualifier for the repository copy", async () => {
    await openAndConfirm();
    expect(ERASURE_RETRY_QUALIFIER).toMatch(/try again until/i);
    expect(ERASURE_RETRY_QUALIFIER).toMatch(/workspace identifier/i);
    expect(screen.getByText(new RegExp(ERASURE_RETRY_QUALIFIER.slice(0, 40)), { exact: false })).toBeInTheDocument();
  });

  it("no longer promises unqualified permanent deletion of workspace files", async () => {
    await openAndConfirm();
    expect(screen.queryByText(/permanently deleted/i)).toBeNull();
    expect(screen.getByText(/this action cannot be undone/i)).toBeInTheDocument();
  });

  it("links the Privacy Policy and never mentions lock/cursor residue or purging", async () => {
    const { container } = render(<DeleteAccountDialog userEmail={EMAIL} />);
    await userEvent.click(screen.getByRole("button", { name: /delete account/i }));
    expect(screen.getByRole("link", { name: /privacy policy/i })).toHaveAttribute(
      "href",
      expect.stringContaining("soleur.ai/legal/privacy-policy"),
    );
    expect(container.textContent ?? "").not.toMatch(/\.gc-cursor|lock file|purge|erased/i);
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
