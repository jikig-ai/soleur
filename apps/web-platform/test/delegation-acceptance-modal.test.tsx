import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// Phase 5 (feat-byok-delegation-consent, #4625, ADVISORY tier): the grantee
// accept surface must carry an INLINE telemetry-visibility acknowledgment
// the grantee actively checks before "I accept" is enabled (CPO finding),
// and a withdraw affordance on the same surface (Art. 7(3)).

import { DelegationAcceptanceModal } from "@/components/settings/delegation-acceptance-modal";

const baseProps = {
  delegationId: "deleg-1",
  grantorDisplayName: "alice",
  dailyCapCents: 1000,
  hourlyCapCents: 200,
  sideLetterVersion: "1.0.0",
  onAccepted: vi.fn(),
  onDeclined: vi.fn(),
};

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn(async () => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe("DelegationAcceptanceModal — telemetry ack gate (Phase 5)", () => {
  it("disables 'I accept' until the telemetry-visibility ack is checked", async () => {
    render(<DelegationAcceptanceModal {...baseProps} />);
    const acceptBtn = screen.getByRole("button", { name: /i accept/i });
    expect(acceptBtn).toBeDisabled();

    const ack = screen.getByRole("checkbox");
    await userEvent.click(ack);
    expect(acceptBtn).toBeEnabled();
  });

  it("posts ONLY { delegationId } to the accept route after ack (server-owned version)", async () => {
    const onAccepted = vi.fn();
    render(<DelegationAcceptanceModal {...baseProps} onAccepted={onAccepted} />);
    await userEvent.click(screen.getByRole("checkbox"));
    await userEvent.click(screen.getByRole("button", { name: /i accept/i }));

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workspace/delegations/accept",
      expect.objectContaining({ method: "POST" }),
    );
    const body = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(body).toEqual({ delegationId: "deleg-1" });
    expect(body).not.toHaveProperty("sideLetterVersion");
  });
});

describe("DelegationAcceptanceModal — withdraw affordance (Phase 5)", () => {
  it("when alreadyAccepted, shows a Withdraw control that posts to the withdraw route", async () => {
    const onWithdrawn = vi.fn();
    render(
      <DelegationAcceptanceModal
        {...baseProps}
        alreadyAccepted
        onWithdrawn={onWithdrawn}
      />,
    );
    const withdrawBtn = screen.getByRole("button", { name: /withdraw/i });
    await userEvent.click(withdrawBtn);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/workspace/delegations/withdraw",
      expect.objectContaining({ method: "POST" }),
    );
    const body = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(body).toEqual({ delegationId: "deleg-1" });
  });

  it("does NOT show the telemetry ack / accept button once alreadyAccepted", () => {
    render(<DelegationAcceptanceModal {...baseProps} alreadyAccepted onWithdrawn={vi.fn()} />);
    expect(screen.queryByRole("button", { name: /i accept/i })).toBeNull();
  });
});
