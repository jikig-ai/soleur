// @vitest-environment happy-dom
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// #9545 PR2 — the Try again / Refresh button. router.refresh() is mocked: the transition around it is
// held pending by returning a promise from the mock (React treats a promise-returning transition
// callback as an async action), standing in for "the server data has not arrived yet".
//
// What is unit-proven here: the component starts a transition, the busy state tracks that transition,
// and the focus rules. What is NOT unit-proven: that Next keeps a real router.refresh() transition
// pending until the RSC payload commits (the real one returns void; this mock does not).

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

  it("a click starts one transition around router.refresh and the busy state tracks it (the mock holds it pending; real Next behaviour is not proven here)", async () => {
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

  it("a retry that settles with the button still mounted (failed retry, same alert) keeps focus on the button, not the heading", async () => {
    render(
      <>
        <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
          Egress audit log
        </h1>
        <EgressAuditRefreshButton label="Try again" />
      </>,
    );
    const btn = screen.getByRole("button");
    btn.focus();
    await act(async () => {
      fireEvent.click(btn);
    });
    await settle();
    const after = screen.getByRole("button", { name: "Try again" });
    expect(document.activeElement).toBe(after);
    expect(document.activeElement?.id).not.toBe(EGRESS_AUDIT_HEADING_ID);
  });

  it("a settled retry returns focus to the button when a disabled busy button dropped it to <body>", async () => {
    render(
      <>
        <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
          Egress audit log
        </h1>
        <EgressAuditRefreshButton label="Try again" />
      </>,
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
    });
    (document.activeElement as HTMLElement | null)?.blur();
    await settle();
    expect(document.activeElement).toBe(screen.getByRole("button", { name: "Try again" }));
  });

  it("does not steal focus when the user moved it elsewhere during the refresh", async () => {
    render(
      <>
        <input aria-label="elsewhere" />
        <EgressAuditRefreshButton label="Try again" />
      </>,
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button"));
    });
    const input = screen.getByLabelText("elsewhere");
    input.focus();
    await settle();
    expect(document.activeElement).toBe(input);
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

  it("an idle unmount (no refresh started) does not move focus to the heading", () => {
    const { rerender } = render(
      <>
        <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
          Egress audit log
        </h1>
        <input aria-label="elsewhere" />
        <EgressAuditRefreshButton label="Refresh" />
      </>,
    );
    screen.getByLabelText("elsewhere").focus();
    rerender(
      <>
        <h1 id={EGRESS_AUDIT_HEADING_ID} tabIndex={-1}>
          Egress audit log
        </h1>
        <input aria-label="elsewhere" />
      </>,
    );
    expect(document.activeElement?.id).not.toBe(EGRESS_AUDIT_HEADING_ID);
    expect(document.activeElement).toBe(screen.getByLabelText("elsewhere"));
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
