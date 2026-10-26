// @vitest-environment happy-dom
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// #9545 PR2 — the Try again / Refresh button. router.refresh() is mocked: the transition around it is
// held pending by returning a promise from the mock (React treats a promise-returning transition
// callback as an async action), standing in for "the server data has not arrived yet". The real
// router.refresh() returns void and Next keeps the transition pending until the RSC payload commits.

const pendingRefreshes: (() => void)[] = [];
const refresh = vi.fn(
  () =>
    new Promise<void>((resolve) => {
      pendingRefreshes.push(resolve);
    }) as unknown as void,
);
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh }) }));

import { EgressAuditRefreshButton } from "@/components/settings/egress-audit-refresh-button";
import { EGRESS_AUDIT_HEADING_ID } from "@/components/settings/egress-audit-focus";

beforeEach(() => {
  refresh.mockClear();
});
// React entangles async transitions: a refresh left unresolved (the unmount test) would hold the next
// test's transition pending too, so every test releases whatever it started.
afterEach(async () => {
  await settle();
  cleanup();
});

const settle = async () => {
  await act(async () => {
    for (const resolve of pendingRefreshes.splice(0)) resolve();
  });
};

describe("EgressAuditRefreshButton", () => {
  it("is idle with its label until clicked", () => {
    render(<EgressAuditRefreshButton label="Try again" />);
    const btn = screen.getByRole("button", { name: "Try again" });
    expect(btn.getAttribute("aria-busy")).toBeNull();
    expect((btn as HTMLButtonElement).disabled).toBe(false);
    expect(refresh).not.toHaveBeenCalled();
  });

  it("a click calls router.refresh once and the button stays busy until the transition settles", async () => {
    render(<EgressAuditRefreshButton label="Refresh" />);
    const btn = screen.getByRole("button", { name: "Refresh" });
    await act(async () => {
      fireEvent.click(btn);
    });
    expect(refresh).toHaveBeenCalledTimes(1);
    const busy = screen.getByRole("button");
    expect(busy.getAttribute("aria-busy")).toBe("true");
    expect((busy as HTMLButtonElement).disabled).toBe(true);
    expect(busy.textContent).toBe("Refresh…");
    await settle();
    const idle = screen.getByRole("button", { name: "Refresh" });
    expect(idle.getAttribute("aria-busy")).toBeNull();
    expect((idle as HTMLButtonElement).disabled).toBe(false);
  });

  it("a second click while busy does not queue another refresh", async () => {
    render(<EgressAuditRefreshButton label="Try again" />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
      fireEvent.click(screen.getByRole("button"));
    });
    expect(refresh).toHaveBeenCalledTimes(1);
    await settle();
  });

  it("moves focus to the page heading when the refresh settles", async () => {
    render(
      <>
        <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
          Egress audit log
        </h1>
        <EgressAuditRefreshButton label="Refresh" />
      </>,
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
    });
    expect(document.activeElement?.id).not.toBe(EGRESS_AUDIT_HEADING_ID);
    await settle();
    expect(document.activeElement?.id).toBe(EGRESS_AUDIT_HEADING_ID);
  });

  it("moves focus to the heading when the button unmounts mid-refresh (the card was swapped out)", async () => {
    const { rerender } = render(
      <>
        <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
          Egress audit log
        </h1>
        <EgressAuditRefreshButton label="Refresh" />
      </>,
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
    });
    rerender(
      <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
        Egress audit log
      </h1>,
    );
    expect(document.activeElement?.id).toBe(EGRESS_AUDIT_HEADING_ID);
  });

  it("settling with no heading in the document is a no-op (no throw)", async () => {
    render(<EgressAuditRefreshButton label="Refresh" />);
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
    });
    await settle();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeTruthy();
  });
});
