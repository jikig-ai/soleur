import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// fix (feat-one-shot-share-a-key-toggle-not-enabling): the owner "Share a key"
// toggle must NEVER silently no-op. A non-OK response OR a thrown fetch (offline,
// DNS/TLS failure, aborted request) must surface a visible error and leave the
// toggle in its prior state — the original bug was a silent revert with no signal.
// AC5 + the user-impact review's network-throw finding.

import { DelegationToggle } from "@/components/settings/delegation-toggle";

const baseProps = {
  memberUserId: "member-1",
  memberEmail: "harry@jikigai.com",
  workspaceId: "ws-1",
  isOwner: true,
  delegation: null,
  isSelf: false,
  flagEnabled: true,
};

let fetchMock: ReturnType<typeof vi.fn>;
let alertMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn(async () => new Response(JSON.stringify({ delegationId: "d-1" }), { status: 200 }));
  alertMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  vi.stubGlobal("alert", alertMock);
  vi.spyOn(console, "error").mockImplementation(() => {});
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  vi.clearAllMocks();
});

function getSwitch() {
  return screen.getByRole("switch", { name: /Fund harry's runs/i });
}

describe("DelegationToggle — owner grant control", () => {
  it("turns the toggle on after a successful grant POST", async () => {
    render(<DelegationToggle {...baseProps} />);
    const toggle = getSwitch();
    expect(toggle).toHaveAttribute("aria-checked", "false");

    await userEvent.click(toggle);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workspace/delegations",
      expect.objectContaining({ method: "POST" }),
    );
    expect(getSwitch()).toHaveAttribute("aria-checked", "true");
    expect(alertMock).not.toHaveBeenCalled();
  });

  it("surfaces a visible error and stays off when the grant POST returns non-OK", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ error: "not_owner" }), { status: 403 }));
    render(<DelegationToggle {...baseProps} />);

    await userEvent.click(getSwitch());

    expect(alertMock).toHaveBeenCalledTimes(1);
    expect(getSwitch()).toHaveAttribute("aria-checked", "false");
  });

  it("surfaces a visible error and stays off when fetch itself rejects (offline/network throw)", async () => {
    // Regression guard for the user-impact finding: a thrown fetch must not be a
    // silent no-op. Without the catch in handleToggle this assertion fails.
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
    render(<DelegationToggle {...baseProps} />);

    await userEvent.click(getSwitch());

    expect(alertMock).toHaveBeenCalledTimes(1);
    expect(getSwitch()).toHaveAttribute("aria-checked", "false");
  });
});
