import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { BashAutonomousToggle } from "@/components/settings/bash-autonomous-toggle";

// Issue B part 2 (AC17) — the settings toggle + risk interstitial. Owner-gated;
// turning ON is gated behind an explicit risk confirmation; turning OFF is not.

const originalFetch = global.fetch;

beforeEach(() => {
  vi.restoreAllMocks();
});
afterEach(() => {
  global.fetch = originalFetch;
});

describe("BashAutonomousToggle", () => {
  test("renders nothing for a non-owner", () => {
    const { container } = render(
      <BashAutonomousToggle initialAutonomous={false} isOwner={false} />,
    );
    expect(container.firstChild).toBeNull();
  });

  test("turning ON shows the risk interstitial BEFORE any write", () => {
    const fetchSpy = vi.fn();
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));

    // Interstitial appears; NO write has happened yet.
    expect(screen.getByRole("alertdialog")).toBeTruthy();
    expect(
      screen.getByText(/no blocklist is perfect/i),
    ).toBeTruthy();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("confirming the interstitial POSTs value:true", async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ autonomous: true }),
    });
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    fireEvent.click(screen.getByRole("button", { name: /turn it on/i }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    const [url, init] = fetchSpy.mock.calls[0];
    expect(url).toBe("/api/workspace/bash-autonomous");
    expect(JSON.parse(init.body)).toEqual({ value: true });
    await waitFor(() =>
      expect(screen.getByRole("switch").getAttribute("aria-checked")).toBe("true"),
    );
  });

  test("Cancel dismisses the interstitial without writing", () => {
    const fetchSpy = vi.fn();
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

    expect(screen.queryByRole("alertdialog")).toBeNull();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("turning OFF writes immediately with NO interstitial", async () => {
    const fetchSpy = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ autonomous: false }),
    });
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={true} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));

    // No interstitial for OFF; write fires straight away with value:false.
    expect(screen.queryByRole("alertdialog")).toBeNull();
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    expect(JSON.parse(fetchSpy.mock.calls[0][1].body)).toEqual({ value: false });
  });

  test("non-owner write rejection (403) alerts and does not flip", async () => {
    const alertSpy = vi.fn();
    window.alert = alertSpy;
    const fetchSpy = vi.fn().mockResolvedValue({ ok: false, status: 403 });
    global.fetch = fetchSpy as unknown as typeof fetch;

    render(<BashAutonomousToggle initialAutonomous={false} isOwner={true} />);
    fireEvent.click(screen.getByRole("switch", { name: /autonomous mode/i }));
    fireEvent.click(screen.getByRole("button", { name: /turn it on/i }));

    await waitFor(() => expect(alertSpy).toHaveBeenCalled());
    expect(screen.getByRole("switch").getAttribute("aria-checked")).toBe("false");
  });
});
