import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// SOL-49 — fix: the delegation acceptance modal must be mounted by the banner,
// and `router.refresh()` must be wired into onAccepted / onDeclined /
// onWithdrawn so the server-component re-fetch resolves the modal's
// unmount condition. `vi.hoisted` is load-bearing for the router mock per
// learning 2026-05-19 (vitest hoists vi.mock above all imports).
const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
}));

import { DelegationBanner } from "@/components/chat/delegation-banner";

const baseProps = {
  grantorDisplayName: "jean",
  todaySpentCents: 0,
  dailyCapCents: 2000,
  hourlyCapCents: 500,
  delegationId: "deleg-1",
  sideLetterVersion: "1.0.0",
  alreadyAccepted: false,
  withdrawn: false,
};

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  mockRefresh.mockClear();
  fetchMock = vi.fn(
    async () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
  );
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe("DelegationBanner — pending (never-accepted) variant", () => {
  it("renders a Review & accept button", () => {
    render(<DelegationBanner {...baseProps} />);
    expect(
      screen.getByRole("button", { name: /review.*accept/i }),
    ).toBeInTheDocument();
  });

  it("opens the modal on click", async () => {
    render(<DelegationBanner {...baseProps} />);
    await userEvent.click(
      screen.getByRole("button", { name: /review.*accept/i }),
    );
    expect(screen.getByRole("dialog")).toBeInTheDocument();
  });

  it("accept success: modal unmounts AND router.refresh fires exactly once", async () => {
    render(<DelegationBanner {...baseProps} />);
    await userEvent.click(
      screen.getByRole("button", { name: /review.*accept/i }),
    );
    await userEvent.click(screen.getByRole("checkbox"));
    await userEvent.click(screen.getByRole("button", { name: /i accept/i }));

    expect(screen.queryByRole("dialog")).toBeNull();
    expect(mockRefresh).toHaveBeenCalledTimes(1);
  });

  it("decline success: modal unmounts AND router.refresh fires exactly once", async () => {
    render(<DelegationBanner {...baseProps} />);
    await userEvent.click(
      screen.getByRole("button", { name: /review.*accept/i }),
    );
    await userEvent.click(screen.getByRole("button", { name: /^decline$/i }));

    expect(screen.queryByRole("dialog")).toBeNull();
    expect(mockRefresh).toHaveBeenCalledTimes(1);
  });

  it("success-only refresh: fetch 500 does NOT call router.refresh", async () => {
    fetchMock.mockImplementationOnce(
      async () => new Response(JSON.stringify({ error: "boom" }), { status: 500 }),
    );
    render(<DelegationBanner {...baseProps} />);
    await userEvent.click(
      screen.getByRole("button", { name: /review.*accept/i }),
    );
    await userEvent.click(screen.getByRole("checkbox"));
    await userEvent.click(screen.getByRole("button", { name: /i accept/i }));

    expect(mockRefresh).not.toHaveBeenCalled();
  });

  it("success-only refresh: fetch rejection does NOT call router.refresh", async () => {
    fetchMock.mockRejectedValueOnce(new Error("network"));
    render(<DelegationBanner {...baseProps} />);
    await userEvent.click(
      screen.getByRole("button", { name: /review.*accept/i }),
    );
    await userEvent.click(screen.getByRole("checkbox"));
    await userEvent.click(screen.getByRole("button", { name: /i accept/i }));

    expect(mockRefresh).not.toHaveBeenCalled();
  });
});

describe("DelegationBanner — active (alreadyAccepted) variant", () => {
  const activeProps = {
    ...baseProps,
    alreadyAccepted: true,
    todaySpentCents: 123,
  };

  it("shows the running-on-grantor copy with a Manage entry point", () => {
    render(<DelegationBanner {...activeProps} />);
    expect(screen.getByText(/running on jean.*key/i)).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /manage/i }),
    ).toBeInTheDocument();
  });

  // #7829: a failed spend read arrives as `todaySpentCents: null`. Rendering it
  // through the numeric path yields "$0.00 of $20 today" — a confident claim
  // that the grantee has spent nothing, on a billing surface where the truth is
  // unknown. The degraded copy must say unknown, and must NOT show "$0.00".
  it("todaySpentCents null renders the unavailable copy, never $0.00", () => {
    render(<DelegationBanner {...activeProps} todaySpentCents={null} />);
    expect(screen.getByText(/spend is unavailable/i)).toBeInTheDocument();
    expect(screen.getByText(/unknown, not \$0\.00/i)).toBeInTheDocument();
    expect(screen.queryByText(/\$0\.00 of/)).toBeNull();
  });

  it("Manage opens the modal in withdraw variant; withdraw success unmounts + refresh", async () => {
    render(<DelegationBanner {...activeProps} />);
    await userEvent.click(screen.getByRole("button", { name: /manage/i }));
    expect(screen.getByRole("dialog")).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole("button", { name: /withdraw consent/i }),
    );

    expect(screen.queryByRole("dialog")).toBeNull();
    expect(mockRefresh).toHaveBeenCalledTimes(1);
  });
});

describe("DelegationBanner — withdrawn (3rd state) variant", () => {
  it("withdrawn renders the re-accept entry point, not the withdraw one", () => {
    render(
      <DelegationBanner
        {...baseProps}
        alreadyAccepted={true}
        withdrawn={true}
      />,
    );
    // Withdrawn behaves like never-accepted per mig 075 SQL gate: the entry
    // surface is the accept flow, not the manage/withdraw flow.
    expect(
      screen.getByRole("button", { name: /review.*accept/i }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /^manage$/i })).toBeNull();
  });
});
