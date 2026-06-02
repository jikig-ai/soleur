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

describe("DelegationToggle — owner revoke control (cannot-disable bug)", () => {
  // T2/T3: once a delegation exists, toggling OFF issues a DELETE. The revoke
  // RPC arg-mismatch (route.ts) made every DELETE return 400, so the toggle
  // snapped back ON and the user could never stop sharing the key. With the
  // route fixed (DELETE → 200) the switch must flip to OFF and stay OFF.
  const activeProps = {
    ...baseProps,
    delegation: { id: "d-1", dailyCapCents: 2000, todaySpentCents: 0, active: true },
  };

  it("turns the toggle off after a successful revoke DELETE (T2)", async () => {
    render(<DelegationToggle {...activeProps} />);
    const toggle = getSwitch();
    expect(toggle).toHaveAttribute("aria-checked", "true");

    await userEvent.click(toggle);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workspace/delegations",
      expect.objectContaining({ method: "DELETE" }),
    );
    expect(getSwitch()).toHaveAttribute("aria-checked", "false");
    expect(alertMock).not.toHaveBeenCalled();
  });

  it("stays on and alerts when the revoke DELETE returns non-OK (T3)", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ error: "forbidden" }), { status: 400 }));
    render(<DelegationToggle {...activeProps} />);

    await userEvent.click(getSwitch());

    expect(alertMock).toHaveBeenCalledTimes(1);
    expect(getSwitch()).toHaveAttribute("aria-checked", "true");
  });
});

describe("DelegationToggle — owner inline cap edit (post-join cap update)", () => {
  // #4779-followup: once a member has joined and a delegation is active, the
  // owner must be able to CHANGE the daily cap without revoke+re-grant. The
  // cap display gains an "Edit cap" affordance that PATCHes the cap in place.
  const activeProps = {
    ...baseProps,
    delegation: { id: "d-1", dailyCapCents: 2000, todaySpentCents: 500, active: true },
  };

  it("shows the current cap and an Edit cap affordance for an active delegation", () => {
    render(<DelegationToggle {...activeProps} />);
    // $5.00 spent / $20 cap
    expect(screen.getByText(/\$5\.00\/\s*\$20/)).toBeTruthy();
    expect(screen.getByRole("button", { name: /edit cap/i })).toBeTruthy();
  });

  it("PATCHes the new cap and updates the displayed cap on success", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }));
    render(<DelegationToggle {...activeProps} />);

    await userEvent.click(screen.getByRole("button", { name: /edit cap/i }));
    const input = screen.getByLabelText(/daily cap in dollars/i);
    await userEvent.clear(input);
    await userEvent.type(input, "50");
    await userEvent.click(screen.getByRole("button", { name: /^save$/i }));

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workspace/delegations",
      expect.objectContaining({ method: "PATCH" }),
    );
    const call = fetchMock.mock.calls.find((c) => c[1]?.method === "PATCH");
    expect(JSON.parse(call![1].body as string)).toEqual({
      delegationId: "d-1",
      dailyCapCents: 5000,
    });
    // Displayed cap updates to $50.
    expect(screen.getByText(/\$5\.00\/\s*\$50/)).toBeTruthy();
    expect(alertMock).not.toHaveBeenCalled();
  });

  it("keeps the prior cap and alerts when the PATCH returns non-OK", async () => {
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ error: "already revoked" }), { status: 400 }));
    render(<DelegationToggle {...activeProps} />);

    await userEvent.click(screen.getByRole("button", { name: /edit cap/i }));
    const input = screen.getByLabelText(/daily cap in dollars/i);
    await userEvent.clear(input);
    await userEvent.type(input, "50");
    await userEvent.click(screen.getByRole("button", { name: /^save$/i }));

    expect(alertMock).toHaveBeenCalledTimes(1);
    // Prior cap ($20) preserved.
    expect(screen.getByText(/\$5\.00\/\s*\$20/)).toBeTruthy();
  });

  it("Cancel closes the editor without issuing a PATCH", async () => {
    render(<DelegationToggle {...activeProps} />);

    await userEvent.click(screen.getByRole("button", { name: /edit cap/i }));
    await userEvent.click(screen.getByRole("button", { name: /^cancel$/i }));

    expect(fetchMock).not.toHaveBeenCalled();
    expect(screen.getByText(/\$5\.00\/\s*\$20/)).toBeTruthy();
  });

  it("keeps the prior cap and alerts when the PATCH fetch throws (offline/network)", async () => {
    // Symmetric with the grant/revoke network-throw guards: a thrown fetch must
    // not be a silent no-op on the cap-save path either.
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
    render(<DelegationToggle {...activeProps} />);

    await userEvent.click(screen.getByRole("button", { name: /edit cap/i }));
    const input = screen.getByLabelText(/daily cap in dollars/i);
    await userEvent.clear(input);
    await userEvent.type(input, "50");
    await userEvent.click(screen.getByRole("button", { name: /^save$/i }));

    expect(alertMock).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/\$5\.00\/\s*\$20/)).toBeTruthy();
  });

  it("disables Save for empty/sub-$1 input (no silent $1 floor write)", async () => {
    render(<DelegationToggle {...activeProps} />);

    await userEvent.click(screen.getByRole("button", { name: /edit cap/i }));
    const input = screen.getByLabelText(/daily cap in dollars/i);
    await userEvent.clear(input);

    expect(screen.getByRole("button", { name: /^save$/i })).toBeDisabled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
